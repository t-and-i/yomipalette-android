# YomiPalette: server-backed Google-account trial

**Chosen product model:** one Android application, 30-day free trial, one
Google Play non-consumable product **`full_access`** (¥500 in Japan, managed
in Play Console), no subscriptions. The discontinued `remove_ads` ID is not
accepted by the new source. Existing Play purchases are not transferred or
altered by the new trial feature.

**DO NOT DEPLOY / RELEASE YET.** OAuth clients, D1 migration, Worker secrets,
privacy/data-safety disclosure and real-device tests must be completed first.
The feature is isolated in `feature/google-account-trial-30d`.

## Authentication and policy

- A **new unpaid trial user** taps "Continue with Google". The Android
  `google_sign_in` SDK (Credential Manager) supplies a short-lived Google ID
  token for the configured OAuth Web client. No Google API scopes are requested.
- The Worker verifies the token with Google's RS256 JWKS, audience, issuer,
  subject and expiry. It also checks a fresh Play Integrity verdict bound to
  the exact Google ID token digest, request ID and installation ID.
- Cloudflare D1 persists an HMAC-SHA256 of the Google `sub`, never a Google
  email address, raw subject, or ID token, together with immutable first-use
  and 30-day expiration times. Atomic INSERT OR IGNORE prevents concurrent
  requests from resetting the clock. The HMAC key is a Worker secret.
- The Worker issues an Ed25519 **v2 trial** grant scoped to an installation.
  Its expiry is the EARLIER of 72 hours or the account's original trial end.
  The Android client verifies signature, kind, version, device, issuance time,
  exact 30-day trial length and hard expiry. A v1 permanent `full_access`
  purchase grant can never masquerade as a trial.
- A **purchased user** is entitled through Play Billing `full_access` and the
  existing signed 72-hour purchase grant WITHOUT Google sign-in in this app.
- Google account changes can initiate a different account's trial. This
  design prevents resets for the *same Google account*, but does not block
  abuse via unlimited fresh accounts. Device Recall can later supplement it.

## Pending console and Worker prerequisites (not completed)

1. Google Cloud OAuth consent configuration: set up Android client for
   `com.tjsongwei.tts_text_mp3_mobile` using the **Play App Signing SHA-1**
   (not merely the upload-key SHA-1), and create the **Web OAuth client**.
   Restrict consent/test-user access as appropriate for internal testing.
2. Set public `GOOGLE_SIGN_IN_WEB_CLIENT_ID` on the Cloudflare Worker
   to the exact Web OAuth client ID. Do not place a client *secret* in the app.
3. Set Worker secret `TRIAL_SUBJECT_HMAC_KEY` to a cryptographically random
   **32-byte base64url string without padding**. Back it up securely; rotating
   it without a migration changes all user subject keys and resets trial
   lookup. Do not log or commit its value.
4. Apply `backend/play-verifier/migrations/0002_trial_entitlements.sql` to
   the correct **staging D1 first**. Verify the D1 database binding and
   existing VERIFY_IP_RATE_LIMIT / VERIFY_TOKEN_RATE_LIMIT bindings.
5. Deploy the new Worker to **staging**, then verify `POST /trial`.
   Production Worker must remain unchanged until staging tests pass.
6. Provide the **same Web OAuth client ID** to the Android Play build as
   `YOMIPALETTE_GOOGLE_WEB_CLIENT_ID`. Updated `scripts/build-play.ps1`
   and `scripts/build-play-linux.sh` reject release builds missing it.
7. Update the public privacy policy, Google Play Data Safety and any required
   account-data deletion/contact procedures before inviting external users.
8. Use a new version code for the next internal release (current S9 is
   0.2.9 build 17). Do **not** replace or reconnect S9 until the scheduled
   real-time 72h purchase-cache test on 26 November 2026 is completed.
   Use S22 for the first authentication E2E if possible.

## Verification checklist

- New Google account: server starts exactly 30 days of entitlement, no
  account information or timestamp trusted from the client.
- Same account on reinstall, app-data deletion, different device: the original
  server deadline is retained.
- Two concurrent starts: one immutable `started_at_ms`.
- No valid Google ID token or mismatched OAuth audience: no grant, no D1 row.
- Missing/invalid Play Integrity: no grant, no D1 row.
- Offline restart within signed window: entitlement still valid; at exactly
  the signed expiry or day 30 it is disabled.
- Online renewal near day 30: signed validity is capped at the original trial
  deadline; no new 30-day period is created.
- Blocked status / invalid Worker secrets or unavailable D1: fail closed.
- Existing `full_access` buyer: no sign-in prompt, purchase restoration
  continues to work.
- `remove_ads`: ignored by the new application and backend (check real
  purchase history before releasing the change).

Backend tests: `cd backend/play-verifier && npm run check && npm test`.
Flutter tests: `flutter analyze && flutter test`.
The test default is QA billing; production-specific trial tests explicitly
set `allowQaTrial:false`, and Play builds omit the QA flag.

## Privacy and operational notes

- Google ID tokens carry identity claims and are **transmitted** to the Worker
  but are not stored in D1. Avoid request-body logging and analytics.
- The stored HMAC and account history remain pseudonymous personal data;
  define retention, access/deletion procedures and disclosure. Deleting a
  record may allow a new trial; policy must address deletion versus abuse.
- Do not mix the 72-hour **purchase** expiry E2E experiment with trial tests.
  S9 stays offline until its existing scheduled test finishes.

## Signed internal Play staging-trial bundle (build 18)

2026-11-23: S22 SCG14 is USB-connected to Lenovo. The Play-installed
YomiPalette 0.2.9+17 displays permanent purchase entitlement.
Do NOT uninstall, clear data, or replace it with a debug-signed APK.

Build 0.2.10+18 uses independent verifier routes and public keys:
- Paid full_access: production /verify + production purchase public key.
- 30-day trial: staging /trial + staging trial public key.
- OAuth uses YOMIPALETTE_GOOGLE_WEB_CLIENT_ID.
- Play Billing QA and entitlement diagnostics remain OFF.

Only upload the signed build 18 to Google Play internal testing AFTER the
S9 real-time 72h offline expiry test scheduled for 2026-11-26 completes.
Otherwise Play automatic updates could change S9's app version when it
reconnects, invalidating expiry E2E evidence.

After S9 test: update S22 from Google Play, verify permanent purchase
does not require Google login. S22 is already purchased, so a separate
unlicensed Play tester/device is necessary to verify actual trial start.
Never promote this staging-trial AAB to a public Play release; rebuild
using production trial verification after successful E2E tests.
