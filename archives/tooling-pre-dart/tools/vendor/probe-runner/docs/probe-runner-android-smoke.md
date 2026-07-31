# probe-runner Android smoke test

**Date:** 2026-05-16
**Host:** macOS Darwin 25.4.0 (Apple Silicon, M4), Python 3 (system)
**Emulator:** Pixel_9 (`emulator-5554`), Android 16, `sdk_gphone64_arm64` (arm64-v8a)
**adb:** `~/Library/Android/sdk/platform-tools/adb` v1.0.41 (build 36.0.0-13206524)
**SDK:** `~/Library/Android/sdk/emulator/emulator` v36.3.10.0
**Skill under test:** `.claude/skills/probe-runner/scripts/adb_*.py` (18 scripts) + `commands/pr-adb-*.md` (18 slash commands)
**Outdir:** `/tmp/probe-runner-smoke/`

## Result matrix

| # | Script | Verbs/args exercised | Verbs untested | Result | Notes |
|---|---|---|---|---|---|
| 1 | `adb_list.py` | (none) | — | PASS | `adb devices`; shows `emulator-5554` |
| 2 | `adb_boot.py` | `list`, `boot Pixel_9`, `kill` | `--wipe` | PASS | Booted ~4s; `kill` returns `OK: killing emulator` |
| 3 | `adb_shot.py` | (none) | — | PASS | 1.39 MB PNG via `screencap -p` + `adb pull` |
| 4 | `adb_record.py` | `--seconds 3` | — | PASS | 65 KB MP4 (ISO Media v2); see bug 2 (stderr leak) |
| 5 | `adb_ui_tree.py` | (none) | — | PASS | 45 KB JSON `{tag, attrs, children}`; see bug 2 |
| 6 | `adb_log.py` | `android --seconds 2` | — | PASS | `logcat` stream; lines returned on stdout |
| 7 | `adb_settings.py` | `darkmode on/off`, `set system screen_brightness 128`, `get system screen_brightness`, `get global animator_duration_scale` | — | PASS | Round-trip set→get returns `128`; darkmode toggles `Night mode: yes` |
| 8 | `adb_perm.py` | `grant com.android.settings android.permission.ACCESS_FINE_LOCATION` | `revoke` | PASS | No-error |
| 9 | `adb_url.py` | `https://example.com/` | — | PASS | Launches default viewer (Chrome) |
| 10 | `adb_key.py` | `HOME` | (no key-name catalogue verified) | PASS | `input keyevent KEYCODE_HOME` |
| 11 | `adb_tap.py` | `100 100` | — | PASS | `input tap` |
| 12 | `adb_swipe.py` | `500 1000 500 200 --duration-ms 300` | — | PASS | `input swipe` |
| 13 | `adb_type.py` | `"smoke test"` | — | PASS | `input text` |
| 14 | `adb_location.py` | `40.7128 -74.0060`, `37.7749 -122.4194` | — | PASS | emu console `geo fix`; returns `OK\n{"lat":..,"lon":..}` |
| 15 | `adb_app.py` | `list` | `launch`, `install`, `uninstall` (need .apk) | PASS | `pm list packages` returns `package:` lines |
| 16 | `adb_files.py` | `push /tmp/smoke_payload.txt /sdcard/smoke_payload.txt`, `pull` round-trip | — | PASS | File mirrored on device, pulled back, content preserved |
| 17 | `adb_push.py` | `am broadcast com.example.PROBE_RUNNER_SMOKE --extra hello=world` | `--component` | PASS | Broadcast `result=0`; **misnamed** — see bug 1 |
| 18 | `adb_cdp.py` | `targets` | `forward`, `eval`, `dom` (need Chrome with `--remote-debugging`) | PASS (env-gated) | Exit 1 with no debugging port — expected when Chrome not launched with CDP flag |

Score: **18 / 18 functional PASS**, 0 functional bugs. Five scripts have partial verb coverage
(`adb_boot --wipe`, `adb_perm revoke`, `adb_app launch/install/uninstall`,
`adb_push --component`, and `adb_cdp forward/eval/dom`) — `--wipe` and `install/uninstall`
not exercised because destructive/state-changing; `cdp` non-`targets` verbs not exercised
because no Chrome was running with `--remote-debugging-port` on the emulator.

Slash commands: **18 / 18** well-formed (YAML frontmatter, `allowed-tools: Bash(python3 *)`,
`$ARGUMENTS` forwarding) and 1:1 mapped to `scripts/adb_<verb>.py`.

## Artefacts produced

```
/tmp/probe-runner-smoke/
├── android-20260516-175755-293964.png      # adb_shot — 1.39 MB
├── android-20260516-175758-193636-ui.json  # adb_ui_tree — 45 KB
├── android-20260516-175812-967969.mp4      # adb_record --seconds 3 — 65 KB
└── window_dump.xml                         # adb_ui_tree intermediate (raw uiautomator)
```

## Bugs and issues found

### Bug 1 — `adb_push.py` is misnamed (NAMING)

`adb_push.py` invokes `am broadcast`, **not** `adb push`. The actual file-push
functionality lives in `adb_files.py push <local> <remote>`. The name collides
with adb's own `adb push` (file copy) and reads as a verb that pushes data to
the device, but the script broadcasts intents.

Observed: tester (this run) and any operator reading the slash-command list
will reach for `adb_push` for file copy and find `adb_files`.

Suggested fix:
- Rename `adb_push.py` → `adb_intent.py` (verb matches behavior).
- Rename `pr-adb-push.md` → `pr-adb-intent.md`.
- Or document prominently in `commands/pr-adb-push.md` and `SKILL.md` table:
  "`adb_push` = intent broadcast; for file push/pull see `adb_files`".

### Bug 2 — `adb_record.py` and `adb_ui_tree.py` leak `adb pull` progress to stderr (COSMETIC)

Both scripts pull a file from the device and print the file path on the last
stdout line. The intermediate `adb pull` call emits progress to stderr:

```
/sdcard/probe-runner.mp4: 1 file pulled, 0 skipped. 37.2 MB/s (65172 bytes in 0.002s)
/tmp/probe-runner-smoke/android-20260516-175812-967969.mp4
```

A caller using `OUT=$(python3 adb_record.py …)` gets both lines in `$OUT`
because shell `$(...)` captures stdout only — *but* this depends on which fd
`adb pull` writes to. In this run the progress line landed in stdout when
running through `bash -c` (not stderr) because `_adb.adb_cmd` doesn't pass
`stderr=DEVNULL` to the pull step. Treating the path as `$(... | tail -1)`
works, but is brittle.

Suggested fix in `_adb.py::adb_cmd`:
```python
subprocess.run(..., stderr=subprocess.DEVNULL if not capture else subprocess.PIPE)
```
or, in `adb_record.py` / `adb_ui_tree.py`, run the pull with stderr suppressed,
since callers only care about the final artefact path.

### Bug 3 — argparse inconsistency, `--help` falls through (COSMETIC)

9 of 18 scripts use argparse (clean `--help`):
`adb_boot`, `adb_cdp`, `adb_log`, `adb_push`, `adb_record`, `adb_shot`,
`adb_swipe`, `adb_ui_tree`. The other 9 use hand-rolled positional checks:
`adb_app`, `adb_files`, `adb_key`, `adb_location`, `adb_perm`, `adb_settings`,
`adb_tap`, `adb_type`, `adb_url`.

For the hand-rolled ones, `--help` is passed straight to `adb shell` and fails
with `adb: no devices/emulators found` or `am start … KEYCODE_--help failed`.
Confusing to a new operator probing the CLI.

Suggested fix: wrap every script in argparse. Single positional + optional
flags for each. ~10 lines per file; consistent UX across the suite.

### Issue 4 — `Medium_Phone_API_36` AVD is arm32, incompatible with Apple Silicon (DOCS)

The AVD installed by Android Studio's default wizard on this machine is
`Medium_Phone_API_36`, configured as `arm` (32-bit). On M4 it fails with:

```
FATAL | CPU Architecture 'arm' is not supported by the QEMU2 emulator,
        (the classic engine is deprecated!)
```

`adb_boot.py boot Medium_Phone_API_36` reports `{"booting": ...}` (success)
because it just `subprocess.Popen`s the emulator and detaches — the silent FATAL
appears only when checking process state. The user waits, nothing connects.

`Pixel_9` (arm64-v8a) works.

Suggested fix:
1. `adb_boot.py boot` should `wait_for_device` for up to N seconds, or at
   least verify the emulator PID is still alive after a short sleep.
2. Or: parse the AVD's `config.ini` (`abi.type=arm`/`arm64-v8a`) and warn
   when arm32 is selected on Apple Silicon.

### Issue 5 — `adb_boot.py boot` requires `ANDROID_HOME` in caller env (DOCS)

`emulator_bin()` falls back to `$ANDROID_HOME/emulator/emulator` if the binary
isn't on PATH. But `subprocess.Popen` then inherits the calling env. If the
operator hasn't exported `ANDROID_HOME`, the emulator binary itself can fail
to locate the SDK (system images, kernel, etc.).

Currently works for me because `~/Library/Android/sdk/emulator/emulator`
self-resolves the SDK root from its own path. But not documented.

Suggested fix in `SKILL.md` "Required tooling (host)":
> Android emulator: install via Android Studio, ensure `$ANDROID_HOME` points
> at `~/Library/Android/sdk` (or set `ANDROID_SDK_ROOT`), then either add
> `$ANDROID_HOME/emulator` and `$ANDROID_HOME/platform-tools` to PATH, or
> rely on `adb_boot.py`'s built-in fallback (`$ANDROID_HOME` env var).

## Operational gotcha (skill-level, not a script bug)

When the screen is locked at boot, `adb_tap` / `adb_swipe` / `adb_type` succeed
at the input layer but produce no visible effect. The `WAKEUP` keyevent must be
sent first:

```bash
adb shell input keyevent KEYCODE_WAKEUP
adb shell input keyevent KEYCODE_MENU  # dismiss lockscreen if PIN-less
```

The skill could either:
1. Auto-wake on first input-class call (`adb_tap`, `adb_swipe`, `adb_type`,
   `adb_key`) by checking `dumpsys power | grep mWakefulness`.
2. Document the gotcha in `SKILL.md` "Failure modes" — "screen locked: inputs
   dispatched but invisible; send KEYCODE_WAKEUP first".

## Reproduction commands

```bash
S=.claude/skills/probe-runner/scripts
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH
export PROBE_RUNNER_OUTDIR=/tmp/probe-runner-smoke

# Boot
python3 $S/adb_boot.py list                     # → Medium_Phone_API_36 / Pixel_9
python3 $S/adb_boot.py boot Pixel_9             # → {"booting":"Pixel_9"}
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done

# Read-only probes
python3 $S/adb_list.py
python3 $S/adb_shot.py
python3 $S/adb_ui_tree.py
python3 $S/adb_log.py android --seconds 2
python3 $S/adb_record.py --seconds 3

# State mutators (safe)
python3 $S/adb_settings.py darkmode on
python3 $S/adb_settings.py set system screen_brightness 128
python3 $S/adb_settings.py get system screen_brightness
python3 $S/adb_url.py "https://example.com/"
python3 $S/adb_location.py 40.7128 -74.0060
python3 $S/adb_perm.py grant com.android.settings android.permission.ACCESS_FINE_LOCATION

# Input
adb shell input keyevent KEYCODE_WAKEUP         # wake screen first
python3 $S/adb_key.py HOME
python3 $S/adb_tap.py 100 100
python3 $S/adb_swipe.py 500 1000 500 200 --duration-ms 300
python3 $S/adb_type.py "smoke test"

# Apps + files
python3 $S/adb_app.py list | head
echo "smoke $(date +%s)" > /tmp/smoke_payload.txt
python3 $S/adb_files.py push /tmp/smoke_payload.txt /sdcard/smoke_payload.txt
python3 $S/adb_files.py pull /sdcard/smoke_payload.txt /tmp/smoke_payload_pulled.txt

# Intent broadcast (misnamed adb_push)
python3 $S/adb_push.py "com.example.PROBE_RUNNER_SMOKE" --extra hello=world

# CDP (gated by Chrome --remote-debugging-port)
python3 $S/adb_cdp.py targets                   # exit 1 unless Chrome launched with CDP

# Teardown
python3 $S/adb_boot.py kill
```

## Follow-ups

- [ ] Rename `adb_push.py` → `adb_intent.py` (and slash command) — bug 1.
- [ ] Suppress `adb pull` stderr noise in `adb_record.py` / `adb_ui_tree.py` (or globally in `_adb.adb_cmd`) — bug 2.
- [ ] Wrap hand-rolled CLIs in argparse for consistent `--help` across all 18 scripts — bug 3.
- [ ] `adb_boot.py boot` should verify emulator PID survived past N seconds and surface the FATAL log line; warn on arm32 AVDs on Apple Silicon — issue 4.
- [ ] Document `ANDROID_HOME` / PATH expectations in `SKILL.md` — issue 5.
- [ ] Document lockscreen-vs-input gotcha or auto-wake before input dispatches — operational gotcha above.
- [ ] Cover the destructive verbs not exercised here: `adb_boot --wipe`, `adb_app install` / `uninstall` (requires .apk), `adb_perm revoke`, `adb_cdp forward/eval/dom` (requires Chrome with `--remote-debugging-port`).
