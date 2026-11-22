# YomiPalette entitlement diagnostics — internal-test only

This instrumentation distinguishes the three boundaries in a 72-hour signed
offline entitlement. **No receipt, purchase token, device identifier,
key, signed payload, signature, request/response body, or exception text
is written to a diagnostic log.** Only predefined enum codes are emitted.

## Android stages

Build-time switch: `YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS=true`.
The default is false in every ordinary release. When enabled, Android emits
`YP_ENTITLEMENT <fixed_code>` to logcat (no dynamic values).

1. **Worker call**: `verifyDeviceScoped`, `verifyIntegrityReady`,
   `verifyWorkerRequest`, then either `verifyWorkerSignedGrantPresent`,
   `verifyWorkerSignedGrantMissing`, or a fixed failure code.
2. **Signature and claims**: `grantSignatureValid` /
   `grantSignatureInvalid`, followed by `grantClaimsValid` /
   `grantClaimsInvalid` or `grantClockInvalid`.
3. **Encrypted storage**: `grantWriteSucceeded`,
   `grantReadbackSucceeded`, `grantAccepted`, and
   `receiptWriteSucceeded` / `receiptReadbackSucceeded`.
4. **Cold start offline**: `storageDeviceReused`, `storedGrantValid`,
   `storageInitSucceeded`. `storedGrantMissing`,
   `storedGrantInvalid`, or `storageInitFailed` indicates the boundary
   to investigate. The app must show the permanent purchase entitlement
   after a forced stop and offline relaunch.

`verifyWorkerSignedGrantPresent` shows that the response contained a
signature-bearing grant field. `grantSignatureValid` confirms the client
verified its Ed25519 signature; `grantReadbackSucceeded` checks a secure
storage read immediately after write. These are distinct assertions.

## Worker stages

The production Worker emits **no new diagnostic logs by default**. If
`OFFLINE_GRANT_DIAGNOSTICS` is temporarily set to `1`, it emits only
`YP_ENTITLEMENT_WORKER grant_issued`,
`YP_ENTITLEMENT_WORKER grant_signing_failed`, or
`YP_ENTITLEMENT_WORKER verified_without_device`.
Remove the opt-in setting after the internal-test investigation. Never
log raw requests or exception objects.

## Internal Play build

From `instabox-cloud-android`, with the existing trusted key and
Google Play signing setup:

```bash
export YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS=1
# Set the usual YOMIPALETTE_BILLING_VERIFY_URL,
# YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER,
# YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY and KEY_ID.
bash scripts/build-play-linux.sh
```

Install the resulting **Play-uploaded** AAB via Google Play Internal Test.
Do not sideload an APK with the Play upload key over the Play-signed app.

For the S9 connected by USB, while the app is running:

```powershell
adb -s 2492676c25017ece logcat -v brief | Select-String YP_ENTITLEMENT
```

Do not export full logcat, which can contain data from unrelated applications.
Test online restore, airplane/Wi-Fi+mobile disconnect, force-stop and offline
restart, then restore radios to their original state. Do not clear app storage,
reset the trial, adjust the device clock, or initiate refunds as part of this
diagnostic test.

## Failure interpretation

- `verifyWorkerSignedGrantMissing`: online entitlement without a signed
  device-scoped grant. Examine request version and Worker signing.
- `grantSignatureInvalid` / `grantClaimsInvalid`: mismatch between Worker
  and Android key/scope; do not bypass signature verification.
- `grantWriteSucceeded` but `grantReadbackFailed`: encrypted storage issue.
- `storedGrantMissing` after successful `grantReadbackSucceeded`: persistence
  or launch/installation issue; compare the installed Play package identity.
- `grantSaveFailed` with no `grantReadbackSucceeded`: storage or receipt
  write failure, with exception details intentionally suppressed.
- `verifyLegacyFallback`: the device-bound signing verification path was
  not used. This must not grant a new 72-hour cache.

All diagnostic events must remain secret-free; never add dynamic identifiers
to this logging helper. Remove the internal-test build or disable the flag
before public Play promotion.

## Galaxy S9 reproduction and remediation (2026-11-22)

With Play-internal 0.2.7 (versionCode 15) installed, the following was observed:

- Online: `verifyWorkerSignedGrantPresent`, `grantSignatureValid`,
  `grantClaimsValid`, `grantWriteSucceeded`,
  `grantReadbackSucceeded`, `receiptReadbackSucceeded`.
- Following `am force-stop` and relaunch (both offline **and online**):
  `storageDeviceCreated` and `storedGrantMissing`.
- No data deletion, uninstall, purchase, or refund was performed.
  Thus the storage failure is independent of network connectivity.

Likely cause: `CredentialStore` enabled Android
`encryptedSharedPreferences:true` while `SignedOfflineEntitlementStore`
used the plugin's default `false`. In flutter_secure_storage 9.2.4,
the native `checkAndMigrateToEncrypted` routine can move all prefixed keys
from the legacy preferences file into encrypted preferences. Subsequent
reads through a default-options store then see the keys as missing.

For 0.2.8 (versionCode 16) both stores use the **same** central
`yomiPaletteAndroidSecureStorageOptions` with
`encryptedSharedPreferences:true` and `resetOnError:false`.
This retains Keystore protection; there is no plaintext fallback.
Do not clear any existing data while testing the migration.

Verification required on Play-installed 0.2.8 after online restore:
`storageDeviceReused`, `storedGrantValid`,
`storedGrantUsable` following an **offline** cold start,
and the purchase screen must still show permanent access.

This is a source-based diagnosis, not yet a confirmed resolution until
the S9 Play-installed 0.2.8 test passes.
