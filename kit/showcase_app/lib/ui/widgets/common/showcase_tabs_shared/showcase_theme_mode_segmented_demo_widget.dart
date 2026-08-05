import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Drives [KitThemeService]'s theme mode via a native segmented control and
/// proves the kit theme is live: the swatch reads the *active*
/// `Theme.of(context).colorScheme` (not static `KitColors`), so it repaints the
/// instant a segment is tapped — `main.dart` rebuilds `MaterialApp` on
/// `themeMode$`. `ThemeMode.values` is `[system, light, dark]`, so the segment
/// index maps 1:1 to the mode.
class ShowcaseThemeModeSegmentedDemoWidget extends StatelessWidget {
  const ShowcaseThemeModeSegmentedDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = locator<KitThemeService>();
    return KitStreamBuilder<ThemeMode>(
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
            KitNativeSegmentedControl(
              segments: const ['Auto', 'Light', 'Dark'],
              selectedIndex: mode.index,
              onChanged: (i) => theme.setTheme(ThemeMode.values[i]),
            ),
            verticalSpaceXSmall,
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: kSize16, vertical: kSize10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(kRad10),
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
