/// Test-facing helpers for appbox_kit_branding — deterministic
/// [AppBoxKitBrandSplash]
/// fixtures so widget and golden tests can pin the brand moment at a known
/// progress position without racing a real timer:
///
/// ```dart
/// await tester.pumpWidget(appBoxKitBrandSplashTestApp()); // settled: "Loading · 100%"
/// expect(find.text('Loading · 100%'), findsOneWidget);
/// ```
///
/// The branding kit ships no runtime services (brand colors are codegen'd
/// into the host by `tools/generate_branding.sh`), so there is nothing to
/// fake via the locator — only the splash widget to stage.
library;

import 'package:flutter/material.dart';

import 'src/appbox_kit_startup_view.dart';

export 'src/appbox_kit_startup_view.dart' show AppBoxKitBrandSplash;

/// A stand-in brand mark sized to the kit's canonical logo edge
/// ([AppBoxKitBrandSplash.logoSize]) — the same box the host's real logo
/// occupies, so layout assertions match production.
Widget fakeAppBoxKitBrandMark({Key? key, double size = AppBoxKitBrandSplash.logoSize}) =>
    FlutterLogo(key: key, size: size);

/// A [MaterialApp] wrapping [AppBoxKitBrandSplash], ready to `pumpWidget`.
///
/// Defaults to [Duration.zero], which renders the splash already settled
/// (progress bar full, "Loading · 100%") on the first frame — the
/// deterministic state for goldens. Pass a real [duration] to exercise the
/// animating states (`pump` partial durations to pin the readout).
///
/// [theme] defaults to a light [ThemeData]; pass the host's theme when a test
/// asserts on theme-derived colors (the splash reads `Theme.of(context)`).
Widget appBoxKitBrandSplashTestApp({
  Key? key,
  Duration duration = Duration.zero,
  Widget? brand,
  String? caption,
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: theme ?? ThemeData.light(),
    home: AppBoxKitBrandSplash(
      key: key,
      duration: duration,
      brand: brand ?? fakeAppBoxKitBrandMark(),
      caption: caption,
    ),
  );
}
