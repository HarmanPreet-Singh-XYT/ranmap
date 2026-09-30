# Store compliance — what's left for you

The code/config side of the App Store + Play Store audit is done (privacy
manifest, entitlements, export-compliance key, report/block moderation,
consent, background-location disclosure, legal links). This file is the
**manual / portal / infrastructure** work that can't be done from the repo.

Bundle id: `com.ranmap.app` · Apple Team ID: `24GYZ37VQU` · Supabase project:
`vcbclecweorugfucdubm` · API: `https://api.harmanita.com/ranmap` · Domain for
links: `ranmap.app`

---

## 1. Apply the database migrations

- [ ] Apply `supabase/migrations/0046_moderation.sql` — creates `user_blocks`,
      `content_reports`, the block/report RPCs, and the RLS enforcement.
- [ ] Apply `supabase/migrations/0047_terms_acceptance.sql` — adds
      `profiles.terms_accepted_at`.

> Until 0046 is applied, the Report/Block buttons and the Blocked-accounts screen
> will error (the RPCs/tables won't exist).

- [ ] Sanity-check after applying: block a test user, confirm they can't send you
      a friend request or a DM, then unblock from Settings → Safety → Blocked
      accounts.
- [ ] Confirm a row lands in `content_reports` when you report something
      (`select * from content_reports;` via the Supabase dashboard).

---

## 2. iOS — Apple Developer portal + App Store Connect

- [ ] **Enable the App ID capabilities** for `com.ranmap.app`:
  - [ ] Push Notifications
  - [ ] Associated Domains
- [ ] Regenerate/download the provisioning profiles so the entitlements take
      effect (otherwise archive/signing fails once `Runner.entitlements` is
      present).
- [ ] **Push**: create an APNs auth key, upload it to Firebase (Project
      Settings → Cloud Messaging), and add `GoogleService-Info.plist` to the
      iOS Runner target.
- [ ] **Associated Domains**: host `https://ranmap.app/.well-known/apple-app-site-association`
      with the Team ID + bundle id so invite links open in the app.
- [ ] App Store Connect → **App Privacy** questionnaire: fill it in to match
      `ios/Runner/PrivacyInfo.xcprivacy` (location, photos, audio, contact info,
      identifiers, user content, purchases; no tracking).
- [ ] Confirm the privacy manifest ships: after archiving, the build should
      contain `Runner.app/PrivacyInfo.xcprivacy`.

---

## 3. Android — Play Console

- [ ] **Background location**: complete the Permissions Declaration Form, and
      make sure the in-app prominent disclosure (now shown before the OS prompt)
      is demonstrated in the review notes/video.
- [ ] **Data safety** form: declare the collected data (location, photos, audio,
      personal info, app activity, purchases) and that data is encrypted in
      transit.
- [ ] Decide on `targetSdk` — it currently inherits Flutter's default
      (`android/app/build.gradle.kts` uses `flutter.targetSdkVersion`). Confirm
      the released build meets Play's current target-API requirement (this was
      left unpinned on purpose to avoid plugin breakage).
- [ ] Content rating questionnaire — the app has UGC (chat, photos, groups), so
      answer accordingly.

---

## 4. Billing — RevenueCat + stores

- [ ] Replace the **Test Store** keys in `.env`
      (`REVENUECAT_IOS_KEY` / `REVENUECAT_ANDROID_KEY`, currently `test_…`) with
      the real `appl_…` / `goog_…` public SDK keys.
- [ ] Create the store products/subscription in App Store Connect and Play
      Console, and confirm the RevenueCat offering + entitlement identifiers
      match what the app expects (paywall uses the `pro_annual` package / the
      standard annual package).
- [ ] Link the RevenueCat webhook secret in the dashboard (`REVENUECAT_WEBHOOK_AUTH`).
- [ ] Verify a real sandbox purchase and **Restore Purchases** on device.

> Do this only once the store products exist — swapping keys before then leaves
> the paywall with nothing to buy.

---

## 5. Domain + legal hosting

- [ ] Move the legal pages off the `*.vercel.app` host to the stable domain
      (`https://ranmap.app/terms`, `/privacy`) and update `TERMS_URL` /
      `PRIVACY_URL` in `.env`.
- [ ] (The app now defaults to the Vercel URLs if the env vars are unset, so the
      links always appear — but the branded domain is what reviewers expect.)
- [ ] Serve the AASA file (see §2) and `/.well-known/assetlinks.json` for Android
      App Links at `ranmap.app`.
- [ ] Publishing contact / support page reachable from the app or listing.

---

## 6. Rotate leaked server credentials

`server/.env` is gitignored and **not** in the client bundle, but the values are
live secrets in the working tree — treat them as disclosed and rotate each:

- [ ] `SUPABASE_SECRET_KEY` (service role — bypasses RLS)
- [ ] `MAPBOX_ACCESS_TOKEN` (`sk.…`, tokens:write) — also used by the Android
      Gradle build, so update both places
- [ ] `REVENUECAT_SECRET_KEY` + `REVENUECAT_WEBHOOK_AUTH` (webhook auth also in
      the RevenueCat dashboard)
- [ ] `TWILIO_AUTH_TOKEN`
- [ ] `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET`
- [ ] `GEMINI_API_KEY`
- [ ] `FIREBASE_SERVICE_ACCOUNT_JSON` (private key)
- [ ] `GOOGLE_MAPS_API_KEY` — restrict it (app/bundle + API restrictions) in
      Google Cloud

---

## 7. Store listing prerequisites

- [ ] Privacy policy URL + support URL in both consoles.
- [ ] Account deletion is already in-app (Settings → account → Delete account);
      no separate web deletion URL needed, but note it in the review notes.
- [ ] Sign in with Apple is already offered alongside Google — no action.
- [ ] Age rating / "made for kids" = no (there's UGC and no age gate).

---

## Deliberately not changed (so you're not surprised)

- `NSAllowsLocalNetworking` stays in `ios/Runner/Info.plist` — it's what lets a
  physical device reach your local backend during development. Remove it once
  you no longer need local-device testing, if you want a fully strict release.
- Android `targetSdk` is left inheriting the Flutter default (see §3).
- The `blocked` value in the friendships enum is still unused; blocking is now
  handled by the dedicated `user_blocks` table so the friend-request "decline =
  delete row" behaviour is preserved.
