# Google Play review access

Japanese device test steps and result forms are available in
[the device test specification](play_review_access_device_test.ja.md).

## Staging deployment verification, November 28, 2026

Deployed Worker `yomipalette-play-verifier-staging`, version
`d63b20f7-b251-47e5-a72e-7692a31766dd`, serves
`https://yp-verify-stg.tiaozheng.dpdns.org/review`.
Migration `0003_review_access.sql` was applied to the staging D1 database
`bb5bfaab-3401-445d-ab8c-127f4ca7aec2`. The common review token is configured
as Worker Secret `REVIEW_ACCESS_TOKEN`. Its local copy is held outside the
repository in the signing directory, with access restricted to the Windows
user and SYSTEM. The temporary upload file was removed after deployment.

Live HTTPS checks passed for invalid-token rejection, two independent
registrations with the same token, credential refresh, installation mismatch
rejection, individual revocation and continued access for the other installation.
Returned grants were verified against the staging public key embedded in the
build-20 APK and AAB, including the review schema and 72-hour validity.
Both synthetic registrations were revoked after verification.

Existing deployed bindings and public variables were preserved. The existing
trial and purchase-revocation tables each retained one row. Existing `/verify`
and `/trial` routes remained reachable. These checks cover server-side behavior.
The device test cases, including actual 72-hour offline operation, remain to be
performed on the prepared artifacts.

Deployment used Wrangler 4.157.0, an explicit staging config, `--keep-vars` and
a protected JSON `--secrets-file`. The relevant references are Cloudflare's
[Secrets documentation](https://developers.cloudflare.com/workers/configuration/secrets/)
and [D1 command documentation](https://developers.cloudflare.com/workers/wrangler/commands/d1/).

## Access and lifecycle

Open **About this app → Google Play review**, enter the reusable Console token,
and select **Activate review access**. The app shows **Review access** and hides
purchase and trial prompts while a signed review grant is valid. Preview, MP3
generation, import, resume and folder selection use the regular app paths.
**End review access** deletes only the review registration and grant, allowing
the reviewer to inspect normal trial and purchase screens again.

`POST /review` accepts `action=register`, `packageName`, `deviceId` and `token`.
The token stays in memory only for the request. The Worker issues a random
256-bit refresh credential, storing only its SHA-256 digest in D1. The app
stores the credential in Android Keystore-backed secure storage. Refresh sends
`action=refresh`, `packageName`, `deviceId` and `credential`.

Grants have `v=3`, `kind=review`, package, installation ID, key ID, issued time
and a 72-hour expiry, signed with Ed25519. The client verifies all these fields,
the signature and clock rollback. Purchase and trial stores reject this schema.
Review access never writes trial start dates, purchase receipts or full_access.

The app rechecks online on startup and foreground resume. While open, it checks
every five minutes and renews when 24 hours or less remain, including after an
outage. Connection recovery can therefore take up to five minutes, or the user
can press **Refresh review access**. Network errors and 429/5xx preserve the
credential and any still-valid grant. Expiry blocks review access until a valid
refresh. An explicit 401 on refresh clears the review grant and credential.
Clearing app data or reinstalling requires the Console token again.

This endpoint authenticates review credentials without Play Integrity or Google
sign-in. Purchase and trial endpoints retain their current Integrity checks.
The installation ID scopes the grant and refresh credential. The credential is
a bearer secret, and copying both it and the installation ID can clone access.
Individual revocation limits that exposure. Physical Play review devices and
end-to-end TTS generation still require internal-track validation.

## Deployment configuration

Apply `backend/play-verifier/migrations/0003_review_access.sql` to the intended
D1 database before deploying the Worker. It uses the existing `ENTITLEMENTS_DB`,
`VERIFY_IP_RATE_LIMIT`, `VERIFY_TOKEN_RATE_LIMIT`, `OFFLINE_GRANT_KEY_ID` and
`OFFLINE_GRANT_PRIVATE_KEY_PKCS8` bindings. Registration is IP-limited before
body parsing. Refresh additionally uses the hashed-credential limiter.

Set Worker Secret `REVIEW_ACCESS_TOKEN` to a cryptographically random value,
for example a base64url encoding of 32 random bytes. Use 32–512 characters.
Keep it in a secret manager and Play Console only. Never put it in source,
Flutter defines, command arguments, screenshots or request logs.

For routine rotation, temporarily set Secret `REVIEW_ACCESS_TOKEN_PREVIOUS`,
install the new primary Secret, update Console, verify the new token, then
remove the previous Secret. Existing refresh credentials continue to work.
For a leaked common token, remove its acceptance and revoke affected registrations.
A registration-only revocation cannot stop someone who still knows an accepted
Console token from registering again. Avoid automatic token expiration or a
global failed-attempt lock that could block reviewers in other locations.

List registrations by digest, installation ID and creation date through trusted
D1 administration. Revoke a selected registration with a bound parameter query
using its `credential_hash`.

```sql
UPDATE review_installations
SET revoked_at_ms = ?
WHERE credential_hash = ?;
```

Use the current Unix timestamp in milliseconds for the first parameter. The
next refresh is rejected. Already-issued offline grants remain usable until
expiry unless the client receives the rejection earlier. No public admin or
revocation endpoint is exposed.

Build with `YOMIPALETTE_REVIEW_ACCESS_URL=https://YOUR_WORKER/review`.
The verifier defaults to the purchase public key and key ID. For a different
Worker signing configuration, also provide `YOMIPALETTE_REVIEW_GRANT_PUBLIC_KEY`
and `YOMIPALETTE_REVIEW_GRANT_KEY_ID`. These are public verification parameters.
The PowerShell Play build script accepts `-ReviewAccessUrl`,
`-ReviewGrantPublicKey` and `-ReviewGrantKeyId`, with the corresponding environment
variables as defaults. Direct Flutter builds accept the same names via
`--dart-define`. Without an endpoint the review entry remains visible and
activation is unavailable. A submitted review build must include the endpoint
and matching public key. Configure the backend and verify it before submission.
The Linux Play build script also accepts these three environment variables.

## English Play Console instructions

Replace the token placeholder in Console only. Confirm the TTS and storage steps
on the submitted build and a clean device before registering these instructions.

> No in-app Google account sign-in or purchase is required for review access.
> Open About this app (the information icon in the top bar), then Google Play
> review. Enter the reusable review token supplied in the credentials field and
> tap Activate review access. The app displays Review access. The same token
> works on multiple devices and after clearing app data or reinstalling.
> Connect to the internet for activation and automatic renewal. Access remains
> available offline for up to 72 hours after a successful activation or renewal.
> After a longer offline period, reconnect and tap Refresh review access.
> To inspect the ordinary trial and purchase screens, return to Google Play
> review and tap End review access. You can reactivate with the same token.

Provide a small TXT/EPUB/text PDF sample and verified steps for selecting an
installed Android TTS engine and voice, previewing, and saving an MP3. Azure
and Google Cloud providers require their own service credentials. Review access
unlocks app features and does not supply those provider credentials. The app
also supports Edge TTS without an API key, subject to that service's availability.

## Acceptance checks

- Clean install, two devices and reinstall all activate with the same token.
- Restart restores access without Google sign-in or token re-entry.
- Preview, MP3 generation, resume and export work through regular UI paths.
- Disconnect within 72 hours, then expire offline, reconnect and renew.
- Test Worker outage, 429, invalid signatures and device mismatch.
- Revoke one digest and confirm refresh rejects it while another device works.
- End review access on a purchased and a trial account and confirm their
  original rights and trial start dates persist.
- Verify all three languages and the English Console instructions.
