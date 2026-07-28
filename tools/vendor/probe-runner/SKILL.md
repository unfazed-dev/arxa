---
name: probe-runner
description: Capture, record, and drive macOS desktop apps (wry/Tauri/Dioxus), iOS simulators, Android emulators, host web (Chrome-default, Safari-fallback), and Flutter targets (iOS/Android/web/macOS) from a single skill. Screencapture-powered image+video, cliclick + Quartz input automation, AX-tree access, Chrome DevTools Protocol, Dart VM service, and a drop-in Dioxus debug-probe Rust module. Use when debugging a desktop app's visual state, automating a smoke test across sims, recording a demo, or capturing pixels + DOM + widget tree in the same pass.
allowed-tools: Bash(python3 *), Bash(osascript *), Bash(cliclick *), Bash(screencapture *), Bash(xcrun *), Bash(idb *), Bash(adb *), Bash(emulator *), Bash(curl *), Bash(ffmpeg *), Bash(pbcopy *), Bash(pbpaste *), Bash(sample *), Bash(leaks *), Bash(vmmap *), Bash(fswatch *), Bash(tcpdump *), Bash(safaridriver *), Bash(open *), Bash(pgrep *), Bash(pkill *), Read, Write
argument-hint: "<subcommand> [args...]"
user-invocable: true
metadata:
  hermes:
    tags: [macos, automation, debug, ios-sim, android-emu, flutter, dioxus, tauri, wry]
    category: devops
---

# probe-runner

End-to-end capture + drive skill spanning five target classes from one Python codebase:

| Target | Primitives | Window/element identity |
|---|---|---|
| **macOS native / wry / Tauri / Dioxus** | `screencapture`, `cliclick`, `osascript`, Quartz, AX | window-owner name → `find_window.py` |
| **Host browsers (Chrome default, Safari fallback)** | CDP via `--remote-debugging-port=9222`, `safaridriver` WebDriver | target URL / CSS selector |
| **iOS Simulator** | `xcrun simctl`, `fb-idb` | `booted` UDID |
| **Android Emulator** | `adb`, `uiautomator dump`, CDP via `adb forward` | `-s <serial>` device |
| **Flutter (iOS/Android/web/macOS)** | Dart VM service JSON-RPC, plus the target-class primitives | widget key/type/text |

## Platform support (host OS)

probe-runner's CORE surface runs on **every OS**: the web (CDP), iOS-sim (idb/xcrun), Android-emu (adb), and Flutter (VM service) verbs are platform-agnostic — they drive external targets, not the host. Only the **desktop** surface is host-coupled:

| Surface | macOS | Linux | Windows |
|---|---|---|---|
| web / ios / adb / flutter verbs | ✅ | ✅ | ✅ |
| `pixdiff` (ssim/mean) / `ocr` (Vision) | ✅ | ssim/mean ✅, ocr ❌ | ssim/mean ✅, ocr ❌ |
| Desktop window capture (`shot`/`record`/`region`) | ✅ (ScreenCaptureKit + screencapture) | ❌ roadmap (PipeWire portal) | ❌ roadmap (DXGI/mss) |
| Desktop input (`click`/`drag`/`type_text`/`ax_*`) | ✅ (cliclick + Quartz AX) | ❌ roadmap (pynput/xdotool) | ❌ roadmap (pynput) |

A `_platform.py` capability layer detects the host and routes desktop verbs: macOS uses the best available backend; Linux/Windows raise a clear `NotImplementedError` naming the researched native path (never a raw ImportError crash). So probe-runner **runs everywhere**; only desktop capture/input is macOS-gated, detected cleanly.

## As a harness (replaces Playwright for observation)

probe-runner is an **observation + certification** surface, not an assertion
framework. It captures pixels, trees, and motion and certifies them
(`certified:true/false`, `above_threshold`); the *assertion* (pass/fail on those
facts) is the consumer's job via `pixdiff` (pixel) or `skeleton_diff`
(geometry/layout). Playwright's `expect(locator).toBeVisible()` has no direct
equivalent here — drive the target, capture, then assert against the emitted
JSON. This keeps probe-runner target-agnostic: one certify contract across web
/ iOS / Android / Flutter instead of N driver-specific assertion APIs.

## When to invoke

- Visual debug: capture a window's pixels to confirm a CSS regression.
- DOM/widget debug: dump element tree + log without re-launching with verbose tracing.
- Smoke automation: launch app, drive through golden path, record video, diff pixels.
- Multi-target validation: same Flutter app on iOS sim + Android emu + Chrome web.
- Demo capture: record a 30-second walkthrough with click highlights.

## Subcommands

All routed through `scripts/<verb>.py`. Slash-command form in `commands/`:

| Class | Verbs |
|---|---|
| Host desktop discovery | `find_window`, `wait_window`, `ax_tree`, `ax_text`, `ax_click`, `ax_observe` |
| Host capture | `shot`, `region`, `record`, `multishot`, `pixdiff`, `ocr`, `vision_probe`, `text_diff` |
| Host pointer | `click`, `drag`, `hover`, `scroll`, `gesture` |
| Host keyboard | `type_text`, `key_chord`, `clipboard` |
| Host window/menu | `focus`, `reposition`, `window_state`, `menu`, `context_menu`, `drop_file`, `wait_pixel` |
| Host diagnostics | `sample`, `mem`, `fswatch`, `nettrace`, `tail_log`, `headless`, `tcc_check` |
| Wry/Dioxus webview | `safari_inspect`, `dom`, `console` (Dioxus template required) |
| Host browser web | `web_launch`, `web_open`, `web_shot`, `web_record`, `web_anim`, `web_flipbook`, `web_eval`, `web_dom`, `web_console`, `web_net`, `web_emu`, `web_click`, `web_type`, `web_scroll`, `web_a11y` |
| iOS sim | `ios_list`, `ios_boot`, `ios_app`, `ios_url`, `ios_push`, `ios_status_bar`, `ios_appearance`, `ios_privacy`, `ios_location`, `ios_shot`, `ios_record`, `ios_ui_tree`, `ios_tap`, `ios_swipe`, `ios_type`, `ios_key`, `ios_log`, `ios_files`, `ios_safari`, `ios_flipbook`, `ios_entrance` |
| Android emu | `adb_list`, `adb_boot`, `adb_app`, `adb_url`, `adb_intent` (formerly `adb_push`), `adb_settings`, `adb_perm`, `adb_location`, `adb_shot`, `adb_record`, `adb_ui_tree`, `adb_tap`, `adb_swipe`, `adb_type`, `adb_key`, `adb_log`, `adb_files`, `adb_cdp`, `adb_flipbook` |
| Flutter | `flutter_attach`, `flutter_vm`, `flutter_tree`, `flutter_find`, `flutter_tap`, `flutter_set_text`, `flutter_inspect`, `flutter_anim`, `flutter_flipbook`, `flutter_eval`, `flutter_reload`, `flutter_diag`, `flutter_log`, `flutter_shot`, `flutter_semantics`, `flutter_skeleton` |
| Design↔built fidelity | `design_golden` (Chrome CDP renders design HTML → state-driven golden PNG), `color_assert` (sample a region, assert colour via CIEDE2000 ΔE) |
| **Tool routing** | `pr-decide` (read-only resolver: intent × target → command + args + fallback + notes; source `verbs.json`; see [Decision matrix](#tool-routing--decision-matrix) below) |

**Certified scroll-animation easing** (`web_anim` / `flutter_anim`, shared core
`_anim_core.py`): recover `prop = f(scroll)` exactly by sampling at *static*
scroll offsets and reading the rendered transform, then emit an easing fit only
when the value held, reproduced on revisit (scroll-scrubbed, not time-based),
stayed monotonic, and matched a standard curve — otherwise `certified:false`
with a reason. `web_anim` runs the identical certification over three
transports: Chrome/CDP (host, default), Safari/WebDriver (host, or Mobile Safari
on a booted iOS sim via `--ios --url`), and Android-emulator Chrome/WebView over
adb-forwarded CDP (`--android`; suppresses the Origin header that on-device
Chrome 403-rejects). `flutter_anim` drives `ScrollPosition.jumpTo` + reads
`RenderObject.getTransformTo(null)` over the Dart VM service (`--self-test`
verifies the core offline; the live VM-eval bridge is verified end-to-end against
Flutter 3.44 macOS, using library-scoped Dart eval against the root library).

**Always pair eval with anim.** Before `web_anim`/`flutter_anim`, run an eval pass to capture three things measurement alone misses: (1) exact element **anchors** (`getBoundingClientRect().top + scrollY`) to feed `--range <y-200>:<y+900>` per region — full-page auto-sampling is too coarse to resolve narrow active windows and leaves movers `certified:false`; (2) the **smooth-scroll config** (Lenis/GSAP) and DOM structure; (3) `getComputedStyle().transition`/`animation` for **time-based** (on-enter) elements `web_anim` cannot certify (their exact curve is the CSS duration + timing-function, read live). Eval is available on every transport `web_anim` measures — Chrome/CDP, host + iOS-sim Safari/WebDriver, Android-emu Chrome over adb-forwarded CDP — and on Flutter via the Dart VM (library-scoped eval against the root library). Standalone `web_eval` now shares `web_anim`'s transport resolver (`_web_eval`), so it carries the same `--ios`/`--android`/`--cdp-port`/`--url` flags — JS eval on host Chrome (CDP), host + iOS-sim Safari (WebDriver), and Android-emulator Chrome (adb-forwarded CDP). `flutter_eval` is the Dart-VM sibling (one-shot root-library eval, shared `_flutter.VMLib` with `flutter_anim`). Native (non-web) iOS/Android have no JS eval — use `ios_ui_tree`/`adb_ui_tree`.

**Frame-based motion recovery (flipbook)** (`web_flipbook` / `flutter_flipbook` / `ios_flipbook` / `adb_flipbook`,
shared core `_flipbook` + `_native_flipbook`/`_frames`). Fills the gap `web_anim`
cannot certify: **time/event** animations (menu open, entrance) and **native**
apps with no DOM. Recovers the motion law (tx/ty/scale/opacity over time) by
TRACKING the element across a frame sequence (cv2 template match), so it is
content-independent (a clone with different images is certified by motion SHAPE)
and platform-universal (the only input is screenshots). `web_flipbook` (CDP)
pauses + scrubs WAAPI timelines deterministically and reads `getAnimations()` as
an exact oracle; `flutter_flipbook` resolves the widget rect over the Dart VM,
real-input taps the trigger, `adb screenrecord`s, recovers, and cross-checks
amplitude against `getTransformTo`. `ios_flipbook` is the native-iOS sibling: it
resolves the element rect AND a start/end displacement oracle from idb's
accessibility tree (`idb ui describe-all` frames, logical points), real-input
taps via `idb ui tap`, `simctl io recordVideo`s, recovers, and cross-checks
amplitude against the idb frame — falling back to `--auto` pixel-localisation +
`--tap-xy` when the mover is not an accessibility element (a Flutter bare widget
needs an explicit `Semantics`; a Material FAB/button is auto-exposed).
**Honest precision:** pixel recovery from a
screen recording certifies the motion FAMILY (ease-in vs out vs linear) +
amplitude; it resolves ease-out COUSINS (easeOutCubic vs easeOutQuart) only when
an introspection oracle is present (getAnimations / VM transform / idb frame /
desktop scrub) — emulator/sim framebuffer noise (~3% rms) blurs cousins, and on
a sim the ease label can even wobble between ease-out sub-families (out↔in-out)
run-to-run while amplitude stays oracle-confirmed (iOS-sim live: idb 260pt vs
recovered 4–17px, ease-out-dominant). Scroll-scrubbed
animations stay on `web_anim` (a fixed window on a scrolling page measures
scroll-through, not the transform). cv2 (`opencv-python`) is required for
tracking; the numpy/Pillow/ffmpeg baseline covers global motion only.

**Two motion models — read the right one.** Motion capture has two pipelines with
deliberately different schemas; do not conflate them:
- **Scroll-scrubbed** (`web_anim` / `flutter_anim` → `_anim_core`): certifies `prop = f(scrollY)`, which is *timeless* — there is **no duration**. Per-channel output is `{from, to, range, easing, rms, certified, activeScroll, scrollDeterministic}`. Amplitude = `to - from`; confidence is the boolean `certified` (signed amplitude preserves direction).
- **Time/event** (`web_flipbook` / `flutter_flipbook` / `ios_flipbook` / `adb_flipbook` → `_flipbook` / `_native_flipbook`): recovers motion from a screen recording. Per-channel output is `{from, to, amp, samples, reliable, easing, bezier, rms}`. `amp` is the recovered pixel amplitude; `reliable` is the confidence flag. **`duration` is NOT in the recovered output** — t0/D are absorbed into the t0-invariant aligned fit; duration lives *only* in the web `getAnimations()` oracle (`web_flipbook`), as a ground-truth cross-check, never in pixel recovery.
Both raw payloads now also carry a top-level **`motion_summary`** block (`motion_adapter.motion_summary`) that lifts the best per-axis reading into one consistent shape — `{klass, channels: {<axis>: {easing, amplitude, rms, window, confidence, source_channel}}}` — so a direct consumer (an agent) does not have to parse the three raw shapes. `confidence` is `"high"` (certified/reliable) or `"low"`. The bundle layer (`motion_adapter` → `bundle_writer.match_motion`) unifies both models into one 10-key motion.json row contract regardless.

**Design-capture engine** — five verbs that capture a live web page into a portable `bundle/` any agent can re-skin and re-content without touching the original. All run over CDP (Chrome, default) and share `_web.py` / `_web_eval.py` / `_common.py`.

- `web_skeleton` — DOMSnapshot → content-free skeleton: bbox, role, z-index, parent-tree, font-size, sizing, layout, `token_ref`, `anim_ref`. REST capture: `GET /skeleton?url=…`. `--viewports w1,w2,…` emits multi-breakpoint sizing inference in one pass.
- `web_tokens` — extracts the real computed palette, then maps it to semantic roles (bg/surface/primary/accent/text/muted/border) + type scale, space scale, radii scale, and shadow scale; emits `tokens.json`.
- `skeleton_diff` — tight geometry + sizing + parent-tree static-design certification. Bounds are CSS px (gates dpr-independent in value); calibrated to the **same-dpr** self-diff floor (same page, same viewport, same devicePixelRatio — measured ~0 px) so measurement noise cannot trigger a false fail. Capture source and clone at the same dpr; cross-dpr quantization (~0.75-px pos / ~1.5-px size) is a degraded mode. Reproducible calibration: `docs/skeleton-diff-css-px-calibration.md`. Outputs `certified:true/false` + per-node delta list.
- `bundle_writer` — assembles the portable `bundle/{meta,skeleton,tokens,motion}.json + assets/manifest.json`. Motion is read from an existing `web_anim` or `web_flipbook` capture file — `bundle_writer` does not capture motion itself. The bundle is the single artifact any agent rebuilds, swaps all content into, and re-skins from.
- `web_vectors` — opt-in, NON-certified: runs `vtracer` raster→SVG reference traces for `<img>` / `<svg>` nodes and writes `assets/vectors/`. Requires `vtracer` on PATH (`cargo install vtracer`). Not part of `skeleton_diff` certification.

**Native skeleton.** The bundle format extends to native targets — exact only where an introspection oracle exists (same honesty model as the flipbook):
- `flutter_skeleton` — **built.** Walks every `RenderBox` from `WidgetsBinding.instance.rootElement` over the Dart VM service (one eval round-trip; reads `localToGlobal(Offset.zero)` + `size` + `devicePixelRatio`), classifies roles (Text→text, Image→image, …), and emits the same `probe-skeleton/2` schema `web_skeleton` does — so `skeleton_diff` works on Flutter output UNMODIFIED. Geometry is exact (logical points); honest v1 limits: `sizing` and `font` are low-confidence placeholders (Flutter has no cheap computed-style path). `flutter_tree --kind render` returns a text dump, NOT bboxes — use `flutter_skeleton` for structured geometry. `--self-test` verifies the core offline.
- `ios_skeleton` — roadmap. `idb ui describe-all` frames → logical-point bbox + role → bundle. The `ios_flipbook` frame oracle (`frame_of`/`region_devpx`) is the reuse seed.
- Desktop "through Chrome" = `web_skeleton` over the webview CDP transport. Image-only input = bounded far edge (CV + OCR + vtracer, confidence:low).
All targets emit `bundle/skeleton.json` → `skeleton_diff` + flipbook motion-cert apply unchanged.

## Tool routing / decision matrix

probe-runner ships ~100 target-prefixed verbs (`ios_tap`, `adb_tap`,
`flutter_tap`, `web_click`, `click`, …). At 100+ tools an agent blows past the
tool-selection accuracy sweet-spot (~10–20 tools) and starts guessing the wrong
prefix or arg shape — verb-fishing through 2–3 retries before landing the right
one. The reverse index below closes that. **Name a GOAL (one of 12 intents) +
a TARGET (one of 6 classes), get the exact command, args, fallback, and
edge-case notes in one read.** Two paths, same data:

- **Fast path** — the compact matrix below (always loaded with this file).
- **Precise path** — `pr-decide` (the read-only resolver), for the arg shape /
  fallback / notes the matrix can't hold. `scripts/verbs.json` is the single
  source of truth; `pr-decide` never executes anything — copy the printed
  command.

### The 12 intents × 6 targets matrix (canonical script per cell)

| intent | iOS sim | Android emu | Host web (Chrome) | macOS desktop | Flutter | Safari |
|---|---|---|---|---|---|---|
| **tap** | `ios_tap` | `adb_tap` | `web_click` | `click` | `flutter_tap` | `web_click` |
| **type** | `ios_type` | `adb_type` | `web_type` | `type_text` | `flutter_set_text` | `web_type` |
| **screenshot** | `ios_shot` | `adb_shot` | `web_shot` | `shot` | `flutter_shot` | `web_shot` |
| **uitree** | `ios_ui_tree` | `adb_ui_tree` | `web_dom` | `ax_tree` | `flutter_tree` | `web_dom` |
| **eval** | — | — | `web_eval` | — | `flutter_eval` | `web_eval` |
| **find** | — | — | — | `find_window` | `flutter_find` | — |
| **scroll** | `ios_swipe` | `adb_swipe` | `web_scroll` | `scroll` | — | `web_scroll` |
| **record** | `ios_record` | `adb_record` | `web_record` | `record` | — | `web_record` |
| **animate** | — | `web_anim` | `web_anim` | — | `flutter_anim` | `web_anim` |
| **launch** | `ios_boot` | `adb_boot` | `web_launch` | — | `flutter_attach` | `web_launch` |
| **quit** | `ios_app` | `adb_app` | — | — | — | — |
| **wait** | — | — | — | `wait_window` | — | — |

`—` = no dedicated verb for that target; resolve the route for the alternative
(e.g. `eval` on native iOS/Android has no JS engine → use `ios_ui_tree` /
`adb_ui_tree`; `find` outside Flutter → rects come from the tree-dump verb;
`scroll`/`record` on Flutter → `flutter_anim` / `flutter_flipbook`).

### Using the resolver (`pr-decide`)

```bash
S=${CLAUDE_SKILL_DIR}/scripts
python3 $S/pr-decide.py tap --target ios      # one route: command + args + fallback + notes
python3 $S/pr-decide.py tap                   # all 6 targets for "tap"
python3 $S/pr-decide.py                       # print the full matrix (cheatsheet)
python3 $S/pr-decide.py --list                # list intents + targets
```
Slash form: `/pr-decide tap --target ios`.

### Before / after — "tap the login button on the iOS sim"

- **Without** — the agent must recall: target prefix is `ios_`, the verb is
  `tap`, args are two coords in logical points, and (if it's a Flutter app) the
  real verb is `flutter_tap`. It guesses `ios_tap`, maybe picks device px, and
  on a Flutter widget retries via `flutter_tap` — 2–3 turns of verb-fishing.
- **With** — `pr-decide tap --target ios` returns immediately:
  ```json
  { "intent": "tap", "target": "ios",
    "command": "python3 scripts/ios_tap.py <x> <y>",
    "fallback": "flutter_tap.py --target ios (for a Flutter widget)",
    "notes": "idb ui tap; coordinates in logical points. NEVER raw-tap without
      a press duration — a 0-duration tap silently no-ops (~80% miss) on
      Flutter/hybrid views; ios_tap.py applies --duration 0.1s for you." }
  ```
  Exact command, the Flutter fallback inline, and the coordinate-unit gotcha —
  one read, zero retries.

### Edge cases the matrix encodes (resolve a route to surface them)

- **`flutter:tap --target macos|web`** → honest-gap rc=2; the resolver's
  `fallback` carries the semantics-enable → `web_dom`/`ax_tree` sequence.
- **`adb:type` / `ios:type` on a Flutter field** → `notes` warns these inject
  into the IME and do NOT fire `onChanged`; the fallback points at
  `flutter_set_text` (the canonical Flutter text verb).
- **`safari:eval --await`** → `notes` flags that `--await` is synchronous on
  WebDriver (no awaitPromise) — promises are NOT awaited.
- **`web:a11y/console/net/emu` on Safari** → die rc=2 (Chrome-only); the
  matrix routes Safari `uitree` to `web_dom`, not `web_a11y`.
- **`adb:tap/swipe` with the screen locked** → `notes` says send
  `KEYCODE_WAKEUP` first (events dispatch but are invisible).
- **`launch:flutter`** → `notes` carries the cold-launch gotcha: `flutter run
  --disable-service-auth-codes` is required (cold-launch via `flutter build` +
  simctl/adb yields an app with NO VM service).

`scripts/test_pr_decide.py` enforces manifest validity + a **drift check**
(every referenced script exists on disk) — so the matrix can't silently rot
when a script is renamed/removed.

## Builder-consumable bundle

The design-capture engine produces a **portable `bundle/` directory** — the single
artifact a builder (an agent, a code generator, a re-skin pipeline) consumes to
rebuild, re-skin, or re-content a target without touching the original. The
bundle is **content-free by construction** (`content_firewall.audit_bundle`
re-scans the whole tree before each run is declared clean; a leak raises
`ContentLeak`, rc=3) — so it is safe to share, diff, or hand to an agent.

### Capture → bundle → consume

```bash
S=$CLAUDE_SKILL_DIR/scripts
# 1. capture a live web route into skeleton + tokens (+ style/theme/responsive/… sidecars)
python3 $S/web_skeleton.py --url https://example.com --cdp-port 9222 --out sk.json
python3 $S/web_tokens.py   --url https://example.com --cdp-port 9222 --out tokens.json
# 2. (optional) capture motion: web_anim (scroll-scrubbed) and/or web_flipbook (time/event)
python3 $S/web_anim.py     --url https://example.com --cdp-port 9222 --out anim.json
python3 $S/motion_adapter.py --anim anim.json --out motion.json   # -> 10-key contract rows
# 3. assemble the bundle (validates the motion contract; content-audits before write)
python3 $S/bundle_writer.py --skeleton sk.json --tokens tokens.json --motion motion.json --out bundle/
```

### `bundle/` layout

| File | Contents |
|---|---|
| `meta.json` | `{url, viewport, page, dpr, schema, timestamp}` |
| `skeleton.json` | content-free node tree: bbox (CSS px), role, z-index, parent-tree, font, sizing, layout, `token_ref`, `anim_ref`, + per-node `style`/`pseudo`/`theme`/`responsive`/`keyframes`/`reduced_motion`/`form_state`/`container` deltas when captured |
| `tokens.json` | computed palette mapped to semantic roles (bg/surface/primary/accent/text/muted/border) + type/space/radii/shadow scales |
| `motion.json` | the **10-key motion contract**: `[{node_id, name, easing, cubic_bezier, amplitude, axis, window, class, source, rms}]` — `class` ∈ `scroll` (timeless, prop=f(scrollY)) or `time` (event/entrance) |
| `substrate.json` | DOM-substrate repro hints (tiered-honest: where a region can/can't be reproduced content-free) |
| `assets/manifest.json` | typed slots (image/text/svg) + index — the swappable-content surface |
| `states.json` *(opt)* | G4 interaction-state presence-diff (modal/tab/hover states) |

### Multi-route capture (`site_capture.py`)

For a whole site, `site_capture.py` drives the per-route pipeline
(`web_skeleton → web_tokens → bundle_writer`) across an **explicit route list**
and emits one bundle per route plus a content-free `site.json` manifest (the merge
contract). `--merge` / `--dedup` run the post-processors (`site_merge →
design_system.json`, `site_chrome → chrome_dedup.json`); each re-audits the whole
tree through the unchanged firewall.

```bash
python3 $S/site_capture.py --urls-file routes.txt --out site_out --cdp-port 9222 [--merge --dedup]
```

### What the bundle is NOT for

The bundle is a **capture-once / rebuild-many** artifact for a builder doing
re-skin/re-content/rebuild. It is **not** a live-running-animation inspector — a
consumer that needs the *currently-running* animation values (e.g. a round-trip
"does the emitted code's `getComputedStyle` match the design's?") should drive
the live target with `web_eval` / `flutter_eval`, not read the bundle. Both
patterns are valid; they serve different jobs. (See `examples/bundle-consume.md`
for a worked consume recipe.)

### Motion contract honesty

`motion_adapter` is the **contract gate**: every row it emits passes
`assert_contract` (all 10 keys, `class` ∈ {scroll,time}, `cubic_bezier` is a
4-float list, `window` is 2 elements, numerics are numeric). It accepts BOTH
flipbook payload shapes — the web/native CLI wrapper `{"selector", "recovery":
{"channels"}}` AND the raw `recover_from_video` dict `{"channels"}` — so motion
from **all four target classes** (web/iOS/Android/Flutter) flows into one
`motion.json`. `motion_summary` (on every verb payload) lifts the best per-axis
reading into one consistent `{klass, channels}` block for a direct consumer that
won't parse the raw shapes.

**Native flipbook parity.** `ios_flipbook` (iOS), `adb_flipbook` (Android), and `flutter_flipbook` (Flutter; `--target adb|ios`) all recover time/event motion from a screen recording via the shared `_native_flipbook.recover_from_video`, each with a target-specific displacement oracle: idb frames (iOS), uiautomator bounds in **device px** (Android — no dpr derivation needed, structurally simpler than iOS), and Flutter VM `getTransformTo` (Flutter, both targets). For a mover that is not an introspection element, pass `--auto --tap-xy`.

**Multi-element entrance probe (`ios_entrance`).** The flipbook verbs are single-element + tap-triggered + translation-keyed, so on a **launch/route-triggered staggered entrance cascade** (many elements appearing together, opacity-fade + small translate) they recover `(0,0)` = "no motion" — the wrong signal there is per-element **luminance onset**, not template translation. `ios_entrance` records one cold-launch/route entrance and, for each tracked element (idb AX frames → device-px regions, or `--regions`), emits coarse per-element facts `{label, kind: fade|pop|none, onset_s, settle_s, lum_delta, present}` — the motion **family** (fade vs pop vs instant), onset **order**, and **band**. Observation-only: it asserts nothing about easing/delay (sim framebuffer noise + opacity-dominance preclude that); the **consumer** compares these facts against an emitted contract. `--self-test` verifies the classifier offline.

**Pixel diff (`pixdiff`) — three metrics, SSIM default.** `pixdiff a.png b.png --engine mean|ssim|odiff`. All three are normalised so **0 = identical** and `above_threshold = score > T` reads identically:
- `ssim` (**default**) — pure-numpy windowed Structural Similarity (`1 - meanSSIM`). Materially more robust to anti-aliasing / sub-pixel font-rendering false positives than raw pixel diff, because it compares local *structure* not raw pixels. No new heavy dep (numpy via `_flipbook`).
- `mean` — mean per-channel RGB / 255 (the original pixdiff score; back-compat).
- `odiff` — SIMD-fast Rust binary (shell-out, opt-in). Built-in `--odiff-antialiasing`. **Strictly opt-in, never auto-detected**: odiff is a 3rd-party binary not installed by default, and its algorithm differs numerically (odiff ~1.07% where pixelmatch ~0.75%), so auto-detecting it on PATH would make the *same command give different scores across machines* — unacceptable for a certification tool whose invariant is reproducibility. Every `pixdiff` output emits `engine` + `metric` so a run is never ambiguous about which engine produced it.

**Vision framework (`vision_probe`) — detectors beyond OCR.** Generalises `ocr.py`'s proven PyObjC/Vision pattern to `--kind face|body|rect|barcode|saliency|text`. macOS-only (Vision framework); `text` reuses `ocr._vision_text` (no dup). Emits `{kind, count, detections:[{bbox (normalised, bottom-left y-up), confidence, ...}]}`. Barcode detections carry `payload` + `symbology`. Use cases: face/body detection ("is a person/avatar present"), QR/barcode for fixtures, rectangle detection for widget-bbox cross-check, saliency for "what draws the eye".

**Apple framework leverage.** ScreenCaptureKit (macOS 12.3+) is the low-latency, zero-copy GPU capture path — `shot` prefers it when `pyobjc-framework-ScreenCaptureKit` is installed (lazy import; falls back to the legacy `screencapture` CLI). Vision (`vision_probe`) adds face/body/barcode/saliency/text detection on-device. All optional — probe-runner runs without them, degraded only in speed/fidelity, never in correctness.

## Output convention

All artefacts land under `${PROBE_RUNNER_OUTDIR:-/tmp/probe-runner}/`:

- Stills: `<target>-<ts>.png`
- Video: `<target>-<ts>.mov` (or `.mp4` for ffmpeg / adb / simctl paths)
- Trees / probes: `<target>-<ts>-<kind>.json`
- Logs: `<target>-<ts>.log`

`<ts>` is `YYYYmmdd-HHMMSS`.

## Required tooling (host)

- `python3` (macOS system Python 3 — ships with `pyobjc-framework-Quartz`).
- `cliclick` (`brew install cliclick`).
- `screencapture(1)` — bundled with macOS.
- `osascript(1)` — bundled with macOS.
- Optional / per-block:
  - `ffmpeg` for lossless video (`brew install ffmpeg`).
  - `fswatch` for `fswatch.py` filesystem-event probe (`brew install fswatch`).
  - `pyobjc-framework-Vision` for OCR + `vision_probe` (`pip3 install pyobjc-framework-Vision`).
  - `pyobjc-framework-ScreenCaptureKit` for low-latency GPU capture (`pip3 install pyobjc-framework-ScreenCaptureKit`; macOS 12.3+; `shot` falls back to the `screencapture` CLI without it).
  - `odiff` for the SIMD-fast pixel-diff engine (`pixdiff --engine odiff`; `npm i -g odiff-bin` or a release binary from https://github.com/dmtrKovalenko/odiff). Strictly opt-in.
  - `Google Chrome.app` for web block (`brew install --cask google-chrome`).
  - `safaridriver` (run `safaridriver --enable` once) for Safari fallback.
  - `xcrun` (Xcode CLI tools: `xcode-select --install`) for iOS sim.
  - `fb-idb` for richer iOS UI ops (`brew install idb-companion && pipx install fb-idb`).
  - `adb` (`brew install android-platform-tools`) for Android emu. Also export `ANDROID_HOME=$HOME/Library/Android/sdk` (or `ANDROID_SDK_ROOT`) and prepend `$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator` to PATH so `adb_boot.py` can find the `emulator` binary and child processes inherit the SDK location.
  - `websocket-client` Python package for Flutter VM service (`pip3 install websocket-client`).
  - `selenium` for safaridriver path (`pip3 install selenium`).

### Flutter prerequisites

- Launch the app with `flutter run --debug` (release builds drop the VM service).
- Prefer `flutter run --disable-service-auth-codes` for the simplest attach path — without it, `flutter run` prints URLs with an auth-code suffix (`http://host:port/<TOKEN>=/`) that some loggers/regexes strip, causing a 403 on the WebSocket handshake. `flutter_attach.py` and `_flutter.parse_url_from_text` preserve the suffix when present; the flag just avoids the issue entirely.
- **Cold-launch does NOT expose the VM service.** Building then launching the artifact directly — `flutter build ios --debug --simulator` + `simctl launch`, or `flutter build apk` + `adb install` + `am start` — produces an app with NO VM service URL advertised (DDS isn't started without `flutter run`'s runner). The app runs and is fully interactive, but `flutter_attach`, `flutter_inspect`, `flutter_set_text`, `color_assert --locate` ALL fail with "Connection refused" because there's nothing to attach to. To drive the app (set text, locate widgets, sample colours), you MUST launch via `flutter run --disable-service-auth-codes` and capture the VM URL from its stdout (`flutter_attach.py --tail <log>` or `--auto --source ios|adb`). Capture the URL ONCE per launch; if `flutter run` restarts (hot restart, crash) the port changes and you must re-cache it.
- Per-target URL discovery:
  - **iOS sim** — `flutter_attach.py --auto --source ios` (reads `idb log`).
  - **Android emu** — `flutter_attach.py --auto --source adb` (reads `adb logcat -T 1`).
  - **macOS desktop / Chrome web** — no `idb`/`adb` stream. Either redirect `flutter run` to a log file and use `flutter_attach.py --tail <log-file>`, or pipe stdout into `flutter_attach.py --auto --source host` (alias for `stdin`).
- `flutter_tap.py` synthesises taps only on `--target ios|adb`. For `macos`/`web` the inspector RPC doesn't expose transform-to-root; the script exits rc=2 with a fallback hint (semantics tree + host/web click).
- **Driving text fields — use `flutter_set_text`, NOT `adb_type`/`ios_type`.** OS-level text injection (`adb shell input text`, `idb ui text`) injects into the IME and does NOT fire Flutter's `onChanged`, so a form's validity gate (a submit button disabled until the email regex passes) never enables during automated driving — a working feature looks broken. `flutter_set_text` routes the value through `EditableTextState.updateEditingValue(TextEditingValue(...))` over the VM eval channel (the technique marionette_flutter uses), firing the field's full input pipeline — formatters, validation, AND `onChanged` — exactly like a real keystroke. Locate by `--type` (EditableText / TextField / CupertinoTextField / a wrapper like AdaptiveTextField), `--key`, or `--focused` (the currently-focused field). No package dep — the types are in `package:flutter`.
- **Fast verify — `flutter_inspect`.** One command: screenshot + filtered widget subtree (label/type/key/rect/enabled) + optional `--golden` pixdiff (SSIM) + auto-flagged off-screen/disabled nodes. The compact snapshot an agent reasons over instead of eyeballing pixel math. `flutter_inspect.py --target ios --type AdaptiveButton,Text --golden baseline.png`.
- **VM eval gotchas (fixed).** `_flutter.ev` collapses literal newlines to spaces before sending (the VM `evaluate` RPC mis-tokenizes newlines — dart-lang/sdk#41671 — so a multi-line closure failed to compile), and follows the `valueAsStringIsTruncated` flag to fetch the full value via `getObject` (large results are truncated to ~128 chars). So multi-line closures (skeleton walks, tree-search) and large string returns both work. Eval runs against the root library, so Flutter type symbols (Element, RenderBox, EditableTextState, Offset) resolve; private cross-library fields (`_viewModel`) do not.

### Design-vs-built colour fidelity loop

Pixel-fidelity bugs (button colour wrong, icon tint wrong, chevron size wrong) are invisible to functional tests and unreliable under eyeballing. Two probes close the loop — **`design_golden`** renders the design's own HTML bundle to a golden PNG, **`color_assert`** measures a region of any screenshot and asserts it matches a target hex within a perceptual tolerance.

- **`design_golden.py` — render the design's ground truth.** Loads a design HTML bundle (React+Babel or static) in Chrome via CDP at a device viewport + DPR, drives it to a requested state, and screenshots a CSS-selector region (or the full page). `--drive 'selector=value'` sets an input via the React-aware setter (the native `.value=` won't fire `onChange`; this reaches the prototype descriptor and dispatches `input`/`change`, the react-testing-library technique) so a `:disabled`-conditional element can be captured in BOTH states — the gap a single-state capture leaves. `--click 'selector'` clicks first. Emits the PNG + the selector's CSS-px and device-px rect. `design_golden.py bundle.html --selector '.auth-btn.primary' --out enabled.png --drive '.auth-input=test@example.com'`.
- **`color_assert.py` — measure + assert colour.** Samples the mean RGB of a region of a screenshot (optionally `--inset N` to dodge border anti-alias / rounded corners), converts to Lab, and computes the CIEDE2000 ΔE against a target hex (the perceptually-uniform metric design tools use — ~1 = just-noticeable, ~5 = clearly different). `--tolerance` (default 5.0) gates pass/fail; rc=0 on pass, rc=2 on fail (the die convention, so a CI gate chains it). Resolve the region either with `--rect X,Y,W,H` on an `--image`, or `--locate 'type=AdaptiveButton,text=Send code'` to find the widget's runtime rect via the VM (same `localToGlobal` walk as `flutter_inspect`). `color_assert.py --target ios --locate 'type=AdaptiveButton,text=Send code' --hex D2522B`.
- **The loop.** `design_golden` produces a golden for each state (disabled + enabled, light + dark); `color_assert` then asserts the BUILT app's rendered colour matches the design's golden within ΔE. Proven end-to-end on the Send-code button: the loop caught a real bug (the capture had frozen the disabled-state colour onto both states) AND surfaced token drift (the design's `--accent` is `oklch(60% 0.16 28)` ≈ `#C05A4D`, but `tokens.json` carried a stale `#D2522B` — invisible without measurement). The ΔE implementation is verified against the Sharma et al. CIEDE2000 reference vector (2.0425) — `python3 scripts/test_color_assert.py`.

## Permissions / TCC

Grant once per macOS user account:

- **Screen Recording** — for `screencapture` window/video capture.
- **Accessibility** — for `cliclick` and AX tree reads.
- **Input Monitoring** — for some Quartz event injections.
- **Files & Folders** — only if `drop_file.py` is used on protected dirs.

`scripts/_common.py::tcc_check(scope)` preflights `screen_recording`
(`CGPreflightScreenCaptureAccess`) and `accessibility` (`AXIsProcessTrusted`)
without triggering the system prompt and exits with rc=3 + a grant hint when
denied. Wired into `shot`, `region`, `record`, `multishot`, `click`, `ax_tree`;
other verbs still surface the native error (cryptic but unmistakeable).
Standalone preflight: `/pr-tcc-check` (or
`python3 scripts/tcc_check.py [scope] [--json]`).

## Failure modes the skill detects and reports

- Target app not running → window-id discovery fails.
- Multiple windows with same owner name → `find_window.py --all` lists them; default picks largest by bounds; `--index N` overrides.
- `cliclick` not installed → install hint.
- Chrome not installed → fall back to Safari (web block only).
- `safaridriver` not enabled → instruct `safaridriver --enable`.
- iOS sim not booted → `ios_boot.py` invoked automatically with operator confirmation.
- Android emu not running → `adb_list.py` reports empty; `adb_boot.py` lists AVDs.
- Android emu boot fails silently → `adb_boot.py boot` polls the emulator PID for 3s and surfaces FATAL log lines (e.g. `CPU Architecture 'arm' is not supported`). On Apple Silicon, arm32 AVDs (`abi.type=arm`) are warned about explicitly — use an `arm64-v8a` AVD.
- Android screen locked → `adb shell input tap/swipe/text` events are dispatched but invisible. Send `KEYCODE_WAKEUP` (and `KEYCODE_MENU` if PIN-less) before driving input.
- `adb_push.py` is deprecated → it broadcasts an intent (`am broadcast`) and prints a deprecation notice; new code should call `adb_intent.py`. For file push/pull use `adb_files.py`.
- Flutter app has no VM service port → app likely built in release; instruct `flutter run --debug`.
- Flutter VM service rejects WS handshake with 403 → auth-code suffix on the printed URL (ends in `=/`) was stripped. `flutter_attach.py` preserves it via the `_AUTH_URL_RE` regex; if you cache a URL manually, keep the trailing `=/`. Simplest workaround: launch with `flutter run --disable-service-auth-codes` to drop the token entirely. `_flutter.rpc()` catches `WebSocketBadStatusException` and emits an operator hint.
- `flutter_tap.py --target macos|web` → honest-gap (rc=2). Flutter inspector RPC doesn't expose transform-to-root, so absolute tap coords aren't synthesisable. The JSON output carries a ready-to-run `fallback_commands` sequence (semantics enable → `ax_tree`/`web_dom --selector flt-semantics` → `click`/`web_click`). Mobile (`--target ios|adb`) still returns rc=0 with `matched`+`render_size` for ios_tap/adb_tap dispatch.
- `web_eval --await` is **CDP-only** (Chrome / Android-forwarded / pre-forwarded port): it sets `awaitPromise`. On the Safari/WebDriver fallback `--await` is accepted but evaluation is **synchronous** (WebDriver has no awaitPromise) — a promise-returning expression will NOT be awaited there. Verify the engine before relying on it.
- `pixdiff` `above_threshold` is **strict `>`**, not `≥` — a score equal to `--threshold` reads `false`. Use `--threshold 0` for "any diff at all". `pixdiff` also requires the two inputs to be **equal dimensions** and **same-dpr** capture; cross-dpr/cross-viewport screenshots `die` on size mismatch. For *design* (layout/geometry) certification, prefer `skeleton_diff` (calibrated CSS-px gates) — `pixdiff` is pixel-only and too brittle for layout regression.
- macOS Secure Input mode active → refuse key synthesis with a clear message (detected via `ioreg -l | grep -q kIOHIDStateSecureInput`).

## Conventions for invoking from chat

Owner is a **positional** argument on every script that targets a macOS window
(e.g. `find_window.py Code`, not `--owner Code`). For convenience, `--owner X`
and `--owner=X` are accepted as aliases and rewritten to the positional form
at import time by `_common.py`.

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/<verb>.py <args...>
```

Slash-command shorthand:

```
/pr-shot perf_domain_heavy_100
/pr-record perf_domain_heavy_100 5
/pr-web-open https://example.com
/pr-ios-launch com.example.app
/pr-adb-tap 500 1000
/pr-flutter-tree
```

See `commands/*.md` for full list. Each script also runs standalone for piping into other tooling.

## Read also

- `README.md` — operator-facing install + troubleshooting.
- `templates/dioxus_debug_probe.rs` — drop-in Rust module for Dioxus crates.
- `examples/*.md` — end-to-end smoke recipes.
