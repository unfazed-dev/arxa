import 'package:flutter/material.dart';

/// Presentational splash / startup view: a centered [brand] mark, an optional
/// uppercase [caption] tagline, and a bottom progress bar that animates 0→100%
/// over [duration] with a "Loading · N%" readout.
///
/// Purely visual — it owns NO routing and NO auth logic. The host's startup
/// view-model drives timing (races a real bootstrap [Future] against
/// [duration]) and decides the next route (auth shell vs app shell); it renders
/// this widget while it waits, then replaces it via the router.
///
/// [duration] MUST match the host view-model's splash floor so the bar reaches
/// 100% as the brand moment ends. Mirrors the reference app's splash layout
/// (logo center, bottom progress) adapted to the host theme.
class ArxaKitBrandSplash extends StatelessWidget {
  /// Canonical brand-logo edge in dp (in-Flutter). SSOT for the logo size across
  /// the pipeline: the host binds its logo `Image.asset` width/height to this,
  /// and `tools/generate_branding.sh` rasterizes the native-splash PNG at 4× this
  /// (`SPLASH_PX`) so the pre-Flutter OS splash shows the logo at the same dp.
  /// Matches the reference app (`logoSize: 80`). Android 12+ sizes its splash
  /// logo by the logo's fraction of a fixed ~240dp icon window, so
  /// `generate_branding.sh` pads a small logo into a 960px canvas
  /// (`splash_logo_android12.png`) to hit the same on-screen size as iOS.
  static const double logoSize = 80;

  const ArxaKitBrandSplash({
    super.key,
    required this.duration,
    required this.brand,
    this.caption,
  });

  /// Brand-moment floor. Keep in sync with the host view-model's splash delay.
  final Duration duration;

  /// The logo / wordmark widget, centered.
  final Widget brand;

  /// Optional uppercase tagline beneath the brand (e.g. "move everyday").
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ponytail: derive muted from the host colorScheme (alpha-blend) so no extra
    // palette surface is needed; upgrade to a dedicated theme extension if a
    // host needs a bespoke muted token.
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            brand,
            if (caption != null) ...[
              const SizedBox(height: 14),
              Text(
                caption!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  letterSpacing: 2.8,
                ),
              ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: duration,
                builder: (context, v, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: v),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Loading · ${(v * 100).round()}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
