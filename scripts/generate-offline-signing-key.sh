#!/usr/bin/env bash
# Creates a long-lived Ed25519 signing key OUTSIDE the repository. NEVER commit
# the private file or pass it as a Flutter dart-define.
set -euo pipefail
umask 077
target="${1:-$HOME/.config/yomipalette-offline-keys}"
if [[ -e "$target/private.pem" || -e "$target/private.pkcs8.base64" ]]; then
  echo 'Signing key already exists. Refusing to overwrite.' >&2
  exit 1
fi
mkdir -p "$target"
chmod 700 "$target"
openssl genpkey -algorithm ED25519 -out "$target/private.pem"
openssl pkey -in "$target/private.pem" -outform DER |
  openssl base64 -A > "$target/private.pkcs8.base64"
openssl pkey -in "$target/private.pem" -pubout -outform DER |
  tail -c 32 | openssl base64 -A | tr '+/' '-_' | tr -d '=' > "$target/public.base64url"
chmod 600 "$target/private.pem" "$target/private.pkcs8.base64" "$target/public.base64url"
[[ $(wc -c < "$target/public.base64url") -eq 43 ]] ||
  { echo 'Unexpected Ed25519 public key size.' >&2; exit 1; }
echo "Generated offline signing key in: $target"
echo 'Private key files must remain outside source control and be backed up securely.'
echo 'Public key (not secret):'
cat "$target/public.base64url"
echo
