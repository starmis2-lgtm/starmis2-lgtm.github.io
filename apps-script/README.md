# Apps Script (web app + API) — deploy notes

The Production Bulletin web app and its API run on Google Apps Script, bound to the
"Production Bulletin – Making & Packing" Google Sheet. The script source lives in that Apps Script
project; this folder only holds files that are added to it.

| What | Value |
|---|---|
| Script ID | `17bgme7TLF-q-GvkTLWtMFJWJ3VakNzHrpPI_2JhnqLYlu8qZlaKdHHBW` |
| Deployment ID (keep this one, the app and the Worker use its URL) | `AKfycbwz492tw24mYnFwSvAG4pQ9oUU_OsW_g8EYPrTGZM119pwKzRdyQODpoGS5pfp3Z5a4zw` |

## Login for a cloud session

The cloud environment has an environment variable `CLASPRC_JSON` holding the content of the
`.clasprc.json` that `clasp login` creates. A session writes it to `~/.clasprc.json` (mode 600) and
installs clasp with `npm i -g @google/clasp`. Never print, commit or paste that content.

## Deploy

```sh
mkdir -p "$SCRATCH/production-bulletin" && cd "$SCRATCH/production-bulletin"
clasp clone 17bgme7TLF-q-GvkTLWtMFJWJ3VakNzHrpPI_2JhnqLYlu8qZlaKdHHBW
# change files, then
clasp push -f
clasp deploy -i AKfycbwz492tw24mYnFwSvAG4pQ9oUU_OsW_g8EYPrTGZM119pwKzRdyQODpoGS5pfp3Z5a4zw -d "what changed"
```

Before pushing, check `clasp versions` and compare a fresh `clasp pull` with your copy, so changes made in
the editor by someone else are not overwritten.

## Files in this folder

- `PmReview.html` — Production Manager review tab for the web app. Add it to the project as an HTML file
  named `PmReview` and put `<?!= include('PmReview'); ?>` just before `</body>` in `Index.html`.
