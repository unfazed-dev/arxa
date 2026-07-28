import 'package:flutter/material.dart';

/// The boot splash, shared by every form factor.
///
/// It is one widget rather than three because a splash has no responsive
/// behaviour to express — the variant files exist for the scaffolder's
/// form-factor contract, not because the pixels differ. Before this, the
/// desktop and tablet variants shipped `stacked create` boilerplate ("Hello,
/// DESKTOP UI - ShowcaseStartupView!") and the mobile one read "KIT SHOWCASE",
/// all three inherited from the fork in plan 8.1.
class StartupSplash extends StatelessWidget {
  const StartupSplash({super.key});

  /// Matches the native splash logo so there is no jump when Flutter takes over.
  static const double logoSize = 80;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icons/splash_logo.png',
              width: logoSize,
              height: logoSize,
              // A missing asset must not white-screen the boot path.
              errorBuilder: (_, __, ___) => Icon(
                Icons.inventory_2_outlined,
                size: logoSize,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'app_box',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
