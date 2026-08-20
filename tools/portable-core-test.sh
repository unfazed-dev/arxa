#!/usr/bin/env bash
# portable-core-test.sh — smoke + pressure + stress + portability tests for the
# portable core (install.sh, the generated PATH wrapper, the AOT binary).
#
# The portable core's whole claim is "works from any checkout on any machine",
# replacing a hand-written shim that hard-coded one Mac's absolute path. These
# tests exist to prove that claim rather than assert it.
#
#   ./tools/portable-core-test.sh              # all suites
#   ./tools/portable-core-test.sh smoke        # one suite
#   ./tools/portable-core-test.sh stress -v    # verbose
#
# Suites: smoke pressure stress portability
#
# NOTE ON STREAMS: `appbox --help` writes to STDERR and produces zero bytes on
# stdout (verified). Assertions about produced output therefore use a verb that
# actually writes stdout, such as `design doctor`. Getting this backwards makes
# a passing binary look broken.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BIN="$REPO/.build/appbox"
VERBOSE=0
SUITES=()
for a in "$@"; do
  case "$a" in
    -v|--verbose) VERBOSE=1 ;;
    smoke|pressure|stress|portability) SUITES+=("$a") ;;
    *) echo "usage: $0 [smoke|pressure|stress|portability] [-v]" >&2; exit 2 ;;
  esac
done
[ ${#SUITES[@]} -eq 0 ] && SUITES=(smoke pressure stress portability)

PASS=0; FAIL=0; SKIP=0
FAILED_NAMES=()
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"; restore_source' EXIT

# The stale-detection tests must dirty a source file. Always put it back.
TOUCHED="$REPO/appboxd/lib/harness.dart"
restore_source() {
  [ -n "${TOUCHED:-}" ] && git -C "$REPO" checkout -- "$TOUCHED" 2>/dev/null
  return 0
}

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33mSKIP\033[0m %s — %s\n' "$1" "${2:-}"; }
note() { [ "$VERBOSE" -eq 1 ] && printf '       %s\n' "$1"; return 0; }
head_() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# assert helpers -------------------------------------------------------------
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
yes_() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "${3:-condition false}"; fi; }

wrapper_path() { command -v appbox 2>/dev/null; }

# Wall-clock a command in ms. Uses `/usr/bin/time -p` (reports seconds to 2dp)
# rather than bracketing with two `python3 -c` calls — those measure python's
# own ~80ms startup as if it were the command's, which turns a 10ms binary into
# a "127ms" one and would hide a real regression behind interpreter noise.
time_ms() {
  local real
  # `time -p` writes its report to STDERR, so the command's stdout goes to
  # /dev/null but stderr must stay on the pipe or the measurement vanishes and
  # every timing assertion silently passes at 0ms.
  real=$( { /usr/bin/time -p "$@" >/dev/null; } 2>&1 | awk '/^real/{print $2}' )
  if [ -z "$real" ]; then echo "-1"; return; fi   # -1 fails loudly, never passes
  awk -v r="$real" 'BEGIN{printf "%d", r*1000}'
}

# ── SMOKE ────────────────────────────────────────────────────────────────────
suite_smoke() {
  head_ "SMOKE — does the installed core work at all"

  [ -x "$REPO/install.sh" ]; yes_ "install.sh exists and is executable" $?

  "$REPO/install.sh" --check >"$TMPD/check.out" 2>&1
  yes_ "install.sh --check runs clean" $?
  note "$(cat "$TMPD/check.out")"

  if [ -x "$BIN" ]; then ok "AOT binary present at .build/appbox"; else
    bad "AOT binary present at .build/appbox" "run ./install.sh first"; return; fi

  local w; w="$(wrapper_path)"
  if [ -n "$w" ]; then ok "appbox resolves on PATH ($w)"; else bad "appbox resolves on PATH"; fi

  # The binary must produce real stdout, from any cwd.
  local bytes; bytes=$(cd / && "$BIN" design doctor 2>/dev/null | wc -c | tr -d ' ')
  if [ "$bytes" -gt 50 ]; then ok "binary produces stdout from cwd=/ ($bytes bytes)"; else
    bad "binary produces stdout from cwd=/" "got $bytes bytes"; fi

  # THE asset test: a binary outside the repo tree silently loses the designer
  # runtime. `design doctor` is the canary — it must report no MISS lines.
  local miss; miss=$(cd / && "$BIN" design doctor 2>/dev/null | grep -c "MISS" || true)
  is "designer assets resolve (no MISS lines)" "$miss" "0"

  # Speed is functional, not cosmetic: hooks fire per tool call.
  local ms; ms=$(time_ms "$BIN" --help)
  if [ "$ms" -lt 0 ]; then bad "binary starts fast" "measurement failed"
  elif [ "$ms" -lt 200 ]; then ok "binary starts fast (${ms}ms < 200ms)"
  else bad "binary starts fast" "${ms}ms — too slow for a per-tool-call hook"; fi
}

# ── PRESSURE ─────────────────────────────────────────────────────────────────
suite_pressure() {
  head_ "PRESSURE — the failure paths, deliberately provoked"
  local w; w="$(wrapper_path)"
  if [ -z "$w" ]; then skip "pressure suite" "appbox not on PATH"; return; fi

  # 1. Stale + APPBOX_FAST: must WARN on stderr, still run, exit 0, NOT compile.
  touch "$TOUCHED"
  local err ec ms
  ms=$(APPBOX_FAST=1 time_ms "$w" design doctor)
  touch "$TOUCHED"
  err=$(APPBOX_FAST=1 "$w" design doctor 2>&1 >/dev/null); ec=$?
  if grep -q "STALE" <<<"$err"; then ok "stale+FAST warns on stderr"; else
    bad "stale+FAST warns on stderr" "stderr: ${err:0:120}"; fi
  is "stale+FAST still exits 0" "$ec" "0"
  if [ "$ms" -lt 0 ]; then bad "stale+FAST does NOT pay for a compile" "measurement failed"
  elif [ "$ms" -lt 1000 ]; then ok "stale+FAST does NOT pay for a compile (${ms}ms)"
  else bad "stale+FAST does NOT pay for a compile" "${ms}ms — it rebuilt"; fi

  # 2. Stale + interactive: must rebuild, then be fast again.
  touch "$TOUCHED"
  err=$("$w" design doctor 2>&1 >/dev/null)
  if grep -qi "rebuilding" <<<"$err"; then ok "stale+interactive rebuilds"; else
    bad "stale+interactive rebuilds" "stderr: ${err:0:120}"; fi
  ms=$(time_ms "$w" design doctor)
  if [ "$ms" -lt 0 ]; then bad "fast again after rebuild" "measurement failed"
  elif [ "$ms" -lt 300 ]; then ok "fast again after rebuild (${ms}ms)"
  else bad "fast again after rebuild" "${ms}ms"; fi

  # 3. Missing binary + APPBOX_FAST: exit 127 loudly, never a silent no-op.
  mv "$BIN" "$TMPD/stash"
  err=$(APPBOX_FAST=1 "$w" design doctor 2>&1 >/dev/null); ec=$?
  is "missing+FAST exits 127" "$ec" "127"
  if grep -q "install.sh" <<<"$err"; then ok "missing+FAST names the fix"; else
    bad "missing+FAST names the fix" "stderr: ${err:0:120}"; fi
  mv "$TMPD/stash" "$BIN"

  # 4. install.sh must refuse a directory that is not an app-box checkout.
  mkdir -p "$TMPD/notrepo"; cp "$REPO/install.sh" "$TMPD/notrepo/"
  ( cd "$TMPD/notrepo" && sh ./install.sh >/dev/null 2>&1 ); ec=$?
  if [ "$ec" -ne 0 ]; then ok "install.sh refuses a non-appbox dir (exit $ec)"; else
    bad "install.sh refuses a non-appbox dir" "it exited 0"; fi

  # 5. Idempotence: a second run must succeed and not change the wrapper.
  local before after
  before=$(shasum -a 256 "$w" | cut -d' ' -f1)
  "$REPO/install.sh" --no-build >/dev/null 2>&1; ec=$?
  after=$(shasum -a 256 "$w" | cut -d' ' -f1)
  is "install.sh --no-build exits 0" "$ec" "0"
  is "wrapper is byte-identical on re-run (idempotent)" "$after" "$before"
}

# ── STRESS ───────────────────────────────────────────────────────────────────
suite_stress() {
  head_ "STRESS — concurrency, the race that corrupts binaries"
  local w; w="$(wrapper_path)"
  if [ -z "$w" ]; then skip "stress suite" "appbox not on PATH"; return; fi
  local N=12

  # N concurrent invocations against a STALE binary: every one of them decides
  # to rebuild. Each compiles to a PID-unique temp then atomically renames, so
  # no process may ever observe a half-written binary.
  touch "$TOUCHED"
  local i
  for ((i=1;i<=N;i++)); do
    ( "$w" design doctor >"$TMPD/s$i.out" 2>"$TMPD/s$i.err"; echo $? >"$TMPD/s$i.ec" ) &
  done
  wait

  local good=0 bad_n=0 detail=""
  for ((i=1;i<=N;i++)); do
    local ec; ec=$(cat "$TMPD/s$i.ec" 2>/dev/null || echo 99)
    local b; b=$(wc -c <"$TMPD/s$i.out" | tr -d ' ')
    if [ "$ec" = "0" ] && [ "$b" -gt 50 ]; then good=$((good+1)); else
      bad_n=$((bad_n+1)); detail="proc$i exit=$ec bytes=$b"; fi
  done
  is "all $N concurrent stale invocations succeeded" "$good" "$N"
  [ "$bad_n" -gt 0 ] && note "$detail"

  # The binary must survive the race intact and executable.
  "$BIN" design doctor >/dev/null 2>&1
  yes_ "binary intact and executable after the race" $?

  # No PID-temp files may be left behind.
  local leaks; leaks=$(find "$REPO/.build" -name '.appbox.*' 2>/dev/null | wc -l | tr -d ' ')
  is "no leftover .appbox.PID temp files" "$leaks" "0"

  # Replacing the binary under a running process must not disturb that process
  # (rename swaps the directory entry; the running image keeps its inode).
  ( "$BIN" design doctor >"$TMPD/long.out" 2>&1 ) &
  local pid=$!
  cp "$BIN" "$TMPD/copy"; mv -f "$TMPD/copy" "$BIN"
  wait $pid; local lec=$?
  is "in-flight process unaffected by binary replacement" "$lec" "0"

  # N concurrent invocations against a FRESH binary: pure read concurrency.
  for ((i=1;i<=N;i++)); do ( "$w" design doctor >/dev/null 2>&1; echo $? >"$TMPD/f$i.ec" ) & done
  wait
  local fgood=0
  for ((i=1;i<=N;i++)); do [ "$(cat "$TMPD/f$i.ec")" = "0" ] && fgood=$((fgood+1)); done
  is "all $N concurrent fresh invocations succeeded" "$fgood" "$N"
}

# ── PORTABILITY ──────────────────────────────────────────────────────────────
suite_portability() {
  head_ "PORTABILITY — a different path on a different filesystem"
  mkdir -p "$TMPD/clone" "$TMPD/prefix"
  # Resolve to the PHYSICAL path: on macOS `mktemp -d` yields /var/... while
  # install.sh (correctly) resolves it through the /var -> /private/var symlink
  # to /private/var/.... Comparing against the logical path fails a wrapper that
  # is in fact right.
  local C P
  C="$(cd "$TMPD/clone" && pwd -P)"
  P="$(cd "$TMPD/prefix" && pwd -P)"

  # Export the committed tree, then overlay any uncommitted install.sh so the
  # test works before the commit lands.
  git -C "$REPO" archive HEAD | tar -x -C "$C" 2>/dev/null
  # Overlay the WORKING-TREE copies of what we are testing, so the suite checks
  # the code you just wrote rather than the last commit. Without this, a fix
  # that is not yet committed looks like a failure and a regression that is not
  # yet committed looks like a pass.
  cp "$REPO/install.sh" "$C/install.sh"; chmod +x "$C/install.sh"
  mkdir -p "$C/hooks"; cp "$REPO"/hooks/*.js "$C/hooks/" 2>/dev/null
  [ -f "$C/config/appbox.config.json" ]; yes_ "exported tree looks like a checkout" $?

  if ! sh "$C/install.sh" --prefix "$P" >"$TMPD/inst.log" 2>&1; then
    bad "install.sh succeeds in the exported clone" "$(tail -3 "$TMPD/inst.log")"; return
  fi
  ok "install.sh succeeds in the exported clone"

  # The generated wrapper must point at the clone and mention no other checkout.
  if grep -q "^REPO='$C'" "$P/appbox"; then ok "wrapper points at the clone"; else
    bad "wrapper points at the clone" "$(grep '^REPO=' "$P/appbox")"; fi
  if grep -q "$REPO" "$P/appbox"; then
    bad "wrapper leaks the original checkout path" "$(grep -n "$REPO" "$P/appbox" | head -1)"
  else ok "wrapper does not leak the original checkout path"; fi

  # The clone must resolve ITS OWN designer assets, run from an unrelated cwd.
  local miss; miss=$(cd / && "$P/appbox" design doctor 2>/dev/null | grep -c "MISS" || true)
  is "clone resolves its own designer assets" "$miss" "0"

  # Independence: hide the original binary; the clone must be unaffected.
  mv "$BIN" "$TMPD/orig_stash" 2>/dev/null
  ( cd / && "$P/appbox" design doctor >/dev/null 2>&1 ); local ec=$?
  mv "$TMPD/orig_stash" "$BIN" 2>/dev/null
  is "clone works while the original binary is absent" "$ec" "0"

  # REGRESSION: the guard must deny through a SYMLINKED path prefix. It resolves
  # its own repo root with realpath; if the target is not resolved the same way,
  # a symlinked prefix (macOS /tmp, /var -> /private/...) makes the target look
  # like it lives outside the repo and the write is silently ALLOWED — a
  # fail-open in the security path. Caught only by installing from an export
  # under $TMPDIR, so it is pinned here.
  local logical="$TMPD/clone/appboxd/lib/regress.dart"   # unresolved /var/... form
  echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$logical\"}}" \
    | APPBOX_GUARD_MODE=using node "$C/hooks/appbox-guard.js" >/dev/null 2>&1
  is "guard denies through a symlinked path prefix (fail-open regression)" "$?" "2"

  # And the physical form must deny too, so the fix did not just move the bug.
  echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$C/appboxd/lib/regress.dart\"}}" \
    | APPBOX_GUARD_MODE=using node "$C/hooks/appbox-guard.js" >/dev/null 2>&1
  is "guard denies through the physical path" "$?" "2"
}

for s in "${SUITES[@]}"; do "suite_$s"; done

printf '\n\033[1m── %d passed, %d failed, %d skipped ──\033[0m\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed:\n'; printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
