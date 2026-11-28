# YomiPalette — 72-hour signed offline purchase grants

## Contract and trust boundary

Google Play Billing emits the receipt for either `full_access` or legacy
`remove_ads`. The app generates a random 256-bit installation identifier in
Android Keystore-backed encrypted storage. A fresh Play Integrity Standard
verdict covers the v2 request hash, including that identifier.

The production Cloudflare Worker:
1. Limits requests by IP and purchase-token hash.
2. Confirms recent D1 voided-purchase synchronization and rejects revoked tokens.
3. Verifies the Play Integrity verdict and request hash (v2).
4. Queries Google Play Developer API for PURCHASED, matching product ID and
   non-refunded state.
5. Signs an Ed25519 grant with the Worker-only private key. Claims:
   `v`, `kid`, `pkg`, `productId`, `deviceId`, SHA-256 `receiptHash`,
   issued-at `iat`, and expiry `exp = iat + 259200` seconds.

The `/verify` endpoint responds with `{"status":"verified","offlineGrant":"<payload>.<signature>"}`
for v2 requests after successful verification. Existing v1 clients continue
receiving `{"status":"verified"}`. Rejected receipts never receive grants.
Signing-key configuration errors return unavailable (503) instead of unsigned
grants.

The app verifies the Ed25519 signature over the exact UTF-8 payload, package,
allowed product, installation ID, SHA-256 receipt hash syntax, key ID and
**exactly 72-hour** validity. An invalid or missing signature is not cached.
It stores the grant, random installation ID, monotonic-ish wall-clock high-water
mark and validated Google Play receipt in secure storage. The receipt is used
only for renewed authenticated verification, never as local proof of ownership.
It is not stored in ordinary SharedPreferences or included in telemetry.

On app foreground or explicit restore, the app attempts online verification
using the stored receipt. A rejection erases the grant and receipt immediately.
Temporary network failures do not extend the signed `exp`. When the app is
offline, the saved grant permits access only while valid; expiry terminates
offline entitlement until the next successful online verification.

## Key management: no keys in Git

**Never put private keys in Git, Android APK/AAB, dart-defines, screenshots or
logs.** Maintain separate keys for staging and production. Back up private
keys in an approved encrypted secret vault.

Generate an Ed25519 pair on a trusted server **outside the repo**:

```bash
bash scripts/generate-offline-signing-key.sh \
  "$HOME/.config/yomipalette-offline-keys/production"
```

The private key intended for Wrangler is `private.pkcs8.base64`. Only
`public.base64url` (32-byte Ed25519 key, encoded without padding) may be
distributed in Android builds. If the cloud machine is replaced, the private
key must already be safely backed up or rotated with a coordinated app update.

To configure the production Worker, from `backend/play-verifier` after the
key is generated, backed up and the secret destination is verified:

```bash
npx wrangler secret put OFFLINE_GRANT_PRIVATE_KEY_PKCS8 \
  --config wrangler.jsonc \
  < "$HOME/.config/yomipalette-offline-keys/production/private.pkcs8.base64"
```

`OFFLINE_GRANT_KEY_ID` must match the Worker environment (production
`ym-2026q4-prod`; staging `ym-2026q4-stg`). A key rotation requires a new
key ID and corresponding app build. Already issued 72-hour grants from the old
key stop validating after an incompatible app-key rotation unless an online
refresh obtains a newly signed grant. Do not silently rotate without a plan.

Build from Linux (or pass equivalent PowerShell parameters) after verifying
the key ID / public key refer to the same signing key:

```bash
export YOMIPALETTE_OFFLINE_GRANT_KEY_ID=ym-2026q4-prod
export YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY="$(cat "$HOME/.config/yomipalette-offline-keys/production/public.base64url")"
export YOMIPALETTE_BILLING_VERIFY_URL=https://yp-verify.t-and-i.date/verify
export YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER=<project number>
bash scripts/build-play-linux.sh
```

The Linux and Windows production build scripts refuse to create a release if
the public key or ID is missing. The app contains **only the public key**.
Do not publish without verifying the backend private key and Android public
key match and successfully completing Play-installed-device tests.

## Tests

```bash
cd backend/play-verifier
npm test && npm run check
cd ../..
flutter test --no-pub
flutter test --no-pub --dart-define=YOMIPALETTE_BILLING_QA=false \
  test/offline_entitlement_cache_test.dart
```

Important tests: real signing and signature verification, v1-v2 Play Integrity
hash compatibility, full_access/legacy grants, revoked/unpaid purchase
rejection, missing signing secret, client-side tampering, another public key,
installation binding, claim scope, 72-hour expiry, clock rollback, simulated
network outage, online re-verification and revocation after refund.

## Known limits / operations

- **72 hours is an offline maximum**, not a guarantee to work offline
  indefinitely. Before a paid entitlement is known and signed, offline access
  is not granted. The separately implemented 30-day trial remains unchanged.
- Google Play refunds are detected on **next successful authenticated online
  verification**, or immediately if a Play purchase update carries a rejected
  receipt. A fully offline device cannot learn about a refund before expiry.
- Local-clock rollback detection is best effort only; a rooted/compromised
  device can tamper with storage and time. Absolute elapsed-time protection
  across device reboots cannot be guaranteed without an online trusted clock.
- Device ID is installation-specific. Clearing app data / reinstalling loses
  the cached grant; users need to restore purchases while online.
- Azure/Google Cloud TTS still requires internet even if paid access is cached.
- Keep both private signing keys and customer Play purchase tokens out of
  logs and crash reports. Limit Cloudflare secret-reading permissions.
- Do not promote a staging build signed with a staging key to Play production.

## Deployment verification (2026-11-21)

- Staging Worker: `yomipalette-play-verifier-staging` on
  `https://yp-verify-stg.tiaozheng.dpdns.org`, version
  `82e9b268-256a-4fa8-ae2d-d70215b5bb36`.
- Staging signing secret `OFFLINE_GRANT_PRIVATE_KEY_PKCS8` installed;
  staging key ID `ym-2026q4-stg`. Public key is held in the trusted
  server-side key directory outside the repository.
- Live staging smoke tests: `GET /verify` yields HTTP 405,
  invalid `POST /verify` yields HTTP 400.
- Worker unit tests: 39 passed. Flutter unit tests: 140 passed with 6
  skipped in the pre-integration full regression, plus 14 focused tests
  passed with production QA mode explicitly disabled.
- No new offline entitlement code has been deployed to the production Worker;
  do not upload an Android build targeting production until the production
  signing key is installed and real Play-billing test coverage is complete.
