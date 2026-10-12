# Operation Bulletin (Android app)

Native Android app (Flutter, Material 3) for the Star Global **Production Bulletin** system.
It talks to the existing Apps Script web app as a JSON API (`doPost` dispatcher in `Code.js`),
so all business rules, approvals and the Google Sheet stay exactly where they are.

## Features
- PIN login (token cached on the device for 30 days), no Google account needed on the phone.
- Two jobs only: **DEO data entry** and **Production Manager review**.
- Flow: DEO submits R&D → Production Manager writes his time next to each DEO time, can add operations
  (added directly) and ask to remove operations → the DEO accepts / keeps each removal → GM picks DEO or PM time,
  sets efficiency and approves in the web app (final).
- Review tab (designation "Production Manager"): DEO time fixed, PM time beside it, add / remove, reject.
- My Pending: stage of every request, confirm the Production Manager's removals, edit only before PM review.
- Data Entry (R&D only): SRNs with pending R&D first, edits show times at 100% efficiency,
  operation library built from past bulletins (tap to add, typical time prefilled),
  type-to-add with manpower guess, **Copy from SRN**, compact rows with inline time, photo upload
  (camera / gallery, resized to 1200px), optional video links.
- Settings (It/Mis & Management): manage ACCESS users, tabs and PINs.

## Build
```
flutter pub get
flutter build apk --release
```
Release signing reads `android/key.properties` (not committed). Keep the keystore safe:
the same key is required to install updates over an existing install.

Backend URL is in `lib/api.dart` (`Api.execUrl`).
