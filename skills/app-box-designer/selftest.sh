#!/usr/bin/env bash
# app-box-designer selftest.
#
# Scaffolds a throwaway producer from the starter and asserts the structural
# contract holds. Every check must be able to FAIL — run with --negative to
# prove it (that mode breaks the fixture on purpose and expects a non-zero
# exit).
#
#   ./selftest.sh                        # the starter; expect exit 0
#   ./selftest.sh <artifact-dir>         # a real artifact; expect exit 0
#   ./selftest.sh [<dir>] --negative     # break one surfaceId; expect exit 1
#
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEGATIVE=0
SRC=""
for a in "$@"; do
  case "$a" in
    --negative) NEGATIVE=1 ;;
    -*) printf 'unknown flag: %s\n' "$a" >&2; exit 64 ;;
    *)  SRC="$a" ;;
  esac
done
# Default to the starter. A path that does not exist is a FAILURE, never a
# silent fallback — greening the starter while the caller named an artifact is
# exactly the false pass this file exists to prevent.
if [ -n "$SRC" ]; then
  [ -d "$SRC" ] || { printf 'no such artifact dir: %s\n' "$SRC" >&2; exit 64; }
else
  SRC="$SKILL/examples/hello-hda"
fi
printf 'artifact: %s\n\n' "$SRC"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ART="$WORK/artifact"
cp -R "$SRC" "$ART"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$1" = 0 ]; then ok "$2"; else bad "$2${3:+ — $3}"; fi; }

if [ "$NEGATIVE" = 1 ]; then
  # Break whichever artifact was given, not a filename only the starter has.
  VICTIM="$(find "$ART/ui/views" -name '*_viewmodel.js' | sort | head -1)"
  [ -n "$VICTIM" ] || { echo "negative mode: no viewmodel to break" >&2; exit 64; }
  echo "negative mode: removing surfaceId from ${VICTIM#"$ART/"}"
  perl -ni -e "print unless /export const surfaceId/" "$VICTIM"
fi

echo "== structure =="

# --- 1. the registry parses and has the required keys -----------------------
REG="$ART/models/screens_model/registry.json"
OUT="$(node -e '
const fs = require("fs");
const r = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(r) || r.length === 0) { console.error("registry is not a non-empty array"); process.exit(1); }
const need = ["id","label","surface","tab","comp"];
let bad = 0;
for (const e of r) for (const k of need)
  if (!(k in e)) { console.error(`entry ${e.id ?? "?"} missing key: ${k}`); bad++; }
if (bad) process.exit(1);
console.log(JSON.stringify({
  total: r.length,
  buildable: r.filter(e => e.surface).length,
  excluded: r.filter(e => !e.surface).length,
}));
' "$REG" 2>&1)"
check $? "registry parses with required keys" "$OUT"
echo "       $OUT"

# --- 2. no separate exclusions list (surface:null IS the exclusion) ---------
[ ! -e "$ART/exclusions.json" ]
check $? "no exclusions.json — surface:null is the exclusion"

# --- 3. every viewmodel declares a surfaceId -------------------------------
MISSING=""
while IFS= read -r f; do
  grep -q 'export const surfaceId' "$f" || MISSING="$MISSING${MISSING:+, }${f#"$ART/"}"
done < <(find "$ART/ui/views" -name '*_viewmodel.js')
[ -z "$MISSING" ]
check $? "every viewmodel declares surfaceId" "missing in: $MISSING"

# --- 4. every declared surfaceId resolves to a registry entry --------------
OUT="$(node -e '
const fs = require("fs"), path = require("path"), cp = require("child_process");
const [reg, ui] = process.argv.slice(1);
const ids = new Set(JSON.parse(fs.readFileSync(reg, "utf8")).map(e => e.id));
const files = cp.execSync(`find ${JSON.stringify(ui)} -name "*_viewmodel.js"`).toString().trim().split("\n").filter(Boolean);
let bad = 0;
for (const f of files) {
  const m = fs.readFileSync(f, "utf8").match(/export const surfaceId\s*=\s*[\x27"]([^\x27"]+)/);
  if (!m) continue;
  if (!ids.has(m[1])) { console.error(`${path.basename(f)}: surfaceId "${m[1]}" matches no registry entry`); bad++; }
}
process.exit(bad ? 1 : 0);
' "$REG" "$ART/ui/views" 2>&1)"
check $? "every surfaceId joins a registry entry" "$OUT"

# --- 5. coverage: buildable entries have a directory -----------------------
OUT="$(node -e '
const fs = require("fs"), cp = require("child_process");
const [reg, ui] = process.argv.slice(1);
const files = cp.execSync(`find ${JSON.stringify(ui)} -name "*_viewmodel.js"`).toString();
const declared = new Set([...files.matchAll(/[^\n]+/g)].map(m => m[0])
  .map(f => (fs.readFileSync(f, "utf8").match(/surfaceId\s*=\s*[\x27"]([^\x27"]+)/) || [])[1])
  .filter(Boolean));
let bad = 0;
for (const e of JSON.parse(fs.readFileSync(reg, "utf8"))) {
  if (e.surface && !declared.has(e.id)) { console.error(`registry "${e.id}" is buildable but no viewmodel declares it`); bad++; }
}
process.exit(bad ? 1 : 0);
' "$REG" "$ART/ui/views" 2>&1)"
check $? "every buildable registry entry has a surface" "$OUT"

# --- 6. tabRoots exported and non-empty ------------------------------------
OUT="$(node --input-type=module -e '
const m = await import(process.argv[1]);
if (!m.tabRoots || Object.keys(m.tabRoots).length === 0) { console.error("tabRoots missing or empty"); process.exit(1); }
console.log(Object.keys(m.tabRoots).join(", "));
' "$ART/app.routes.js" 2>&1)"
check $? "app.routes.js exports a non-empty tabRoots" "$OUT"

# --- 7. viewmodels do not reach past facades -------------------------------
LEAK="$(grep -rl "repositories/" "$ART/ui" 2>/dev/null || true)"
[ -z "$LEAK" ]
check $? "no viewmodel imports a repository directly" "$LEAK"

# --- 8. fixtures are generated, not authored -------------------------------
UNGEN="$(grep -Lr '_generated_from' "$ART"/models/*/*_fixtures.json 2>/dev/null || true)"
[ -z "$UNGEN" ]
check $? "fixtures record their seed provenance" "$UNGEN"

# --- 9. the ladder is documented, configured, and unhardcoded in code ------
[ -f "$SKILL/references/viewport-ladder.md" ]
check $? "references/viewport-ladder.md exists"

[ -f "$SKILL/runtime/ladder.json" ]
check $? "runtime/ladder.json exists — the ladder is config, not code"

# the doc and the config must agree; a doc that drifts from the config is how a
# width nothing checks gets designed against
OUT="$(node "$SKILL/runtime/check_ladder.mjs" 2>&1)"
check $? "ladder.json and viewport-ladder.md agree; no rung on a boundary" "$OUT"
# A line may opt out with a `ladder-exempt:` marker stating why it is not an
# app viewport. Exemptions are per-line and visible in the diff — never a
# blanket file skip.
HARD="$(grep -anE '\b(390|744|1280)\b' \
          "$SKILL"/runtime/*.mjs "$SKILL"/runtime/lib/*.mjs "$SKILL"/agents/*.mjs 2>/dev/null \
        | grep -v 'ladder-exempt:' || true)"
[ -z "$HARD" ]
check $? "no ladder width hardcoded in skill code" "$HARD"

# --- 10. no upstream identity leaked --------------------------------------
# The pattern is assembled so this file does not match itself.
U="$(printf 'k%s\\|b%s\\|h%s\\|j%s\\|f%s' imi aoyu uashu imliu lutter-crew)"
# runtime/vendor IS scanned — it was verified clean, so there is no reason to
# carve it out. node_modules is gitignored and not part of the deliverable.
LEFT="$(grep -rlIi "$U" "$SKILL" --exclude=LICENSE --exclude=selftest.sh \
        --exclude-dir=node_modules 2>/dev/null || true)"
[ -z "$LEFT" ]
check $? "no upstream references outside LICENSE" "$LEFT"

# --- 11. mutations answer with a swap, not a full page reload --------------
# `h.refresh` sets HX-Refresh: true — the browser reloads. A POST answered that
# way is a form post wearing htmx's coat: same reload, but now it needs JS to
# work at all, and under the standard responseHandling a 4xx fails silently.
# Every other check here is a prohibition; nothing else notices an artifact
# that carries htmx and uses none of it. A line may opt out with a
# `refresh-exempt:` marker stating why a swap cannot do the job (the theme flip
# is the real one: body/#app attributes are outside any swap target).
RELOAD="$(find "$ART/ui" -name '*_viewmodel.js' -exec awk '
  FNR == 1        { ok = -99 }
  /refresh-exempt:/ { ok = FNR }
  /h\.refresh\(/  { if (FNR - ok > 4) print FILENAME ":" FNR ": " $0 }
' {} + 2>/dev/null || true)"
[ -z "$RELOAD" ]
check $? "no mutation answers with a full reload" "$RELOAD"

echo
echo "== render (skipped unless Node deps are installed) =="
if [ -d "$SKILL/runtime/node_modules" ]; then
  node "$SKILL/runtime/lint.mjs" "$ART" >/dev/null 2>&1
  check $? "zero-custom-client-JS lint"
else
  echo "  skip  runtime/node_modules absent — run: (cd $SKILL/runtime && npm install)"
  echo "        a skipped check is NOT a pass; the render gate is unverified"
fi

echo
echo "passed $PASS, failed $FAIL"
if [ "$NEGATIVE" = 1 ]; then
  if [ "$FAIL" -gt 0 ]; then
    echo "negative case OK: the broken fixture was caught"; exit 1
  fi
  echo "NEGATIVE CASE DID NOT FAIL — the checks cannot detect a missing surfaceId"; exit 2
fi
[ "$FAIL" -eq 0 ]
