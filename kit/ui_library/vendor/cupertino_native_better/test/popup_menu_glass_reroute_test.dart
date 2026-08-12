import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the iOS 26 popup-menu chrome theme reversal.
///
/// ## What the bug is (measured, not assumed)
///
/// A `showsMenuAsPrimaryAction` UIButton's popup chrome does not re-derive
/// its appearance per presentation: on device (08-12 10-40 clip) the FAB
/// and overflow menus rendered with the PREVIOUS presentation's traits —
/// light panels in dark mode, dark panels in light mode, always exactly one
/// presentation behind, while the SwiftUI `Menu` of the Send split button
/// (a `CNGlassButtonGroup` popup segment) followed the in-app theme in both
/// directions in the same clip. No public lever reaches the cached UIKit
/// presentation (FB13391355-class), so group-compatible glass icon triggers
/// route through a one-button `CNGlassButtonGroup` instead
/// (`popup_menu_button.dart` `_canUseGlassGroupTrigger`).
///
/// ## What these tests assert
///
/// - **Red-then-green:** a plain glass icon popup builds a
///   `CNGlassButtonGroup`, not the UIKit `UiKitView`. Fails before the
///   reroute.
/// - **Invariant guard:** feature-rich menus (dividers, per-item state) keep
///   the UIKit path — passes before and after; it pins the escape hatch.
///
/// Reachability: `PlatformVersion.shouldUseNativeGlass` is true on a macOS
/// 26+ test host (see rebuild_stability_test.dart), and the target platform
/// override makes the iOS branch taken.
void main() {
  /// Sets [debugDefaultTargetPlatformOverride] for the duration of [body].
  /// Restore-in-finally, not tearDown: flutter_test's invariant check runs
  /// before tearDown callbacks.
  Future<void> withIOS(Future<void> Function() body) async {
    final saved = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = saved;
    }
  }

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets(
    'kit.cupertino-native-better.popup-menu — glass icon trigger routes through the glass button group',
    (tester) async {
      await withIOS(() async {
        await tester.pumpWidget(
          host(
            CNPopupMenuButton.icon(
              buttonIcon: const CNSymbol('plus'),
              items: const [
                CNPopupMenuItem(label: 'New post'),
                CNPopupMenuItem(label: 'Sign out', isDestructive: true),
              ],
              onSelected: (_) {},
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(CNGlassButtonGroup), findsOneWidget);
      });
    },
  );

  testWidgets(
    'kit.cupertino-native-better.popup-menu — menus with dividers keep the UIKit button path',
    (tester) async {
      await withIOS(() async {
        await tester.pumpWidget(
          host(
            CNPopupMenuButton.icon(
              buttonIcon: const CNSymbol('ellipsis'),
              items: const [
                CNPopupMenuItem(label: 'Refresh'),
                CNPopupMenuDivider(),
                CNPopupMenuItem(label: 'Sign out', isDestructive: true),
              ],
              onSelected: (_) {},
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(CNGlassButtonGroup), findsNothing);
      });
    },
  );
}
