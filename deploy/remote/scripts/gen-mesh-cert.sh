#!/usr/bin/env bash
# gen-mesh-cert.sh — private mesh-CA root + wildcard leaf for the appbox tailnet.
# Port of arxa ADR-0036 (network/src/openssl.rs): every daemon web-builder origin
# is `https://<origin>.<slug>.<MESH_TLD>`, browser-trusted over the mesh once the
# CA root is installed at pairing. Re-running re-issues the leaf (auto-regen
# friendly) and NEVER re-roots an existing CA.
#
# Usage:  ./gen-mesh-cert.sh <slug> [outdir]
# Env:    MESH_TLD   (default: appbox)
#         LEAF_DAYS  (default: 825 — CA/Browser-Forum cap)
#         CA_DAYS    (default: 3650)
#         OPENSSL    (default: openssl; must be OpenSSL 3.x)
#
# Writes <outdir>/<slug>/{ca.key,ca.crt,leaf.key,leaf.crt}. Install ca.crt on
# clients at pairing; serve leaf.crt+leaf.key from the daemon's tls terminator.

set -euo pipefail
umask 077

SLUG="${1:?usage: gen-mesh-cert.sh <slug> [outdir]}"
OUT="${2:-./mesh-ca}"
MESH_TLD="${MESH_TLD:-appbox}"
LEAF_DAYS="${LEAF_DAYS:-825}"
CA_DAYS="${CA_DAYS:-3650}"
OPENSSL="${OPENSSL:-openssl}"

# Slug = one DNS label; keep it tight so the wildcard SAN is well-formed.
[[ "$SLUG" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
  echo "error: slug '$SLUG' must be a single lowercase DNS label" >&2; exit 2; }

command -v "$OPENSSL" >/dev/null || { echo "error: '$OPENSSL' not on PATH" >&2; exit 2; }
case "$("$OPENSSL" version)" in
  "OpenSSL 3"*) ;;
  *) echo "error: need OpenSSL 3.x (macOS ships LibreSSL; try: brew install openssl, OPENSSL=$(brew --prefix openssl)/bin/openssl)" >&2; exit 2 ;;
esac

DIR="$OUT/$SLUG"
WILDCARD="*.$SLUG.$MESH_TLD"
mkdir -p "$DIR"
CA_KEY="$DIR/ca.key"; CA_CRT="$DIR/ca.crt"
LEAF_KEY="$DIR/leaf.key"; LEAF_CSR="$DIR/leaf.csr"
LEAF_EXT="$DIR/leaf.ext"; LEAF_CRT="$DIR/leaf.crt"

# --- CA root: written once, idempotent (existing leaves are never orphaned). ---
if [[ ! -f "$CA_CRT" ]]; then
  "$OPENSSL" genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$CA_KEY"
  "$OPENSSL" req -x509 -new -key "$CA_KEY" -sha256 -days "$CA_DAYS" \
    -subj "/CN=appbox Mesh CA $SLUG" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "$CA_CRT"
  echo "created CA root:  $CA_CRT"
else
  echo "reusing CA root:  $CA_CRT"
fi

# --- Wildcard leaf: fresh every run (leaf rotation is cheap; re-rooting is not). ---
"$OPENSSL" genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$LEAF_KEY"
"$OPENSSL" req -new -key "$LEAF_KEY" -subj "/CN=$WILDCARD" -out "$LEAF_CSR"

# Signing extensions come from an extfile we author — NOT copied from the CSR —
# so a hostile CSR cannot smuggle in CA:TRUE or a wider SAN.
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n' \
  "$WILDCARD" > "$LEAF_EXT"

"$OPENSSL" x509 -req -in "$LEAF_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
  -days "$LEAF_DAYS" -sha256 -extfile "$LEAF_EXT" -out "$LEAF_CRT"

rm -f "$LEAF_CSR" "$LEAF_EXT" "$DIR/ca.srl"
chmod 600 "$CA_KEY" "$LEAF_KEY"; chmod 644 "$CA_CRT" "$LEAF_CRT"

"$OPENSSL" verify -CAfile "$CA_CRT" "$LEAF_CRT" >/dev/null

cat <<EOF
issued leaf:      $LEAF_CRT  (SAN $WILDCARD, ${LEAF_DAYS}d, serverAuth)
leaf key:         $LEAF_KEY
CA root to ship:  $CA_CRT    (install on clients at pairing)
EOF
