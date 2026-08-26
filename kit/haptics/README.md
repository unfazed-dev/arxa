# arxa_kit_haptics

Device haptic feedback for Stacked apps. Phase 2B extraction from `arxa_kit`
core — a standalone capability kit with **no dependency on arxa_kit**.

## Scope

- Reactive `ArxaKitHapticService` wrapping the [`haptic_feedback`](https://pub.dev/packages/haptic_feedback)
  package: RxDart state streams, `SharedPreferences`-persisted enable flag, and
  device-capability (`canVibrate`) checking.
- `ArxaKitHapticExtension` — one-liner widget wrapping:
  `myWidget.withHapticFeedback()`, `.withSuccessHaptic()`, `.withSelectionHaptic()`, etc.
- `FakeArxaKitHapticService` (in `package:arxa_kit_haptics/arxa_kit_testing.dart`) for tests:
  records invocations, and simulates unsupported-device and platform-failure states.

## Non-goals

- No UI components, theming, or navigation — those live in `arxa_kit` core.
- No dependency back on `arxa_kit` core, `stacked_services`, or a host app's
  `app.locator.dart`. The extension resolves the service through the shared
  `StackedLocator.instance`, so it stays portable across Stacked apps.
- Not a general vibration/notification-sound library — device haptics only.

## Usage

```dart
import 'package:arxa_kit_haptics/arxa_kit_haptics.dart';

// 1. Register in your app (Stacked @StackedApp dependencies or setupLocator):
//    LazySingleton(classType: ArxaKitHapticService)

// 2. Drive it from a view model:
final haptics = arxaKitLocator<ArxaKitHapticService>();
await haptics.initialize();          // reads canVibrate + persisted enable state
await haptics.triggerSuccessHaptic();

// 3. Or wrap any widget:
MyButton().withSelectionHaptic(onTap: _onTap);
```

## Testing

```dart
import 'package:arxa_kit_haptics/arxa_kit_testing.dart';

final fake = FakeArxaKitHapticService(canVibrate: false); // unsupported device
locator.registerSingleton<ArxaKitHapticService>(fake);
// ... exercise UI ...
expect(fake.triggeredHaptics, isEmpty); // no-op on unsupported device
```

## Dependency direction

`arxa_kit_haptics` never imports `arxa_kit`. The allowed direction is the
reverse: `arxa_kit` core (or any app) may take a path dependency on this kit.
