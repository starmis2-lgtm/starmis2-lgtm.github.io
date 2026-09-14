# Operation Bulletin (Android app)

Native Android app (Flutter, Material 3) for the Star Global **Production Bulletin** system.
It talks to the existing Apps Script web app as a JSON API (`doPost` dispatcher in `Code.js`),
so all business rules, approvals and the Google Sheet stay exactly where they are.

## Features
- PIN login (token cached on the device for 30 days), no Google account needed on the phone.
- Home: pending bulletins with due dates / MIS status, filters, one-tap **Create**.
- Production Pending, My Pending (edit before approval), Not Required.
- Data Entry: operation library built from past bulletins (tap to add, typical time prefilled),
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
