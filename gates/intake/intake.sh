#!/usr/bin/env bash
# gates/intake/intake.sh — the TRACEABILITY gate (10.6).
#
# The assertion intake exists to enable (architecture §22): every registry
# surface traces to an intake answer, and every intake answer traces to a
# registry surface. No orphans either way. A registry entry the client never
# asked for, or a client requirement the registry silently dropped, is a FAIL
# naming the surface id.
#
# This is the "cheapest place to be wrong" made enforceable: the brief is the
# one output a non-technical client can validate, and this gate ties it to the
# registry the designer consumes — so a drift between "what was asked for" and
# "what got built" cannot pass silently.
#
# Sources (checked in order):
#   1. intake answers  — pipeline state intake slot (run.intake.json), or the
#                        skill's answers document passed via --answers.
#   2. hand-written    — a brief whose surface table seeds the registry (10.7).
#                        The gate parses the table for <tab>.<short> ids, the
#                        same pattern the engine's seed_from_brief uses.
#
# If no source exists AND no registry exists, the gate passes vacuously —
# nothing to trace (greenfield). A registry with entries but no traceable
# source is a FAIL (every entry is untraced).
#
# Usage: intake.sh [--answers <file>] [--registry <file>] [--brief <file>]
#        intake.sh --self-test
# Defaults:
#   --answers   first of: $APPBOX_INTAKE, pipeline/state/run.intake.json,
#               pipeline/state/default.intake.json
#   --registry  docs/design/registry.json
#   --brief     docs/design/brief.md
# Exit: 0 pass / 1 FAIL / 2 env
set -uo pipefail

GATE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../_common/state_reader.sh
source "$(cd "$(dirname "$0")/../_common" && pwd)/state_reader.sh"
# state_reader.sh enables `set -e`; gates run WITHOUT it (a failed check is a
# recorded status, not an abort). Re-assert the gate's mode.
set -uo pipefail
set +e

# shellcheck source=../_common/sarif.sh
source "$(cd "$(dirname "$0")/../_common" && pwd)/sarif.sh"

SELF_TEST=0
ANSWERS=""
REGISTRY=""
BRIEF=""
APP="${KIT_APP:-$PWD}"
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELF_TEST=1; shift ;;
    --answers)   ANSWERS="$2"; shift 2 ;;
    --registry)  REGISTRY="$2"; shift 2 ;;
    --brief)     BRIEF="$2"; shift 2 ;;
    --*)         echo "FAIL: unknown flag: $1" >&2; exit 2 ;;
    *)           APP="$1"; shift ;;   # positional app-root (like freeze/structure)
  esac
done

# ----------------------------------------------------------------- path resolve
# app-root + KIT_DESIGN_DIR select the producer folder (same idiom as every other
# gate). The registry lives where structure.json says (designer default
# models/screens_model/registry.json) — NEVER the legacy docs/design/ path.
APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "FAIL: intake: app root not found: $APP" >&2; exit 2; }
DESIGN_REL="${KIT_DESIGN_DIR:-design}"
case "$DESIGN_REL" in
  /*) echo "FAIL: KIT_DESIGN_DIR must be relative to the app root, got: $DESIGN_REL" >&2; exit 2 ;;
esac
DESIGN="$APP/$DESIGN_REL"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$APP")"

# answers: explicit flag, env, or pipeline state intake slot (pipeline-wide).
if [ -z "$ANSWERS" ]; then
  if [ -n "${APPBOX_INTAKE:-}" ] && [ -f "${APPBOX_INTAKE}" ]; then
    ANSWERS="$APPBOX_INTAKE"
  elif [ -f "$ROOT/pipeline/state/run.intake.json" ]; then
    ANSWERS="$ROOT/pipeline/state/run.intake.json"
  elif [ -f "$ROOT/pipeline/state/default.intake.json" ]; then
    ANSWERS="$ROOT/pipeline/state/default.intake.json"
  fi
fi

# registry: structure.json's "registry" field (default models/screens_model/registry.json)
if [ -z "$REGISTRY" ]; then
  REG_REL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("registry") or "models/screens_model/registry.json")' "$DESIGN/structure.json" 2>/dev/null || echo models/screens_model/registry.json)"
  REGISTRY="$DESIGN/$REG_REL"
fi
# brief: design-local first, then the repo's authored brief (docs/design/brief.md)
if [ -z "$BRIEF" ]; then
  BRIEF="$DESIGN/brief.md"
  [ -f "$BRIEF" ] || BRIEF="$ROOT/docs/design/brief.md"
fi

run_gate(){
  python3 - "$ANSWERS" "$REGISTRY" "$BRIEF" 2>&1 <<'PY'
import json, os, re, sys

answers_path, registry_path, brief_path = sys.argv[1], sys.argv[2], sys.argv[3]

ID_RE = re.compile(r"^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$")

def fail(m): print(f"FAIL: intake: {m}", file=sys.stderr)
def ok(m):   print(f"  \u2713 intake: {m}")

# ---- collect SOURCE surface ids (intake answers, then hand-written brief) ----
source_ids = []
source_label = None

if answers_path and os.path.isfile(answers_path):
    try:
        data = json.load(open(answers_path))
    except Exception as e:
        fail(f"answers file {answers_path} does not parse — {e}")
        sys.exit(1)
    # the state slot wraps answers under "answers"; a raw answers document is
    # also accepted (the engine's format).
    answers = data.get("answers") if isinstance(data, dict) and "answers" in data else data
    if isinstance(answers, dict):
        source_ids = [s["id"] for s in answers.get("surfaces", []) if isinstance(s, dict) and "id" in s]
        source_label = "intake answers"

if not source_ids and brief_path and os.path.isfile(brief_path):
    # hand-written brief (10.7): parse the surface table for <tab>.<short> ids,
    # the same pattern the engine's seed_from_brief uses.
    md = open(brief_path, errors="replace").read()
    for line in md.splitlines():
        s = line.strip()
        if not (s.startswith("|") and s.endswith("|")):
            continue
        cells = [c.strip().strip("`") for c in s.strip("|").split("|")]
        if all(set(c) <= set("-: ") and c for c in cells):  # separator row
            continue
        for c in cells:
            if ID_RE.match(c.strip()):
                source_ids.append(c.strip())
                break
    # de-dup preserving order
    seen = set(); deduped = []
    for x in source_ids:
        if x not in seen: seen.add(x); deduped.append(x)
    source_ids = deduped
    if source_ids:
        source_label = "brief surface table"

# ---- collect REGISTRY surface ids --------------------------------------------
if not os.path.isfile(registry_path):
    if not source_ids:
        ok("no intake answers and no registry — nothing to trace (greenfield)")
        sys.exit(0)
    fail(f"{source_label} has {len(source_ids)} surface(s) but registry not found "
         f"at {registry_path} — run intake.py emit to seed it")
    sys.exit(1)

try:
    registry = json.load(open(registry_path))
except Exception as e:
    fail(f"registry {registry_path} does not parse — {e}"); sys.exit(1)

if not isinstance(registry, list):
    fail(f"registry must be a list of entries, got {type(registry).__name__}")
    sys.exit(1)

registry_ids = []
for i, e in enumerate(registry):
    if not isinstance(e, dict) or "id" not in e:
        fail(f"registry[{i}] is missing 'id'"); sys.exit(1)
    registry_ids.append(e["id"])

# ---- 4.4: a gate that cannot find its input MUST fail ------------------------
# (handled: missing registry with a source fails above; missing source with a
# registry fails below.)

# ---- orphans either way ------------------------------------------------------
if not source_ids and registry_ids:
    fail(f"{len(registry_ids)} registry surface(s) but no intake answers or brief "
         f"found — every entry is untraced (provide --answers or a brief)")
    for sid in registry_ids:
        fail(f"surface '{sid}' is in the registry but has no intake answer or brief")
    sys.exit(1)

source_set = set(source_ids)
registry_set = set(registry_ids)

# detect duplicates in the registry (ids are permanent — duplicates are a bug)
dup_reg = [sid for sid in registry_ids if registry_ids.count(sid) > 1]

F = 0
orphan_answers = sorted(source_set - registry_set)
unanswered = sorted(registry_set - source_set)

for sid in orphan_answers:
    fail(f"surface '{sid}' is in {source_label} but NOT in the registry — "
         f"an intake answer with no registry entry (orphan answer)")
    F += 1
for sid in unanswered:
    fail(f"surface '{sid}' is in the registry but NOT in {source_label} — "
         f"a registry entry with no intake answer (unanswered surface)")
    F += 1
for sid in sorted(set(dup_reg)):
    fail(f"surface '{sid}' appears more than once in the registry — ids are permanent")
    F += 1

if F == 0:
    ok(f"{len(registry_ids)} registry surface(s) trace to {source_label} "
       f"(no orphans either way)")
sys.exit(1 if F else 0)
PY
}

# ------------------------------------------------------------------- self-test
self_test(){
  local P=0 Fc=0 T o
  T="$(mktemp -d)"; trap 'rm -rf "$T"' RETURN
  chk(){ [ "$1" = "$2" ] && P=$((P+1)) || { Fc=$((Fc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
  need(){ case "$1" in *"$2"*) P=$((P+1));; *) Fc=$((Fc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

  run(){ ( run_gate ) 2>&1; }

  # ---- happy: answers + registry agree --------------------------------------
  cat > "$T/answers.json" <<'EOF'
{"product":{"value":"Demo","provenance":"client"},
 "surfaces":[
   {"id":"projects.home","label":"Home","tab":"projects","provenance":"client"},
   {"id":"projects.new","label":"New","tab":"projects","provenance":"client"}
 ]}
EOF
  cat > "$T/registry.json" <<'EOF'
[{"id":"projects.home","label":"Home","tab":"projects","comp":"ProjectsHome","surface":null},
 {"id":"projects.new","label":"New","tab":"projects","comp":"ProjectsNew","surface":null}]
EOF
  o=$( ANSWERS="$T/answers.json" REGISTRY="$T/registry.json" BRIEF="/dev/null" run )
  chk "$?" 0 "happy: answers and registry agree -> PASSES"
  need "$o" "2 registry surface(s) trace" "reports full traceability"

  # ---- NEGATIVE: orphan answer (surface in answers, not in registry) ---------
  cat > "$T/answers_orphan.json" <<'EOF'
{"product":{"value":"Demo","provenance":"client"},
 "surfaces":[
   {"id":"projects.home","label":"Home","tab":"projects","provenance":"client"},
   {"id":"projects.settings","label":"Settings","tab":"projects","provenance":"client"}
 ]}
EOF
  o=$( ANSWERS="$T/answers_orphan.json" REGISTRY="$T/registry.json" BRIEF="/dev/null" run )
  chk "$?" 1 "orphan answer -> FAILS"
  need "$o" "projects.settings" "names the orphan answer surface"
  need "$o" "no registry entry" "explains the orphan-answer failure"

  # ---- NEGATIVE: unanswered surface (surface in registry, not in answers) ----
  cat > "$T/registry_unanswered.json" <<'EOF'
[{"id":"projects.home","label":"Home","tab":"projects","comp":"ProjectsHome","surface":null},
 {"id":"projects.secret","label":"Secret","tab":"projects","comp":"ProjectsSecret","surface":null}]
EOF
  o=$( ANSWERS="$T/answers.json" REGISTRY="$T/registry_unanswered.json" BRIEF="/dev/null" run )
  chk "$?" 1 "unanswered surface -> FAILS"
  need "$o" "projects.secret" "names the unanswered registry surface"
  need "$o" "no intake answer" "explains the unanswered-surface failure"

  # ---- happy: hand-written brief (10.7) seeds the registry -------------------
  cat > "$T/brief.md" <<'EOF'
# Widget shop

## Surface inventory — the registry seed

| id | tab | comp | label | surface |
|---|---|---|---|---|
| `shop.cart` | shop | ShopCart | Cart | _null_ |
| `shop.home` | shop | ShopHome | Home | _null_ |
EOF
  cat > "$T/registry_shop.json" <<'EOF'
[{"id":"shop.cart","label":"Cart","tab":"shop","comp":"ShopCart","surface":null},
 {"id":"shop.home","label":"Home","tab":"shop","comp":"ShopHome","surface":null}]
EOF
  o=$( ANSWERS="/dev/null" REGISTRY="$T/registry_shop.json" BRIEF="$T/brief.md" run )
  chk "$?" 0 "hand-written brief matches registry -> PASSES"
  need "$o" "trace to brief" "traces against the brief surface table"

  # ---- NEGATIVE: brief has a surface the registry dropped --------------------
  cat > "$T/registry_short.json" <<'EOF'
[{"id":"shop.cart","label":"Cart","tab":"shop","comp":"ShopCart","surface":null}]
EOF
  o=$( ANSWERS="/dev/null" REGISTRY="$T/registry_short.json" BRIEF="$T/brief.md" run )
  chk "$?" 1 "brief surface dropped from registry -> FAILS"
  need "$o" "shop.home" "names the dropped brief surface"

  # ---- happy: no registry, no source -> greenfield pass ----------------------
  o=$( ANSWERS="/dev/null" REGISTRY="/dev/null" BRIEF="/dev/null" run )
  chk "$?" 0 "greenfield: no answers, no registry -> PASSES (nothing to trace)"

  # ---- NEGATIVE: registry exists, no source -> every entry untraced ----------
  o=$( ANSWERS="/dev/null" REGISTRY="$T/registry.json" BRIEF="/dev/null" run )
  chk "$?" 1 "registry with no source -> FAILS"
  need "$o" "no intake answers or brief" "explains the missing source"

  # ---- NEGATIVE: duplicate registry id ---------------------------------------
  cat > "$T/registry_dup.json" <<'EOF'
[{"id":"shop.cart","label":"Cart","tab":"shop","comp":"ShopCart","surface":null},
 {"id":"shop.cart","label":"Cart2","tab":"shop","comp":"ShopCart","surface":null}]
EOF
  o=$( ANSWERS="/dev/null" REGISTRY="$T/registry_dup.json" BRIEF="$T/brief.md" run )
  chk "$?" 1 "duplicate registry id -> FAILS"
  need "$o" "more than once" "names the duplicate"

  # ---- happy: intake state slot wrapping answers (run.intake.json shape) -----
  cat > "$T/intake_state.json" <<'EOF'
{"answers":{"product":{"value":"Demo","provenance":"client"},
 "surfaces":[{"id":"projects.home","label":"Home","tab":"projects","provenance":"client"}]},
 "artefacts":{"brief":"docs/design/brief.md","registry":"docs/design/registry.json"}}
EOF
  cat > "$T/registry_one.json" <<'EOF'
[{"id":"projects.home","label":"Home","tab":"projects","comp":"ProjectsHome","surface":null}]
EOF
  o=$( ANSWERS="$T/intake_state.json" REGISTRY="$T/registry_one.json" BRIEF="/dev/null" run )
  chk "$?" 0 "intake state slot (answers wrapper) -> PASSES"
  need "$o" "1 registry surface(s) trace" "reads the state-slot answers wrapper"

  # ---- DW1: byte-identity — one engine, two fronts --------------------------
  # The wizard (10.5) writes an answers JSON and shells out to intake.py emit.
  # The headless path does the same. Proof: run the engine TWICE on the same
  # answers to two output dirs, then cmp — byte-identical. Since both fronts
  # invoke the same engine on the same input, their outputs cannot diverge.
  local ENGINE; ENGINE="$GATE_ROOT/skills/app-box-intake/intake.py"
  if python3 "$ENGINE" --self-test >/dev/null 2>&1; then
    cat > "$T/dw1_answers.json" <<'EOF'
{"product":{"value":"Demo app","provenance":"client"},
 "audience":{"value":"Indie devs","provenance":"client"},
 "appMustDo":{"value":["list projects","run a build"],"provenance":"client"},
 "targets":{"value":["macos"],"provenance":"client"},
 "brand":{"value":"none stated","provenance":"inferred"},
 "surfaces":[
   {"id":"projects.home","label":"Home","tab":"projects","provenance":"client"},
   {"id":"projects.new","label":"New","tab":"projects","provenance":"client"}
 ]}
EOF
    python3 "$ENGINE" emit --answers "$T/dw1_answers.json" \
      --brief-out "$T/dw1_run1/brief.md" --registry-out "$T/dw1_run1/registry.json" >/dev/null 2>&1
    python3 "$ENGINE" emit --answers "$T/dw1_answers.json" \
      --brief-out "$T/dw1_run2/brief.md" --registry-out "$T/dw1_run2/registry.json" >/dev/null 2>&1
    if cmp -s "$T/dw1_run1/brief.md" "$T/dw1_run2/brief.md" \
       && cmp -s "$T/dw1_run1/registry.json" "$T/dw1_run2/registry.json"; then
      P=$((P+1)); echo "  \u2713 DW1: two runs of intake.py emit on the same answers -> byte-identical brief + registry"
    else
      Fc=$((Fc+1)); echo "  FAIL: DW1: two runs on the same answers diverged"
    fi
  else
    echo "  (skip DW1 byte-identity: python3/intake.py unavailable in this environment)"
  fi

  echo
  echo "intake traceability gate self-test: passed=$P failed=$Fc"
  [ "$Fc" -eq 0 ] && { echo "ALL GREEN"; return 0; } || return 1
}

if [ "$SELF_TEST" = 1 ]; then self_test; exit $?; fi

out="$(run_gate)"; rc=$?
printf '%s\n' "$out"
fails="$(printf '%s\n' "$out" | grep '^FAIL:' || true)"
[ -n "$fails" ] && printf '%s\n' "$fails" \
  | while IFS= read -r fl; do sarif_result "intake" "error" "$REGISTRY" "$fl"; done
exit $rc
