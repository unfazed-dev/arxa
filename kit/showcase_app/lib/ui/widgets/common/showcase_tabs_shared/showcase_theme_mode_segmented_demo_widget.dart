import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Drives [AppBoxKitThemeService]'s theme mode via a native segmented control and
/// proves the kit theme is live: the swatch reads the *active*
/// `Theme.of(context).colorScheme` (not static `AppBoxKitColors`), so it repaints the
/// instant a segment is tapped — `main.dart` rebuilds `MaterialApp` on
/// `themeMode$`. `ThemeMode.values` is `[system, light, dark]`, so the segment
/// index maps 1:1 to the mode.
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
                  horizontal: axSize16, vertical: axSize10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(axRad10),
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
