# device_input_probe — real-touch verification for the native input stack

Verifies `AppBoxKitNativeInputBar` / `AppBoxKitNativeTextField` behavior with
**real touches on real platform views** — the one thing `flutter test` and the
`integration_test` harness structurally cannot do.

## Why this exists (measured, 2026-08)

The `integration_test` harness does **not** deliver real touches to platform
views: synthetic tester pointers never become UITouches, and idb HID taps are
dropped there too, while the same code in a plain app focuses fine (verified by
binary search: bare CN field → TapRegion-wrapped → kit widget → full bar all
worked in a plain app, none in the harness). Device verification therefore
runs this plain app and drives it from the host.

## The protocol

A file-exchange handshake, phase by phase (see `lib/main.dart`):

1. App writes `<tmp>/phase<N>.done` containing a payload describing what the
   host should do — `ok`, `tap:x,y`, `long:x,y`, or `drag`. Coordinates are
   in the **host's unit**: points on iOS, pixels on Android (devicePixelRatio).
2. Host performs the gesture, takes a screenshot, writes `phase<N>.go`.
3. App measures and appends a `P<N> …` line to `<tmp>/composer.log`
   (also debugPrinted with the `COMPOSER` tag — followable via logcat).

Phases: P1 rest height · P2 focus+insets+firstFocusShrink (focus **polled**,
not sampled — the original single-sample read raced the notification) · P3
re-tap keeps focus (the original bug) · P4 outside-tap dismisses · P5 re-focus
(+ P5b IME typing on Android) · P6 grow multiline · P7 shrink · P8 long-press
selection menu · P9 drag dismisses · P10 second native field (per-field focus;
two native glass surfaces at once on iOS) · **P11a/11b re-focus then tap the
bar's add action — focus must SURVIVE the action tap** (the 2026-08-16
action-tap dismissal regression; on Android 11a dismisses first so the IME-up
check can't pass vacuously on the previous field's focus).

Focus truth is per tier: the iOS CN tier owns first responder inside the
platform view (`CNTextFieldFocus`), the Material/M3E tier lives in Flutter's
focus tree (checked by render-tree containment, which distinguishes fields).

## Running it

### Android (emulator or device)

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell settings put secure show_ime_with_hard_keyboard 1  # emulator only
adb shell monkey -p dev.appbox.device_input_probe -c android.intent.category.LAUNCHER 1
./android_choreo.sh emulator-5554 /tmp/probe_android_shots
```

Screenshots land in the shots dir; the final composer.log is printed and copied
there. `adb input` gestures are real touches in **pixels**; the phase-file
channel runs through `adb shell run-as` (debug builds only). NOTE: Dart's
`Directory.systemTemp` resolves to the app's **`code_cache/`** dir on Android
(the engine sets TMPDIR there), NOT `cache/` — phase files live at
`code_cache/phase<N>.{done,go}`.

### iOS (simulator)

```bash
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted dev.appbox.deviceInputProbe
./ios_choreo.sh <UDID>   # defaults: booted GlassDebug sim, this bundle id
```

Taps go through `idb ui tap` in **points**; composer-field taps aim at the AX
`TextField` frame from `idb ui describe-all` because the bar's padded center
can miss the field. Phase files exchange through the simulator app container.

## Known limitations & measured instrument facts

- No iOS text injection: P5b IME typing is Android-only (iOS logs a skip).
- The harness limitation itself is documented in
  `kit/showcase_app/integration_test/input_composer_device_test.dart`, kept as
  the runnable record of what the harness cannot do.
- **Emulator input delivery is flaky** (the AVD used here hard-rebooted twice
  mid-session and can silently drop taps). Every load-bearing Android gesture
  is retried until its OBSERVED effect holds (keyboard shown/hidden via
  `dumpsys input_method`) — same posture as the iOS idb retry loop. A dropped
  tap must never log a vacuous pass.
- **The app-emitted whole-bar Builder center is a HINT, not a target, on
  Android**: at rest it measures ~16dp below the field's tappable center
  (transient first layout: 162dp rest vs 90dp settled), and with the keyboard
  up it lands ON the keyboard (the bar's internal keyboard-riding padding is
  inside the measured box). The choreography therefore sweeps verified
  candidates around the hint and reuses the last verified y for long-press.
  iOS aims composer taps at the AX `TextField` frame instead, which is why it
  never hits this.
- Height numbers are per-platform instruments: iOS reports honest content
  height (the `heightChanged` channel drives the slot); Android's Builder
  slot keeps the grown height after text clears (measured 166dp after shrink)
  — shrink is verified by screenshot there, not by the number.
