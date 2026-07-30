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
fragment-typo|every rendered fragment exists as a macro
orphan-post|every mutation route is reachable from markup
dead-url|every static URL in markup resolves to a route
dangling-target|every hx-target names an element that exists
emoji-icon|icons come from the icon() global, never emoji stand-ins
widget-partials|surfaces compose shared partials from ui/widgets
untracked-file|every artifact file is tracked by git
client-js|zero-custom-client-JS lint
commented-js|ok:zero-custom-client-JS lint
broken-route|every GET route answers 200
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
    # The wiring mutations each cut ONE strand of a join, which is the only
    # way to tell a join from a pair of independent greps.
    fragment-typo)      node -e 'const fs=require("fs");for(const f of process.argv.slice(1)){const s=fs.readFileSync(f,"utf8");if(/\{%\s*macro\s+\w+\s*\(/.test(s)){fs.writeFileSync(f,s.replace(/(\{%\s*macro\s+)(\w+)/,"$1$2zz"));break}}' $(find "$ART/ui" -name '*.html' | sort) ;;
    orphan-post)        node -e 'const fs=require("fs");for(const f of process.argv.slice(1)){const s=fs.readFileSync(f,"utf8");if(/hx-post="/.test(s)){fs.writeFileSync(f,s.replace(/hx-post="[^"]*"/,""));break}}' $(find "$ART/ui" -name '*.html' | sort) ;;
    dead-url)           node -e 'const fs=require("fs");for(const f of process.argv.slice(1)){const s=fs.readFileSync(f,"utf8");const r=/href="\/(?!assets\/|_ds\/)[^"{]*"/;if(r.test(s)){fs.writeFileSync(f,s.replace(r,String.raw`href="/zzz-nope"`));break}}' $(find "$ART/ui" -name '*.html' | sort) ;;
    dangling-target)    node -e 'const fs=require("fs");for(const f of process.argv.slice(1)){const s=fs.readFileSync(f,"utf8");if(/hx-target="#/.test(s)){fs.writeFileSync(f,s.replace(/hx-target="#[^"]*"/,String.raw`hx-target="#zznope"`));break}}' $(find "$ART/ui" -name '*.html' | sort) ;;
    # A text arrow is the same violation as an emoji: a stand-in wearing an
    # icon's hat. Both must flip the icons check.
    emoji-icon)         printf '<p>\xe2\x86\x92</p>\n' >> "$HTML" ;;
    widget-partials)    rm -rf "$ART/ui/widgets" ;;
    untracked-file)     printf 'stray\n' > "$ART/ui/stray.txt" ;;
    broken-route)       node -e 'const fs=require("fs"),f=process.argv[1];fs.writeFileSync(f,fs.readFileSync(f,"utf8").replace(/\[\s*.GET.\s*,\s*(.[^\x27"]+.)\s*,[^\]]+\]/,"[\x27GET\x27, $1, () => { throw new Error(\x27mutation\x27); }]"))' "$ART/app.routes.js" ;;
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

  # Nothing joins the table to the checks, so adding a new check tomorrow
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
    # Skipped checks are scanned too — a check that always skips is unproven
    # AND unmapped, which is the quietest way for one to rot. Safe to scan
    # here because the driver refuses to start without node_modules, so the
    # render section's own skip line cannot appear in a baseline.
  done < <(printf '%s\n' "$BASE" | sed -n 's/^  ok   //p; s/^  skip  //p')
  [ -z "$UNMAPPED" ] || {
    echo "checks with no mutation — they would be reported proven without ever being tested: $UNMAPPED" >&2
    exit 65; }

  echo "== falsifiability: one full run per mutation =="
  while IFS='|' read -r NAME WANT; do
    [ -n "${NAME:-}" ] || continue
    WANT_OK=0
    case "$WANT" in ok:*) WANT_OK=1; WANT="${WANT#ok:}" ;; esac
    # A check the baseline skipped cannot be proven here, and pretending
    # otherwise is the whole failure mode. Say skip and move on.
    if printf '%s\n' "$BASE" | grep -qF "  skip  $WANT"; then
      printf '  skip  %s — "%s" does not apply to this artifact\n' "$NAME" "$WANT"
      continue
    fi
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
# The pattern is assembled so this file does not match itself: each upstream
# identity token is split across the printf args (first char + rest), and the
# longest is split twice so no stripped name appears literally in this file.
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

# --- 12-15. wiring: the artifact must DO something, not merely avoid things --
# Everything above is a prohibition, and a prohibition passes vacuously on an
# empty artifact — strip every hx- attribute and the old suite still swept
# clean. These four are joins (markup against routes, viewmodels against
# templates); a join cannot pass when one side is missing.
for P in fragments mutations-posted urls-resolve targets-exist; do
  case "$P" in
    fragments)        LBL="every rendered fragment exists as a macro" ;;
    mutations-posted) LBL="every mutation route is reachable from markup" ;;
    urls-resolve)     LBL="every static URL in markup resolves to a route" ;;
    targets-exist)    LBL="every hx-target names an element that exists" ;;
  esac
  OUT="$(node "$SKILL/runtime/check_wiring.mjs" "$ART" "$P" 2>&1 >/dev/null)"
  check $? "$LBL" "$OUT"
done

# --- 16-17. the component library is real, and icons are vocabulary ---------
# The components-first contract (DESIGN-ARCHITECTURE "Shared components"):
# shared UI lives in `_*.html` partials under ui/widgets|dialogs|bottomsheets/
# (or macros in ui/common/) and surfaces pull them with {% include %} — a
# pattern used on two surfaces is extracted, never copied. And every glyph is
# the icon() global (vendored Lucide, inlined server-side): an emoji or a text
# arrow wearing an icon's hat is the same violation.
WID="$(find "$ART/ui/widgets" "$ART/ui/dialogs" "$ART/ui/bottomsheets" -name '_*.html' 2>/dev/null | head -1)"
if [ -n "$WID" ]; then
  grep -rq '{% include "ui/' "$ART/ui/views" 2>/dev/null
else
  grep -rq '{%[[:space:]]*macro' "$ART/ui/common" 2>/dev/null
fi
check $? "surfaces compose shared partials from ui/widgets"

EMOJI="$(perl -CSD -ne 'print "$ARGV:$.: $_" if /[\x{2190}-\x{21FF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F000}-\x{1FAFF}\x{FE0F}]/' $(find "$ART/ui" -name '*.html' | sort) 2>/dev/null)"
[ -z "$EMOJI" ] && grep -rq "icon('" "$ART/ui"
check $? "icons come from the icon() global, never emoji stand-ins" "$(printf '%s' "$EMOJI" | head -3 | tr '\n' ' ')"

# --- 18. the tree the gates read is the tree git has ------------------------
# Every check above runs on the WORKING TREE. That is right — work in progress
# has to be checkable — but it means a green suite says nothing about what a
# clone would get. A generic `build/` ignore once swallowed three surfaces out
# of a commit that reported 58 files and looked complete; every gate stayed
# green because no gate ever asked git. This one asks.
#
# Two branches, because "untracked file inside a repo" is the defect and "not
# in a repo at all" is not one — an ejected app and a scratch prototype have
# no git to disagree with. Reported as a visible skip, never a silent pass.
TRACKLBL="every artifact file is tracked by git"
if ( cd "$SRC" && git rev-parse --show-toplevel >/dev/null 2>&1 ); then
  OUT="$(
    git -C "$SRC" ls-files -z . | tr '\0' '\n' | LC_ALL=C sort > "$WORK/tracked.txt"
    ( cd "$ART" && find . -type f | sed 's|^\./||' ) | LC_ALL=C sort \
      | comm -23 - "$WORK/tracked.txt"
  )"
  [ -z "$OUT" ]
  check $? "$TRACKLBL" "$(printf '%s' "$OUT" | tr '\n' ' ')"
else
  printf '  skip  %s — not a git work tree; nothing to be inconsistent with\n' "$TRACKLBL"
fi

echo
echo "== render (skipped unless Node deps are installed) =="
if [ -d "$SKILL/runtime/node_modules" ]; then
  node "$SKILL/runtime/lint.mjs" "$ART" >/dev/null 2>&1
  check $? "zero-custom-client-JS lint"

  # The static joins above prove the wiring is consistent; this proves it runs.
  # A handler that throws is a 500 no amount of grepping will find.
  OUT="$(cd "$SKILL/runtime" && node --input-type=module -e '
const { createArtifactApp } = await import("./lib/router.mjs");
const { readFileSync } = await import("node:fs");
const dir = process.argv[1];
const app = await createArtifactApp(dir);
let bad = 0;
for (const m of readFileSync(dir + "/app.routes.js", "utf8")
       .matchAll(/\[\s*.GET.\s*,\s*.([^\x27"]+)./g)) {
  const res = await app.request(m[1]);
  if (res.status !== 200) { console.error(`GET ${m[1]} -> ${res.status}`); bad++; }
}
process.exit(bad ? 1 : 0);
' "$ART" 2>&1)"
  check $? "every GET route answers 200" "$OUT"
else
  echo "  skip  runtime/node_modules absent — run: (cd $SKILL/runtime && npm install)"
  echo "        a skipped check is NOT a pass; the render gate is unverified"
fi

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
