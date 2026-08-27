#!/usr/bin/env bash
# Mint a dev HS256 JWT for the arxa_kit_cairn "local live" harness: `sub`
# becomes both the account id and the tenant id (cairn-infra auth.rs's
# SupabaseJwtAuth — tenant-from-sub). Signature check + non-empty `sub` only
# (no exp/aud/iss), matching the server's HS256 verifier exactly.
#
# Usage: tool/mint_jwt.sh <sub>
#   tool/mint_jwt.sh user-a

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./live_env.sh

sub="${1:?usage: mint_jwt.sh <sub>}"

b64url() {
  openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

header='{"alg":"HS256","typ":"JWT"}'
payload="{\"sub\":\"$sub\"}"

header_b64=$(printf '%s' "$header" | b64url)
payload_b64=$(printf '%s' "$payload" | b64url)
signing_input="$header_b64.$payload_b64"
sig_b64=$(printf '%s' "$signing_input" | openssl dgst -sha256 -hmac "$CAIRN_DEV_JWT_SECRET" -binary | b64url)

echo "$signing_input.$sig_b64"
