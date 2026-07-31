# probe-runner — capture + drive + DOM-probe skill for wry/Dioxus desktop apps

## Context

Debugging Dioxus desktop apps today is manual: spawn the binary, eyeball the window,
right-click → Inspect, copy `tracing` output from stderr. The recent blank-canvas
bug in `perf_domain_heavy_100` chewed up an autonomous loop because each diagnostic
step (screenshot → window-id discovery → reposition → scroll → DOM probe) was
hand-orchestrated against bare macOS tools (`screencapture`, Quartz/AppKit via
Python, `osascript`, `cliclick`, `dioxus::document::eval`).

Playwright solves this for browser apps. There is no equivalent for wry/Tauri/
Dioxus desktop apps: WebKit Remote Inspector on macOS is a private API, wry’s
`evaluate_script` is one-way unless the host wires an `ipc_handler` or
framework-specific bounce, and Dioxus 0.7's `dioxus-desktop` does not expose a
public `open_devtools()` Rust API (verified against `dioxus-desktop` 0.7.9
docs.rs).

This plan creates a **personal-scope Claude Code skill** that bundles the proven
manual recipe into a single reusable toolset. The skill is:

- **Generic.** Targets any macOS-resident wry-backed app by window-owner name —
  brainiac-visualizer today, hermes-agent later, any third-party Tauri app.
- **Observe + drive.** Screencapture image/video + cliclick/Quartz input
  automation + Quartz scroll synthesis. Honest about scope:
  "Playwright-shaped, screencapture-powered" — not CDP.
- **Framework-aware probes.** Drop-in Dioxus module that wraps
  `dioxus::document::eval` into typed DOM-probe and console-tail helpers
  (Phase C). Tauri and raw-wry templates listed as future work.
- **All three phases this round.** Capture + drive + Dioxus probe template
  ship together. Validation against `brainiac-visualizer`'s
  `perf_domain_heavy_100` gates completion.
- **Single language for runtime: Python.** macOS ships system Python 3 at
  `/usr/bin/python3` with `pyobjc-framework-Quartz` available; one toolchain
  eliminates shell-quoting hazards, makes JSON-shaped outputs native, and
  ports cleanly when Linux/Windows support arrives. Rust is reserved for the
  in-process probe template — that file is meant to be dropped into a Rust
  crate, so it must be Rust.

The intended outcome is that future bug hunts (CSS regressions, layout
overflow, sector-tile pixel diffs, perf videos, demo recordings) collapse from
a 30-minute manual loop into a 3-command skill invocation.

## Capability matrix — full human parity + beyond

This skill must give an autonomous agent the same affordances a human at the
keyboard has, plus several that a human cannot perform reliably. Each row
below maps to a script in `scripts/` and a `commands/` slash-command.

### Human-parity actions (everything a person at the desk can do)

| Action | Script | macOS primitive |
|---|---|---|
| Find a window by app name | `find_window.py` | Quartz `CGWindowListCopyWindowInfo` |
| Focus / raise a window | `focus.py` | osascript `tell app "X" to activate` + `set frontmost` |
| Move / resize window | `reposition.py` | osascript `System Events` window bounds |
| Minimize / zoom / close window | `window_state.py` | osascript window properties |
| Single / double / triple / right click | `click.py` | `cliclick c:` / `dc:` / `tc:` / `rc:` |
| Click + hold (mouse-down only) | `click.py --hold` | `cliclick dd:` (down) / `du:` (up) |
| Drag & drop (intra-window) | `drag.py` | `cliclick dd:x,y w:200 m:x,y du:gx,gy` |
| Hover | `hover.py` | `cliclick m:x,y` |
| Type text (verbatim, Unicode) | `type_text.py` | `cliclick t:`, paste-via-pasteboard fallback |
| Key chord (cmd/shift/opt/ctrl + key) | `key_chord.py` | osascript `keystroke … using {…}` inside a single `tell application "System Events" … end tell` block (one subprocess per call); foreground-changing subprocess work cannot interleave between modifier-down and keystroke. |
| Repeat key | `key_chord.py --repeat N` | All N keystrokes fold into one osascript `tell` block with `delay <delay-ms>` between iterations — drop-free under parallel `screencapture`. (Pre-2026-05-16: one subprocess per repeat; intermittent drops surfaced in gate-3.) |
| Hold key | `key_chord.py --hold-ms N` | Presses the chord's modifier keys via `cliclick kd:` for N ms (any non-modifier key is sent inside the hold window). cliclick's `kd:` supports cmd/alt/shift/ctrl/fn only. Unchanged. |
| Batch chords | `key_chord.py owner <first> --batch` (extra chords on stdin, one per line) | Dispatches all chords inside one osascript `tell` block with `delay <delay-ms>` between each — drop-free under parallel `screencapture`. |
| Mouse-wheel / trackpad scroll | `scroll.py` | Quartz `CGEventCreateScrollWheelEvent` |
| Pinch-zoom / rotate (gesture) | `gesture.py` (best-effort) | Quartz private `kCGEventTypeGesture` (limited) |
| File drag-and-drop into window | `drop_file.py` | osascript `tell app "Finder" to drag selection` + coords |
| Clipboard read / write | `clipboard.py` | `pbcopy` / `pbpaste` via subprocess |
| Take screenshot (window / region / full) | `shot.py`, `region.py` | `screencapture -l/-R/-D` |
| Record video (fixed / start-stop) | `record.py` | `screencapture -v/-V`, optional `ffmpeg avfoundation` |
| Record with click highlights + audio | `record.py --clicks --audio` | `screencapture -k -g` |
| Read on-screen text (OCR) | `ocr.py` | macOS Vision framework via pyobjc `VNRecognizeTextRequest` |
| Open / interact with menu bar | `menu.py` | osascript `System Events` menu items by path |
| Open / interact with context menu | `context_menu.py` | `cliclick rc:` then `menu.py` |
| Switch app (Cmd+Tab equivalent) | `focus.py --app` | osascript activate |
| Wait for window to exist / disappear | `wait_window.py` | poll `find_window` with timeout |
| Wait for pixel / region change | `wait_pixel.py` | hash region screenshots; diff with tolerance |

### Superhuman actions (things a human can't do reliably or at all)

| Action | Script | Mechanism |
|---|---|---|
| Accessibility-tree dump (every focusable element + its label, role, value, hidden state) | `ax_tree.py` | `AXUIElementCopyAttributeValue` via pyobjc `ApplicationServices` |
| Click element by accessibility identifier or label (no coords) | `ax_click.py` | resolve AXUIElement → `AXPress` action |
| Read text values out of fields without OCR | `ax_text.py` | `AXValue` attribute on AX element |
| Watch the AX tree for changes (no polling) | `ax_observe.py` | `AXObserverAddNotification` |
| DOM probe inside a wry/Dioxus webview (Phase C) | `dom.py` + Rust template | `dioxus::document::eval` JSON bounce |
| Tail webview `console.log/warn/error` (Phase C) | `console.py` + Rust template | JS shim ring buffer + eval polling |
| 100 fps multi-frame burst | `multishot.py --fps 100` | tight loop on `CGWindowListCreateImage` |
| Coordinate-perfect actions (no jitter, no slip) | (all click/scroll scripts) | Quartz event injection, no human latency |
| Headless execution while screen is locked | `headless.py` | `caffeinate -dimsu` + `bsexec` of loginwindow |
| Read process pasteboard / clipboard history | `clipboard.py --history` | system pasteboard general changes |
| Sample CPU stacks of the target | `sample.py` | `sample <pid> <secs>` |
| Memory snapshot / leaks | `mem.py` | `leaks <pid>`, `vmmap <pid>` |
| File-system change watch around the app | `fswatch.py` | `fswatch -o <paths>` |
| Network capture for the app's PID | `nettrace.py` | `tcpdump -i any -w out.pcap` with BPF on pid (via `lsof` resolve) |
| Pixel-hash diff between two states | `pixdiff.py` | Pillow `ImageChops.difference` + hash. `--region X,Y,W,H` crops both inputs before differencing — use for per-tile or canvas-only diffs where chrome would dilute the score. |
| Region OCR diff (catch text drift) | `text_diff.py` | Vision OCR then `difflib` |
| Force window pixel-exact size for reproducible screenshots | `reposition.py --size WxH` | osascript bounds, post-condition assert |
| Capture every screen including hidden displays | `shot.py --all-displays` | iterate `-D 1..N` |

### iOS Simulator (native + WebKit)

| Action | Script | Mechanism |
|---|---|---|
| List boot-able sims + states | `ios_list.py` | `xcrun simctl list devices --json` |
| Boot / shutdown / erase a sim | `ios_boot.py` | `xcrun simctl boot|shutdown|erase <UDID>` |
| Install / uninstall / launch / terminate `.app` | `ios_app.py` | `xcrun simctl install|uninstall|launch|terminate` |
| Open URL (deep link / universal link) | `ios_url.py` | `xcrun simctl openurl booted <url>` |
| Push a remote notification | `ios_push.py` | `xcrun simctl push booted <bundle> <json>` |
| Set status bar (time, battery, signal) | `ios_status_bar.py` | `xcrun simctl status_bar booted override ...` |
| Set appearance (light/dark) + locale | `ios_appearance.py` | `xcrun simctl ui booted appearance light|dark` |
| Grant / revoke permissions (camera, photos, mic, location) | `ios_privacy.py` | `xcrun simctl privacy booted grant|revoke|reset` |
| Spoof location (point or route) | `ios_location.py` | `xcrun simctl location booted set lat,lon` |
| Screenshot sim window | `ios_shot.py` | `xcrun simctl io booted screenshot out.png` |
| Record video of sim window | `ios_record.py` | `xcrun simctl io booted recordVideo out.mp4` |
| UI hierarchy dump (every visible element with bounds + role) | `ios_ui_tree.py` | `idb ui describe-all` (requires `fb-idb`) |
| Tap / swipe by coords | `ios_tap.py`, `ios_swipe.py` | `idb ui tap x y`, `idb ui swipe x1 y1 x2 y2` |
| Type text into focused field | `ios_type.py` | `idb ui text "..."` |
| Send hardware key (home, lock, volume, power) | `ios_key.py` | `idb ui key <keycode>` |
| Tail device log | `ios_log.py` | `idb log` |
| Push / pull files from sim container | `ios_files.py` | `idb file push|pull` |
| Inspect Mobile Safari pages (DOM, console) | `ios_safari.py` | macOS Safari `safaridriver` WebDriver → iOS sim Safari |

### Android Emulator (native + Chrome WebView)

| Action | Script | Mechanism |
|---|---|---|
| List attached devices / emulators | `adb_list.py` | `adb devices -l` |
| Boot / kill / wipe AVD | `adb_boot.py` | `emulator -avd <name>`, `adb -s X emu kill`, `emulator -wipe-data` |
| Install / uninstall / launch / kill app | `adb_app.py` | `adb install`, `adb uninstall`, `adb shell am start -n pkg/.Activity`, `adb shell am force-stop` |
| Open URL / deep link | `adb_url.py` | `adb shell am start -W -a android.intent.action.VIEW -d <url>` |
| Push notification (FCM-style) | `adb_push.py` | `adb shell am broadcast ...` |
| Set system settings (dark mode, language, timezone) | `adb_settings.py` | `adb shell cmd uimode night yes`, `adb shell settings put ...` |
| Grant / revoke runtime permission | `adb_perm.py` | `adb shell pm grant|revoke pkg perm` |
| Spoof location | `adb_location.py` | `adb emu geo fix <lon> <lat>` |
| Screenshot device | `adb_shot.py` | `adb exec-out screencap -p > out.png` |
| Record video of device | `adb_record.py` | `adb shell screenrecord /sdcard/x.mp4` + `adb pull` |
| UI hierarchy dump (XML tree of elements + bounds + resource-id) | `adb_ui_tree.py` | `adb shell uiautomator dump` + `adb pull` |
| Tap / swipe by coords | `adb_tap.py`, `adb_swipe.py` | `adb shell input tap`, `adb shell input swipe` |
| Type text / send keyevent | `adb_type.py`, `adb_key.py` | `adb shell input text`, `adb shell input keyevent` |
| Tail logcat scoped to package | `adb_log.py` | `adb logcat --pid=$(adb shell pidof <pkg>)` |
| Push / pull files | `adb_files.py` | `adb push`, `adb pull` |
| Inspect Chrome / WebView pages | `adb_cdp.py` | `adb forward tcp:9223 localabstract:chrome_devtools_remote` → CDP client. **Local port defaults to 9223** (not 9222) to avoid collision with the host-Chrome CDP at 9222. Override with `--port`. |

### Host-browser web automation (Chrome default, Safari fallback)

For automating real web pages on the macOS host (outside any wry/Tauri/Dioxus
desktop app, outside iOS/Android sims), the skill defaults to **Chrome over
the Chrome DevTools Protocol**. Safari via `safaridriver` (WebDriver) is the
fallback for sites that misbehave on Chrome or when Chrome is unavailable.

Why Chrome default: CDP is richer than WebDriver (network interception, full
runtime eval, performance traces, coverage, accessibility tree, raw DOM
snapshots), most operators already have Chrome installed, and the same CDP
client works against the Android Chrome path so the skill has one mental
model for "Chrome-based web."

| Action | Script | Mechanism |
|---|---|---|
| Launch Chrome with CDP open | `web_launch.py [--url URL]` | `Google Chrome` binary with `--remote-debugging-port=9222 --user-data-dir=/tmp/pr-chrome --no-first-run`; if `--url` is provided, the active tab is navigated via CDP `Page.navigate` after launch. `--browser=safari --status` reports `safaridriver` availability and Safari running state. |
| Open URL | `web_open.py` | CDP `Page.navigate` (Chrome) → fallback `safaridriver` `url` (Safari) |
| Take page screenshot (full, viewport, element) | `web_shot.py` | CDP `Page.captureScreenshot {captureBeyondViewport:true}` → fallback macOS `screencapture` of Safari window |
| Eval JS, return value | `web_eval.py` | CDP `Runtime.evaluate` → fallback WebDriver `executeScript` |
| Dump DOM snapshot | `web_dom.py` | CDP `DOMSnapshot.captureSnapshot` → fallback WebDriver `pageSource` |
| Tail console logs | `web_console.py` | CDP `Runtime.consoleAPICalled` event stream → fallback Safari Web Inspector log (best-effort) |
| Intercept network (URLs, status, response body) | `web_net.py` | CDP `Network.*` events → fallback: not supported on Safari, skill reports gap |
| Set viewport / emulate device | `web_emu.py --device iPhone-12` | CDP `Emulation.setDeviceMetricsOverride` → unsupported on Safari (rc=2). Device names accept both dashed (`iPhone-12`) and space (`iPhone 12`) forms. |
| Click / type / scroll by selector | `web_click.py`, `web_type.py`, `web_scroll.py --by DX,DY` | CDP `Input.*` + `Runtime.evaluate` to resolve selector. `web_scroll` uses `--by DX,DY` (one comma-separated pair, not `--offset`). |
| Record video of page | `web_record.py [--out PATH]` | CDP `Page.screencastFrame` event stream → mp4 via ffmpeg pipe; fallback: macOS `screencapture -v -l` of Safari window. `--out` overrides the auto-named path in `PROBE_RUNNER_OUTDIR`. |
| Measure scroll-animation easing | `web_anim.py [--selector S] [--range LO:HI] [--steps N] [--android\|--ios --url U\|--cdp-port P]` | Static-scroll transfer-function probe (core in `_anim_core.py`): sets scrollY, polls the smooth-scroll lib (Lenis/GSAP-scrub) to convergence, reads decomposed transform+opacity, fits a standard easing. Emits an easing ONLY when certified (scroll held + reproducible on revisit + monotonic + low RMS); else flags it with a reason. Auto-discovers movers or takes a selector; `--detect-only` reports the animation stack. **Three transports, identical certification:** host Chrome over CDP (default); host Safari **and Mobile Safari on a booted iOS sim** over WebDriver (`--ios --url`); **Android-emulator Chrome/WebView** over adb-forwarded CDP (`--android`, auto `adb forward` + Origin-header suppression for on-device Chrome's 403). JSON to `PROBE_RUNNER_OUTDIR`. |
| Measure Flutter scroll-animation easing | `flutter_anim.py [--type T\|--key K\|--text S] [--range LO:HI] [--steps N]` · `--self-test` | Dart-VM-service sibling of `web_anim` (shared `_anim_core.py`). Drives `ScrollPosition.jumpTo(offset)` (instant, exact) and reads the target widget's `RenderObject.getTransformTo(null)` Matrix4, decomposed to the same tx/ty/sx/sy/rot channels, then runs the identical certification. `--self-test` verifies the core + Matrix4 decomposition offline (no VM needed). **Live bridge verified end-to-end** against Flutter 3.44 (macOS): measured transform matched a known easeOutQuad ground truth to ≤0.002px. Evaluates library-scoped Dart expressions against the root library — the inspector `valueId` is *not* a valid `evaluate` targetId — walking `WidgetsBinding.instance.rootElement` to locate the Scrollable + target; a validation recipe prints if the walk fails on another Flutter version. Target the widget that *moves* (the content), not a Transform wrapper above it. |
| Accessibility tree of page | `web_a11y.py` | CDP `Accessibility.getFullAXTree` → fallback WebDriver `wd/hub/computedrole` |

Fallback selection rule (encoded in `_common.py`):

1. If `Google Chrome` / `Chromium` is launch-able on `$PATH` or
   `/Applications/Google Chrome.app`, use it. Spawn with CDP enabled if not
   already running.
2. If Chrome is unavailable AND `safaridriver` is on `$PATH`, use Safari +
   WebDriver. Log a one-line warning that some features (network intercept,
   device emulation, screencast video) are unavailable.
3. If neither, fail with a clear error and an install hint (`brew install
   --cask google-chrome`).

Operator override: `--browser=chrome|safari` flag on every `web_*.py` script
forces a specific engine and bypasses fallback. Useful for diff-testing the
same page on both engines.

### Mobile web (the part Playwright doesn't reach)

Playwright emulates mobile viewport+UA but runs desktop WebKit/Chromium. To
debug real Mobile Safari (iOS) or Chrome-on-Android with their actual
engines, use the platform's native remote-debug rails:

| Action | Script | Mechanism |
|---|---|---|
| Open Mobile Safari in iOS sim, attach Web Inspector, eval JS, dump DOM | `ios_safari.py` | `safaridriver --enable` once; `safaridriver` WebDriver session against booted sim's Safari |
| Read Mobile Safari console logs | `ios_safari.py --console` | WebDriver `goog:logging` / Safari log endpoint |
| Open Chrome on Android emu, attach CDP, eval JS, dump DOM | `adb_cdp.py` | `adb forward tcp:9222 ...` then `chrome-remote-interface` or raw HTTP `/json` endpoint |
| Read Chrome Android console + network | `adb_cdp.py --logs` | CDP `Runtime.consoleAPICalled`, `Network.responseReceived` |
| Run a Playwright-style E2E suite against a real mobile WebView | (out of scope) | use Appium with WDA / UiAutomator2 driver; skill provides primitives, not a test runner |

### Flutter (mobile / web / macOS desktop)

Flutter renders all UI into a single Skia surface, so the OS-level AX
trees (`idb describe-all`, `uiautomator dump`) and webview-DOM probes
miss every widget. Coord + pixel automation still works; widget-level
introspection requires the **Dart VM service** that every Flutter app
exposes in debug / profile mode (prints
`Observatory listening on ws://127.0.0.1:<port>/<auth>`).

| Action | Script | Mechanism |
|---|---|---|
| Detect a running Flutter app (find VM service port) | `flutter_attach.py [--auto --source ios\|adb\|stdin\|host \| --tail <log>]` | parse `flutter run` stdout (or `idb log` / `adb logcat`). The printed URL ends in `=/` (auth code) — the parser preserves the suffix. Simplest workflow: launch with `flutter run --disable-service-auth-codes` to drop the auth code entirely. `--source host` is the alias for `stdin` when targeting macOS desktop or Chrome web. |
| Connect to Dart VM service over WebSocket | `flutter_vm.py` | JSON-RPC 2.0 over `ws://127.0.0.1:<port>/<auth>=/ws`. On 403 (auth-code stripped) `_flutter.rpc()` catches `WebSocketBadStatusException` and emits an operator hint. |
| Dump widget tree | `flutter_tree.py` | VM-service `ext.flutter.inspector.getRootWidget` |
| Dump render / layer / semantics tree | `flutter_tree.py --kind` | `ext.flutter.debugDumpRenderTree`, `…debugDumpLayerTree`, `…debugDumpSemanticsTreeInTraversalOrder` |
| Find widget by key / type / text | `flutter_find.py` | VM-service `getRootWidgetSummaryTreeWithPreviews` + filter |
| Tap widget by key (no coords) | `flutter_tap.py --target ios\|adb\|macos\|web` | `ext.flutter.inspector.setSelectionById` + `getLayoutExplorerNode` for size. **Mobile (`ios`/`adb`)**: rc=0 with `matched`+`render_size` payload — caller dispatches `ios_tap.py`/`adb_tap.py` with explicit `--x --y`. **Desktop/web (`macos`/`web`)**: **honest-gap rc=2** — Flutter inspector RPC doesn't expose transform-to-root, so absolute coords aren't synthesisable; fall back to `flutter_semantics.py enable` + `ax_tree.py`/`web_dom.py --selector flt-semantics` + `click.py`/`web_click.py`. |
| Live reload / hot restart | `flutter_reload.py` | VM-service `_flutter.reloadSources`, `_flutter.restart` |
| Toggle perf overlay, repaint rainbow, slow animations | `flutter_diag.py perf on\|off`, `repaint on\|off`, `slow <factor>` | `ext.flutter.showPerformanceOverlay`, `…debugRepaintRainbowEnabled`, `…timeDilation`. **Verb is positional**, not a flag: `flutter_diag.py perf on` (not `--perf on`). |
| Read Flutter logs (Dart `print`, `debugPrint`) | `flutter_log.py` | VM-service `streamListen('Stdout')` + `streamListen('Logging')` |
| Screenshot through Flutter (lossless, off-screen) | `flutter_shot.py` | `ext.ui.window.scheduleFrame` then `_flutter.screenshot` (debug builds) |
| Enable semantics (so iOS / Android AX trees populate) | `flutter_semantics.py --enable` | `ext.flutter.inspector.show` + `SemanticsBinding.instance.ensureSemantics()` toggle |
| Run a Flutter integration test from the skill | (out of scope) | use `flutter test integration_test` directly; skill wires up screenshots/logs only |

**Targets supported by Flutter block (all three platforms transparently):**

- **iOS sim** — Flutter app prints VM port to console; skill discovers it
  via `idb log` tail or `flutter logs`. Pixel ops still go through
  `ios_*.py`; widget ops go through `flutter_vm.py`.
- **Android emu** — VM port is forwarded automatically by `flutter run`,
  or skill runs `adb forward tcp:<port> tcp:<port>`. Pixel ops via
  `adb_*.py`; widget ops via `flutter_vm.py`.
- **macOS Flutter desktop** — VM port printed to host stdout. Pixel ops
  via the host-app block (`shot.py`, `click.py`, `ax_tree.py` if
  semantics enabled); widget ops via `flutter_vm.py`.
- **Flutter Web** — Dart VM service runs in the dev server alongside
  Chrome; widget ops still via `flutter_vm.py`. Pixel + DOM ops via
  `web_*.py` (Chrome-default). Note that Flutter Web's canvas renderer
  hides widget DOM inside `<flt-glass-pane>`; selectors against widgets
  fail there — use `flutter_find.py` instead.

**Operator convenience:** `flutter_attach.py --auto` listens on a known
log source (idb log / adb logcat / host stdout) and prints the VM
service URL as soon as the Flutter app boots; subsequent `flutter_*.py`
calls reuse the discovered URL from `${PROBE_RUNNER_OUTDIR}/flutter.url`.

### Limits and honest constraints

- **macOS Secure Input mode** (e.g., password fields) blocks synthetic
  keystrokes. Skill detects via `ioreg -l | grep SecureInput` and refuses
  with a clear error rather than failing silently.
- **TCC permissions required** the first time a script runs of each kind:
  Screen Recording (capture/record), Accessibility (cliclick, AX tree),
  Input Monitoring (some scroll APIs). README has a TCC checklist.
- **Multi-touch gestures** (pinch, three-finger swipe) are limited to
  best-effort via private Quartz APIs and may not work on every macOS
  version. Pinch-zoom is implemented as a Cmd+scroll fallback.
- **App-Store-distributed apps** with hardened runtime + sandbox may reject
  AX events; the skill reports the error and suggests `--cliclick-only`
  fallback (pure coord-based).
- **Sandbox / FileVault / login window**: cannot capture or drive while
  user is logged out. Skill assumes a logged-in user session.
- **Retina pixel doubling**: all coords are *points* (logical), screenshots
  are at *physical* resolution. Scripts normalize via the window's
  `bounds` from `find_window.py`.

## Language policy

- **All `scripts/`**: Python 3 (`/usr/bin/python3`), single-file, shebang
  `#!/usr/bin/env python3`. Use `subprocess.run` to shell out to
  `screencapture`, `cliclick`, `osascript` — no shell wrappers.
- **All `commands/`**: Markdown with YAML frontmatter (Claude Code slash-command
  format, agentskills.io standard).
- **One exception, `templates/dioxus_debug_probe.rs`**: Rust. This file is
  copied into the target Dioxus crate, so it must compile under their
  toolchain.
- **Zero shell scripts.** No `.sh`. AppleScript is embedded via
  `subprocess.run(["osascript", "-e", "..."])` inside Python.

## Source-of-truth research

Grounded in:

- **Anthropic skills spec** (`docs.anthropic.com/en/docs/claude-code/skills`,
  `agentskills.io` open standard) — directory `~/.claude/skills/<name>/`,
  required `SKILL.md` + YAML frontmatter (`name`, `description`,
  `allowed-tools`, optional `argument-hint`, `user-invocable`,
  `disable-model-invocation`), optional `scripts/`, `templates/`, `examples/`,
  `commands/`. Substitutions: `${CLAUDE_SKILL_DIR}`, `$ARGUMENTS`, `$N`.
- **macOS `screencapture(1)`** — `-l <windowid>` window, `-v` indefinite
  video, `-V <seconds>` fixed-length video, `-k` show clicks, `-g`/`-G` audio,
  `-C` cursor, `-R x,y,w,h` rectangle, `-D <display>`, `-t {png,jpg,pdf,tiff}`,
  `-T <secs>` delay, `-c` clipboard.
- **ffmpeg `avfoundation`** — `ffmpeg -f avfoundation -list_devices true -i ""`
  then `ffmpeg -f avfoundation -i "<screen>:<audio>" out.mkv` for lossless /
  long recordings where `screencapture -v` is awkward.
- **wry 0.55** — devtools always on in debug; `devtools` Cargo feature for
  release; `evaluate_script` is wry's JS injection primitive; `ipc_handler` is
  the webview→host channel; macOS uses Safari Web Inspector via private API.
- **Tauri v2 debug guide** — confirms inspector is platform-native (Safari on
  macOS); Tauri exposes `WebviewWindow::open_devtools()` programmatically;
  Dioxus does not.
- **Existing skill conventions on this machine** — `brainiac/skills/icm/`
  (vendored skill: `SKILL.md` + `policy.md` + `scripts/` + `templates/` +
  `commands/`); `~/.claude/skills/graphify/` (single SKILL.md + `extras/`);
  superpowers plugin skills (minimal `SKILL.md` only).

## Skill layout

Install location: `~/.claude/skills/probe-runner/`. Personal scope so it
follows the operator across every project (brainiac, hermes-agent,
third-party).

```
~/.claude/skills/probe-runner/
├── SKILL.md                       # entrypoint, agentskills.io frontmatter
├── README.md                      # operator-facing docs + troubleshooting
├── scripts/                       # ALL Python 3, no shell
│   ├── _common.py                 # shared: resolve_window(), out_path(),
│   │                              #   tcc_check(), ax_app(), arg parsing
│   │
│   │ # Discovery / inspection
│   ├── find_window.py             # Quartz CGWindowListCopyWindowInfo
│   ├── wait_window.py             # poll until window exists/vanishes
│   ├── ax_tree.py                 # dump accessibility tree → JSON
│   ├── ax_text.py                 # read AX element value/text
│   ├── ax_observe.py              # subscribe to AX notifications, stream
│   │
│   │ # Capture (still / video / OCR)
│   ├── shot.py                    # `screencapture -l <id>` (window/full)
│   ├── region.py                  # `screencapture -R x,y,w,h`
│   ├── record.py                  # `screencapture -v/-V`, ffmpeg fallback
│   ├── multishot.py               # burst N frames at interval / fps
│   ├── ocr.py                     # Vision framework text recognition
│   ├── pixdiff.py                 # Pillow image diff + hash
│   ├── text_diff.py               # OCR-then-difflib
│   │
│   │ # Drive — pointer
│   ├── click.py                   # left/right/double/triple + hold
│   ├── drag.py                    # mouse-down → move → mouse-up
│   ├── hover.py                   # move cursor without click
│   ├── scroll.py                  # Quartz scroll-wheel events
│   ├── gesture.py                 # best-effort pinch/swipe
│   │
│   │ # Drive — keyboard
│   ├── type_text.py               # cliclick + pasteboard fallback
│   ├── key_chord.py               # cmd/shift/opt/ctrl chords, hold, repeat
│   │
│   │ # Drive — window / app / menus
│   ├── focus.py                   # activate app, raise window
│   ├── reposition.py              # move, resize, --size WxH assert
│   ├── window_state.py            # minimize / zoom / close
│   ├── menu.py                    # navigate menu-bar by path
│   ├── context_menu.py            # right-click → menu navigate
│   ├── drop_file.py               # drag a file path into a window region
│   ├── clipboard.py               # get/set pasteboard, --history
│   │
│   │ # Diagnostics (superhuman)
│   ├── sample.py                  # `sample <pid> <secs>` CPU stacks
│   ├── mem.py                     # `leaks`, `vmmap`
│   ├── fswatch.py                 # filesystem change watch
│   ├── nettrace.py                # tcpdump scoped to pid
│   ├── tail_log.py                # tail stderr by pid
│   ├── headless.py                # caffeinate + bsexec wrapper
│   │
│   │ # Webview-specific (macOS host wry/Tauri/Dioxus)
│   ├── dom.py                     # invoke probe template's probe_dom
│   ├── console.py                 # tail webview console (template)
│   ├── safari_inspect.py          # best-effort open Safari Web Inspector
│   │
│   │ # Host-browser web automation (Chrome default, Safari fallback)
│   ├── web_launch.py              # spawn Chrome with --remote-debugging-port
│   ├── web_open.py                # navigate (CDP or safaridriver)
│   ├── web_shot.py                # page screenshot
│   ├── web_record.py              # page video / screencast
│   ├── web_anim.py                # certified scroll-animation easing probe (Chrome/Safari/iOS-sim/Android-emu)
│   ├── _anim_core.py              # engine-agnostic easing certification core (web_anim + flutter_anim)
│   ├── web_eval.py                # Runtime.evaluate / executeScript
│   ├── web_dom.py                 # DOM snapshot
│   ├── web_console.py             # tail console events
│   ├── web_net.py                 # network intercept (Chrome only)
│   ├── web_emu.py                 # device emulation (Chrome only)
│   ├── web_click.py               # click by selector
│   ├── web_type.py                # type into selector
│   ├── web_scroll.py              # scroll by selector / offset
│   ├── web_a11y.py                # accessibility tree
│   │
│   │ # iOS Simulator
│   ├── ios_list.py                # simctl list devices
│   ├── ios_boot.py                # boot/shutdown/erase
│   ├── ios_app.py                 # install/uninstall/launch/terminate
│   ├── ios_url.py                 # openurl
│   ├── ios_push.py                # push notification
│   ├── ios_status_bar.py          # status bar override
│   ├── ios_appearance.py          # light/dark, locale
│   ├── ios_privacy.py             # grant/revoke/reset permissions
│   ├── ios_location.py            # spoof location
│   ├── ios_shot.py                # simctl io screenshot
│   ├── ios_record.py              # simctl io recordVideo
│   ├── ios_ui_tree.py             # idb ui describe-all
│   ├── ios_tap.py                 # idb ui tap
│   ├── ios_swipe.py               # idb ui swipe
│   ├── ios_type.py                # idb ui text
│   ├── ios_key.py                 # idb ui key
│   ├── ios_log.py                 # idb log
│   ├── ios_files.py               # idb file push/pull
│   ├── ios_safari.py              # safaridriver → Mobile Safari WebDriver
│   │
│   │ # Android Emulator
│   ├── adb_list.py                # adb devices -l
│   ├── adb_boot.py                # emulator boot / kill
│   ├── adb_app.py                 # install/uninstall/launch/force-stop
│   ├── adb_url.py                 # am start VIEW <url>
│   ├── adb_push.py                # am broadcast notification
│   ├── adb_settings.py            # dark mode, language, timezone
│   ├── adb_perm.py                # pm grant/revoke
│   ├── adb_location.py            # emu geo fix
│   ├── adb_shot.py                # exec-out screencap -p
│   ├── adb_record.py              # screenrecord
│   ├── adb_ui_tree.py             # uiautomator dump → XML → JSON
│   ├── adb_tap.py                 # input tap
│   ├── adb_swipe.py               # input swipe
│   ├── adb_type.py                # input text
│   ├── adb_key.py                 # input keyevent
│   ├── adb_log.py                 # logcat scoped to pid
│   ├── adb_files.py               # adb push/pull
│   ├── adb_cdp.py                 # forward 9222 → CDP /json + eval
│   │
│   │ # Flutter (mobile / web / macOS desktop)
│   ├── flutter_attach.py          # find VM service URL (auto-discover)
│   ├── flutter_vm.py              # JSON-RPC client wrapper
│   ├── flutter_tree.py            # widget / render / layer / semantics
│   ├── flutter_find.py            # locate widget by key / type / text
│   ├── flutter_tap.py             # tap widget by key (no coords)
│   ├── flutter_anim.py            # certified scroll-animation easing probe (Dart VM service)
│   ├── flutter_reload.py          # hot reload / hot restart
│   ├── flutter_diag.py            # perf overlay, repaint rainbow
│   ├── flutter_log.py             # stream stdout + Logging events
│   ├── flutter_shot.py            # in-engine screenshot (debug builds)
│   └── flutter_semantics.py       # toggle SemanticsBinding
├── templates/
│   ├── dioxus_debug_probe.rs      # drop-in Rust module: probe_dom,
│   │                              #   tail_console, dom_snapshot, install()
│   ├── dioxus_cargo_feature.md    # how to add [features] debug-probe = []
│   │                              #   to a crate's Cargo.toml
│   └── env_skill.example          # WRY_SPY_OUTDIR (kept name for legacy) etc.
├── commands/                      # agentskills.io slash commands
│   │                              #   (one per script; verbs grouped)
│   ├── pr-shot.md                 # /pr-shot <app>
│   ├── pr-record.md               # /pr-record <app> <secs>
│   ├── pr-region.md               # /pr-region <app> <x,y,w,h>
│   ├── pr-multishot.md            # /pr-multishot <app> <count> <fps>
│   ├── pr-ocr.md                  # /pr-ocr <app|region>
│   ├── pr-pixdiff.md              # /pr-pixdiff <imgA> <imgB>
│   ├── pr-click.md                # /pr-click <app> <x> <y> [opts]
│   ├── pr-drag.md                 # /pr-drag <app> <fromXY> <toXY>
│   ├── pr-hover.md                # /pr-hover <app> <x> <y>
│   ├── pr-scroll.md               # /pr-scroll <app> <dx> <dy>
│   ├── pr-type.md                 # /pr-type <app> <text>
│   ├── pr-key.md                  # /pr-key <app> <chord>
│   ├── pr-focus.md                # /pr-focus <app>
│   ├── pr-window.md               # /pr-window <app>   (list/inspect)
│   ├── pr-resize.md               # /pr-resize <app> <WxH> [at x,y]
│   ├── pr-menu.md                 # /pr-menu <app> "<File>/<Open…>"
│   ├── pr-drop.md                 # /pr-drop <app> <path> <x> <y>
│   ├── pr-clipboard.md            # /pr-clipboard get|set "<text>"
│   ├── pr-ax-tree.md              # /pr-ax-tree <app>
│   ├── pr-ax-click.md             # /pr-ax-click <app> "<identifier|label>"
│   ├── pr-wait.md                 # /pr-wait window|pixel|text <expr>
│   ├── pr-sample.md               # /pr-sample <app> <secs>
│   ├── pr-mem.md                  # /pr-mem <app>
│   ├── pr-nettrace.md             # /pr-nettrace <app> <secs>
│   ├── pr-tail.md                 # /pr-tail <app>
│   ├── pr-dom.md                  # /pr-dom <selector>  (Phase C)
│   │
│   │ # Host-browser web (Chrome-default)
│   ├── pr-web-open.md             # /pr-web-open <url> [--browser]
│   ├── pr-web-shot.md             # /pr-web-shot [--full|--element <sel>]
│   ├── pr-web-record.md           # /pr-web-record <secs>
│   ├── pr-web-eval.md             # /pr-web-eval "<js>"
│   ├── pr-web-dom.md              # /pr-web-dom [<selector>]
│   ├── pr-web-console.md          # /pr-web-console [--since N]
│   ├── pr-web-net.md              # /pr-web-net [--filter pattern]
│   ├── pr-web-emu.md              # /pr-web-emu <device-preset|wxh@dpr>
│   ├── pr-web-click.md            # /pr-web-click "<sel>"
│   ├── pr-web-type.md             # /pr-web-type "<sel>" "<text>"
│   ├── pr-web-scroll.md           # /pr-web-scroll "<sel>"|<dx,dy>
│   └── pr-web-a11y.md             # /pr-web-a11y
│   │
│   │ # iOS sim
│   ├── pr-ios-list.md             # /pr-ios-list
│   ├── pr-ios-boot.md             # /pr-ios-boot <udid|name>
│   ├── pr-ios-launch.md           # /pr-ios-launch <bundle-id>
│   ├── pr-ios-shot.md             # /pr-ios-shot
│   ├── pr-ios-record.md           # /pr-ios-record <secs>
│   ├── pr-ios-tap.md              # /pr-ios-tap <x> <y>
│   ├── pr-ios-swipe.md            # /pr-ios-swipe <x1,y1> <x2,y2>
│   ├── pr-ios-type.md             # /pr-ios-type <text>
│   ├── pr-ios-ui.md               # /pr-ios-ui   (describe-all)
│   ├── pr-ios-url.md              # /pr-ios-url <url>
│   ├── pr-ios-push.md             # /pr-ios-push <bundle> <payload.json>
│   ├── pr-ios-perm.md             # /pr-ios-perm grant|revoke <svc>
│   ├── pr-ios-loc.md              # /pr-ios-loc <lat> <lon>
│   ├── pr-ios-log.md              # /pr-ios-log
│   ├── pr-ios-safari.md           # /pr-ios-safari <url|eval>
│   │
│   │ # Android emu
│   ├── pr-adb-list.md             # /pr-adb-list
│   ├── pr-adb-boot.md             # /pr-adb-boot <avd>
│   ├── pr-adb-launch.md           # /pr-adb-launch <pkg/.Activity>
│   ├── pr-adb-shot.md             # /pr-adb-shot
│   ├── pr-adb-record.md           # /pr-adb-record <secs>
│   ├── pr-adb-tap.md              # /pr-adb-tap <x> <y>
│   ├── pr-adb-swipe.md            # /pr-adb-swipe <x1,y1> <x2,y2>
│   ├── pr-adb-type.md             # /pr-adb-type <text>
│   ├── pr-adb-key.md              # /pr-adb-key <KEYCODE>
│   ├── pr-adb-ui.md               # /pr-adb-ui   (uiautomator dump)
│   ├── pr-adb-url.md              # /pr-adb-url <url>
│   ├── pr-adb-perm.md             # /pr-adb-perm grant|revoke <pkg> <perm>
│   ├── pr-adb-loc.md              # /pr-adb-loc <lat> <lon>
│   ├── pr-adb-log.md              # /pr-adb-log <pkg>
│   ├── pr-adb-cdp.md              # /pr-adb-cdp <eval js | dom selector>
│   │
│   │ # Flutter
│   ├── pr-flutter-attach.md       # /pr-flutter-attach
│   ├── pr-flutter-tree.md         # /pr-flutter-tree [--kind widget|render|semantics]
│   ├── pr-flutter-find.md         # /pr-flutter-find <key|type|text>
│   ├── pr-flutter-tap.md          # /pr-flutter-tap <key>
│   ├── pr-flutter-reload.md       # /pr-flutter-reload [--restart]
│   ├── pr-flutter-diag.md         # /pr-flutter-diag <perf|repaint|slow>
│   ├── pr-flutter-log.md          # /pr-flutter-log
│   ├── pr-flutter-shot.md         # /pr-flutter-shot
│   └── pr-flutter-semantics.md    # /pr-flutter-semantics enable|disable
└── examples/
    ├── brainiac_perf_smoke.md     # end-to-end: launch, scroll sidebar,
    │                              #   probe DOM, screenshot 2 sector tiles
    └── tauri_smoke.md             # same recipe against a stock Tauri app
                                   #   (proves genericity)
```

## SKILL.md frontmatter (canonical)

```yaml
---
name: probe-runner
description: Capture, record, and drive macOS desktop apps (especially wry/Tauri/Dioxus). Screencapture-powered image + video + region capture, cliclick + Quartz-based input automation, Quartz window-id discovery, and (for Dioxus crates) a drop-in debug-probe Rust module that bounces DOM + console state out via `dioxus::document::eval`. Use when debugging a desktop app's visual state, recording a demo, automating a smoke test, or capturing pixels + DOM in the same pass. macOS only; relies on `screencapture(1)`, `cliclick`, `osascript`, and system Python 3 with pyobjc-Quartz.
allowed-tools: Bash(python3 *), Read, Write
argument-hint: "<subcommand> <app-name> [args...]"
user-invocable: true
---
```

Body of `SKILL.md` documents:

1. **Scope honesty.** Capture is universal; input automation is universal but
   coarse (window-relative coords); probes are Dioxus-only this iteration.
2. **Subcommands.** `shot`, `record`, `region`, `click`, `type`, `key`,
   `scroll`, `window`, `tail`, `dom`. Each routes to a Python script in
   `scripts/`.
3. **App-name → window-id resolution.** Always via
   `scripts/find_window.py`. macOS system Python ships `pyobjc-Quartz` by
   default; no `pip install` required on this machine. Document
   `python3 -c "import Quartz"` smoke check.
4. **Output convention.** `${PROBE_RUNNER_OUTDIR:-/tmp/probe-runner}/<app>-<ts>.<ext>`.
5. **Failure modes.** TCC permission prompts (Screen Recording for
   `screencapture`, Accessibility for `cliclick`); window minimized /
   off-screen; multiple windows with same owner name; `cliclick` not
   installed (`brew install cliclick`).
6. **Manual fallback for Safari Web Inspector** — right-click → Inspect; or
   `scripts/safari_inspect.py` best-effort drive of Safari menu bar.

## Critical files (paths to be created)

All paths under `~/.claude/skills/probe-runner/`:

- `SKILL.md` — agentskills.io-compliant frontmatter + body above.
- `README.md` — operator docs, install, troubleshooting.
- `scripts/_common.py` — shared helpers: `resolve_window(name) ->
  {window_id, bounds}`, `out_path(app, ext)`, `tcc_check()`, click-coord
  translation. Single import point for the other scripts.
- `scripts/find_window.py` — port of the inline Quartz snippet used during
  the blank-canvas debug session. Outputs JSON `{window_id, owner, bounds:
  {x,y,w,h}}` for the first window matching the owner name; `--all` lists
  every match; `--index N` picks N-th match.
- `scripts/shot.py`, `record.py`, `region.py` — Python subprocess wrappers
  honoring `PROBE_RUNNER_OUTDIR`. `record.py` supports both fixed-length
  (`--seconds N` → `screencapture -V`) and start/stop (`--start` /
  `--stop` storing pid in `/tmp/probe-runner/record.pid`).
- `scripts/click.py` — calls `_common.resolve_window`, adds window bounds
  to requested local coords, then `subprocess.run(["cliclick", f"c:{gx},{gy}"])`.
- `scripts/key_chord.py` — parses `cmd+shift+s` syntax → emits osascript
  `keystroke "s" using {command down, shift down}`. Activates the target app
  via `tell application "<owner>" to activate` first.
- `scripts/scroll.py` — Quartz `CGEventCreateScrollWheelEvent` direct, as
  used in the blank-canvas session to scroll the sidebar.
- `templates/dioxus_debug_probe.rs` — pure-Rust module providing:
  - `pub async fn probe_dom(selector: &str) -> serde_json::Value` —
    `getBoundingClientRect` + tag + child count.
  - `pub async fn tail_console(max_lines: usize) -> Vec<String>` —
    relies on a JS shim installed by the module on mount that monkey-patches
    `console.log/warn/error` into a ring buffer reachable via
    `__probe_runner_console_buffer`.
  - `pub async fn dom_snapshot(selector: &str, max_depth: usize) ->
    serde_json::Value` — light-weight DOM tree.
  - `pub fn install()` — installs the shim via `dioxus::document::eval` on
    first call.
  - Behind `#[cfg(feature = "debug-probe")]` so release builds compile
    without it.

## Brainiac-side companion plan (separate, post-skill)

A short follow-up plan that lives in `brainiac/docs/plans/` (per the
project's mandatory plans rule):

- Copy `dioxus_debug_probe.rs` into
  `crates/brainiac-visualizer/src/presentation/debug_probe.rs`.
- Add `[features] debug-probe = []` to `crates/brainiac-visualizer/Cargo.toml`.
- Gate `pub mod debug_probe;` in `lib.rs` behind the feature.
- Document `cargo run --features debug-probe --example perf_domain_heavy_100`
  in `brainiac/docs/05-tests/`.

The above is **out of scope** for the present skill plan; it’s called out so
the path-to-validation is visible.

## Plan-file location reconciliation

Plan mode assigned `~/.claude/plans/sunny-watching-matsumoto.md` as the
authoritative location. The global CLAUDE.md rule ("plans must be copied
into `docs/plans/` in the current project directory") applies because
brainiac is the current cwd — the implementation phase must copy this plan
to `brainiac/.claude/skills/probe-runner/docs/probe-runner-skill.md` (kebab-case per the rule).
That copy is an implementation step.

## Verification (must pass before marking done)

### Capture
1. `python3 scripts/find_window.py "perf_domain_heavy_100"` returns a JSON
   blob with a 4-tuple bounds.
2. `python3 scripts/shot.py perf_domain_heavy_100` produces a PNG under
   `/tmp/probe-runner/`; opens visually identical to manual right-click →
   Take Screenshot.
3. `python3 scripts/record.py perf_domain_heavy_100 --seconds 5` produces a
   5-second MOV showing the live app, with `-k` click highlights enabled.
4. `python3 scripts/region.py perf_domain_heavy_100 --rect 0,0,400,400`
   crops the top-left quadrant.

### Drive
5. `python3 scripts/key_chord.py perf_domain_heavy_100 "cmd+shift+s"` cycles
   the sector strategy (verified via stderr log line
   `[strategy] <kind>` from `workbench.rs::on_keydown`).
6. `python3 scripts/scroll.py perf_domain_heavy_100 0 -500` scrolls the
   sidebar; follow-up `shot.py` shows different domain rows than baseline.
7. `python3 scripts/click.py perf_domain_heavy_100 200 300` lands inside the
   sidebar pane and triggers a context-click highlight visible in the next
   shot.

### Dioxus probe (validated against brainiac, not in skill repo)
8. With `--features debug-probe` enabled in brainiac, calling
   `debug_probe::probe_dom(".brainiac-canvas svg")` from a test/example
   returns a JSON `{x,y,w,h,childCount}` matching the bounds seen by
   `shot.py`.
9. `debug_probe::tail_console(10)` returns the last 10 `console.log` lines
   produced by the running webview.

### Drive — extended (human-parity)
14. `python3 scripts/focus.py perf_domain_heavy_100` raises the window even
    if another app is frontmost.
15. `python3 scripts/drag.py perf_domain_heavy_100 --from 100,100 --to
    300,300` drags within the window; verified by follow-up `shot.py`.
16. `python3 scripts/hover.py perf_domain_heavy_100 200 200` parks cursor;
    follow-up `shot.py` shows hover-state styling.
17. `python3 scripts/clipboard.py set "hello"` then `paste` via `key_chord
    "cmd+v"` inserts the text into a focused input.
18. `python3 scripts/menu.py perf_domain_heavy_100 "File/Open…"` invokes the
    menu item if present.
19. `python3 scripts/drop_file.py perf_domain_heavy_100 /tmp/sample.txt 400
    400` drops a file into the window; if the app handles it, AX tree shows
    new state.

### Superhuman
20. `python3 scripts/ax_tree.py perf_domain_heavy_100` returns a JSON tree
    listing AX roles + identifiers for every focusable element.
21. `python3 scripts/ax_click.py perf_domain_heavy_100 "<some-label>"`
    clicks without coords if the app exposes AX.
22. `python3 scripts/ocr.py perf_domain_heavy_100` returns the on-screen
    text (Vision framework) — verify by matching sidebar context names.
23. `python3 scripts/pixdiff.py shot_before.png shot_after.png` returns a
    diff score > 0 after `key_chord cmd+shift+s`. Add `--region X,Y,W,H`
    to crop both inputs to the canvas before differencing (skips
    toolbar/breadcrumb chrome that would otherwise dilute the score).
24. `python3 scripts/sample.py perf_domain_heavy_100 3` produces a CPU
    sample dump.
25. `python3 scripts/multishot.py perf_domain_heavy_100 --count 60 --fps 30`
    captures a 2-second burst with timestamps embedded in filenames.

### Host-browser web (Chrome default, Safari fallback)
37. `python3 scripts/web_launch.py` spawns Chrome with
    `--remote-debugging-port=9222`; `curl localhost:9222/json/version`
    returns the protocol version.
38. `python3 scripts/web_open.py https://example.com` navigates; follow-up
    `web_shot.py --full out.png` produces a full-page PNG.
39. `python3 scripts/web_eval.py "document.title"` returns
    `"Example Domain"` via CDP.
40. `python3 scripts/web_open.py https://example.com --browser=safari`
    explicitly forces safaridriver; `web_eval.py` still returns the
    title (via WebDriver `executeScript`).
41. `python3 scripts/web_net.py --filter example.com` records the first
    request/response pair for the navigation (Chrome only — script reports
    "unsupported on Safari" if `--browser=safari`).

### iOS Simulator
26. `python3 scripts/ios_list.py` returns JSON of available simulators.
27. `python3 scripts/ios_boot.py "iPhone 15"` boots that sim; subsequent
    `ios_shot.py` produces a PNG of the home screen.
28. `python3 scripts/ios_app.py install /path/to/app.app` then `launch
    com.example.bundle` lights the app; `ios_ui_tree.py` lists the launch
    screen's elements.
29. `python3 scripts/ios_tap.py 100 200` registers as a tap;
    `ios_record.py --seconds 3` captures the resulting transition.
30. `python3 scripts/ios_safari.py --url https://example.com --eval
    "document.title"` returns `"Example Domain"` via safaridriver, proving
    Mobile Safari DOM access works.

### Android Emulator
31. `python3 scripts/adb_list.py` lists attached emulators / devices.
32. `python3 scripts/adb_app.py launch com.example/.MainActivity` opens
    the app on the currently booted emulator.
33. `python3 scripts/adb_shot.py` produces a PNG via
    `adb exec-out screencap -p`.
34. `python3 scripts/adb_ui_tree.py` returns the UI hierarchy as JSON
    (converted from `uiautomator dump`'s XML).
35. `python3 scripts/adb_tap.py 500 1000` and `adb_type.py "hello"`
    interact with a focused field; follow-up `adb_shot.py` shows state.
36. `python3 scripts/adb_cdp.py --eval "document.title"` returns the
    title of the active page in Chrome on the emulator via CDP after
    `adb forward tcp:9222 localabstract:chrome_devtools_remote`.

### Flutter
42. With a Flutter counter app running on the iOS sim
    (`flutter run -d "iPhone 15"`),
    `python3 scripts/flutter_attach.py --auto` resolves the VM service
    URL within 10 s and writes it to
    `${PROBE_RUNNER_OUTDIR}/flutter.url`.
43. `python3 scripts/flutter_tree.py --kind widget` returns JSON of
    the widget tree containing the default `Scaffold` + `FloatingActionButton`.
44. `python3 scripts/flutter_find.py --type FloatingActionButton`
    returns the widget id + bounding rect.
45. `python3 scripts/flutter_tap.py <key-from-44>` increments the
    counter; follow-up `flutter_tree.py` shows `Text` value increased
    by one.
46. `python3 scripts/flutter_reload.py` hot-reloads after touching a
    source file; `flutter_log.py` shows the reload event.
47. Same recipe run against `flutter run -d chrome` and `flutter run -d
    macos` produces equivalent results, proving cross-target genericity.

### Cross-cutting
10. Skill is invocable via `/pr-shot perf_domain_heavy_100` (Claude Code
    auto-discovers the slash command from `commands/pr-shot.md`).
11. `scripts/find_window.py` against a Tauri app (e.g. spawned via
    `cargo install create-tauri-app && create-tauri-app smoke && cd smoke
    && cargo tauri dev`) returns a sensible window-id, proving the
    discovery layer is framework-agnostic.
12. README.md "Troubleshooting" covers: screen-recording TCC prompt,
    Accessibility prompt for `cliclick`, empty window-id (app not running,
    minimized, wrong owner name), `cliclick` not installed.
13. `python3 -c "import Quartz"` smoke check documented in README; if
    it fails the user is told to `pip3 install pyobjc-framework-Quartz`.

## Out of scope (named to forestall scope creep)

- Tauri/raw-wry probe templates — design only, not shipped this round.
- Linux/Windows host support — wry's macOS-only Safari Inspector path
  means the probe template assumes WebKit behavior; Linux uses webkit2gtk
  WebInspector, Windows uses Edge DevTools. Generalizing the probe to
  those host platforms is a follow-up.
- Network-traffic capture inside the macOS webview — wry doesn't expose
  CDP, and reading from Safari Web Inspector programmatically requires
  WebKit internals. Future spike: Tauri-style custom protocol logger.
- Coordinate-based pixel diff / visual regression — `pixdiff.py` ships, but
  golden-image test harness (a la `reg-cli`, `Pixelmatch`) is out of scope.
- Video editing / trimming — operator uses `ffmpeg` post-hoc.
- Real-device (non-simulator) iOS / Android — design supports it
  (`idb` and `adb` both handle real devices), but TCC/signing complications
  (developer team provisioning, USB debugging trust prompts) are not
  documented this round. Sim/emu is the validated target.
- Appium / WDA / UIAutomator2 test-runner integration — skill provides
  primitives (tap, swipe, ui dump, install) so that an external test runner
  can be wired up. The skill is not itself a test framework.
- Mobile network capture (mitmproxy CA install on sim/emu) — separate
  concern; the skill exposes `--proxy` env passthrough but does not
  bootstrap the proxy.

## Implementation order

The order is incremental but **all of it ships this round**. Verify after
each block; no block depends on the next compiling first.

1. Scaffold `~/.claude/skills/probe-runner/` with `SKILL.md` + `README.md`.
2. `scripts/_common.py` + `scripts/find_window.py` + `wait_window.py`.
   Verify (1).
3. Capture block: `shot.py`, `region.py`, `record.py`, `multishot.py`,
   `pixdiff.py`. Verify (2-4, 23, 25).
4. OCR block: `ocr.py`, `text_diff.py` (depends on Vision framework
   `pyobjc-framework-Vision` — document install). Verify (22).
5. Pointer-drive block: `click.py`, `drag.py`, `hover.py`, `scroll.py`,
   `gesture.py`. Verify (7, 15, 16).
6. Keyboard-drive block: `type_text.py`, `key_chord.py`, `clipboard.py`.
   Verify (5, 17).
7. Window/app/menu block: `focus.py`, `reposition.py`, `window_state.py`,
   `menu.py`, `context_menu.py`, `drop_file.py`. Verify (14, 18, 19).
8. Accessibility block: `ax_tree.py`, `ax_text.py`, `ax_click.py`,
   `ax_observe.py`. Verify (20, 21).
9. Diagnostics block: `sample.py`, `mem.py`, `fswatch.py`, `nettrace.py`,
   `tail_log.py`, `headless.py`. Verify (24).
10. Webview block: `safari_inspect.py`, `dom.py`, `console.py` +
    `templates/dioxus_debug_probe.rs`. Validate against brainiac in a
    separate brainiac change. Verify (8-9).
10.5. Host-browser web block: `web_*.py` set. Requires Chrome at
    `/Applications/Google Chrome.app` (or `chromium` on $PATH) for default
    path; `safaridriver --enable` once for the fallback path. Python
    dependency: `pychrome` or raw `websockets` + `requests` for CDP, plus
    `selenium` for the WebDriver fallback. Verify (37-41).
11. iOS sim block: `ios_*.py` set + safaridriver helper. Requires
    `xcrun simctl` (Xcode CLI tools) and `fb-idb` (`brew install idb-companion
    && pipx install fb-idb`). Verify (26-30).
12. Android emu block: `adb_*.py` set + CDP helper. Requires
    `platform-tools` (`brew install android-platform-tools`). Verify (31-36).
12.5. Flutter block: `flutter_*.py` set. Python deps: `websockets` for
    Dart VM service JSON-RPC, no extra binary required (Flutter SDK
    already on operator's machine for any Flutter project). Verify
    (42-47).
13. Commands directory: one markdown stub per script. Verify (10).
14. README.md with troubleshooting + smoke checks + capability matrix
    (now including iOS sim + Android emu prerequisites: Xcode CLI tools,
    `fb-idb`, `android-platform-tools`, optional `safaridriver --enable`).
    Verify (12-13).
15. Examples: `brainiac_perf_smoke.md`, `tauri_smoke.md`,
    `chrome_cdp_smoke.md`, `safari_fallback_smoke.md`,
    `ios_safari_smoke.md`, `android_chrome_smoke.md`,
    `flutter_counter_smoke.md` (iOS/Android/web/macOS x4 from one app).
    Verify (11, 30, 36, 37-41, 42-47).
16. Copy this plan to `brainiac/.claude/skills/probe-runner/docs/probe-runner-skill.md`
    (CLAUDE.md global rule).

End of plan.
