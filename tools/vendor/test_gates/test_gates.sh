#!/usr/bin/env bash
# test_gates.sh — adversarial scenario tests for the stacked_kit gates + wiring.
#
# Smoke (happy paths), pressure (many kits / malformed input), and stress (payload
# matrix, idempotency, symlink edge cases) for: conventions.sh, doc-health.js,
# install.sh, gate.sh, validate_docs.sh, extract_facts.sh, capability_scan.sh,
# api_map_scan.sh.
#
# Each test plants a deliberate condition and asserts the gate's exit/output, so a
# behavior change is caught here, not in a real edit. bash 3.2-safe (no assoc
# arrays / mapfile / readlink -f). Deliberately NO `set -e` — one failure must not
# abort the suite.
#
#   tools/test_gates.sh              # full suite
#   tools/test_gates.sh -v           # verbose (show every PASS)
#   tools/test_gates.sh -g NAME      # one group: conventions|pressure|dochealth|install|gate|capscan|apimap|smoke|pipeline|fixity|translate|emit|structure|coverage
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
VERBOSE=0; WANT=""
while [ $# -gt 0 ]; do
  case "$1" in -v) VERBOSE=1;; -g) shift; WANT="${1:-}";; *) WANT="$1";; esac
  shift
done

PASS=0; FAIL=0; FAILED=()
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

say(){ printf '\n### %s\n' "$1"; }
ok(){ PASS=$((PASS+1)); [ "$VERBOSE" -eq 1 ] && echo "  PASS: $*"; return 0; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$*"); echo "  FAIL: $*"; return 0; }
run(){ ( "$@" ) 2>&1; echo "exit:$?"; }
has(){ [ "${2:-$out}" != "${2%%$1*}" ]; }   # substring test: has NEEDLE [HAY]

# fresh sandbox subdir with tools/conventions.sh copied in; echo its path
sb(){ local p="$SCRATCH/$1"; rm -rf "$p"; mkdir -p "$p/tools"; cp "$REAL/tools/conventions.sh" "$p/tools/"; echo "$p"; }

# make_kit <sb> <dirname> <pkgname> [dep...]  — writes a conformant kit
make_kit(){
  local sb=$1 d=$2 name=$3; shift 3
  mkdir -p "$sb/$d/lib/src"
  cat > "$sb/$d/pubspec.yaml" <<YAML
name: $name
description: test kit
publish_to: 'none'
environment:
  sdk: '>=3.0.3 <4.0.0'
YAML
  if [ $# -gt 0 ]; then
    printf 'dependencies:\n' >> "$sb/$d/pubspec.yaml"
    local dep; for dep in "$@"; do printf '  %s:\n' "$dep" >> "$sb/$d/pubspec.yaml"; done
  fi
  case "$d" in
    showcase_app) : ;;
    *) printf "library %s;\nexport 'src/x.dart';\n" "$name" > "$sb/$d/lib/$name.dart"
       printf "// testing seam\n" > "$sb/$d/lib/testing.dart" ;;
  esac
}

conv(){ ( cd "$1" && bash tools/conventions.sh ) 2>&1; echo "exit:$?"; }
conv_pass(){ has "exit:0" "$1"; }
conv_fail(){ has "exit:1" "$1"; }

# ---------------------------------------------------------------------------
test_conventions(){
  say "CONVENTIONS"; local s o
  s=$(sb c-clean);  make_kit "$s" alpha stacked_kit_alpha;                   conv_pass "$(conv "$s")" && ok "clean standalone kit passes" || bad "clean standalone should pass"
  s=$(sb c-nobarrel); make_kit "$s" alpha stacked_kit_alpha; rm "$s/alpha/lib/stacked_kit_alpha.dart"; conv_fail "$(conv "$s")" && ok "missing barrel fails" || bad "missing barrel should fail"
  s=$(sb c-nopubnone); make_kit "$s" alpha stacked_kit_alpha; sed -i '' "/publish_to/d" "$s/alpha/pubspec.yaml"; conv_fail "$(conv "$s")" && ok "missing publish_to fails" || bad "missing publish_to should fail"
  s=$(sb c-baddep);   make_kit "$s" alpha stacked_kit_alpha stacked_kit_media; conv_fail "$(conv "$s")" && ok "forbidden cross-kit dep fails" || bad "forbidden dep should fail (alpha not allowed media)"
  s=$(sb c-data-core); make_kit "$s" core stacked_kit_core; make_kit "$s" data stacked_kit_data stacked_kit_core; conv_pass "$(conv "$s")" && ok "data -> core allowed" || bad "data->core should pass"
  s=$(sb c-ui-core);  make_kit "$s" core stacked_kit_core; make_kit "$s" ui_library stacked_kit_ui_library stacked_kit_core; conv_pass "$(conv "$s")" && ok "ui_library -> core allowed" || bad "ui_library->core should pass"
  s=$(sb c-showall);  make_kit "$s" core stacked_kit_core; make_kit "$s" media stacked_kit_media; make_kit "$s" showcase_app stacked_kit_showcase_app stacked_kit_core stacked_kit_media; o=$(conv "$s"); conv_pass "$o" && ok "showcase_app -> all allowed (app, no barrel)" || bad "showcase_app->all should pass: $o"
  s=$(sb c-divsdk);   make_kit "$s" alpha stacked_kit_alpha; make_kit "$s" beta stacked_kit_beta; sed -i '' "s|sdk: '>=3.0.3 <4.0.0'|sdk: '>=2.17.0 <4.0.0'|" "$s/beta/pubspec.yaml"; conv_fail "$(conv "$s")" && ok "divergent SDK fails" || bad "divergent SDK should fail"
  s=$(sb c-notesting); make_kit "$s" alpha stacked_kit_alpha; rm "$s/alpha/lib/testing.dart"; o=$(conv "$s"); conv_pass "$o" && has "WARN" "$o" && ok "missing testing.dart warns (non-fatal)" || bad "testing.dart-missing should warn+pass: $o"
  s=$(sb c-malformed); mkdir -p "$s/odd/lib"; printf 'not a real pubspec\n' > "$s/odd/pubspec.yaml"; o=$(conv "$s"); has "syntax error" "$o" && bad "malformed pubspec caused bash error" || ok "malformed pubspec handled gracefully"
  s=$(sb c-empty);    o=$(conv "$s"); conv_pass "$o" && ok "empty tree passes (vacuous)" || bad "empty tree should pass: $o"
}

test_pressure(){
  say "PRESSURE"; local s i o
  s=$(sb p-50); for i in $(seq 1 50); do make_kit "$s" "k$i" "stacked_kit_k$i"; done
  o=$(conv "$s"); conv_pass "$o" && ok "50 clean kits pass" || bad "50 kits should pass: $(echo "$o" | tail -2)"
  # malformed + many: one broken among 30
  s=$(sb p-mixed); for i in $(seq 1 30); do make_kit "$s" "k$i" "stacked_kit_k$i"; done
  rm "$s/k15/lib/stacked_kit_k15.dart"
  conv_fail "$(conv "$s")" && ok "1 violation among 30 kits is caught" || bad "mixed 30 kits should fail on k15"
}

test_dochealth(){
  say "DOC_HEALTH"; local H="$REAL/hooks/doc-health.js" o
  dh(){ echo "$1" | node "$H" 2>&1; echo "exit:$?"; }
  # Hook contract (commit 5b0e372): clean doc edit → SILENT exit 0 (PostToolUse
  # exit-0 stdout never reaches the model, so emitting on clean is noise); dirty
  # doc edit → exit 2 + "[stacked_kit] doc-health found issues" — the only
  # PostToolUse→model channel. The repo is clean here, so every doc edit below is
  # silent exit 0; the last case plants a stale-path probe to prove the exit-2 path.
  o=$(dh '{"tool_name":"Edit","tool_input":{"file_path":"/x/payments/payments_playbook.mdx"}}');     has "exit:0" "$o" && ! has "doc-health" "$o" && ok "clean playbook edit: silent exit 0" || bad "clean playbook should be silent exit 0: $o"
  o=$(dh '{"tool_name":"Write","tool_input":{"file_path":"/stacked_kit/kb/sources.json"}}');          has "exit:0" "$o" && ! has "doc-health" "$o" && ok "clean kb/ edit: silent exit 0" || bad "clean kb edit should be silent exit 0: $o"
  o=$(dh '{"tool_name":"Edit","tool_input":{"file_path":"/x/stacked_kit_playbook.mdx"}}');            has "exit:0" "$o" && ! has "doc-health" "$o" && ok "clean parent-playbook edit: silent exit 0" || bad "clean parent playbook should be silent exit 0: $o"
  o=$(dh '{"tool_name":"Edit","tool_input":{"file_path":"/x/lib/foo.dart"}}');                       ! has "doc-health" "$o" && ok "non-doc .dart: silent" || bad "non-doc .dart should be silent: $o"
  o=$(dh '{"tool_name":"Edit","tool_input":{}}');                                                    has "exit:0" "$o" && ok "missing file_path fails open (exit 0)" || bad "missing file_path should exit 0: $o"
  o=$(dh 'not json at all');                                                                         has "exit:0" "$o" && ok "malformed JSON fails open (exit 0)" || bad "malformed JSON should fail open: $o"
  o=$(dh '');                                                                                        has "exit:0" "$o" && ok "empty stdin fails open (exit 0)" || bad "empty stdin should fail open: $o"
  o=$(dh '{"tool_name":"MultiEdit","tool_input":{"file_path":"/x/forms/forms_playbook.mdx"}}');      has "exit:0" "$o" && ! has "doc-health" "$o" && ok "clean MultiEdit on playbook: silent exit 0" || bad "clean MultiEdit should be silent exit 0: $o"
  # exit-2 branch + symlink self-location in one shot: plant a stale-path probe
  # (check 3 scans */*_playbook.mdx), run the hook THROUGH a symlink in a subshell
  # whose EXIT trap removes the probe. exit 2 + "found issues" proves BOTH the
  # failure-surfacing contract AND that the hook self-located validate_docs.sh.
  ln -sf "$H" "$SCRATCH/dh_link.js"
  o=$( trap 'rm -f "$REAL/payments/__dhprobe_playbook.mdx"' EXIT; \
       printf '<!-- probe -->\npackages/stacked_kit/old/path\n' > "$REAL/payments/__dhprobe_playbook.mdx"; \
       printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/x/auth/auth_playbook.mdx"}}' | node "$SCRATCH/dh_link.js" 2>&1; \
       echo "exit:$?" )
  has "exit:2" "$o" && has "found issues" "$o" && ok "dirty doc edit surfaces to model (exit 2) via symlinked hook" || bad "dirty doc edit should exit 2 + surface: $o"
}

test_install(){
  say "INSTALL"; local I="$REAL/install.sh" p o
  p="$SCRATCH/proj1"; mkdir -p "$p"
  bash "$I" "$p" >/dev/null 2>&1
  local allok=1 s
  for s in stacked-kit kit-designer kit-scaffolder kit-reviewer kit-tester kit-feature-implementer; do
    [ -e "$p/.claude/skills/$s" ] || allok=0
  done
  { [ "$allok" -eq 1 ] && [ -e "$p/.claude/hooks/doc-health.js" ] && grep -q PostToolUse "$p/.claude/settings.json"; } && ok "fresh install wires all 6 skills + hook + settings" || bad "fresh install incomplete (skills missing)"
  # idempotent: run again, hook not duplicated
  local before after; before=$(grep -c doc-health "$p/.claude/settings.json"); bash "$I" "$p" >/dev/null 2>&1; after=$(grep -c doc-health "$p/.claude/settings.json")
  [ "$before" = "$after" ] && ok "idempotent (hook not duplicated: $before)" || bad "re-run duplicated the hook ($before -> $after)"
  [ -e "$p/.claude/skills/stacked-kit" ] && ok "idempotent re-run keeps symlink valid" || bad "re-run broke the symlink"
  # repair a pre-existing BROKEN symlink (the old packages/ -> moved case)
  p="$SCRATCH/proj2"; mkdir -p "$p/.claude/skills"; ln -s "../../packages/stacked_kit/skill" "$p/.claude/skills/stacked-kit" # deliberately dead
  bash "$I" "$p" >/dev/null 2>&1
  [ -e "$p/.claude/skills/stacked-kit" ] && ok "install repairs a dead symlink" || bad "install did not repair dead symlink"
}

test_gate(){
  say "GATE"; local o
  # smoke: real tree passes the default gate
  o=$( ( cd "$REAL" && bash tools/gate.sh ) 2>&1; echo "exit:$?" )
  has "GATE PASSED" "$o" && ok "real tree gate passes (smoke)" || bad "real tree gate should pass: $(echo "$o" | tail -3)"
  # exit-aggregation: sandbox gate where conventions fails (stub validate_docs passes)
  local s="$SCRATCH/gate-agg"; rm -rf "$s"; mkdir -p "$s/tools"
  cp "$REAL/tools/gate.sh" "$s/tools/"; cp "$REAL/tools/conventions.sh" "$s/tools/"
  printf '#!/usr/bin/env bash\necho stub-validate-ok; exit 0\n' > "$s/tools/validate_docs.sh"; chmod +x "$s/tools/validate_docs.sh"
  make_kit "$s" alpha stacked_kit_alpha; rm "$s/alpha/lib/stacked_kit_alpha.dart"  # convention violation
  o=$( ( cd "$s" && bash tools/gate.sh ) 2>&1; echo "exit:$?" )
  has "exit:1" "$o" && has "GATE FAILED" "$o" && ok "gate fails non-zero when a sub-gate fails" || bad "gate should exit 1 on convention failure: $o"
}

test_capscan(){
  say "CAPABILITY_SCAN"; local s o
  cap(){ ( KIT_APP="$1" bash "$REAL/tools/capability_scan.sh" ) 2>&1; echo "exit:$?"; }
  mkapp(){ local p="$SCRATCH/$1"; rm -rf "$p"; mkdir -p "$p/lib" "$p/docs"; echo "$p"; }
  # clean app: no playback signals, no manifest — passes vacuously
  s=$(mkapp cs-clean); printf 'void main() {}\n' > "$s/lib/a.dart"
  o=$(cap "$s"); has "exit:0" "$o" && has "no audio/video playback signals" "$o" && ok "clean app passes (vacuous)" || bad "clean app should pass: $o"
  # audio violation: playback import in lib/, nothing declared — fails non-zero
  s=$(mkapp cs-audio); printf "import 'package:just_audio/just_audio.dart';\nfinal p = AudioPlayer();\n" > "$s/lib/a.dart"
  o=$(cap "$s"); has "exit:1" "$o" && has "FAIL: audio playback" "$o" && ok "undeclared just_audio import fails" || bad "just_audio import should fail: $o"
  # video violation via the kit port symbol (no direct plugin import)
  s=$(mkapp cs-video); printf "import 'package:stacked_kit_media/stacked_kit_media.dart';\nVideoPlayerService? svc;\n" > "$s/lib/v.dart"
  o=$(cap "$s"); has "exit:1" "$o" && has "FAIL: video playback" "$o" && ok "undeclared VideoPlayerService usage fails" || bad "VideoPlayerService usage should fail: $o"
  # declared passes: same audio usage + a manifest row containing "audio playback"
  s=$(mkapp cs-decl); printf "import 'package:audioplayers/audioplayers.dart';\n" > "$s/lib/a.dart"
  printf '| T02 | Audio playback — session cues | session_runner | read | Stage 2 |\n' > "$s/docs/capability-manifest.md"
  o=$(cap "$s"); has "exit:0" "$o" && has "all signals declared" "$o" && ok "declared audio playback passes" || bad "declared audio should pass: $o"
  # pubspec runtime dep is a signal; dev_dependencies do not ship
  s=$(mkapp cs-pub); printf 'dependencies:\n  video_player: ^2.9.0\ndev_dependencies:\n  just_audio: ^0.10.0\n' > "$s/pubspec.yaml"
  o=$(cap "$s"); has "exit:1" "$o" && has "FAIL: video playback" "$o" && ! has "FAIL: audio playback" "$o" && ok "runtime dep fails, dev_dependency ignored" || bad "pubspec signal wrong: $o"
  # doc comments are not usage (the sample-app workout_detail placeholder case)
  s=$(mkapp cs-comment); printf '/// playback placeholder — VideoPlayerService is a phase-2A stub.\nclass X {}\n' > "$s/lib/a.dart"
  o=$(cap "$s"); has "exit:0" "$o" && ok "comment-only mention is not usage" || bad "comment mention should pass: $o"
  # native signal: iOS background-audio mode without a Dart signal still fails
  s=$(mkapp cs-ios); mkdir -p "$s/ios/Runner"; printf '<key>UIBackgroundModes</key><array><string>audio</string></array>\n' > "$s/ios/Runner/Info.plist"
  o=$(cap "$s"); has "exit:1" "$o" && has "FAIL: audio playback" "$o" && ok "iOS UIBackgroundModes audio fails undeclared" || bad "native audio signal should fail: $o"
}

test_apimap(){
  say "API_MAP_SCAN"; local o
  am(){ ( KIT_APP="$1" bash "$REAL/tools/api_map_scan.sh" ) 2>&1; echo "exit:$?"; }
  # dirty fixture: planted banned APIs must fail non-zero with named FAIL lines
  o=$(am "$REAL/tools/fixtures/api_map/dirty")
  has "exit:1" "$o" && has "FAIL: lib/main.dart" "$o" && ok "dirty fixture fails non-zero" || bad "dirty fixture should fail: $o"
  # clean fixture: no banned APIs — passes
  o=$(am "$REAL/tools/fixtures/api_map/clean")
  has "exit:0" "$o" && ok "clean fixture passes" || bad "clean fixture should pass: $o"
  # real app tree stays clean (true negative guard)
  o=$(am "$REAL/..")
  has "exit:0" "$o" && ok "real app has no banned Flutter APIs" || bad "real app violation crept in: $o"
}

test_smoke(){
  say "SMOKE"
  ( cd "$REAL" && bash tools/validate_docs.sh --fast >/dev/null 2>&1 ) && ok "validate_docs --fast passes on real tree" || bad "validate_docs --fast failed"
  ( cd "$REAL" && bash tools/extract_facts.sh >/dev/null 2>&1 ) && ok "extract_facts runs clean" || bad "extract_fakes failed"
  # facts JSON validity
  local f badjson=0
  for f in "$REAL"/memory/facts/*.json; do python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$f" 2>/dev/null || badjson=1; done
  [ "$badjson" -eq 0 ] && ok "all memory/facts/*.json are valid JSON" || bad "a facts JSON is invalid"
}

test_pipeline(){
  say "PIPELINE"; local o g
  # FSM + reviewer-authority invariant (hermetic selftest)
  o=$( bash "$REAL/tools/pipeline.sh" selftest 2>&1 )
  has "ALL GREEN" "$o" && ok "pipeline.sh selftest green (FSM + reviewer last word)" || bad "pipeline selftest failed: $o"
  # every gated skill's gate has a calibrated self-test
  for g in kit-scaffolder/scripts/scaffold_gate.sh kit-feature-implementer/scripts/slice_gate.sh kit-tester/scripts/run_suite.sh kit-reviewer/scripts/review_checklist.sh; do
    o=$( bash "$REAL/skills/$g" --self-test 2>&1 | tail -1 )
    has "ALL GREEN" "$o" && ok "gate self-test green: $g" || bad "gate self-test failed: $g — $o"
  done
  # kit-designer's Dart gate
  o=$( (cd "$REAL/skills/kit-designer" && dart scripts/enforce_design.dart --self-test) 2>&1 | tail -1 )
  has "SELF-TEST PASSED" "$o" && ok "kit-designer enforce_design self-test green" || bad "kit-designer gate failed: $o"
  # Drift guard for the checks mirrored review_checklist.sh → enforce_design.dart
  # (1w2, 1i, 1d). Most of that mirror is a bash→Dart TRANSLATION and cannot be
  # compared mechanically — POSIX [[:space:]] is not a Dart RegExp. But two
  # patterns are literally portable, so those two are pinned here: if someone
  # tightens the spacing pattern or adds a glass component on one side only, the
  # design and review gates start disagreeing about the same surface, which is
  # the exact failure this mirror exists to remove.
  local RC="$REAL/skills/kit-reviewer/scripts/review_checklist.sh"
  local ED="$REAL/skills/kit-designer/scripts/enforce_design.dart"
  local pat glass
  pat=$(  sed -n "s/.*PAT = re\.compile(r'\(.*\)').*/\1/p"  "$RC" | head -1 )
  glass=$(sed -n "s/.*GLASS_RE='\([^']*\)'.*/\1/p"          "$RC" | head -1 )
  # Non-empty FIRST: `grep -qF ""` matches everything, so an extraction that
  # silently broke would turn both assertions below into vacuous passes.
  [ -n "$pat" ]   && ok "drift guard: 1w2 pattern extracted from review_checklist" || bad "drift guard: could not extract 1w2 PAT from $RC"
  [ -n "$glass" ] && ok "drift guard: 1i glass alternation extracted"              || bad "drift guard: could not extract GLASS_RE from $RC"
  if [ -n "$pat" ]; then
    grep -qF "$pat" "$ED" && ok "1w2 spacing pattern identical in design + review gates" \
      || bad "1w2 spacing pattern drifted: review_checklist has [$pat], enforce_design.dart does not"
  fi
  if [ -n "$glass" ]; then
    grep -qF "$glass" "$ED" && ok "1i glass alternation identical in design + review gates" \
      || bad "1i glass alternation drifted: review_checklist has [$glass], enforce_design.dart does not"
  fi
  # structural-reproducibility substrate (ADR 0009): differ, manifest validator,
  # renderer, scaffolder vocabulary membership
  for g in tools/region_diff.sh tools/validate_slot_manifest.sh tools/render_template.sh skills/kit-scaffolder/scripts/validate_slot_vocabs.sh; do
    o=$( bash "$REAL/$g" --self-test 2>&1 | tail -1 )
    has "ALL GREEN" "$o" && ok "substrate self-test green: $g" || bad "substrate self-test failed: $g — $o"
  done
}

test_fixity(){
  say "FIXITY"; local t o
  # 1. prose-preserving regen is idempotent: regenerating an in-sync playbook
  #    reproduces it byte-for-byte (excluding the kb_build-owned References region).
  #    This is the load-bearing guard — if prose-merge breaks, regen drifts.
  t=$(mktemp)
  python3 "$REAL/tools/gen_playbook.py" payments -o "$t" >/dev/null 2>&1
  if diff -q <(sed '/<!-- kb:begin -->/,/<!-- kb:end -->/d' "$REAL/payments/payments_playbook.mdx") \
              <(sed '/<!-- kb:begin -->/,/<!-- kb:end -->/d' "$t") >/dev/null 2>&1; then
    ok "prose-preserving regen is idempotent (payments reproduces committed, excl kb)"
  else
    bad "regen is NOT idempotent — an in-sync playbook drifts on regen"
  fi
  rm -f "$t"
  # 2. fence-aware extraction (the HIGH-risk design case): a '### ' inside a ``` code
  #    block is NOT treated as a section header, yet the fenced code is kept in the
  #    section body verbatim.
  o=$( PYTHONPATH="$REAL/tools" python3 - <<'PY'
import gen_playbook as g, tempfile, os
p = tempfile.mktemp(suffix='.mdx')
open(p, 'w').write('### Architecture\n\nReal prose.\n\n```dart\n### NotAHeader\nclass X {}\n```\n\nmore prose\n')
s = g.existing_sections(p)
body = s.get('Architecture', '')
ok = ('### NotAHeader' in body) and ('NotAHeader' not in s) and ('more prose' in body) and ('Real prose' in body)
os.unlink(p)
print('FENCE_OK' if ok else 'FENCE_BAD ' + repr(s))
PY
)
  has "FENCE_OK" "$o" && ok "fenced '### ' is not a section header (code preserved in body)" || bad "fence handling broke: $o"
}

test_translate(){
  say "TRANSLATE"; local o s
  local TD="$REAL/tools/translate_design/translate_design.py"
  # (W1) hermetic self-test (fixture transform + golden parity + planted drift +
  # node-absent cascade + the W2 extraction legs)
  o=$( python3 "$TD" --self-test 2>&1; echo "exit:$?" )
  has "exit:0" "$o" && ok "translate_design self-test green (fixture + drift + node-absent + legs)" || bad "translate_design self-test failed: $(echo "$o" | tail -4)"
  # (W1) real-app transform runs clean (write-on-diff: idempotent on an in-sync
  # app). --design-dir design/new: the 2026-07-25 producer reorg moved each
  # producer's tokens+surfaces into its own self-contained folder, so the React
  # producer — not the repo root — is the design root now.
  #
  # WHICH app? `$REAL/..` was the consuming repo while stacked_kit was a
  # subdirectory of it. Since the 2026-07-26 extraction this repo stands alone and
  # its parent is just a workspace folder with no design/ in it — so the real-app
  # leg is SKIPPED unless an app is named. Point $KIT_APP at a consumer to run it:
  #   KIT_APP=/path/to/sample-app tools/test_gates.sh -g translate
  # Skipping is deliberate: a standalone library repo has no real app, and failing
  # would report a missing consumer as a translator defect. The hermetic self-test
  # above still covers the transform, the golden, drift, and the legs.
  local RD="design/new"
  local RAPP="${KIT_APP:-$REAL/..}"
  if [ -f "$RAPP/$RD/tokens.json" ]; then
    o=$( python3 "$TD" tokens --app "$RAPP" --design-dir "$RD" 2>&1; echo "exit:$?" )
    has "exit:0" "$o" && ok "real-app token transform runs clean" || bad "real-app token transform failed: $(echo "$o" | tail -3)"
    # (W1) token parity (fixity): committed derived file matches regen
    o=$( python3 "$TD" tokens --app "$RAPP" --design-dir "$RD" --check 2>&1; echo "exit:$?" )
    has "exit:0" "$o" && ok "real-app token parity PASS (committed == regen)" || bad "real-app token parity drifted: $(echo "$o" | tail -3)"
  else
    echo "  SKIP: real-app token legs — no $RD/tokens.json under $RAPP"
    echo "        (standalone kit repo; set KIT_APP=<consumer> to exercise them)"
  fi
  # (W2) extraction legs + manifest validators.
  #
  # These ran against design/surfaces/train_shell_{workout,home}_view until
  # 2026-07-25. Those two were among the 5 legacy frozen surfaces retired that
  # day, and they were the *only* real-app surfaces carrying the .css/.js
  # sidecars the extraction legs need — every live surface the React producer
  # emits is self-contained HTML with no sidecar triple. So there is no live
  # real-app specimen to retarget at, and the legs now run against the tool's
  # own fixture surfaces in a tempdir. (That path predates the reorg — the
  # surfaces dir is design/new/surfaces/ now.)
  #
  # Net coverage change: the legs and the two shell validators still run (same
  # assertions, fixture inputs); what is genuinely gone is real-app *fixity* of
  # the per-surface derived artifacts, because no such artifacts are committed
  # any more. The token leg above still carries real-app fixity. If a real
  # surface ever ships a triple again, point RD/--surface back at it.
  local FIXAPP; FIXAPP=$( mktemp -d )
  mkdir -p "$FIXAPP/design"
  cp "$REAL/tools/translate_design/fixtures/tokens.json" "$FIXAPP/design/tokens.json"
  cp -R "$REAL/tools/translate_design/fixtures/surfaces" "$FIXAPP/design/surfaces"
  o=$( python3 "$TD" all --app "$FIXAPP" 2>&1; echo "exit:$?" )
  has "exit:0" "$o" && ok "extraction legs run clean (fixture app, both surfaces)" || bad "extraction legs failed: $(echo "$o" | tail -3)"
  o=$( python3 "$TD" all --app "$FIXAPP" --check 2>&1; echo "exit:$?" )
  has "exit:0" "$o" && ok "derived artifacts parity green (fixture app)" || bad "derived artifacts drifted: $(echo "$o" | tail -3)"
  for s in train_shell_demo_view train_shell_demo2_view; do
    o=$( bash "$REAL/tools/validate_slot_manifest.sh" "$FIXAPP/design/derived/$s/slot-manifest.json" 2>&1; echo "exit:$?" )
    has "exit:0" "$o" && ok "derived slot-manifest shape valid: $s" || bad "slot-manifest invalid for $s: $(echo "$o" | tail -3)"
    o=$( bash "$REAL/skills/kit-scaffolder/scripts/validate_slot_vocabs.sh" "$FIXAPP/design/derived/$s/slot-manifest.json" 2>&1; echo "exit:$?" )
    has "exit:0" "$o" && ok "derived slot-manifest vocabs valid: $s" || bad "slot-manifest vocabs invalid for $s: $(echo "$o" | tail -3)"
  done
  # (W2) geometry + translation-map schema gates (fixture app — same reason)
  o=$( python3 "$TD" validate --app "$FIXAPP" 2>&1; echo "exit:$?" )
  has "exit:0" "$o" && ok "geometry + translation-map schema validation green" || bad "schema validation failed: $(echo "$o" | tail -3)"
  rm -rf "$FIXAPP"
}

test_emit(){
  say "EMIT"; local o
  # hermetic self-test: fixture emit (chrome strip, hermetic doc, registry-null
  # skip, role fallback) + write-on-diff + planted drift + EMIT_RENDER=skip.
  # The real-app emit is orchestrated separately (the design/new registry is
  # annotated in parallel) — never run from here.
  o=$( python3 "$REAL/tools/emit_playground/emit_playground.py" --self-test 2>&1; echo "exit:$?" )
  has "exit:0" "$o" && has "ALL GREEN" "$o" && ok "emit_playground self-test green (fixture emit + drift + skip)" || bad "emit_playground self-test failed: $(echo "$o" | tail -4)"
  # Same contract over the htmx producer (design/new-htmx → design/new-htmx/surfaces).
  # Its fixture producer is dependency-free node, so this stays offline; it adds
  # the boot/teardown and placeholder-trap checks the static sibling has no need of.
  o=$( python3 "$REAL/tools/emit_htmx/emit_htmx.py" --self-test 2>&1; echo "exit:$?" )
  has "exit:0" "$o" && has "ALL GREEN" "$o" && ok "emit_htmx self-test green (server boot/teardown + placeholder trap + drift)" || bad "emit_htmx self-test failed: $(echo "$o" | tail -4)"
}

# mk_design <app-root> — minimal design root that passes shape/vocab/exclusions,
# so the ONLY thing a variant below can fail on is freeze check 4 (structure).
# Every bad twin is this good twin with a SINGLE planted defect — that is what
# makes an observed FAIL attributable to the assertion under test rather than to
# fixture noise (the S6 lesson: 51/51 in both directions proves nothing).
mk_design(){
  local app="$1" d="$1/design/new"
  rm -rf "$app"; mkdir -p "$d/surfaces"
  : > "$d/surfaces/train_shell_library_view.html"
  : > "$d/surfaces/train_shell_stats_view.html"
  for f in design-system.md direction-approved.md brand-spec.md; do echo "# fixture" > "$d/$f"; done
  echo '{"globs":[],"selectors":[]}' > "$d/exclusions.json"
  python3 - "$d/tokens.json" <<'PY'
import json,sys
P=["color.brand.0","color.bg.surface","color.bg.surface-2","color.bg.paper",
   "color.fg.ink","color.fg.muted","color.fg.faint","color.border.rule",
   "color.status.good","color.status.warn","color.status.danger",
   "typography.sans","typography.mono"]
d={}
for p in P:
    n=d; parts=p.split('.')
    for k in parts[:-1]: n=n.setdefault(k,{})
    n[parts[-1]]={"$type":"color","$value":"#000000"}
json.dump(d,open(sys.argv[1],'w'),indent=2)
PY
  cat > "$d/structure.json" <<'JSON'
{
  "$schema": "kit/design-structure@1",
  "registry": "jsx/app.jsx",
  "tabRoots": { "train": "train.library" },
  "screens": [
    { "id": "train.library", "tab": "train", "comp": "TrainLib",
      "shell": "train_shell", "surface": "train_shell_library_view" },
    { "id": "train.stats", "tab": "train", "comp": "TrainStats",
      "shell": "train_shell", "surface": "train_shell_stats_view" }
  ]
}
JSON
}

# patch_structure <app> <python stmt over `d`> — plant exactly one defect
patch_structure(){ python3 - "$1/design/new/structure.json" "$2" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); exec(sys.argv[2]); json.dump(d,open(p,'w'),indent=2)
PY
}

fz(){ ( cd "$1" && KIT_DESIGN_DIR=design/new FREEZE_RENDER=skip \
        bash "$REAL/tools/freeze_design.sh" . ) 2>&1; echo "exit:$?"; }

test_structure(){
  say "STRUCTURE (freeze check 4 + emit_structure)"; local o a="$SCRATCH/fz"

  o=$( python3 "$REAL/tools/emit_structure/emit_structure.py" --self-test 2>&1; echo "exit:$?" )
  has "exit:0" "$o" && has "ALL GREEN" "$o" \
    && ok "emit_structure self-test green (nulls preserved + drift + bad input)" \
    || bad "emit_structure self-test failed: $(echo "$o" | tail -4)"

  # ---- the good twin. If THIS goes red, every bad twin below proves nothing.
  mk_design "$a"; o=$(fz "$a")
  has "exit:0" "$o" && has "structure:" "$o" \
    && ok "structure: conformant design root PASSES freeze" \
    || bad "good twin should pass: $(echo "$o" | grep FAIL | head -2)"

  # ---- drift: a registry screen added without re-running the emitter. The
  # on-disk assertions below cannot see this (an added screen contradicts
  # nothing), so the gate re-derives from jsx/app.jsx when a registry exists.
  mk_design "$a"; mkdir -p "$a/design/new/jsx"
  cat > "$a/design/new/jsx/app.jsx" <<'JSX'
const P2_REGISTRY = [
  { id: 'train.library', label: 'x', tab: 'train', comp: 'TrainLib', surface: 'train_shell_library_view' },
  { id: 'train.stats',   label: 'x', tab: 'train', comp: 'TrainStats', surface: 'train_shell_stats_view' },
];
const P2_TAB_ROOTS = { train: 'train.library' };
JSX
  python3 "$REAL/tools/emit_structure/emit_structure.py" --app "$a" --design-dir design/new >/dev/null
  o=$(fz "$a")
  has "exit:0" "$o" && has "in sync with" "$o" \
    && ok "structure: emitted structure.json reports in-sync with app.jsx" \
    || bad "emitted structure should be in sync: $(echo "$o" | grep FAIL | head -2)"
  printf "const P2_REGISTRY = [\n  { id: 'train.zzz', label: 'x', tab: 'train', comp: 'Z', surface: null },\n  { id: 'train.library', label: 'x', tab: 'train', comp: 'TrainLib', surface: 'train_shell_library_view' },\n  { id: 'train.stats', label: 'x', tab: 'train', comp: 'TrainStats', surface: 'train_shell_stats_view' },\n];\nconst P2_TAB_ROOTS = { train: 'train.library' };\n" > "$a/design/new/jsx/app.jsx"
  o=$(fz "$a")
  has "exit:1" "$o" && has "drifted from jsx/app.jsx" "$o" \
    && ok "structure: registry screen added without re-emitting FAILS as drift" \
    || bad "planted registry drift should fail: $o"

  # ---- (a) resolution: a declared surface with no file on disk
  mk_design "$a"; patch_structure "$a" "d['screens'][0]['surface']='train_shell_ghost_view'"
  o=$(fz "$a")
  has "exit:1" "$o" && has "does not exist" "$o" \
    && ok "structure: declared surface with no .html FAILS" \
    || bad "dangling surface should fail: $o"

  # ---- (b) coverage: a surface on disk that nobody claims
  mk_design "$a"; : > "$a/design/new/surfaces/train_shell_orphan_view.html"
  o=$(fz "$a")
  has "exit:1" "$o" && has "claimed by no screen" "$o" \
    && ok "structure: orphan surface FAILS (emit_playground only ever noted it)" \
    || bad "orphan surface should fail: $o"

  # ---- (c) uniqueness: two screens claiming one surface
  mk_design "$a"; patch_structure "$a" "d['screens'][1]['surface']=d['screens'][0]['surface']"
  o=$(fz "$a")
  has "exit:1" "$o" && has "is claimed by 2 screens" "$o" \
    && ok "structure: duplicate surface claim FAILS" \
    || bad "duplicate claim should fail: $o"

  # ---- (d) shell: the filename-prefix convention, asserted not assumed
  mk_design "$a"; patch_structure "$a" "d['screens'][0]['shell']='shop_shell'"
  o=$(fz "$a")
  has "exit:1" "$o" && has "is not under shell" "$o" \
    && ok "structure: surface/shell prefix mismatch FAILS" \
    || bad "shell mismatch should fail: $o"
  mk_design "$a"; patch_structure "$a" "d['screens'][0]['shell']=None"
  o=$(fz "$a")
  has "exit:1" "$o" && has "has a surface but no shell" "$o" \
    && ok "structure: surface with null shell FAILS" \
    || bad "null shell should fail: $o"

  # ---- (e) roots: the assertion that catches train.home in the real design
  mk_design "$a"
  rm "$a/design/new/surfaces/train_shell_library_view.html"
  patch_structure "$a" "d['screens'][0]['surface']=None; d['screens'][0]['shell']=None"
  o=$(fz "$a")
  has "exit:1" "$o" && has "landing screen was never designed" "$o" \
    && ok "structure: excluded tab-root screen FAILS (the train.home defect)" \
    || bad "excluded tab root should fail: $o"

  # ---- schema floor: absent/empty/malformed is never a silent pass
  mk_design "$a"; rm "$a/design/new/structure.json"; o=$(fz "$a")
  has "exit:1" "$o" && has "structure.json missing" "$o" \
    && ok "structure: absent structure.json FAILS at shape" \
    || bad "missing structure.json should fail: $o"
  mk_design "$a"; echo '{"screens":[],"tabRoots":{}}' > "$a/design/new/structure.json"; o=$(fz "$a")
  has "exit:1" "$o" && has "non-empty" "$o" \
    && ok "structure: empty screens list FAILS (no opting out by emptiness)" \
    || bad "empty screens should fail: $o"
  mk_design "$a"; echo 'not json' > "$a/design/new/structure.json"; o=$(fz "$a")
  has "exit:1" "$o" && has "does not parse" "$o" \
    && ok "structure: unparseable structure.json FAILS" \
    || bad "bad json should fail: $o"

  rm -rf "$a"
}

test_coverage(){
  say "COVERAGE (scaffold gate E)"; local o
  o=$( bash "$REAL/tools/scaffold_coverage_gate.sh" --self-test 2>&1; echo "exit:$?" )
  has "exit:0" "$o" && has "ALL GREEN" "$o" \
    && ok "scaffold_coverage_gate self-test green (21 twins: C1 coverage, C2 orphans, C3 escape hatch, C4 progress)" \
    || bad "scaffold_coverage_gate self-test failed: $(echo "$o" | grep FAIL | head -3)"
  # Wiring: E must actually be reachable from the scaffold phase, not just exist.
  has "SCAFFOLD_GATE_E" "$(cat "$REAL/tools/pipeline.sh")" \
    && ok "coverage gate is wired as SCAFFOLD_GATE_E in pipeline.sh" \
    || bad "pipeline.sh does not reference SCAFFOLD_GATE_E"
  o=$(grep -c 'run_gate "\$SCAFFOLD_GATE_E"' "$REAL/tools/pipeline.sh")
  [ "$o" = 1 ] && ok "gate_scaffold invokes SCAFFOLD_GATE_E exactly once" \
                || bad "gate_scaffold should invoke SCAFFOLD_GATE_E once (found $o)"
}

run_group(){ case "$1" in
  coverage) test_coverage;;
  conventions) test_conventions;; pressure) test_pressure;;
  dochealth) test_dochealth;; install) test_install;;
  gate) test_gate;; capscan) test_capscan;; apimap) test_apimap;; smoke) test_smoke;; pipeline) test_pipeline;; fixity) test_fixity;; translate) test_translate;; emit) test_emit;; structure) test_structure;; *) ;;
esac; }

say "stacked_kit gate test suite"
if [ -n "$WANT" ]; then run_group "$WANT"; else
  for g in conventions pressure dochealth install gate capscan apimap smoke pipeline fixity translate emit structure coverage; do run_group "$g"; done
fi

say "RESULT"
echo "passed=$PASS failed=$FAIL"
if [ "$FAIL" -gt 0 ]; then echo "FAILURES:"; printf '  - %s\n' "${FAILED[@]}"; exit 1; fi
echo "ALL GREEN"
