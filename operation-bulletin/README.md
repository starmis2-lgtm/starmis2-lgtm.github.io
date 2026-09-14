# Operation Bulletin (mobile app)

Installable PWA launcher for the Star Global **Production Bulletin** web app (Apps Script).

- `index.html` – launcher; when opened as an installed app it goes straight to the web app.
- `config.js` – `OB_APP_URL` = the live web app `/exec` URL. Change it here if the deployment changes.
- `manifest.webmanifest` – app name **Operation Bulletin**, its own id and icon, so it installs separately from other apps.
- `sw.js` – minimal service worker (required for "Install app" in Chrome).
- `icons/` – app icons.

## Hosting
Enable **GitHub Pages** (Settings → Pages → Deploy from a branch → `main` / root).
Then open `https://<user>.github.io/<repo>/` on the phone in Chrome → menu → **Install app / Add to Home screen**.
