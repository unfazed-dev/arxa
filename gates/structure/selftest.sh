#!/usr/bin/env bash
# gates/structure/selftest.sh — R5 suite for the structure gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the offending file/surface/screen. Runs inside a throwaway git repo
# so the porcelain (S1b) assertion is exercised for real — `git diff --exit-code`
# cannot see an untracked structure.json, and a producer that adds a surface is
# the expected case.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/structure.sh"
EMIT="$HERE/../../tools/emit_structure/emit_structure.py"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }
none(){ case "$1" in *"$2"*) failc=$((failc+1)); echo "  FAIL: output should NOT mention [$2] — $3";; *) pass=$((pass+1));; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git init -q "$T"; git -C "$T" config user.email t@t.t; git -C "$T" config user.name t

# Mini producer mirroring the real layout: app-root/tools/emit_structure + a
# designs/<name> design-dir carrying the authored registry, routes, viewmodels.
mkdir -p "$T/tools/emit_structure"
cp "$EMIT" "$T/tools/emit_structure/emit_structure.py"
D="$T/designs/app"
mkdir -p "$D/models/screens_model" \
         "$D/ui/views/stage_shell/proj/home" \
         "$D/ui/views/stage_shell/proj/new"

cat > "$D/models/screens_model/registry.json" <<'JSON'
[
  {"id":"stage.shell","tab":"stage","comp":"StageShell","surface":"stage_shell_view"},
  {"id":"proj.home","tab":"proj","comp":"ProjHome","surface":"stage_shell_proj_home_view"},
  {"id":"proj.new","tab":"proj","comp":"ProjNew","surface":"stage_shell_proj_new_view"},
  {"id":"proj.splash","tab":"proj","comp":"ProjSplash","surface":null}
]
JSON
cat > "$D/app.routes.js" <<'JS'
export default [['GET','/',home.page]];
export const tabRoots = { proj: '/', stage: '/' };
JS
printf "export const surfaceId = 'stage.shell';\nimport {c} from '../../../services/facades/shell_facade.js';\n" > "$D/ui/views/stage_shell/stage_shell_viewmodel.js"
printf "export const surfaceId = 'proj.home';\nimport {l} from '../../../../../services/facades/project_facade.js';\n" > "$D/ui/views/stage_shell/proj/home/home_viewmodel.js"
printf "export const surfaceId = 'proj.new';\n" > "$D/ui/views/stage_shell/proj/new/new_viewmodel.js"

run(){ KIT_DESIGN_DIR=designs/app bash "$GATE" "$T" 2>&1; }

# Generate + commit the baseline so porcelain starts clean.
python3 "$T/tools/emit_structure/emit_structure.py" --app "$T" --design-dir designs/app >/dev/null
git -C "$T" add -A; git -C "$T" commit -qm baseline

# ---- HAPPY: committed structure.json resolves and is in sync ------------------
o="$(run)"; chk "$?" 0 "happy: committed structure.json passes"
need "$o" "structure: PASS" "happy prints PASS"
need "$o" "exclusions (surface:null): proj.splash" "happy prints the exclusion list"

# ---- NEGATIVE: hand-edit structure.json by one char (done-when #4) ------------
# A one-char edit must fail the gate. The emitter --check regenerates to memory
# and diffs against the on-disk file, so a hand-edit is caught even though
# regeneration would silently revert it.
f="$D/structure.json"
sed -i.bak 's/StageShell/StageShellX/' "$f"; rm -f "$f.bak"
o="$(run)"; chk "$?" 1 "negative: one-char hand-edit fails"
git -C "$T" checkout -- "$f"   # restore

# ---- NEGATIVE: a declared surface with no viewmodel (done-when #2) ------------
# Remove the surfaceId binding by deleting the home viewmodel; the gate must fail
# and NAME the screen whose viewmodel went missing.
vm_home="$D/ui/views/stage_shell/proj/home/home_viewmodel.js"
rm "$vm_home"
o="$(run)"; chk "$?" 1 "negative: dangling surface (no viewmodel) fails"
need "$o" "proj.home" "negative names the screen whose surfaceId is unbound"
# restore + regenerate the (unchanged) structure.json + recommit baseline files
printf "export const surfaceId = 'proj.home';\nimport {l} from '../../../../../services/facades/project_facade.js';\n" > "$vm_home"

# ---- NEGATIVE: an orphan viewmodel / added surface (done-when #5) -------------
# A new viewmodel whose surfaceId the registry never claims must fail — this is
# the porcelain semantic: a producer that adds a surface cannot pass until the
# registry declares it.
vm_ghost="$D/ui/views/stage_shell/proj/ghost/ghost_viewmodel.js"
mkdir -p "$(dirname "$vm_ghost")"
printf "export const surfaceId = 'proj.ghost';\n" > "$vm_ghost"
o="$(run)"; chk "$?" 1 "negative: orphan viewmodel (unclaimed surface) fails"
need "$o" "proj.ghost" "negative names the orphan surfaceId"
rm -rf "$D/ui/views/stage_shell/proj/ghost"

# ---- NEGATIVE: porcelain — an uncommitted regeneration fails (S1b) -----------
# A legit registry change: add a new declared screen + viewmodel, regenerate
# structure.json, but DO NOT commit. The gate must fail on porcelain (`git diff
# --exit-code` could not see this — the file is tracked-and-modified but the
# principle is the same one that catches an untracked structure.json).
python3 - <<PY
import json
p="$D/models/screens_model/registry.json"
d=json.load(open(p))
d.append({"id":"proj.extra","tab":"proj","comp":"ProjExtra","surface":"stage_shell_proj_extra_view"})
json.dump(d,open(p,"w"))
PY
vm_extra="$D/ui/views/stage_shell/proj/extra/extra_viewmodel.js"
mkdir -p "$(dirname "$vm_extra")"
printf "export const surfaceId = 'proj.extra';\n" > "$vm_extra"
python3 "$T/tools/emit_structure/emit_structure.py" --app "$T" --design-dir designs/app >/dev/null
o="$(run)"; chk "$?" 1 "negative: uncommitted regeneration fails (porcelain)"
need "$o" "porcelain" "negative cites porcelain"
# now commit it and the gate goes green again
git -C "$T" add -A; git -C "$T" commit -qm "declare proj.extra"
o="$(run)"; chk "$?" 0 "after commit, the added surface passes"

echo "structure selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
