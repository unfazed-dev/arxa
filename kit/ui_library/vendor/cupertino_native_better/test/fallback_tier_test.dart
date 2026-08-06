import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for LOCAL PATCH #3 (CNButton fallback width) and
/// LOCAL PATCH #4 (CNIcon widget-selection gate) — see playbook/plan.mdx.
void main() {
  /// Sets debugDefaultTargetPlatformOverride for the duration of [body].
  /// The restore must happen before the test body returns (flutter_test's
  /// invariant check runs before tearDown), so it lives in a finally here.
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    final saved = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = saved;
    }
  }

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('LOCAL PATCH #3: CNButton fallback width', () {
    testWidgets('icon+label button is not width-pinned (Material fallback)', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(
          host(
            CNButton(
              label: 'Continue',
              customIcon: CupertinoIcons.add,
              onPressed: () {},
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        // Pre-patch the SizedBox width fell through to defaultHeight (44)
        // whenever any icon was present, squashing the label.
        final size = tester.getSize(find.byType(CNButton));
        expect(size.width, greaterThan(44.0));
        expect(find.text('Continue'), findsOneWidget);
      });
    });

    testWidgets('icon-only button stays square (Material fallback)', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(
          host(CNButton.icon(customIcon: CupertinoIcons.add, onPressed: () {})),
        );

        expect(tester.takeException(), isNull);
        // The width pin is correct for icon-ONLY buttons: 44pt square
        // (Apple HIG minimum touch target).
        final size = tester.getSize(find.byType(CNButton));
        expect(size.width, 44.0);
        expect(size.height, 44.0);
      });
    });
  });

  group('LOCAL PATCH #4: CNIcon widget selection', () {
    testWidgets('no platform view under flutter test (android override)', (
      tester,
    ) async {
      // The reported wall: on a macOS test host, dart:io Platform.isMacOS is
      // true, so the old supportsSFSymbols gate built an AppKitView headless
      // even though the override asked for the non-Apple tier.
      await withPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(host(const CNIcon(symbol: CNSymbol('star'))));

        expect(tester.takeException(), isNull);
        expect(find.byType(UiKitView), findsNothing);
        expect(find.byType(AppKitView), findsNothing);
        expect(find.byType(Icon), findsOneWidget);
      });
    });

    testWidgets('no platform view under flutter test (iOS override)', (
      tester,
    ) async {
      // Widget selection must be test-deterministic: even an Apple-platform
      // override cannot conjure a platform view in a headless test.
      await withPlatform(TargetPlatform.iOS, () async {
        await tester.pumpWidget(host(const CNIcon(symbol: CNSymbol('star'))));

        expect(tester.takeException(), isNull);
        expect(find.byType(UiKitView), findsNothing);
        expect(find.byType(AppKitView), findsNothing);
        expect(find.byType(Icon), findsOneWidget);
      });
    });

    testWidgets('CNButton label+SF-symbol renders headless (the flows wall)', (
      tester,
    ) async {
      // End-to-end shape of the original failure: AppBoxKitNativeButton(label +
      // sfSymbol) on the Material fallback embeds a CNIcon, which pre-patch
      // crashed the whole button with MissingPluginException in tests.
      await withPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(
          host(
            CNButton(
              label: 'Continue',
              icon: const CNSymbol('plus'),
              onPressed: () {},
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(UiKitView), findsNothing);
        expect(find.byType(AppKitView), findsNothing);
        expect(find.text('Continue'), findsOneWidget);
      });
    });
  });
}
