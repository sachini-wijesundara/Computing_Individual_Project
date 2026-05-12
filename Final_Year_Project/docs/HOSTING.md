# Hosting — admin web, delivery staff web, and iOS

Firebase project: **`finalyearproject-45e32`** (`.firebaserc`).

This repo deploys **two** Hosting targets from `firebase.json` (consumer shop web is **not** included in the deploy script):

| Target | Flutter entry | Output folder | Typical URL |
|--------|----------------|---------------|----------------|
| **admin** | `lib/main_admin_web.dart` | `build/web_admin` | `https://finalyearproject-45e32-admin.web.app` |
| **delivery** | `lib/main_delivery_staff.dart` | `build/web_delivery` | `https://finalyearproject-45e32-delivery.web.app` |

The default Firebase site (`finalyearproject-45e32.web.app`) is **not** updated by `./scripts/deploy_firebase_hosting.sh`. To ship the main consumer app on Hosting again, add a `consumer` block back to `firebase.json`, map it in `.firebaserc`, and extend the deploy script to build `build/web` and deploy that target.

Mobile apps are **not** hosted on Firebase Hosting — use **TestFlight** / **App Store** (iOS) and **Play Console** (Android).

---

## 1. Prerequisites

```bash
npm install -g firebase-tools
cd Final_Year_Project
firebase login
firebase use finalyearproject-45e32
```

Enable **Hosting** once in [Firebase Console](https://console.firebase.google.com/) → **Build → Hosting** → Get started (if you have not already).

---

## 2. Create extra Hosting sites (one time)

Admin and delivery use **separate sites** with IDs that match `.firebaserc`:

- `finalyearproject-45e32-admin`
- `finalyearproject-45e32-delivery`

Run:

```bash
cd Final_Year_Project
chmod +x scripts/setup_firebase_hosting_sites.sh
./scripts/setup_firebase_hosting_sites.sh
```

Or create them manually: Console → **Hosting** → **Add another site** → use those exact IDs.

If deploy says a site is missing, create it and run deploy again.

---

## 3. Deploy admin + delivery web apps

1. Put API keys in **`Final_Year_Project/.env`** (used as `--dart-define` at build time), **or** export the same variables in your shell.

2. Run:

```bash
cd Final_Year_Project
chmod +x scripts/deploy_firebase_hosting.sh
./scripts/deploy_firebase_hosting.sh
```

This script:

1. `flutter build web -t lib/main_admin_web.dart --release -o build/web_admin`  
2. `flutter build web -t lib/main_delivery_staff.dart --release -o build/web_delivery`  
3. `firebase deploy --only hosting:admin,hosting:delivery`

Copy the **Hosting URL** lines from the CLI output for each site.

**Local dev (unchanged):**

- Main app web: `flutter run -d chrome`  
- Admin: `./web_quick_run.sh` (uses `main_admin_web.dart`)

---

## 4. iOS app — TestFlight / App Store (not Firebase Hosting)

1. **Apple Developer** account + app record in [App Store Connect](https://appstoreconnect.apple.com/).  
2. Open **`ios/Runner.xcworkspace`** in Xcode.  
3. Select **Any iOS Device** or a generic device, then **Product → Archive**.  
4. In the Organizer window → **Distribute App** → App Store Connect → Upload.  
5. In App Store Connect → your app → **TestFlight** → add internal testers, then submit for review for the public store.

CLI alternative (after signing configured):

```bash
cd Final_Year_Project
flutter build ipa
```

Then upload the IPA from `build/ios/ipa/` with Transporter or Xcode.

---

## 5. Custom domains (optional)

Firebase Console → **Hosting** → pick each site → **Add custom domain** → add DNS records → wait for SSL.

---

## 6. Firestore / Storage rules

```bash
firebase deploy --only firestore:rules,storage:rules
```

Everything (including any Hosting targets still in `firebase.json`):

```bash
firebase deploy
```

---

## 7. Troubleshooting

| Issue | What to try |
|--------|-------------|
| `HTTP Error: 404` for admin/delivery URL | Sites not created — run `setup_firebase_hosting_sites.sh` or add sites in Console. |
| Blank web page | Each Hosting target needs SPA **rewrites** to `/index.html` (already in `firebase.json`). |
| Wrong project | `firebase use finalyearproject-45e32` |
| API keys missing on web | Rebuild after editing `.env`; keys are compile-time `--dart-define` for these scripts. |

---

## 8. Targets file

`.firebaserc` maps **target** names (`admin`, `delivery`) to **site IDs**. If you rename sites in Firebase, update `.firebaserc` and `firebase.json` together.
