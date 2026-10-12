# Operation Bulletin (installable web app)

The Operation Bulletin phone app as a web app (PWA) on GitHub Pages: open
**https://starmis2-lgtm.github.io/operation-bulletin/** in Chrome on the phone → menu → **Install app**.
It always runs the latest version, no APK download needed.

- Built from the Flutter app in `operation-bulletin-app/` with
  `flutter build web --release --base-href /operation-bulletin/ --no-web-resources-cdn`
  (debug `*.symbols`, `skwasm*` and `wimp*` files are left out; the JS build uses CanvasKit only).
- `index.html`, `manifest.webmanifest`, `sw.js` come from `operation-bulletin-app/web/`.
  `sw.js` is network first, so a new deploy reaches phones on the next open; the cached copy is used offline.
- Talks to the Apps Script web app (`Api.execUrl` in `operation-bulletin-app/lib/api.dart`) with a
  plain-text POST, so the browser needs no CORS preflight.
- `app/` still holds the Android APK (`operation-bulletin.apk`) and its `version.json` for the native app.
