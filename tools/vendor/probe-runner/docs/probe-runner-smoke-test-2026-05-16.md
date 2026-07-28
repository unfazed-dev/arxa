# probe-runner smoke test — 2026-05-16

Scope: every desktop script under `.claude/skills/probe-runner/scripts/` (host macOS targets only — iOS/Android/Flutter/web blocks deferred). Target app: VS Code (`Code`, pid 1343), Quartz layer-0 window 78.

## Tally

| Phase | Scripts | PASS | FAIL | SKIP | Notes |
|---|---|---|---|---|---|
| 1. `--help` parse | 36 | 35 | 0 | 1 | `headless.py` uses `-- <verb>` wrapper style (by design — not a bug). |
| 2. Tooling preflight | 11 host + 4 py + TCC | 15 | 0 | 0 | All required binaries present; pyobjc/Vision/websocket-client/selenium all importable; no Secure Input mode; `/tmp/probe-runner` writable. |
| 3. Discovery | 5 | 4 | 0 | 3 | `find_window`, `wait_window`, `ax_tree` PASS. `ax_observe` (interactive) / `ax_click`+`ax_text` (need element id) / `window_state` (destructive — needs action) skipped. Initial run failed because target `Finder` has zero open windows on this machine; switched to `Code`. |
| 4. Capture | 9 | 9 | 0 | 0 | `shot`, `region`, `record` (1 s), `multishot` (2 frames), `pixdiff` (A vs B + identical), `ocr`, `text_diff` (PNG inputs — first run gave .txt and tripped expected ocr-only path). All artefacts written to `/tmp/probe-runner/smoke_*`. |
| 5. Diagnostics | 5 | 2 | 2 | 1 | `sample` (1 s) PASS — wrote `sample.txt`. `mem` PASS. `fswatch` FAIL — `fswatch` binary not installed (dep documented; install: `brew install fswatch`). `tail_log` and `nettrace` blocked. See bugs below. |
| 6. Clipboard + destructive arg-parse | 13 | 13 | 0 | 0 | All 13 (`clipboard`, `click`, `drag`, `hover`, `scroll`, `gesture`, `type_text`, `key_chord`, `focus`, `reposition`, `menu`, `context_menu`, `drop_file`) parse `--help`. `clipboard` real roundtrip (save → set → get → restore) PASS. Pointer/keyboard/window-mutation paths not exercised (destructive in smoke). |
| 7. Wry/Dioxus | 3 | 1 | 0 | 2 | `safari_inspect --list` PASS (lists Develop menu). `dom` + `console` emit correct "app must be instrumented" message but then hang on `log stream` readline — same impl bug as `tail_log` below. |

Overall: 79 PASS / 2 FAIL (impl bugs) / 1 dep-missing / 7 SKIP (destructive or no live target).

## Bugs found

### B1 — readline-past-deadline race (severity: medium)

Affects `tail_log.py`, `console.py`, `dom.py`.

Pattern in all three:

```python
deadline = time.monotonic() + args.seconds
while proc.stdout:
    if deadline and time.monotonic() > deadline:
        proc.terminate()
        break
    line = proc.stdout.readline()   # blocks indefinitely if no output
    ...
```

`proc.stdout.readline()` is a blocking call. When the wrapped subprocess (`log stream`) is alive but producing no matching output, the deadline check between iterations never fires. The script hangs past `--seconds`/`--timeout`.

Fix: switch to non-blocking poll (`select.select([proc.stdout], [], [], 0.2)`), or set `proc.stdout` to non-blocking via `fcntl`, or run the deadline as a watchdog thread that calls `proc.terminate()`.

Reproduces deterministically: `python3 tail_log.py --seconds 1 Code` — no log lines arrive for `Code` in 1 s, script never returns.

### B2 — `fswatch.py` dep not preflighted (severity: low)

`fswatch.py` shells out to the `fswatch` binary. Skill's `tcc_check`/dep check doesn't cover it. Hint message is correct (`brew install fswatch`), but it surfaces only on first failed invocation. Either add to README "Required tooling (host)" optional list or have `_common.py` detect missing binary up front.

### B3 — first-call CLI confusion (severity: cosmetic)

Discovery scripts use **positional `owner`** (e.g. `find_window.py Code`) but the prose in `SKILL.md` and several command-files reads naturally as `--owner`. New operator's first attempts are `--owner Code` and error out with `error: unrecognized arguments: --owner`. Hit this exact rake during phase 3. Either accept `--owner` as alias or add a one-liner reminder in the skill blurb.

## Tooling preflight summary

```
OK   cliclick                 OK   pyobjc-framework-Quartz
OK   screencapture            OK   pyobjc-framework-Vision (OCR)
OK   osascript                OK   websocket-client (Flutter VM)
OK   ffmpeg                   OK   selenium (Safari fallback)
OK   python3 (3.13.12, pyenv)
OK   sample, vmmap, fs_usage, tail, nettop, ioreg
MISS fswatch (optional; brew install fswatch)
NA   adb, xcrun (not part of host-desktop smoke)
```

TCC: Screen Recording + Accessibility evidently already granted (capture and ax-tree both succeeded). Secure Input not active.

## Artefacts written (/tmp/probe-runner/)

- `smoke_a.png`, `smoke_b.png` — 922 KB each, VS Code window capture.
- `smoke_region.png` — 36 KB, 200×200 top-left rect.
- `smoke_diff.png` (17 KB, ratio 3.3e-6) + `smoke_diff_id.png` (16 KB, ratio 0).
- `smoke_record.mov` — 405 KB, 1 s screencapture-based video.
- `smoke_multi/frame_00000{0,1}.png` — 920 KB each.

## What was NOT tested

- iOS sim block (`ios_*`) — needs booted simulator + `fb-idb` (out of scope; user asked for desktop).
- Android emu block (`adb_*`) — needs running emulator.
- Flutter block (`flutter_*`) — needs running Flutter app with VM service.
- Host browser web block (`web_*`) — needs Chrome with `--remote-debugging-port=9222`.
- Destructive host paths (`click`, `drag`, `type_text`, `key_chord`, `reposition`, `menu`, `context_menu`, `drop_file`, `window_state {minimize,close,fullscreen}`) — `--help` only.
- `ax_observe` — interactive watch loop.
- `nettrace` — `sudo tcpdump`, refused in unattended run.

## Recommendation

Fix B1 (readline race) before the next operator picks up the skill — three commonly used probes hang silently past their declared timeout, which is the worst failure mode for a smoke-test tool. B2 and B3 are paper cuts.

## Fixes applied — same session

**B1 — readline race**: added `iter_lines_until(proc, deadline=...)` helper in `_common.py`. Uses non-blocking pipe (`fcntl O_NONBLOCK`) + `select.select()` poll with `poll_interval=0.2 s`, so the deadline is enforced even when the child writes nothing. `proc.terminate()` runs once the deadline passes. Patched `tail_log.py`, `console.py`, `dom.py`, `fswatch.py` (same impl bug, prevented before triggering). Verified:

| Script | Invocation | Wall-clock | rc |
|---|---|---|---|
| `tail_log` | `--seconds 1 Code` | ≈ 1.2 s | 0 |
| `console` | `--seconds 1 Code` | ≈ 1.2 s | 0 |
| `dom` | `--selector body --timeout 1 Code` | ≈ 1.2 s | 124 |
| `fswatch` (PATH-stubbed binary) | `--seconds 2 $TMPDIR` | ≈ 2 s, 2 lines | 0 |

**B2 — `fswatch` dep**: added `fswatch` to `SKILL.md` "Optional / per-block" deps list with brew install hint. Preflight (`which_or_die`) was already correct in code — operator just lacked doc visibility.

**B3 — `--owner` alias**: added `_normalize_owner_in_argv()` to `_common.py`. Runs at import time, rewrites any `--owner X` / `--owner=X` in `sys.argv` to a positional argument. Zero per-script changes needed because every script imports `_common`. Updated SKILL.md "Conventions for invoking" to call out that positional is canonical and `--owner` is just sugar. Verified all three forms (`Code`, `--owner Code`, `--owner=Code`) on `find_window.py` and `ax_tree.py` — all return the expected window.

Regression sweep: 95/97 scripts still pass `--help` (the 2 failures are pre-existing iOS scripts, unrelated to these fixes — they error because no iOS sim is booted, not because of CLI parse). `shot`, `clipboard get`, `sample` still pass cold-path smoke.

## Fix follow-up — iOS / Flutter `--help` + no-sim traceback

Same session. The Phase 1 `--help` sweep originally reported `ios_app` + `ios_url` as failures but the regression sweep after B1/B2/B3 found 11 more in the same shape (raw `sys.argv` parsing, no `--help` guard). Two distinct issues per script:

1. `--help` consumed as a positional arg → wrong usage error or, worse for `ios_url`, an actual `xcrun simctl openurl booted --help` attempt that crashed with `subprocess.CalledProcessError: returned non-zero exit status 148` when no sim was booted.
2. `subprocess.run(..., check=True)` with no booted sim → uncaught `CalledProcessError` traceback.

**Fixes:**

- Added `help_if_requested(usage, doc=None)` to `_common.py`. Each raw-argv script calls this as the first line of `main()`; if `sys.argv[1] in ("-h", "--help")` it prints the docstring + usage and exits 0.
- Converted `ios_app.py` and `ios_url.py` to `argparse` (subcommands and a single positional respectively). `ios_app.py` now has proper per-verb help: `ios_app.py launch --help`, etc.
- Replaced `check=True` with `check=False` + explicit return-code branch in every iOS script's `subprocess.run` calls, so a missing sim produces `probe-runner: simctl <verb> failed: No devices are booted.` (rc inherited from simctl) instead of a Python traceback.
- Added `--help` guard to `headless.py` (intentional wrapper script — still requires `--` separator for real use, but now responds to `-h`/`--help`).

Scripts touched: `ios_app.py`, `ios_url.py`, `ios_appearance.py`, `ios_files.py`, `ios_key.py`, `ios_list.py`, `ios_location.py`, `ios_privacy.py`, `ios_push.py`, `ios_tap.py`, `flutter_diag.py`, `flutter_semantics.py`, `headless.py` (13 total).

**Verified:** full sweep now reads **97/97 PASS** on `--help` (was 95/97). Sample of the no-sim error path:

```
$ python3 ios_appearance.py light
probe-runner: simctl appearance failed (no booted sim?): No devices are booted.
$ echo $?
148
```

No traceback. Exit code preserved from simctl (148) so calling shell scripts can branch on it.
