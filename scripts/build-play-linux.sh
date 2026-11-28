#!/usr/bin/env bash
# Build a signed Play AAB using the configured purchase-verification service.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
signing_dir="${YOMIPALETTE_SIGNING_DIR:-$HOME/.android/yomipalette-signing}"
properties="$signing_dir/key.properties"
cert="$signing_dir/upload-certificate.pem"
url="${YOMIPALETTE_BILLING_VERIFY_URL:-}"
project="${YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER:-}"
offline_key="${YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY:-}"
offline_key_id="${YOMIPALETTE_OFFLINE_GRANT_KEY_ID:-}"
google_web_client_id="${YOMIPALETTE_GOOGLE_WEB_CLIENT_ID:-}"
[[ -f "$properties" && -f "$cert" ]] || { echo 'Play signing properties or certificate missing.' >&2; exit 1; }
[[ "$url" =~ ^https://[^/]+/verify$ ]] || { echo 'Set YOMIPALETTE_BILLING_VERIFY_URL to the HTTPS /verify endpoint.' >&2; exit 1; }
[[ "$project" =~ ^[0-9]+$ && "$project" != 0 ]] || { echo 'Set YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER.' >&2; exit 1; }
[[ "$offline_key" =~ ^[A-Za-z0-9_-]{43}$ ]] || { echo 'Set YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY (Ed25519 base64url).' >&2; exit 1; }
[[ "$offline_key_id" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || { echo 'Set YOMIPALETTE_OFFLINE_GRANT_KEY_ID.' >&2; exit 1; }
[[ "$google_web_client_id" =~ ^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$ ]] || { echo 'Set YOMIPALETTE_GOOGLE_WEB_CLIENT_ID.' >&2; exit 1; }
for tool in flutter jarsigner keytool openssl sha256sum; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }; done
export ORG_GRADLE_PROJECT_PLAY_RELEASE=true
export ORG_GRADLE_PROJECT_PLAY_SIGNING_PROPERTIES="$properties"
cd "$repo"
marker="$(mktemp)"
trap 'rm -f "$marker"' EXIT
args=(build appbundle --release "--dart-define=YOMIPALETTE_BILLING_VERIFY_URL=$url" "--dart-define=YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER=$project" "--dart-define=YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY=$offline_key" "--dart-define=YOMIPALETTE_OFFLINE_GRANT_KEY_ID=$offline_key_id" "--dart-define=YOMIPALETTE_GOOGLE_WEB_CLIENT_ID=$google_web_client_id")
# Opt-in, fixed-code diagnostic logging for INTERNAL TEST builds only.
review_url="${YOMIPALETTE_REVIEW_ACCESS_URL:-}"
if [[ -n "$review_url" ]]; then
  [[ "$review_url" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?/review$ ]] || { echo 'Invalid HTTPS review endpoint.' >&2; exit 1; }
  args+=("--dart-define=YOMIPALETTE_REVIEW_ACCESS_URL=$review_url")
  review_key="${YOMIPALETTE_REVIEW_GRANT_PUBLIC_KEY:-$offline_key}"
  review_key_id="${YOMIPALETTE_REVIEW_GRANT_KEY_ID:-$offline_key_id}"
  [[ "$review_key" =~ ^[A-Za-z0-9_-]{43}$ && "$review_key_id" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || { echo 'Invalid review verifier public key or key ID.' >&2; exit 1; }
  args+=("--dart-define=YOMIPALETTE_REVIEW_GRANT_PUBLIC_KEY=$review_key" "--dart-define=YOMIPALETTE_REVIEW_GRANT_KEY_ID=$review_key_id")
fi
if [[ "${YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS:-0}" == 1 ]]; then
  args+=("--dart-define=YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS=true")
elif [[ "${YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS:-0}" != 0 ]]; then
  echo 'YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS must be 0 or 1.' >&2
  exit 1
fi
if [[ -n "${YOMIPALETTE_BUILD_NUMBER:-}" ]]; then
  [[ "$YOMIPALETTE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid build number.' >&2; exit 1; }
  args+=("--build-number=$YOMIPALETTE_BUILD_NUMBER")
fi
if [[ -n "${YOMIPALETTE_BUILD_NAME:-}" ]]; then args+=("--build-name=$YOMIPALETTE_BUILD_NAME"); fi
flutter "${args[@]}"
bundle="$repo/build/app/outputs/bundle/release/app-release.aab"
[[ -f "$bundle" && "$bundle" -nt "$marker" ]] || { echo 'New AAB not found.' >&2; exit 1; }
verify="$(jarsigner -J-Duser.language=en -J-Duser.country=US -verify "$bundle")"
[[ "$verify" == *'jar verified.'* && "$verify" != *'unsigned entries'* ]] || { echo 'AAB signature verification failed.' >&2; exit 1; }
expected="$(openssl x509 -in "$cert" -outform DER | sha256sum | cut -d' ' -f1)"
actual="$(keytool -J-Duser.language=en -J-Duser.country=US -printcert -rfc -jarfile "$bundle" | openssl x509 -outform DER | sha256sum | cut -d' ' -f1)"
[[ "$actual" == "$expected" ]] || { echo 'AAB signing certificate mismatch.' >&2; exit 1; }
echo "Verified Play upload bundle: $bundle"
sha256sum "$bundle"
echo 'Not uploaded to Play Console.'
if [[ "${YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS:-0}" == 1 ]]; then
  echo 'INTERNAL TEST DIAGNOSTICS ENABLED: Do not promote this AAB to public Play.'
fi
