# YomiPalette Android development on Lenovo

**Development host:** Lenovo Windows, `C:\CodexWorkspace\yomipalette-android`.

**Active working branch (November 2026):** `diagnostics/offline-entitlement-20261122` at or after `5bb0910`.

The repository was transferred from `instabox-cloud-android` through GitHub,
not by copying local build directories. The Lenovo pre-migration
`pubspec.yaml` version change was preserved in a Git stash labeled
`Lenovo pre-migration version 0.2.4+12 2026-11-22`.
Do not apply this old stash to the new branch.

## Responsibilities

- **Lenovo:** Flutter/Android app development, Play-upload AAB builds,
  Galaxy S9/S22 USB ADB testing and internal-test diagnostics.
- **instabox-cloud-android:** Cloudflare Worker, D1/RTDN, server tests and
  previously held server-side signing keys. Do not remove the cloud environment
  until backups and all server-side procedures are independently verified.
- **GitHub:** source of truth and transfer between hosts.

## Local Play signing

The existing Play-upload keystore, upload certificate, and properties are
kept outside Git in `%USERPROFILE%\.android\yomipalette-signing\`.
The **upload certificate** was verified against the cloud build certificate
(SHA-256 `9947a68658e2afba019bff36c9e21d8af097224495b6207029b2f1546111728b`).
The server-side **Ed25519 grant private key must never be copied into the app**.

The public half of the production offline-grant signing key is saved as
`%USERPROFILE%\.android\yomipalette-signing\offline-grant-public.base64url`.

## Build a real-billing internal-test diagnostic AAB

In a new PowerShell session:

```powershell
cd C:\CodexWorkspace\yomipalette-android
$env:YOMIPALETTE_BILLING_VERIFY_URL = 'https://yp-verify.tiaozheng.dpdns.org/verify'
$env:YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER = '22173932202'
$env:YOMIPALETTE_OFFLINE_GRANT_KEY_ID = 'ym-2026q4-prod'
$env:YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY = (Get-Content -Raw "$env:USERPROFILE\.android\yomipalette-signing\offline-grant-public.base64url").Trim()
.\scripts\build-play.ps1 -EntitlementDiagnostics
```

This is a **real Play purchase verification** build with only the
`YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS` flag enabled. Do **not** add
`-InternalTestBilling` for server-side purchase E2E tests.

Successful output:
`build\app\outputs\bundle\release\app-release.aab`.

Always verify the current `pubspec.yaml` build number, AAB signature and
file modification time. Do not mistake a stale AAB for the latest release.
Upload **only to Google Play internal testing**; never promote a diagnostic
AAB to production. Do not sideload the upload-key APK over a Play-signed app.

## S9 offline E2E

Use Lenovo USB ADB to update S9 via Play Internal Test, restore the entitlement
online, collect only the fixed `YP_ENTITLEMENT` diagnostics, then disable both
Wi-Fi and mobile data, force-stop/relaunch, and confirm `storedGrantUsable`.
Always restore radio states in a `finally` block. Never clear app data or
reinstall when testing persistence. Additional checks: `grantReadbackFailed`
must not recur after the 0.2.9 concurrent validation fix, 72-hour expiry
and refund revocation must still be tested.

## Notes

- Check `git status` before each branch switch or dependency update.
- Do not commit keystores, tokens, private keys, or `key.properties`.
- A different Flutter SDK version can rewrite `pubspec.lock`; review
  resolution-only changes before committing.
