import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Height the floating [KitNativeTabBar] occupies above the system safe area
/// (M3E "small" bar = 64dp; the iOS Liquid Glass pill measures ~61pt plus its
/// float margin). The host shell's `extendBody` lets tab content slide under
/// the bar, so scrollable tab bodies add `MediaQuery.paddingOf(context)
/// .bottom + kShowcaseTabBarBlockHeight` of trailing clearance — without it
/// the last row lays out unreachable beneath the bar.
const double kShowcaseTabBarBlockHeight = 64.0;

/// Section header used across the showcase tabs.
class ShowcaseSectionLabel extends StatelessWidget {
  const ShowcaseSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: KitColors.muted,
        ),
      );
}

/// Small live-value pill shown beside a slider label so the current value is
/// visible while dragging. Tabular figures keep the digits from jittering.
class ShowcaseValueChip extends StatelessWidget {
  const ShowcaseValueChip(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kRad10),
      ),
      child: Text(
        value,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Drives [KitThemeService]'s theme mode via a native segmented control and
/// proves the kit theme is live: the swatch reads the *active*
/// `Theme.of(context).colorScheme` (not static `KitColors`), so it repaints the
/// instant a segment is tapped — `main.dart` rebuilds `MaterialApp` on
/// `themeMode$`. `ThemeMode.values` is `[system, light, dark]`, so the segment
/// index maps 1:1 to the mode.
class ShowcaseThemeModeSegmentedDemo extends StatelessWidget {
  const ShowcaseThemeModeSegmentedDemo({super.key});

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
