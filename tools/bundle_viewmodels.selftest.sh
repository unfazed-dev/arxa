#!/usr/bin/env bash
# tools/bundle_viewmodels.selftest.sh — plan 09 step 9.3 selftest (R5: must fail).
#
# Happy path: bundles a real design and asserts the bundle exposes a non-empty
# routes table. Negative case: a viewmodel that imports a bare (non-relative,
# non-node:fs) spec must fail the bundler with exit 65 — shipping a half-bundle
# that silently dropped a dependency would be worse than a loud error.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BUNDLER="$HERE/bundle_viewmodels.js"
DESIGN="$ROOT/designs/appbox"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { echo "  ok   $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1"; fail=$((fail+1)); }

echo "== happy path: bundle the reference design =="
node "$BUNDLER" appbox --out "$TMP/happy" >/dev/null
if node -e "
  globalThis.__readFileSync = () => '';
  const c = require('fs').readFileSync('$TMP/happy/artifact.bundle.js','utf8');
  eval(c);
  const a = globalThis.__artifact;
  if (!a || !Array.isArray(a.default) || a.default.length === 0) process.exit(1);
  if (!a.tabRoots || Object.keys(a.tabRoots).length === 0) process.exit(2);
  process.exit(0);
"; then ok "bundle exposes routes + tabRoots"; else bad "bundle missing routes/tabRoots"; fi

echo "== negative case: a bare spec must fail the bundler (exit 65) =="
mkdir -p "$TMP/bad/ui/views/x"
cat > "$TMP/bad/app.routes.js" <<'EOF'
import { page } from 'some-bare-package';
export default [['GET', '/x', page]];
EOF
if node "$BUNDLER" "$TMP/bad" --out "$TMP/badout" >/dev/null 2>&1; then
  bad "bundler accepted a bare spec (should have exited 65)"
else
  ok "bundler rejected the bare spec"
fi

echo "== negative case: a missing entry (no app.routes.js) must fail (exit 66) =="
mkdir -p "$TMP/noentry"
if node "$BUNDLER" "$TMP/noentry" --out "$TMP/noeout" >/dev/null 2>&1; then
  bad "bundler accepted a dir with no app.routes.js"
else
  ok "bundler rejected the missing entry"
fi

echo
echo "selftest: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
