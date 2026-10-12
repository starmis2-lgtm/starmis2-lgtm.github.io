// Operation Bulletin API on Cloudflare Workers.
//
// The phone / web app talks to this Worker instead of Apps Script directly:
//  - getInitialPayload (the big "load everything" call) is answered from D1 right away and refreshed from
//    Apps Script in the background when it is old or when anybody has saved something since (stale-while-revalidate);
//  - every other call (submit, PM review, approve, upload, ...) is passed straight to Apps Script, so all
//    business rules and the Google Sheet stay exactly where they are and the sheet is always up to date.
// Request / response format is the same as the Apps Script doPost API: {"fn": "...", "args": [...]} -> {"result": ...}.

const CACHED_FN = 'getInitialPayload';
// Calls that only read; any other call may change data, so it bumps the global data version.
const READ_FNS = new Set(['getInitialPayload', 'getMyRejectedLight', 'getMisPayload', 'apiPing', 'loginWithPin', 'uploadOperationImage']);
// D1 limits a value to ~2 MB, so a payload is stored in parts.
const CHUNK = 500000;
const LOCK_MS = 25000;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Expose-Headers': 'X-Cache, X-Cache-Age',
  'Access-Control-Max-Age': '86400',
};

function reply(text, extra) {
  return new Response(text, { headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...CORS, ...(extra || {}) } });
}

function errorReply(msg) {
  return reply(JSON.stringify({ error: msg }), { 'X-Cache': 'ERROR' });
}

let schemaReady = false;
async function ensureSchema(db) {
  if (schemaReady) return;
  await db.batch([
    db.prepare('CREATE TABLE IF NOT EXISTS payload_cache (k TEXT NOT NULL, part INTEGER NOT NULL, n INTEGER NOT NULL, data TEXT NOT NULL, ver INTEGER NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (k, part))'),
    db.prepare('CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v INTEGER NOT NULL)'),
    db.prepare("INSERT OR IGNORE INTO meta (k, v) VALUES ('ver', 1)"),
  ]);
  schemaReady = true;
}

async function sha(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Sends the request body to Apps Script and returns its JSON text. */
async function upstream(env, bodyText) {
  const r = await fetch(env.APPS_SCRIPT_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain;charset=utf-8' },
    body: bodyText,
    redirect: 'follow',
  });
  const t = await r.text();
  if (!r.ok || t.charAt(0) !== '{') throw new Error('Google server is busy (' + r.status + '). Please try again.');
  return t;
}

/** Only real payloads are kept (not "please login" or error answers). */
function cacheable(text) {
  return text.startsWith('{"result":') && text.length > 1000 && !/needLogin|\\"error\\"/.test(text.slice(0, 300));
}

async function currentVersion(db) {
  const row = await db.prepare("SELECT v FROM meta WHERE k = 'ver'").first();
  return row ? Number(row.v) : 1;
}

/** Takes the refresh lock for a key; false when another refresh started less than LOCK_MS ago. */
async function takeLock(db, key) {
  const now = Date.now();
  const r = await db.prepare('INSERT INTO meta (k, v) VALUES (?1, ?2) ON CONFLICT(k) DO UPDATE SET v = excluded.v WHERE meta.v < ?3')
    .bind('lock:' + key, now, now - LOCK_MS).run();
  return !!(r.meta && r.meta.changes > 0);
}

/** Loads a fresh payload from Apps Script and stores it. Returns the Apps Script text. */
async function refresh(env, key, args, ver) {
  const text = await upstream(env, JSON.stringify({ fn: CACHED_FN, args }));
  const db = env.DB;
  if (!cacheable(text)) {
    await db.prepare('DELETE FROM payload_cache WHERE k = ?').bind(key).run();
    return text;
  }
  const n = Math.ceil(text.length / CHUNK);
  const at = Date.now();
  const stmts = [db.prepare('DELETE FROM payload_cache WHERE k = ?').bind(key)];
  for (let i = 0; i < n; i++) {
    stmts.push(db.prepare('INSERT INTO payload_cache (k, part, n, data, ver, at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(key, i, n, text.slice(i * CHUNK, (i + 1) * CHUNK), ver, at));
  }
  await db.batch(stmts);
  return text;
}

async function cachedPayload(env, ctx, req) {
  const args = Array.isArray(req.args) ? req.args : [];
  const key = await sha(JSON.stringify(args));
  const db = env.DB;
  const [verRes, rowsRes] = await db.batch([
    db.prepare("SELECT v FROM meta WHERE k = 'ver'"),
    db.prepare('SELECT part, n, data, ver, at FROM payload_cache WHERE k = ? ORDER BY part').bind(key),
  ]);
  const gver = verRes.results.length ? Number(verRes.results[0].v) : 1;
  const parts = rowsRes.results || [];
  const complete = parts.length > 0 && parts.length === Number(parts[0].n);

  if (complete && req.fresh !== true) {
    const age = Math.max(0, Math.round((Date.now() - Number(parts[0].at)) / 1000));
    const stale = Number(parts[0].ver) < gver || age > Number(env.CACHE_MAX_AGE_SEC || 600);
    if (stale) {
      ctx.waitUntil((async () => {
        if (await takeLock(db, key)) await refresh(env, key, args, gver);
      })().catch(() => {}));
    }
    return reply(parts.map((p) => p.data).join(''), { 'X-Cache': stale ? 'STALE' : 'HIT', 'X-Cache-Age': String(age) });
  }

  const text = await refresh(env, key, args, gver);
  return reply(text, { 'X-Cache': 'MISS', 'X-Cache-Age': '0' });
}

/** After a save: everybody's cached payload is out of date; refresh the caller's own one right away. */
async function afterWrite(env, token) {
  const db = env.DB;
  await db.prepare("UPDATE meta SET v = v + 1 WHERE k = 'ver'").run();
  if (!token) return;
  const args = [token];
  const key = await sha(JSON.stringify(args));
  if (await takeLock(db, key)) await refresh(env, key, args, await currentVersion(db));
}

/**
 * Operation photos: GET /?img=<Drive file id>&w=<width> returns the Drive thumbnail with CORS, so the app can show it
 * (Drive itself sends no CORS headers). Only files shared "anyone with the link" can be read. Cached at the edge for a week.
 */
async function imageReply(request, ctx, id, w) {
  if (!/^[A-Za-z0-9_-]{20,}$/.test(id)) return new Response('Bad image id', { status: 400, headers: CORS });
  const width = Math.min(Math.max(parseInt(w, 10) || 400, 64), 2000);
  const cache = caches.default;
  const key = new Request(`https://img.cache/${id}/${width}`);
  const hit = await cache.match(key);
  if (hit) return hit;
  const r = await fetch(`https://drive.google.com/thumbnail?id=${id}&sz=w${width}`, { redirect: 'follow' });
  const type = r.headers.get('Content-Type') || '';
  if (!r.ok || !type.startsWith('image/')) return new Response('Image not found', { status: 404, headers: { ...CORS, 'Cache-Control': 'no-store' } });
  const res = new Response(r.body, { headers: { ...CORS, 'Content-Type': type, 'Cache-Control': 'public, max-age=604800' } });
  ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    let bodyText = '';
    if (request.method === 'GET') {
      const u = new URL(request.url);
      if (u.searchParams.has('img')) return imageReply(request, ctx, u.searchParams.get('img') || '', u.searchParams.get('w'));
      const fn = u.searchParams.get('fn');
      if (!fn) return reply(JSON.stringify({ ok: true, service: 'operation-bulletin', time: new Date().toISOString() }));
      let args = [];
      try { args = JSON.parse(u.searchParams.get('args') || '[]'); } catch (e) { args = []; }
      bodyText = JSON.stringify({ fn, args });
    } else if (request.method === 'POST') {
      bodyText = await request.text();
    } else {
      return errorReply('Method not allowed');
    }

    // Big bodies (photo uploads) are not parsed: the function name sits at the start, the token at the end.
    const fnMatch = /"fn"\s*:\s*"([A-Za-z0-9_]+)"/.exec(bodyText.slice(0, 300));
    if (!fnMatch) return errorReply('Bad request');
    const fn = fnMatch[1];

    try {
      await ensureSchema(env.DB);
      if (fn === CACHED_FN) {
        let req;
        try { req = JSON.parse(bodyText); } catch (e) { return errorReply('Bad request'); }
        return await cachedPayload(env, ctx, req);
      }
      const text = await upstream(env, bodyText);
      if (!READ_FNS.has(fn)) {
        // the session token is the last argument: "<base64>.<signature>"]}
        const tok = /"([A-Za-z0-9_-]+\.[A-Za-z0-9_\-+/=]+)"\s*\]\s*\}\s*$/.exec(bodyText.slice(-400));
        ctx.waitUntil(afterWrite(env, tok ? tok[1] : '').catch(() => {}));
      }
      return reply(text, { 'X-Cache': 'BYPASS' });
    } catch (e) {
      return errorReply((e && e.message) || String(e));
    }
  },

  async scheduled(event, env, ctx) {
    await ensureSchema(env.DB);
    const weekAgo = Date.now() - 7 * 24 * 3600 * 1000;
    await env.DB.batch([
      env.DB.prepare('DELETE FROM payload_cache WHERE at < ?').bind(weekAgo),
      env.DB.prepare("DELETE FROM meta WHERE k LIKE 'lock:%' AND v < ?").bind(Date.now() - 24 * 3600 * 1000),
    ]);
  },
};
