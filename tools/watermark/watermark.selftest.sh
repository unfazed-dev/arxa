#!/usr/bin/env bash
# tools/watermark/watermark.selftest.sh — provenance/watermark pass selftest.
#
# The licence tool (appboxd/bin/licence_tool.dart) is built concurrently, so
# these tests mock it via the documented env override APPBOX_LICENCE_STATUS
# (JSON string or a plain status word — it bypasses the dart call entirely).
# The fallback case points APPBOXD_DIR at a nonexistent dir: a missing/broken
# licence tool must degrade to "free" (watermarked), never block emission.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WM="$HERE/watermark.mjs"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

# plant <dir> — fixture tree covering every comment style + json skip.
plant() {
  local d="$1"
  mkdir -p "$d/lib" "$d/web" "$d/scripts"
  printf 'void main() {}\n'                 > "$d/lib/main.dart"
  printf 'export const x = 1;\n'           > "$d/lib/util.js"
  printf '<!DOCTYPE html>\n<html></html>\n' > "$d/web/index.html"
  printf 'name: fixture\n'                 > "$d/pubspec.yaml"
  printf '#!/bin/sh\necho hi\n'            > "$d/scripts/run.sh"
  printf '{"a":1}\n'                       > "$d/data.json"
}

count_marker() { grep -c 'appbox:provenance' "$1" || true; }

echo "== free tier: watermark inside the provenance block, every style =="
plant "$TMP/free"
APPBOX_LICENCE_STATUS=free node "$WM" "$TMP/free" >/dev/null
grep -q 'Built with app-box (free tier)' "$TMP/free/lib/main.dart" \
  && ok "dart: // block with watermark" || bad "dart block missing watermark"
grep -q 'Built with app-box (free tier)' "$TMP/free/lib/util.js" \
  && ok "js: // block with watermark" || bad "js block missing watermark"
grep -q 'Built with app-box (free tier)' "$TMP/free/pubspec.yaml" \
  && ok "yaml: # block with watermark" || bad "yaml block missing watermark"
grep -q 'Built with app-box (free tier)' "$TMP/free/web/index.html" \
  && ok "html: <!-- --> block with watermark" || bad "html block missing watermark"
grep -q 'Built with app-box (free tier)' "$TMP/free/scripts/run.sh" \
  && ok "sh: # block with watermark" || bad "sh block missing watermark"
[ "$(head -1 "$TMP/free/scripts/run.sh")" = '#!/bin/sh' ] \
  && ok "sh: shebang still line 1" || bad "shebang displaced"
[ "$(head -1 "$TMP/free/web/index.html")" = '<!DOCTYPE html>' ] \
  && ok "html: doctype still line 1" || bad "doctype displaced"
! grep -q 'appbox:provenance' "$TMP/free/data.json" \
  && ok "json: untouched (no comment syntax)" || bad "json was modified"

echo "== manifest: paths, sha256, tier, json note =="
M="$TMP/free/.appbox-provenance.json"
[ -f "$M" ] && ok "manifest written" || bad "manifest missing"
node -e '
  const fs = require("fs"), crypto = require("crypto"), path = require("path");
  const root = process.argv[1];
  const m = JSON.parse(fs.readFileSync(path.join(root, ".appbox-provenance.json"), "utf8"));
  const byPath = Object.fromEntries(m.files.map((f) => [f.path, f]));
  const bad = [];
  if (m.tier !== "free") bad.push("tier != free");
  if (!m.ts) bad.push("no ts");
  for (const rel of ["lib/main.dart", "lib/util.js", "web/index.html", "pubspec.yaml", "scripts/run.sh", "data.json"]) {
    const e = byPath[rel];
    if (!e) { bad.push("missing " + rel); continue; }
    const real = crypto.createHash("sha256").update(fs.readFileSync(path.join(root, rel))).digest("hex");
    if (e.sha256 !== real) bad.push("sha256 mismatch " + rel);
  }
  if (!byPath["data.json"].note) bad.push("json entry lacks skip note");
  if (bad.length) { console.error("  " + bad.join("; ")); process.exit(1); }
' "$TMP/free" && ok "manifest entries + sha256 correct" || bad "manifest incorrect"

echo "== paid tier: provenance only, no watermark line =="
plant "$TMP/paid"
APPBOX_LICENCE_STATUS='{"status":"paid","tier":"pro","expires":"2099-01-01"}' \
  node "$WM" "$TMP/paid" >/dev/null
grep -q 'appbox:provenance' "$TMP/paid/lib/main.dart" \
  && ok "paid: provenance block present" || bad "paid: provenance missing"
if grep -q 'Built with app-box' "$TMP/paid/lib/main.dart"; then
  bad "paid: watermark line leaked into clean output"
else
  ok "paid: no watermark line"
fi
node -e '
  const m = JSON.parse(require("fs").readFileSync(process.argv[1] + "/.appbox-provenance.json", "utf8"));
  process.exit(m.tier === "paid" ? 0 : 1);
' "$TMP/paid" && ok "paid: manifest tier=paid" || bad "paid: manifest tier wrong"

echo "== idempotency: a second pass injects nothing twice =="
before="$(sha256sum "$TMP/paid/lib/main.dart" | cut -d' ' -f1)"
APPBOX_LICENCE_STATUS=paid node "$WM" "$TMP/paid" >/dev/null
after="$(sha256sum "$TMP/paid/lib/main.dart" | cut -d' ' -f1)"
[ "$before" = "$after" ] && ok "second pass left file byte-identical" || bad "second pass rewrote file"
n="$(APPBOX_LICENCE_STATUS=free node "$WM" "$TMP/free" >/dev/null; count_marker "$TMP/free/lib/main.dart")"
[ "$n" = "1" ] && ok "exactly one provenance block after re-run" || bad "duplicate block ($n)"

echo "== licence tool missing: degrade to free, never block =="
plant "$TMP/notool"
env -u APPBOX_LICENCE_STATUS APPBOXD_DIR="$TMP/does-not-exist" \
  node "$WM" "$TMP/notool" >/dev/null
grep -q 'Built with app-box (free tier)' "$TMP/notool/lib/main.dart" \
  && ok "missing licence tool => free-tier watermark" || bad "missing tool did not fall back to free"

echo
echo "selftest: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
