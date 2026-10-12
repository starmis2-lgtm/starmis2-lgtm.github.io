# Operation Bulletin API — Cloudflare Worker

Makes the Operation Bulletin app fast without moving the data out of Google Sheets.

```
phone / web app  ──►  Cloudflare Worker (this folder)  ──►  Apps Script web app  ──►  Google Sheet
                         │
                         └─ D1 database: last app data of every user (opens instantly)
```

- **Loading the app** (`getInitialPayload`) is answered from D1 at once (~50 ms). If it is older than
  10 minutes, or anybody saved something since, the Worker answers with the saved copy (`X-Cache: STALE`)
  and fetches a fresh copy from Apps Script in the background. The app asks again a few seconds later.
- **Saving** (submit, PM review, DEO confirm, approve, reject, photo upload, …) goes straight to Apps Script,
  so all business rules stay there and the Google Sheet is always up to date. After a save the Worker
  refreshes the caller's data in the background and marks everybody else's copy as out of date.
- Same request format as Apps Script: `POST {"fn": "...", "args": [...]}` → `{"result": ...}`.
- The D1 tables are created by the Worker itself on the first request. A daily cron removes copies
  nobody asked for in a week.

## Setup (one time, Cloudflare dashboard)

1. **D1 database** `operation-bulletin` — already created; its id is in `wrangler.toml`.
2. **Workers & Pages → Create → Import a repository** → GitHub → `starmis2-lgtm/starmis2-lgtm.github.io`.
   - Project name: `operation-bulletin` (must match `name` in `wrangler.toml`)
   - Root directory: `cloudflare`
   - Build command: empty · Deploy command: `npx wrangler deploy` (default)
   - Deploy.
3. Open the Worker URL (`https://operation-bulletin.<your-subdomain>.workers.dev/`). It should show
   `{"ok":true,"service":"operation-bulletin",...}`.
4. Put that URL in `operation-bulletin/api.json` (`{"url": "https://..."}`) — the app reads it at start.
   Without it the app keeps calling Apps Script directly.

Every push to `main` that changes this folder redeploys the Worker automatically.

## Settings (`wrangler.toml` → `[vars]`)

- `APPS_SCRIPT_URL` — the Apps Script `/exec` URL (change it here if the deployment changes).
- `CACHE_MAX_AGE_SEC` — after this many seconds a saved copy is refreshed in the background (default 600).

## Limits

On the free Workers plan each request gets very little CPU time. The Worker only passes text through
(it never parses the big app data), which should fit. If the dashboard shows "exceeded CPU" errors,
switch to Workers Paid.

## Local test

```
npx wrangler dev --local --var APPS_SCRIPT_URL:<url>
curl -X POST --data '{"fn":"apiPing","args":[]}' http://localhost:8787
```
