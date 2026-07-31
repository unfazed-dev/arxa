# probe-runner — platform-by-platform thorough smoke

**Date authored:** 2026-05-16
**Skill under test:** `.claude/skills/probe-runner/`
**Predecessors (already executed, will be re-verified, not re-written):**

- `.claude/skills/probe-runner/docs/probe-runner-smoke-test-2026-05-16.md` — host macOS desktop block
- `.claude/skills/probe-runner/docs/probe-runner-ios-smoke.md` — iOS simulator block
- `.claude/skills/probe-runner/docs/probe-runner-android-smoke.md` — Android emulator block

This plan covers the **three platforms the predecessors did not cover** (host-browser web, wry/Dioxus webview probes, Flutter), and a focused **re-verification pass** of the three platforms already covered. One platform at a time, in cheapest→most-setup order, with destructive-verb coverage filled in where prior reports explicitly skipped them.

## Scope and exit criteria

**In scope (the seven platform "blocks" in `SKILL.md`):**

| # | Platform | Block prefix | Status before this run |
|---|---|---|---|
| P1 | macOS host desktop (Quartz / AX / cliclick / screencapture) | `find_window`, `shot`, `click`, … (no prefix) | Covered 2026-05-16 (B1/B2/B3 fixes shipped). Re-verify + cover destructive verbs. |
| P2 | wry / Dioxus webview probe (Safari Web Inspector + `dioxus::document::eval`) | `dom`, `console`, `safari_inspect` | **Untested** — needs probe template installed in a Dioxus crate. |
| P3 | Host browser — Chrome (CDP) | `web_*` | **Untested.** |
| P4 | Host browser — Safari (safaridriver fallback) | `web_*` with `--browser=safari` | **Untested.** |
| P5 | iOS simulator | `ios_*` | Covered 2026-05-16. Re-verify + cover `ios_boot --shutdown/--erase`, `ios_app install/uninstall`, `ios_privacy reset`. |
| P6 | Android emulator | `adb_*` | Covered 2026-05-16. Re-verify + cover `adb_boot --wipe`, `adb_app install/uninstall`, `adb_perm revoke`, `adb_cdp forward/eval/dom`. |
| P7 | Flutter (iOS sim + Android emu + Chrome web + macOS desktop, all from one counter app) | `flutter_*` | **Untested.** |

**Out of scope (explicit, do not let this expand):**

- Test-runner integration (Appium / WDA / UIAutomator2 / `flutter test integration_test`).
- Real-device (non-simulator) iOS / Android.
- Linux/Windows host paths.
- Mobile network capture (mitmproxy CA install).
- Rewriting any probe-runner script. This is a **smoke** + **report** pass. Bugs go into the report's "follow-ups" section; in-place fixes only if a script blocks the entire platform's smoke.

**Exit criteria for the whole task:**

1. Each of P1–P7 has a section in the report file with: tally row, artefacts list, bugs found, operational gotchas, follow-ups.
2. Every script under `.claude/skills/probe-runner/scripts/` has been **invoked at least once** (either by a smoke step, by `--help`, or marked SKIP with a documented reason).
3. Every slash command under `.claude/skills/probe-runner/commands/` has its YAML frontmatter validated (`allowed-tools: Bash(python3 *)`, `$ARGUMENTS` forwarding, 1:1 mapping to a script).
4. The report ends with a cross-platform summary table (PASS / FAIL / SKIP per platform) and a deduplicated follow-up list.

## Preflight (run once before P1)

Environment fingerprint captured at top of report. Commands serialized into a single shell block so the report can quote them verbatim:

```bash
sw_vers
python3 --version
which cliclick screencapture osascript ffmpeg fswatch xcrun adb idb flutter
ls /Applications/'Google Chrome.app' /Applications/Safari.app
xcrun simctl list devices booted -j 2>/dev/null | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin),indent=2))" | head
adb devices -l
flutter --version
flutter doctor -v 2>&1 | head -40
python3 -c "import Quartz, Vision, websocket, selenium; print('ok')"
```

Required green lights (any failure stops P1 and the report records a SKIP for the affected platform):

- `cliclick`, `screencapture`, `osascript`, `xcrun`, `adb`, `flutter` on PATH.
- `python3 -c "import Quartz, Vision, websocket, selenium"` succeeds (already verified in prior smoke).
- Chrome.app and Safari.app present.
- iOS sim bootable (any sim, target: `iPhone 17` already known-good).
- Android AVD bootable (target: `Pixel_9` arm64-v8a, already known-good).
- Flutter SDK ≥ 3.41 on PATH (verified at preflight authoring time: `Flutter 3.41.4`).

Also one TCC sanity:

```bash
ioreg -l | grep -c kIOHIDStateSecureInput   # must be 0
```

If Secure Input is active the report records a hard stop with the screen still locked.

## Platform-by-platform run order and per-platform recipe

Strict order. Do **not** start the next platform until the prior platform's report section is **written to file**. This makes partial work durable: a session interrupt leaves a half-complete report instead of nothing.

**Per-platform timebox: 20 minutes hard cap.** If a platform exceeds 20 min wall clock from first command to written report section, the executor SKIPs the remaining steps for that platform, writes what was learned to the report (PASS+SKIP rows with reasons), and moves on. Slow platforms are recorded as a follow-up, not retried in-band.

### P1 — macOS host desktop (re-verify + destructive)

**Target window:** VS Code (`Code`), as in predecessor. If unavailable, fall back to Finder with a window open, or `Activity Monitor`.

**Steps:**

1. **`--help` sweep** for every host-desktop script (the 36 non-iOS/non-Android/non-web/non-flutter scripts). Expect 97/97 PASS post-B1/B2/B3 fixes — confirm no regression.
2. **Discovery + capture re-run** (identical to predecessor, abbreviated):
   - `find_window Code`, `wait_window Code --timeout 5`, `ax_tree Code` (size-cap), `shot Code`, `region Code 0,0,200,200`, `record Code --seconds 1`, `multishot Code --count 2`, `pixdiff smoke_a.png smoke_b.png`, `ocr Code` (region), `text_diff` on two PNG inputs.
   - Pass if all artefacts land in `${PROBE_RUNNER_OUTDIR}` with sane byte sizes.
3. **Diagnostics re-run:** `sample Code --seconds 1`, `mem Code`, `fswatch /tmp --seconds 2`, `tail_log Code --seconds 1` (must terminate ≤ 2 s post-fix), `nettrace` — **SKIP unless run with sudo**; record reason.
4. **Destructive coverage (new this round):** spawn a throwaway target (`open -na TextEdit`) and exercise the steps **in this exact order** — window-state-mutation steps live at the end so prior steps run against a live window:
   - `focus TextEdit`.
   - `click TextEdit 100 100` (single, into the new doc) → follow `shot` to confirm focus.
   - `drag TextEdit 200,200 300,300` (mouse drag within window).
   - `hover TextEdit 200 200`.
   - `scroll TextEdit 0 -100`.
   - `type_text TextEdit "smoke"`.
   - `key_chord TextEdit "cmd+a"` then `key_chord TextEdit "delete"`.
   - `clipboard set "hello"` → `key_chord TextEdit "cmd+v"` → `clipboard get` round-trip.
   - `menu TextEdit "TextEdit/About TextEdit"` (open menu, dismiss with Escape via `key_chord`).
   - `context_menu TextEdit 200 200` and `drop_file TextEdit /tmp/smoke.txt 200 200`.
   - `reposition TextEdit --size 800x600 --at 100,100` and verify post-condition via `find_window`.
   - **(window-state mutations, last):** `window_state TextEdit minimize` → verify via `find_window` → `osascript -e 'tell app "TextEdit" to activate'` to restore → `window_state TextEdit fullscreen` → restore via `key_chord "ctrl+cmd+f"` → `window_state TextEdit close`. If any step destroys the window mid-sequence, re-spawn with `open -na TextEdit` before the next step.
5. **Webview / wry path (`safari_inspect`):** `safari_inspect --list` against a wry app if one is running; expect "Develop menu" listing. Defer `dom` / `console` to P2.

**PASS criteria:** every step rc=0 OR documented as SKIP with reason. Window-state destructive steps verified by follow-up `find_window` reading post-state.

**Artefacts captured under** `/tmp/probe-runner/p1-*` (override `PROBE_RUNNER_OUTDIR=/tmp/probe-runner/p1`).

### P2 — wry / Dioxus webview probe

**Target:** `crates/brainiac-visualizer/` (a Dioxus desktop app already in this repo). The skill's `templates/dioxus_debug_probe.rs` is meant to be dropped in.

**Decision branches:**

- **Branch B (default):** smoke must NOT modify another crate. Run syntactic check on the template (`rustc --edition 2021 --emit=metadata templates/dioxus_debug_probe.rs` against a stub crate that provides minimal `dioxus::document::eval` shim, or `cargo check` against a throwaway crate that depends on `dioxus`), exercise `safari_inspect --list` against a running brainiac-visualizer window (cold-launch the existing binary, no source edits), and document the wiring gap in the report. The brainiac-side companion plan in `probe-runner-skill.md` already enumerates the install steps — link to it.
- **Branch A (only if operator explicitly authorizes installing the probe into brainiac-visualizer):** install the probe module into `crates/brainiac-visualizer/src/presentation/debug_probe.rs`, gate behind `#[cfg(feature = "debug-probe")]`, add `[features] debug-probe = []` to that crate's `Cargo.toml`, and `cargo run --features debug-probe`. Then exercise `python3 scripts/dom.py --selector body Brainiac` and `python3 scripts/console.py --seconds 2 Brainiac`. This validates the **template end-to-end** and is the actual deliverable of Phase C of `probe-runner-skill.md`, but treats the brainiac crate as a delivery vehicle rather than smoke surface — escalate to operator before taking this branch.

**Steps (Branch A path):**

1. Verify `brainiac-visualizer` builds clean before touching: `cargo check -p brainiac-visualizer` from `crates/`.
2. Copy `.claude/skills/probe-runner/templates/dioxus_debug_probe.rs` → `crates/brainiac-visualizer/src/presentation/debug_probe.rs`. Add the cfg-gate. Add `debug-probe` feature in `Cargo.toml`.
3. `cargo run -p brainiac-visualizer --features debug-probe` — confirm app opens.
4. From a second shell: `python3 .claude/skills/probe-runner/scripts/dom.py --selector ".brainiac-app" --timeout 2 Brainiac` — expect JSON with `getBoundingClientRect`.
5. `python3 .claude/skills/probe-runner/scripts/console.py --seconds 2 Brainiac` — expect at least one `console.*` line (or empty if the app is quiet, with rc=0).
6. `python3 .claude/skills/probe-runner/scripts/safari_inspect.py --list` — verify Safari sees the wry webview.

**PASS criteria for Branch A:** `dom` returns valid JSON with non-zero bounds, `console` exits within deadline post-B1 fix, `safari_inspect --list` shows the brainiac webview.

**If Branch B taken:** record exactly which step failed, capture stderr to the report, then confine to syntactic + `safari_inspect`.

**Cleanup:** revert `Cargo.toml` + delete `debug_probe.rs` if Branch A is run, OR leave installed and create a follow-up plan to land the brainiac-side companion change (per `probe-runner-skill.md` "Brainiac-side companion plan"). Decision made at execute time; report records which.

### P3 — Host browser, Chrome (CDP)

**Target:** stock Chrome on macOS host, launched with `--remote-debugging-port=9222`.

**Steps:**

1. `python3 scripts/web_launch.py --url about:blank` — spawn Chrome with CDP. Confirm `curl -s http://127.0.0.1:9222/json/version` returns the protocol version.
2. `python3 scripts/web_open.py https://example.com` — `Page.navigate`, follow with `web_eval "document.title"` → `"Example Domain"`.
3. `python3 scripts/web_shot.py --full /tmp/probe-runner/p3/full.png` and `web_shot.py --element h1`.
4. `python3 scripts/web_dom.py --selector body` — DOM snapshot JSON.
5. `python3 scripts/web_console.py --seconds 2` — capture `console.log` events; trigger one with `web_eval "console.log('smoke')"`.
6. `python3 scripts/web_net.py --filter example.com --seconds 5` then `web_open.py https://example.com` from a second shell — first request/response captured.
7. `python3 scripts/web_emu.py --device "iPhone 12"` then `web_shot.py --full` — verify mobile viewport.
8. `python3 scripts/web_click.py "a"` (the only link on example.com — IANA), confirm navigation via `web_eval "location.href"`.
9. `python3 scripts/web_type.py "input" "smoke"` against a page with an input (use `data:text/html,<input id=x>` URL).
10. `python3 scripts/web_scroll.py 0 500` and verify via `web_eval "window.scrollY"`.
11. `python3 scripts/web_a11y.py` — `Accessibility.getFullAXTree`.
12. `python3 scripts/web_record.py --seconds 3 /tmp/probe-runner/p3/rec.mp4` — screencast → ffmpeg pipe.

**PASS criteria:** 12/12 rc=0, all artefacts present, `web_eval` returns expected scalar values.

### P4 — Host browser, Safari (safaridriver fallback)

**Pre-req:** `safaridriver --enable` (once per machine; record whether it was already enabled).

**Steps:**

1. Re-run P3 steps **1, 2, 3 (`--full` only), 4 (`web_dom` via WebDriver `pageSource`), 5 (best-effort), 8, 9, 10, 11** with `--browser=safari` flag.
2. Explicitly verify the **honest gap** scripts report unsupported:
   - `python3 scripts/web_net.py --browser=safari --filter example.com` — expect rc=2 with message "unsupported on Safari".
   - `python3 scripts/web_emu.py --browser=safari --device "iPhone 12"` — same.
   - `python3 scripts/web_record.py --browser=safari --seconds 2` — falls back to `screencapture -v -l` of Safari window; must produce a `.mov`.
3. Force-fallback test: with Chrome **not running**, invoke `web_open.py` without `--browser` flag and confirm the skill auto-falls-back to Safari (`_common.py` fallback rule).

**PASS criteria:** supported flows rc=0; unsupported flows rc=2 with a one-line message; fallback selection works without operator hint.

### P5 — iOS simulator (re-verify + destructive)

**Target sim:** `iPhone 17` (`3340DCE5-FCA3-45E5-B7AA-F2C190840A06`), iOS 26.5 — same as predecessor.

**Steps:**

1. Re-run the 17 PASS cases from `probe-runner-ios-smoke.md` (P-row matrix). Confirm no regressions.
2. **Destructive verbs not exercised before:**
   - `ios_boot --shutdown <UDID>` then `ios_boot <UDID>` to reboot — verify state transitions via `ios_list`.
   - `ios_boot --erase <UDID>` — only against a **throwaway sim** (`xcrun simctl create probe-throwaway "iPhone 17"` then erase it).
   - `ios_app install` / `ios_app uninstall` — use `xcrun simctl install booted` with a tiny sample `.app` from `~/Library/Developer/Xcode/iOS DeviceSupport/`, or generate a no-op SwiftUI app via `xcrun simctl spawn booted launchctl` — if no `.app` is readily available, build a 5-line SwiftUI hello-world with `swift package init --type executable` (deferred — record SKIP if blocked > 5 min).
   - `ios_privacy reset com.example.app` — same throwaway bundle.
3. **Bug 1 re-test:** confirm `ios_key.py HOME` still fails (HW_MAP not yet patched). Record exact rc + stderr for the report.
4. **Bug 2 re-test:** `ios_files.py push /nonexistent com.apple.mobilesafari /tmp/x` → still exits 0 with bogus success message. Record.
5. **Bug 3 re-test:** `ios_url.py --help` → still raises CalledProcessError. Record.

**PASS criteria:** 19/19 functional probes complete; 3 destructive verbs covered; bug regressions noted (these are pre-existing, this run only confirms they persist).

### P6 — Android emulator (re-verify + destructive)

**Target AVD:** `Pixel_9` (arm64-v8a), Android 16 — same as predecessor.

**Steps:**

1. Re-run the 18 PASS cases from `probe-runner-android-smoke.md`.
2. **Destructive verbs not exercised before:**
   - `adb_boot --wipe <avd>` — record "destructive: confirm before run" prompt path; against a **throwaway AVD** if one can be created (`avdmanager create avd -n probe-throwaway -k "system-images;android-16;google_apis;arm64-v8a"`). If no throwaway AVD can be created in < 5 min, document SKIP.
   - `adb_app install` / `adb_app uninstall` — install a minimal APK. Use a known-good test apk if cached locally (`~/Library/Android/sdk/extras/...`) or build one. SKIP if blocked > 5 min, document.
   - `adb_perm revoke com.android.settings android.permission.ACCESS_FINE_LOCATION` — round-trip with the prior `grant`.
   - `adb_cdp forward`, `adb_cdp eval`, `adb_cdp dom` — open Chrome on the emulator with `--remote-debugging`, run all three.
3. **Bug 1 re-test:** `adb_push.py` deprecation notice — confirm it still emits and routes to `adb_intent.py`. (Listing already shows `adb_intent.py` exists, so the rename **shipped** since the prior smoke; this verifies.)
4. **Bug 2 re-test:** `adb_record.py` / `adb_ui_tree.py` stderr-leak — confirm or document fix.
5. **Bug 3 re-test:** `--help` consistency across all 18 scripts.

### P7 — Flutter (4 targets from one counter app)

**Target app:** scaffold a fresh counter app on a tmpdir to avoid polluting any existing project:

```bash
flutter create /tmp/probe-runner/p7-counter --platforms=ios,android,web,macos
cd /tmp/probe-runner/p7-counter
```

For each of the four targets, run the same recipe:

**Per-target recipe (T = ios | android | web | macos):**

**Backgrounding mechanism (declared upfront, identical across all four targets):**

- Launch `flutter run -d <device>` via `Bash` with `run_in_background: true`, redirecting both stdout and stderr to a per-target log: `/tmp/probe-runner/p7-<target>.log`. Capture the Bash shell id for later teardown.
- `flutter_attach.py --auto` reads from this same log path (set via `PROBE_RUNNER_FLUTTER_LOG=/tmp/probe-runner/p7-<target>.log` env or `--log` flag) to scrape the `Observatory listening on ws://…` line that announces the VM service URL.
- Monitor the background shell via the `Monitor` tool while waiting for the Observatory line (don't sleep-poll).
- Teardown at end of each target: send `q` to the `flutter run` stdin (via the Bash shell id), or kill the shell. Do not stack four `flutter run` processes — finish one before launching the next.

1. Launch: `flutter run -d <device>` in a backgrounded shell (log to `/tmp/probe-runner/p7-<target>.log`).
   - `ios`: `flutter run -d "iPhone 17"`.
   - `android`: `flutter run -d emulator-5554`.
   - `web`: `flutter run -d chrome --web-port 8765` (fixed port keeps `web_*` URLs predictable).
   - `macos`: `flutter run -d macos`.
2. **Discovery:** `python3 .claude/skills/probe-runner/scripts/flutter_attach.py --auto` — must resolve the VM service URL within 30 s. Verify `${PROBE_RUNNER_OUTDIR}/flutter.url` exists.
3. **Widget tree:** `flutter_tree.py --kind widget` — JSON contains `Scaffold` + `FloatingActionButton` + the counter `Text`.
4. **Find:** `flutter_find.py --type FloatingActionButton` — returns widget id + bounds.
5. **Tap:** `flutter_tap.py <key-from-step-4>` — counter increments. Verify via second `flutter_tree.py` showing `Text` value updated.
6. **Reload:** edit `lib/main.dart` (append a no-op comment), call `flutter_reload.py`, observe reload event via `flutter_log.py --seconds 2`.
7. **Diag:** `flutter_diag.py --perf on` then `--perf off` — toggle perf overlay (visual confirmation via `flutter_shot.py` if engine supports it; otherwise verify via `flutter_log.py`).
8. **Log:** `flutter_log.py --seconds 2` — `print("hello")` injected via `flutter_vm.py` call should appear.
9. **Semantics:** `flutter_semantics.py --enable` then re-run `ios_ui_tree` / `adb_ui_tree` and verify widgets now appear in OS AX tree.
10. **Shot:** `flutter_shot.py` — must succeed on debug builds.

Then for `macos` target, *also* run `shot.py "Flutter Counter"` (host-app block) and verify pixel ops still work. For `web` target, *also* run `web_shot.py --full` against the Chrome page. Cross-block parity is part of the contract.

**PASS criteria:** all four targets complete steps 1–10 without traceback. SKIP individual steps with documented reason if a target's harness doesn't support them (e.g., `flutter_shot.py` on web may be limited).

### Post-platform — slash command audit (one pass after P7)

Single pass over `.claude/skills/probe-runner/commands/`:

1. For each `.md`, parse YAML frontmatter and assert: `allowed-tools` includes `Bash(python3 *)`, `argument-hint` non-empty, `$ARGUMENTS` referenced in body, file mode mentions the target script.
2. Cross-check 1:1 mapping: every `pr-<verb>.md` has a `scripts/<verb>.py`, and vice versa. Report any orphan.
3. Spot-check three commands end-to-end (`/pr-shot Code`, `/pr-ios-shot`, `/pr-flutter-tree`) — these are already validated indirectly via the per-platform runs, but slash-command syntax is a separate failure surface.

## Report file

**Path:** `.claude/skills/probe-runner/docs/probe-runner-platform-thorough-smoke-report.md` (same directory as this plan, kebab-case `-report` suffix to match the existing `probe-runner-*-smoke.md` convention).

**Required sections, in order:**

```markdown
# probe-runner — platform-by-platform thorough smoke (report)

**Date:** <YYYY-MM-DD>
**Host fingerprint:** <from preflight>
**Skill commit:** <git rev-parse HEAD>

## Cross-platform tally

| Platform | Scripts | PASS | FAIL | SKIP | Verdict |
|---|---|---|---|---|---|
| P1 host desktop | … | … | … | … | … |
| P2 wry/Dioxus webview | … | … | … | … | … |
| P3 host browser Chrome | … | … | … | … | … |
| P4 host browser Safari | … | … | … | … | … |
| P5 iOS simulator | … | … | … | … | … |
| P6 Android emulator | … | … | … | … | … |
| P7 Flutter (4 targets) | … | … | … | … | … |
| Total | … | … | … | … | … |

## P1 — macOS host desktop
…  (matrix, artefacts, bugs, gotchas, follow-ups)

## P2 — wry / Dioxus webview
…

## P3 — host browser (Chrome / CDP)
…

## P4 — host browser (Safari / safaridriver fallback)
…

## P5 — iOS simulator
…

## P6 — Android emulator
…

## P7 — Flutter (iOS / Android / web / macOS)
…

## Slash-command audit
…  (orphan list, frontmatter conformance)

## Deduplicated follow-ups
…  (one-liner per actionable bug, severity tagged, ordered by impact)

## What was not tested
…  (named here so it's not lost)
```

The report is **written incrementally** — each platform section lands in the file as soon as that platform's smoke is finished, not at the end. The cross-platform tally and deduplicated follow-ups are filled in last, after P7 + the slash-command audit.

## Task list (mirrors superpowers TaskCreate output)

The executor of this plan must create one task per platform plus the audit + report-finalize step (9 tasks). Tasks named "Smoke P<N> — <platform>" so progress is visible.

## Reconciliation with predecessors

- This plan **does not supersede** `probe-runner-ios-smoke.md` or `probe-runner-android-smoke.md`. Their bug findings are still authoritative; this plan re-verifies and extends.
- It **does extend** `probe-runner-smoke-test-2026-05-16.md` by covering host-desktop destructive verbs that earlier report explicitly SKIPped.
- The report file is **new**, not an edit of an earlier report — keeps the historical record of each smoke pass intact.

End of plan.
