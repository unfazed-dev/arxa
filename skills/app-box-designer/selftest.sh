#!/usr/bin/env bash
# app-box-designer selftest.
#
# Scaffolds a throwaway producer from the starter and asserts the structural
# contract holds.
#
# A check that has never been observed failing is not a check, it is a line
# that runs. `--negative` proves each one: it re-runs the whole selftest once
# per mutation in MUTATIONS below and requires the named check to flip. It used
# to break exactly one thing (surfaceId) and settle for "something failed",
# which left every other check unproven — and unproven is how this skill
# shipped four green results about the wrong thing.
#
#   ./selftest.sh                        # the starter; expect exit 0
#   ./selftest.sh <artifact-dir>         # a real artifact; expect exit 0
#   ./selftest.sh [<dir>] --negative     # prove every check can fail
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

# One deliberate break per check, and the check that must catch it. An `ok:`
# row is the inverse: the break must leave that check PASSING — that is the
# regression guard for the linter reading comments.
MUTATIONS='
registry-key|registry parses with required keys
exclusions-file|no exclusions.json
surface-id|every viewmodel declares surfaceId
orphan-id|every surfaceId joins a registry entry
uncovered-entry|every buildable registry entry has a surface
empty-tabroots|app.routes.js exports a non-empty tabRoots
repo-import|no viewmodel imports a repository directly
fixture-provenance|fixtures record their seed provenance
ladder-doc|references/viewport-ladder.md exists
ladder-config|runtime/ladder.json exists
ladder-drift|ladder.json and viewport-ladder.md agree
ladder-hardcode|no ladder width hardcoded in skill code
upstream-leak|no upstream references outside LICENSE
full-reload|no mutation answers with a full reload
client-js|zero-custom-client-JS lint
commented-js|ok:zero-custom-client-JS lint
'

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ART="$WORK/artifact"
cp -R "$SRC" "$ART"

mutate() {
  # Four checks assert on the SKILL, not the artifact, and their mutations
  # `rm -f` real files. Editing the skill to test the skill is how a test
  # becomes an outage, so the guard is that $SKILL is demonstrably a throwaway
  # copy — an env flag the caller sets would just be the same trust, moved.
  case "$1" in
    ladder-*|upstream-leak)
      case "$SKILL" in
        /tmp/*|/var/folders/*|/private/var/folders/*|/private/tmp/*) ;;
        *) printf 'refusing %s: it deletes files under %s; --negative runs it against a temp copy\n' "$1" "$SKILL" >&2
           exit 64 ;;
      esac ;;
  esac
  VM="$(find "$ART/ui/views" -name '*_viewmodel.js' | sort | head -1)"
  HTML="$(find "$ART/ui" -name '*_view.html' | sort | head -1)"
  FIX="$(ls "$ART"/models/*/*_fixtures.json 2>/dev/null | head -1)"
  REGJ="$ART/models/screens_model/registry.json"
  case "$1" in
    registry-key)       node -e 'const fs=require("fs"),f=process.argv[1],r=JSON.parse(fs.readFileSync(f));delete r[0].label;fs.writeFileSync(f,JSON.stringify(r,null,2))' "$REGJ" ;;
    exclusions-file)    : > "$ART/exclusions.json" ;;
    surface-id)         perl -ni -e 'print unless /export const surfaceId/' "$VM" ;;
    orphan-id)          node -e 'const fs=require("fs"),f=process.argv[1];fs.writeFileSync(f,fs.readFileSync(f,"utf8").replace(/(surfaceId\s*=\s*["\x27])[^"\x27]+/,"$1zzz.nope"))' "$VM" ;;
    uncovered-entry)    node -e 'const fs=require("fs"),f=process.argv[1],r=JSON.parse(fs.readFileSync(f));r.push({id:"zzz.ghost",label:"Ghost",surface:"ghost_view",tab:"main",comp:"Ghost"});fs.writeFileSync(f,JSON.stringify(r,null,2))' "$REGJ" ;;
    empty-tabroots)     node -e 'const fs=require("fs"),f=process.argv[1];fs.writeFileSync(f,fs.readFileSync(f,"utf8").replace(/export const tabRoots\s*=\s*\{[^}]*\}/,"export const tabRoots = {}"))' "$ART/app.routes.js" ;;
    # A real import would also break the module graph and prove less; that
    # check is a text scan, so the honest break is text.
    repo-import)        printf '// reaches services/repositories/x.js directly\n' >> "$VM" ;;
    fixture-provenance) perl -ni -e 'print unless /_generated_from/' "$FIX" ;;
    ladder-doc)         rm -f "$SKILL/references/viewport-ladder.md" ;;
    ladder-config)      rm -f "$SKILL/runtime/ladder.json" ;;
    ladder-drift)       node -e 'const fs=require("fs"),f=process.argv[1],j=JSON.parse(fs.readFileSync(f));j.rungs.compact.width+=1;fs.writeFileSync(f,JSON.stringify(j,null,2))' "$SKILL/runtime/ladder.json" ;;
    ladder-hardcode)    printf 'const _probe = 390;\n' >> "$SKILL/runtime/console-check.mjs" ;;
    upstream-leak)      printf 'k%s\n' imi > "$SKILL/LEAK.md" ;;
    full-reload)        printf 'export const _probe = (c, h) => h.refresh(c);\n' >> "$VM" ;;
    client-js)          printf '<div hx-on:click="alert(1)"></div>\n' >> "$HTML" ;;
    commented-js)       printf '{# hx-on:click is banned here — ADR-0002 #}\n' >> "$HTML" ;;
    *) printf 'unknown mutation: %s\n' "$1" >&2; exit 64 ;;
  esac
  printf 'mutation: %s\n\n' "$1"
}
[ -n "${SELFTEST_MUTATION:-}" ] && mutate "$SELFTEST_MUTATION"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$1" = 0 ]; then ok "$2"; else bad "$2${3:+ — $3}"; fi; }

if [ "$NEGATIVE" = 1 ]; then
  # Some mutations target the skill, so the runs happen against a throwaway
  # copy of it — BASH_SOURCE means the copy resolves its own $SKILL with no
  # override to keep in sync. node_modules is symlinked back, read-only.
  [ -d "$SKILL/runtime/node_modules" ] || {
    echo "negative mode needs runtime/node_modules — the lint mutations cannot be proven without it" >&2
    exit 64; }
  SK="$WORK/skill"
  mkdir -p "$SK"
  tar -cf - -C "$SKILL" --exclude node_modules . | tar -xf - -C "$SK"
  ln -s "$SKILL/runtime/node_modules" "$SK/runtime/node_modules"

  # A check that is ALREADY failing gets "proven" by every mutation, including
  # the ones that do not touch it — the free pass is the same shape as the bug
  # this mode exists to find, so the baseline must be green first. (It was not:
  # the starter's theme flip tripped the no-full-reload check, and every run
  # below would have reported that check as proven without doing anything.)
  BASE="$("$SK/selftest.sh" "$SRC" 2>&1)"
  if ! printf '%s\n' "$BASE" | grep -qF 'failed 0'; then
    echo "baseline is not green — mutations cannot prove anything against it:" >&2
    printf '%s\n' "$BASE" | grep -F '  FAIL' >&2
    exit 65
  fi

  # Nothing joins the table to the checks, so adding a 16th check tomorrow
  # would still print "proven, unproven 0" — an untested check counted as
  # tested, which is the exact shape of the defect this mode exists to kill.
  # Every label the baseline reported must be claimed by some row.
  UNMAPPED=""
  while IFS= read -r LBL; do
    HIT=0
    while IFS='|' read -r _ W; do
      [ -n "${W:-}" ] || continue
      case "$LBL" in "${W#ok:}"*) HIT=1 ;; esac
    done <<EOF
$MUTATIONS
EOF
    [ "$HIT" = 1 ] || UNMAPPED="$UNMAPPED${UNMAPPED:+; }$LBL"
  done < <(printf '%s\n' "$BASE" | sed -n 's/^  ok   //p')
  [ -z "$UNMAPPED" ] || {
    echo "checks with no mutation — they would be reported proven without ever being tested: $UNMAPPED" >&2
    exit 65; }

  echo "== falsifiability: one full run per mutation =="
  while IFS='|' read -r NAME WANT; do
    [ -n "${NAME:-}" ] || continue
    WANT_OK=0
    case "$WANT" in ok:*) WANT_OK=1; WANT="${WANT#ok:}" ;; esac
    OUT="$(SELFTEST_MUTATION="$NAME" "$SK/selftest.sh" "$SRC" 2>&1)"
    if [ "$WANT_OK" = 1 ]; then
      printf '%s\n' "$OUT" | grep -qF "ok   $WANT" \
        && ok "$NAME leaves \"$WANT\" passing" \
        || bad "$NAME broke \"$WANT\" — a comment is not behaviour"
    else
      printf '%s\n' "$OUT" | grep -qF "FAIL $WANT" \
        && ok "\"$WANT\" catches $NAME" \
        || bad "\"$WANT\" did NOT fail under $NAME — the check cannot detect it"
    fi
  done <<EOF
$MUTATIONS
EOF

  echo
  echo "proven $PASS, unproven $FAIL"
  [ "$FAIL" -eq 0 ]
  exit
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
# (plan 03: flutter-crew split further — f%s%s + lutter-cr + ew — so the bare
#  token 'crew' does not appear literally now that 'crew' is itself a stripped name.)
U="$(printf 'k%s\\|b%s\\|h%s\\|j%s\\|f%s%s' imi aoyu uashu imliu lutter-cr ew)"
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
[ "$FAIL" -eq 0 ]
