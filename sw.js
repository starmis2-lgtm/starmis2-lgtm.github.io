// ===== GITHUB REPO  ·  file name: sw.js =====
const CACHE = 'checklist-v25';
const SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) {
    return c.addAll(SHELL);
  }).then(function () {
    return self.skipWaiting();
  }));
});

self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.map(function (k) {
      return k === CACHE ? null : caches.delete(k);
    }));
  }).then(function () {
    return self.clients.claim();
  }));
});

function isShell(req) {
  if (req.mode === 'navigate') return true;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return false;
  return SHELL.some(function (path) {
    return new URL(path, self.registration.scope).href === url.origin + url.pathname;
  });
}

function fromNetwork(req) {
  return fetch(req).then(function (res) {
    const copy = res.clone();
    caches.open(CACHE).then(function (c) { c.put(req, copy); });
    return res;
  });
}

self.addEventListener('fetch', function (e) {
  if (e.request.method !== 'GET') return;
  if (e.request.url.indexOf('script.google.com') !== -1) return;
  // Other apps hosted under this origin (e.g. /SG-Data-Manage/) have their own service worker — leave them alone.
  if (new URL(e.request.url).pathname.indexOf('/SG-Data-Manage/') === 0) return;
  if (isShell(e.request)) {
    e.respondWith(caches.match(e.request, { ignoreSearch: true }).then(function (hit) {
      const net = fromNetwork(e.request).catch(function () {
        return hit || caches.match('./index.html');
      });
      return hit || net;
    }));
    return;
  }
  e.respondWith(
    fromNetwork(e.request).catch(function () {
      return caches.match(e.request).then(function (hit) {
        return hit || caches.match('./index.html');
      });
    })
  );
});
