# Embedding a live iOS Simulator / Android emulator in the appbox canvas

Reading-research digest (2026-07-29), with local measurements where marked
**[measured]** — taken on this machine: macOS 26.5 arm64, Xcode 26.5-era
simctl, iOS 26.5 sim runtime, Android emulator 36.5.11.0.

**Verdict.** Literal embedding — putting Simulator.app's or the emulator's
window *inside* the appbox window — is not possible on either platform.
macOS has no supported cross-process NSWindow embedding; there is no Apple
"embed the simulator" API. Every working approach is **capture → re-display
in our own Flutter surface → inject input back**. The platforms differ
sharply in how good the capture path is: Android has a first-party
streaming gRPC API; iOS has screenshots (headless-friendly) and window
capture (windowed-only), and no official input injection at all.

## 1. iOS Simulator on macOS

What `simctl io` actually offers (`xcrun simctl help io`, run locally):

- `screenshot [--type=png|jpeg|tiff|bmp|gif] [--display=…] [--mask=…] <file|url>`
- `recordVideo [--codec=h264|hevc] <file>` — writes a QuickTime movie to a
  **file**, finalized on SIGINT. No frame streaming; useless for a live
  canvas, fine for demo clips.
- No input-injection operation exists anywhere in simctl (42 subcommands
  in `xcrun simctl help`; the only HID-ish verbs are `pbcopy`/`status_bar`).

**[measured]** Headless operation works end to end:

- `simctl create` + `simctl boot` + `simctl bootstatus -b` booted an
  iPhone 17 Pro / iOS 26.5 sim in ~26s with **Simulator.app not running**,
  and screenshots captured fine. So a windowless sim is a real option.
- 10 sequential PNG screenshots: 2.64s total → ~260ms/shot; a single
  JPEG shot: ~240ms. The CLI poll ceiling is ~3–4 fps (process spawn
  dominates), plenty for a "live-ish" canvas, not for video.
- **Gotcha:** the documented `screenshot -` (write to stdout) is broken in
  this Xcode build — simctl treats `-` as a literal filename and fails
  with NSCocoaErrorDomain 513 / EPERM. Use a real file path and read it.

Live capture of a *windowed* sim: **ScreenCaptureKit** (macOS 12.3+)
captures individual windows/apps at 60fps+ with low CPU (a Rust binding
benchmarks full-screen 60fps at ~1.9% of one core). It requires the user
to grant Screen Recording permission (TCC) and requires Simulator.app to
be visible — there is no window to capture when headless.
Sources: https://developer.apple.com/videos/play/wwdc2022/10156/ ,
https://github.com/doom-fish/screencapturekit-rs

Input injection (no official path):

- `idb ui tap X Y` (Facebook's idb) injects HID events into simulators via
  the **private** CoreSimulator framework. Works headless, ~100ms/action,
  but Apple can break it any Xcode release.
  https://fbidb.io/docs/commands/ , https://fbidb.io/docs/fbsimulatorcontrol/
- Heavier alternative: WebDriverAgent/XCTest. Not worth it for a canvas.

## 2. Android emulator

Confirmed locally (`emulator -help`, v36.5.11.0): `-no-window`,
`-grpc <port>` ("TCP ports used for the gRPC bridge"), `-grpc-use-jwt`
(default; `-grpc-use-token` for console-token auth), `-grpc-ui`
(experimental), `-idle-grpc-timeout`.

The gRPC API (`EmulatorController`, experimental, "might change without
notice") is the same one Android Studio's Running Devices tool window and
Google's container streaming use:

- `streamScreenshot(ImageFormat) → stream Image` — server-streamed frames
  on every new device frame; PNG encoding noted as CPU-intensive; optional
  MMAP shared-memory transport. Plus one-shot `getScreenshot`.
- `sendTouch`, `sendMouse`, `sendKey`, `streamInputEvent` — full input
  injection on the **same channel**.
- `streamLogcat`, `getStatus`, display/posture control, etc.
Source: https://github.com/google/android-emulator-webrtc/blob/master/proto/emulator_controller.proto

Official headless+streaming prior art: google/android-emulator-container-scripts
runs the emulator in Docker and streams to a browser via the emulator's
native `android.emulation.control.v2.Rtc` gRPC → WebRTC; it documents
macOS discovery files (`~/Library/Android/avd/running/pid_*.ini`), gRPC
port 8554. https://github.com/google/android-emulator-container-scripts

scrcpy (Apache 2.0) is the latency benchmark: 30–120fps, 1080p+,
**35–70ms** latency, ~1s to first frame, with keyboard/mouse injection via
adb shell permissions. Prior art, not a library — consuming it means
decoding H.264/H.265 ourselves. https://github.com/Genymobile/scrcpy

adb fallbacks (documented at https://developer.android.com/tools/adb):
`adb exec-out screencap -p` (binary-clean PNG stream), `adb shell input
tap|swipe|text|keyevent`, `adb shell screenrecord` (mp4, 3-minute cap).

## 3. Flutter-side options

- `package:grpc` (Dart-native, works in Flutter) can consume the emulator
  gRPC API directly — **no native code needed for Android**. Decode frames
  in Dart (`Image.memory`) or push raw frames into a `Texture`.
  https://pub.dev/packages/grpc
- `device_preview` renders *the app it is compiled into* inside device
  frames on any platform, macOS included — a "first-order approximation".
  It cannot show a separately-built artifact, so it does not answer
  "show the scaffolded app running".
  https://pub.dev/packages/device_preview
- macOS platform views (`AppKitView`, hybrid composition) exist in current
  Flutter; issue flutter/flutter#41722 is still open but gesture support
  is now checked off. For a video stream, a `FlutterTexture` fed
  CVPixelBuffers from a Swift platform channel is the mature route.
  https://docs.flutter.dev/platform-integration/macos/platform-views ,
  https://github.com/flutter/flutter/issues/41722

## 4. Interaction (click/key forwarding), easy → hard

| mechanism | platform | effort | notes |
|---|---|---|---|
| gRPC `sendTouch/sendMouse/sendKey` | Android emu | trivial | same channel as the video stream |
| `adb shell input …` | Android | trivial | ~50–150ms/event process spawn; taps fine, drags laggy |
| scrcpy protocol | Android | medium | best latency; own server jar + H.264 decode |
| idb (`idb ui tap`) | iOS sim | medium | private CoreSimulator APIs; brew install; breakage risk per Xcode |
| WDA / XCTest | iOS sim | high | not justified for a canvas |

## 5. Recommendation

**v1 (lazy, honest): device chrome + polling screenshots.** Draw the bezel
in Flutter; behind it, show the freshest frame:

- iOS: boot a sim headless (`simctl boot`, no Simulator.app), loop
  `simctl io <udid> screenshot --type=jpeg /tmp/x.jpg` every ~300ms
  (**[measured]** ~240ms/shot → 2–4fps). Read-only, zero permissions,
  zero native code.
- Android: launch emulator (windowed or `-no-window`), loop
  `adb exec-out screencap -p`. Same effort.
- Cost: ~1 day. It is *not* a video stream and shouldn't be sold as one —
  label it "preview refreshing".

**v1.5: interactive Android via gRPC.** `streamScreenshot` +
`sendTouch/sendMouse/sendKey` over `package:grpc`, all Dart. Mind the auth
flags (`-grpc-use-token`, token in `~/.emulator_console_auth_token`).
Cost: ~2–3 days. This is the best effort-to-wow ratio in the whole matrix.

**v2: live iOS.** Run Simulator.app windowed, capture its window with
ScreenCaptureKit in a small Swift plugin, push frames into a
FlutterTexture (30–60fps), inject input with idb. Cost: ~3–5 days of
Swift + a Screen Recording permission prompt + permanent brittleness of
private-API input injection. No headless variant exists for live iOS
frames — that is Apple's constraint, not ours.

Explicitly rejected: `simctl io recordVideo` (file-only, not streamable),
scrcpy integration (H.264 decode pipeline for marginal gain over gRPC),
device_preview for the built artifact (wrong tool — it previews compiled-in
code only).
