# appbox_kit_haptics

Device haptic feedback for Stacked apps. Phase 2B extraction from `appbox_kit`
core — a standalone capability kit with **no dependency on appbox_kit**.

## Scope

- Reactive `AppBoxKitHapticService` wrapping the [`haptic_feedback`](https://pub.dev/packages/haptic_feedback)
  package: RxDart state streams, `SharedPreferences`-persisted enable flag, and
  device-capability (`canVibrate`) checking.
- `AppBoxKitHapticExtension` — one-liner widget wrapping:
  `myWidget.withHapticFeedback()`, `.withSuccessHaptic()`, `.withSelectionHaptic()`, etc.
- `FakeAppBoxKitHapticService` (in `package:appbox_kit_haptics/appbox_kit_testing.dart`) for tests:
  records invocations, and simulates unsupported-device and platform-failure states.

## Non-goals

- No UI components, theming, or navigation — those live in `appbox_kit` core.
- No dependency back on `appbox_kit` core, `stacked_services`, or a host app's
  `app.locator.dart`. The extension resolves the service through the shared
  `StackedLocator.instance`, so it stays portable across Stacked apps.
- Not a general vibration/notification-sound library — device haptics only.

## Usage

```dart
import 'package:appbox_kit_haptics/appbox_kit_haptics.dart';

// 1. Register in your app (Stacked @StackedApp dependencies or setupLocator):
//    LazySingleton(classType: AppBoxKitHapticService)

// 2. Drive it from a view model:
final haptics = appBoxKitLocator<AppBoxKitHapticService>();
await haptics.initialize();          // reads canVibrate + persisted enable state
await haptics.triggerSuccessHaptic();

// 3. Or wrap any widget:
MyButton().withSelectionHaptic(onTap: _onTap);
```

## Testing

```dart
import 'package:appbox_kit_haptics/appbox_kit_testing.dart';

final fake = FakeAppBoxKitHapticService(canVibrate: false); // unsupported device
locator.registerSingleton<AppBoxKitHapticService>(fake);
// ... exercise UI ...
expect(fake.triggeredHaptics, isEmpty); // no-op on unsupported device
```

## Dependency direction

`appbox_kit_haptics` never imports `appbox_kit`. The allowed direction is the
reverse: `appbox_kit` core (or any app) may take a path dependency on this kit.
