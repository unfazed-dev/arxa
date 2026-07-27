#!/usr/bin/env bash
# gates/coverage/selftest.sh — R5 suite for the coverage gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the offending file. Includes the 4.4 proof: a missing structure.json
# (the gate's input) MUST fail, not pass quietly.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/coverage.sh"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# read the form-factor set from the same config the gate uses (R3: config-driven)
FACTORS="$(python3 -c "import json;d=json.load(open('$(git rev-parse --show-toplevel)/config/app-box.config.json'));print(' '.join(d['viewports'].keys()))" 2>/dev/null || echo "mobile tablet desktop")"

# plant <app> <manifest-json> [surface-dirs-to-build-under train_shell/]
plant(){ local a="$1" man="$2"; shift 2
  rm -rf "$a"; mkdir -p "$a/lib/ui/views/train_shell" "$a/design/new"
  cat > "$a/design/new/structure.json" <<'JSON'
{"tabRoots":{},"screens":[
  {"id":"train.library","tab":"train","shell":"train_shell","surface":"train_shell_library_view"},
  {"id":"train.stats","tab":"train","shell":"train_shell","surface":"train_shell_stats_view"}]}
JSON
  printf '%s' "$man" > "$a/lib/ui/views/.shell-structure.json"
  local d f; for d in "$@"; do
    mkdir -p "$a/lib/ui/views/train_shell/$d"
    for f in _view.dart $(printf '_view.%s.dart ' $FACTORS) _viewmodel.dart; do
      : > "$a/lib/ui/views/train_shell/$d/$d$f"
    done
  done
}
FULL='{"selfContained":["train_shell"],"surfaces":{"train_shell":{"train_shell_library_view":"library","train_shell_stats_view":"stats"}}}'
run(){ ( cd "$T" && KIT_DESIGN_DIR=design/new bash "$GATE" "$1" 2>&1 ); }

# ---- HAPPY: both frozen surfaces mapped and fully scaffolded -----------------
plant "$T/a" "$FULL" library stats
o="$(run "$T/a")"; chk "$?" 0 "happy: fully covered adopted shell passes"
need "$o" "2/2 frozen surfaces scaffolded" "happy reports full coverage"

# ---- NEGATIVE: a frozen surface left unmapped --------------------------------
# NEGATIVE: train_shell_stats_view is frozen but not mapped -> exit 1, naming it.
plant "$T/a" '{"selfContained":["train_shell"],"surfaces":{"train_shell":{"train_shell_library_view":"library"}}}' library
o="$(run "$T/a")"; chk "$?" 1 "negative: unmapped frozen surface fails"
need "$o" "train_shell_stats_view" "negative names the unmapped surface"

# ---- NEGATIVE (4.4): missing structure.json -> exit 1, never a silent N/A ----
# NEGATIVE: the gate's input is absent; it must fail loudly, not print "N/A" exit 0.
rm -rf "$T/b"; mkdir -p "$T/b/lib/ui/views"
o="$(run "$T/b")"; chk "$?" 1 "negative (4.4): missing structure.json fails"
need "$o" "structure.json not found" "negative names the missing input"

echo "coverage selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
