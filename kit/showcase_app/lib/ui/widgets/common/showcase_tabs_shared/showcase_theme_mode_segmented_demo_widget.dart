/// A widget is a reusable UI building block: props in via the constructor,
/// widgets out via `build`. It never owns business logic.
///
/// This is the user interface for the theme-mode demo — a native segmented
/// control that drives the kit theme service and a swatch that repaints the
/// instant a segment is tapped.
///
/// Requirements:
/// 1. [Theme demo] — profile-and-gallery-demos.gallery.browse-the-components-gallery
/// Drives the kit theme mode via a native segmented control with a live swatch.
///
/// Relationships:
///
///       ┌──────────────────────────────────┐
///       │ theme mode segmented demo widget │
///       └──────────────────────────────────┘
///            ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/common/showcase_tabs_shared/showcase_theme_mode_segmented_demo_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseThemeModeSegmentedDemoWidget extends StatelessWidget {
  const ShowcaseThemeModeSegmentedDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = appBoxKitLocator<AppBoxKitThemeService>();
    return AppBoxKitStreamBuilder<ThemeMode>(
      stream: theme.themeMode$,
      initialData: theme.themeMode$.value,
      builder: (context, mode) {
        final scheme = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Intrinsic width/height: SegmentedButton sizes to its labels + the
            // 48px tap target, so the active fill is never clipped. No fixed
            // SizedBox (that was what "cut" the rounded active segment).
            AppBoxKitNativeSegmentedControl(
              segments: const ['Auto', 'Light', 'Dark'],
              selectedIndex: mode.index,
              onChanged: (i) => theme.setTheme(ThemeMode.values[i]),
            ),
            appBoxKitVerticalSpaceXSmall,
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: abxSize16, vertical: abxSize10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(abxRad10),
              ),
              child: Text(
                'theme: ${mode.name}',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
