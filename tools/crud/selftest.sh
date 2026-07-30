#!/usr/bin/env bash
# tools/crud/selftest.sh — R5 suite for the feature-CRUD layer.
#
# The proof is the round-trip (feature-crud.md: "the test that is the whole
# contract"): create a feature, delete it, and the tree must be byte-identical to
# before the create. Asserted with `git status --porcelain` inside a temp repo
# (R5: never `git diff --exit-code` — a delete that leaves an untracked orphan
# file is the exact case git-diff cannot see, and porcelain can).
#
# Every gate has a negative case (R5): duplicate id, no-confirm delete, orphan
# pair, crash-mid-delete, and the generated-layer guard (CRUD must never write
# structure.json or lib/**).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CRUD="$ROOT/tools/crud/crud.py"
PY="python3"

pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

GIT=(git -c user.name=crud-selftest -c user.email=crud@test -c commit.gpgsign=false)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ---- fresh design root, committed as the baseline tree ----------------------
seed(){
  rm -rf "$T/app"; mkdir -p "$T/app/models/screens_model"
  printf '[]\n' > "$T/app/models/screens_model/registry.json"
  ( cd "$T/app" && "${GIT[@]}" init -q && "${GIT[@]}" add -A && "${GIT[@]}" commit -qm baseline )
}
# porcelain: empty ⇒ working tree byte-identical to the committed baseline.
# -uall lists each untracked file (default collapses a new dir to '?? ui/', which
# would hide the exact orphan file the round-trip exists to catch — R5).
porcelain(){ ( cd "$T/app" && "${GIT[@]}" status --porcelain --untracked-files=all ); }
# git cannot see empty dirs, so a rename/delete that leaves an empty folder is
# debris porcelain misses — assert no empty dirs exist either (.git excluded).
empty_dirs(){ find "$T/app" -type d -empty -not -path "*/.git/*"; }

echo "== CRUD R5 suite =="

# ============================================================================
# READ
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Threads >/dev/null
o="$($PY "$CRUD" list "$T/app" 2>&1)"; chk "$?" 0 "list exits 0"
need "$o" "inbox.threads" "list names the feature"
need "$o" "[frozen]" "list tags a surfaced feature as frozen"
o="$($PY "$CRUD" show "$T/app" inbox.threads 2>&1)"; chk "$?" 0 "show exits 0"
need "$o" '"id": "inbox.threads"' "show prints the entry as JSON"

# ============================================================================
# CREATE — entry + pair appear; porcelain sees the new files
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Threads >/dev/null
chk "$?" 0 "create exits 0"
[ -f "$T/app/ui/views/inbox/threads/threads_view.html" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: create wrote the _view.html pair"; }
[ -f "$T/app/ui/views/inbox/threads/threads_viewmodel.js" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: create wrote the _viewmodel.js pair"; }
need "$(cat "$T/app/ui/views/inbox/threads/threads_viewmodel.js")" "surfaceId = 'inbox.threads'" \
  "viewmodel declares its surfaceId (the assertion that removes the fuzzy join)"
o="$(porcelain)"; need "$o" "threads_view" "porcelain sees the newly created pair"

# ============================================================================
# NEGATIVE: duplicate id fails validation (Done-when #3)
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp A --surface s_a_view >/dev/null
o="$($PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp B --surface s_b_view 2>&1)"; rc=$?
chk "$rc" 1 "duplicate id is rejected (id is a stable key, §18)"
need "$o" "already exists" "duplicate names the offending id"
[ -z "$(porcelain | grep s_b)" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: rejected create must not write the s_b pair"; }

# ============================================================================
# UPDATE — content edits; id/surface stay immutable
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Old >/dev/null
$PY "$CRUD" update "$T/app" --id inbox.threads --label "New label" >/dev/null
chk "$?" 0 "update exits 0"
o="$($PY "$CRUD" show "$T/app" inbox.threads)"
need "$o" '"label": "New label"' "update changed the label"
need "$o" '"surface": "stage_shell_inbox_threads_view"' "update left surface unchanged (immutable identity)"
need "$o" '"id": "inbox.threads"' "update left id unchanged (stable key)"

# ============================================================================
# RENAME — new id + migration; old pair removed only AFTER the new exists
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Threads >/dev/null
o="$($PY "$CRUD" rename "$T/app" --from inbox.threads --to inbox.feed \
     --surface stage_shell_inbox_feed_view 2>&1)"; chk "$?" 0 "rename exits 0"
need "$o" "migration recorded" "rename records the explicit migration entry (§18)"
[ -f "$T/app/ui/views/inbox/feed/feed_view.html" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: rename created the new pair"; }
[ ! -e "$T/app/ui/views/inbox/threads" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: rename must remove the old pair dir (no debris)"; }
$PY "$CRUD" show "$T/app" inbox.threads 2>&1 >/dev/null; chk "$?" 1 "old id is gone after rename (show fails)"
o="$($PY "$CRUD" show "$T/app" inbox.threads 2>&1)"; need "$o" "no entry" "old id retired from the registry"
need "$(cat "$T/app/models/screens_model/migrations.json")" '"from": "inbox.threads"' \
  "migrations log records the from-id"
need "$(cat "$T/app/models/screens_model/migrations.json")" '"to": "inbox.feed"' \
  "migrations log records the to-id"

# ============================================================================
# Done-when #1 — CREATE → DELETE round-trip: tree byte-identical (the contract)
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Threads >/dev/null
$PY "$CRUD" delete "$T/app" --id inbox.threads --confirm humantok >/dev/null
chk "$?" 0 "delete (with confirm) exits 0"
o="$(porcelain)"; [ -z "$o" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: round-trip left tree changes — porcelain: $o"; }
o="$(empty_dirs)"; [ -z "$o" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: round-trip left empty dir(s) — $o"; }

# ============================================================================
# Done-when #4 — RENAME round-trip: rename then delete leaves no debris
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Threads >/dev/null
$PY "$CRUD" rename "$T/app" --from inbox.threads --to inbox.feed \
     --surface stage_shell_inbox_feed_view >/dev/null
$PY "$CRUD" delete "$T/app" --id inbox.feed --confirm humantok >/dev/null
o="$(porcelain)"; [ -z "$o" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: rename round-trip left debris — porcelain: $o"; }
[ ! -e "$T/app/models/screens_model/migrations.json" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: delete must prune the now-stale migration (no debris)"; }

# ============================================================================
# Done-when #5 — delete refuses to run unattended (no / empty confirm)
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Threads >/dev/null
"${GIT[@]}" -C "$T/app" add -A && "${GIT[@]}" -C "$T/app" commit -qm "feature present" >/dev/null
# --- NEGATIVE: no token → exit 1 and the tree is untouched ---
$PY "$CRUD" delete "$T/app" --id inbox.threads 2>&1 >/dev/null; chk "$?" 1 "no --confirm → exit 1"
o="$(porcelain)"; [ -z "$o" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: refused delete changed the tree — porcelain: $o"; }
# --- NEGATIVE: empty token → exit 1 and the tree is untouched ---
$PY "$CRUD" delete "$T/app" --id inbox.threads --confirm "" 2>&1 >/dev/null; chk "$?" 1 "empty --confirm → exit 1"
o="$(porcelain)"; [ -z "$o" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: empty-confirm delete changed the tree — porcelain: $o"; }

# ============================================================================
# 7.6 — surface:null is a declared exclusion, distinct from deletion
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.splash --shell inbox --comp InboxSplash \
    --surface null --label Splash >/dev/null
chk "$?" 0 "create with surface:null exits 0"
[ ! -e "$T/app/ui/views/inbox/splash" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: surface:null must not create a view pair"; }
need "$($PY "$CRUD" list "$T/app" 2>&1)" "[exclude]" "exclusion is tagged, not frozen"
$PY "$CRUD" delete "$T/app" --id inbox.splash --confirm humantok >/dev/null; chk "$?" 0 "delete exclusion exits 0"
o="$(porcelain)"; [ -z "$o" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: exclusion round-trip left debris — $o"; }

# ============================================================================
# Done-when #6 — crash mid-delete: the next run repairs (idempotent end state)
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Threads >/dev/null
"${GIT[@]}" -C "$T/app" add -A && "${GIT[@]}" -C "$T/app" commit -qm "feature present" >/dev/null
# Simulate the crash window: registry already rewritten (entry gone), pair NOT
# yet removed. This is the dangerous mid-delete state §18 warns about.
printf '[{"id":"inbox.other","label":"x","surface":null,"shell":"inbox","comp":"X"}]\n' \
  > "$T/app/models/screens_model/registry.json"
# verify DETECTS the orphaned pair (entry gone, pair lingers)…
o="$($PY "$CRUD" verify "$T/app" 2>&1)"; chk "$?" 1 "verify flags the crash-left orphan"
need "$o" "orphan" "verify names the orphaned pair"
need "$o" "inbox.threads" "verify names the dead surfaceId"
# …re-running delete (the natural 'next run') converges on the end state, sweeping
# the orphan even though its registry entry is already gone.
$PY "$CRUD" delete "$T/app" --id inbox.threads --confirm humantok >/dev/null; chk "$?" 0 "re-run delete repairs"
$PY "$CRUD" verify "$T/app" >/dev/null 2>&1; chk "$?" 0 "verify clean after repair"
[ ! -e "$T/app/ui/views/inbox/threads" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: repair must remove the orphaned pair dir"; }

# ============================================================================
# NEGATIVE: verify --fix without confirm refuses (removing files is gated)
# ============================================================================
seed
mkdir -p "$T/app/ui/views/inbox/ghost"
printf "export const surfaceId = 'inbox.ghost';\n" > "$T/app/ui/views/inbox/ghost/ghost_viewmodel.js"
: > "$T/app/ui/views/inbox/ghost/ghost_view.html"
$PY "$CRUD" verify "$T/app" --fix 2>&1 >/dev/null; chk "$?" 1 "verify --fix without confirm → exit 1"
[ -e "$T/app/ui/views/inbox/ghost" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: refused --fix must not delete files"; }

# ============================================================================
# 7.7 — CRUD NEVER writes the generated layer (structure.json / lib/**)
# ============================================================================
seed
$PY "$CRUD" create "$T/app" --id inbox.threads --shell inbox --comp InboxThreads \
    --surface stage_shell_inbox_threads_view --label Threads >/dev/null
$PY "$CRUD" rename "$T/app" --from inbox.threads --to inbox.feed \
     --surface stage_shell_inbox_feed_view >/dev/null
$PY "$CRUD" delete "$T/app" --id inbox.feed --confirm humantok >/dev/null
[ ! -e "$T/app/structure.json" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: CRUD must never write structure.json"; }
[ ! -e "$T/app/lib" ] && pass=$((pass+1)) \
  || { failc=$((failc+1)); echo "  FAIL: CRUD must never write lib/** (scaffolded Dart)"; }

echo
echo "crud selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && { echo "ALL GREEN"; exit 0; } || exit 1
