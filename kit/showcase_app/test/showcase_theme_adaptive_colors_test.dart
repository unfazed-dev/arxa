// Regression guard for the theme-flip colour leaks in the 08-11 21:25 device
// clip: after switching to dark, every uppercase section label ("RADIUS",
// "PRICE RANGE", "NAVIGATION RAIL", …) stayed in the light-ramp `muted`
// constant and went near-invisible on the dark background, and the gallery
// icon rows forwarded the same fixed light-ramp constants as the native
// glyph/tint colours.
//
// Both widgets must resolve their colours from the active theme so a flip
// re-reads them, like every other Flutter-painted surface does.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/showcase_section_label_widget.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_home_widgets/showcase_snackbar_smoke_row_widget.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_ui_library/arxa_kit_testing.dart';

void main() {
  setUp(() {
    // Android tier override (repo pattern): no platform views headless. The
    // assertions target the colours the showcase widgets choose and forward,
    // which are tier-independent.
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    if (!arxaKitLocator.isRegistered<ArxaKitNotificationService>()) {
      arxaKitLocator.registerLazySingleton<ArxaKitNotificationService>(
          () => FakeArxaKitNotificationService());
    }
  });

  tearDown(ArxaKitPlatform.reset);

  final light = arxaKitLightTheme();
  final dark = arxaKitDarkTheme();

  testWidgets(
      'profile-and-gallery-demos.gallery.browse-the-components-gallery — '
      'section labels take their colour from the active theme, staying '
      'legible across a theme flip', (tester) async {
    Future<Text> pumpFor(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        // Instant flip, same as the showcase app root: without it the second
        // pumpWidget leaves AnimatedTheme at t=0 and the "dark" pump reads
        // the LIGHT scheme — the harness re-creates the very desync this
        // test guards against.
        themeAnimationDuration: Duration.zero,
        home: const Scaffold(
            body: ShowcaseSectionLabelWidget('Progress & Loading')),
      ));
      return tester.widget<Text>(find.text('PROGRESS & LOADING'));
    }

    final inLight = await pumpFor(light);
    final inDark = await pumpFor(dark);

    expect(inLight.style?.color, light.colorScheme.onSurfaceVariant);
    expect(inDark.style?.color, dark.colorScheme.onSurfaceVariant);
    // Anti-vacuous: the two themes must actually disagree here, or the
    // assertions above prove nothing about adaptivity.
    expect(light.colorScheme.onSurfaceVariant,
        isNot(dark.colorScheme.onSurfaceVariant));
  });

  testWidgets(
      'profile-and-gallery-demos.gallery.browse-the-components-gallery — '
      'gallery icon rows resolve semantic colours from the active theme '
      'instead of the fixed light ramp', (tester) async {
    Future<List<Color?>> pumpFor(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero, // see above
        home: const Scaffold(body: ShowcaseSnackbarSmokeRowWidget()),
      ));
      return tester
          .widgetList<ArxaKitNativeIconButton>(
              find.byType(ArxaKitNativeIconButton))
          .map((button) => button.color)
          .toList();
    }

    expect(await pumpFor(light), [
      ArxaKitColors.muted,
      ArxaKitColors.good,
      ArxaKitColors.danger,
      ArxaKitColors.warn,
      ArxaKitColors.muted,
      ArxaKitColors.danger,
      ArxaKitColors.muted,
    ]);
    expect(await pumpFor(dark), [
      ArxaKitDarkColors.ink3,
      ArxaKitDarkColors.good,
      ArxaKitDarkColors.danger,
      ArxaKitDarkColors.warn,
      ArxaKitDarkColors.ink3,
      ArxaKitDarkColors.danger,
      ArxaKitDarkColors.ink3,
    ]);
  });
}
