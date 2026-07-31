import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'package:ui_library/widgets/kit_frosted_surface.dart';
import 'package:ui_library/widgets/kit_native_button.dart';
import 'package:ui_library/widgets/kit_native_dialog.dart';

import 'native_test_helpers.dart';

/// kitShowNativeDialog tests. Two tiers:
///
/// - **iOS / default tier**: a [KitFrostedSurface] panel with stacked
///   full-width [KitNativeButton] actions. The buttons delegate to CNButton,
///   which embeds a real UiKitView on iOS/macOS 26+ — a UiKitView can't
///   render in a headless flutter_test, so the iOS-tier tests run inside
///   [withAndroidFallback] to make CNButton take its pure-Material fallback.
/// - **Android tier** (kit gate: `KitPlatformOverride(isAndroid: true)`): a
///   stock M3 [AlertDialog] — no CN widgets at all, so no platform override
///   is needed (same pattern as the sheet test's Android case).
void main() {
  tearDown(KitPlatform.reset);

  testWidgets('iOS tier renders the frosted panel with title + message',
      (tester) async {
    await withAndroidFallback(() async {
      KitPlatform.override = const KitPlatformOverride(isIOS: true);
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byType(KitFrostedSurface),
        findsOneWidget,
        reason: 'the iOS tier body is the content-layer frosted panel',
      );
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'AlertDialog is the Android tier — never on iOS',
      );
      expect(find.text('Delete event?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
    });
  });

  testWidgets('iOS tier stacks actions in order, primary filled first',
      (tester) async {
    await withAndroidFallback(() async {
      KitPlatform.override = const KitPlatformOverride(isIOS: true);
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final deleteY = tester.getCenter(find.text('Delete')).dy;
      final cancelY = tester.getCenter(find.text('Cancel')).dy;
      expect(
        deleteY,
        lessThan(cancelY),
        reason: 'actions stack vertically in declaration order',
      );

      final deleteButton = tester.widget<KitNativeButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(KitNativeButton),
        ),
      );
      expect(
        deleteButton.style,
        KitButtonStyle.prominentGlass,
        reason: 'the primary role renders as the filled accent pill',
      );
      final cancelButton = tester.widget<KitNativeButton>(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(KitNativeButton),
        ),
      );
      expect(
        cancelButton.style,
        KitButtonStyle.glass,
        reason: 'the secondary role renders as the subdued glass pill',
      );
    });
  });

  testWidgets('tapping an action runs onPressed and pops with its value',
      (tester) async {
    await withAndroidFallback(() async {
      KitPlatform.override = const KitPlatformOverride(isIOS: true);
      final results = <String?>[];
      var fired = false;
      await tester.pumpWidget(_hostWithOpener(
        onResult: results.add,
        onDelete: () => fired = true,
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(fired, isTrue, reason: 'onPressed fires on tap');
      expect(
        results,
        ['deleted'],
        reason: "the future resolves to the tapped action's value",
      );
      expect(
        find.text('Delete event?'),
        findsNothing,
        reason: 'the dialog is popped',
      );
    });
  });

  testWidgets('barrier tap dismisses (null result) when dismissible',
      (tester) async {
    await withAndroidFallback(() async {
      KitPlatform.override = const KitPlatformOverride(isIOS: true);
      final results = <String?>[];
      await tester.pumpWidget(_hostWithOpener(onResult: results.add));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(results, [null], reason: 'barrier-dismiss resolves to null');
      expect(find.text('Delete event?'), findsNothing);
    });
  });

  testWidgets('barrierDismissible false ignores barrier taps', (tester) async {
    await withAndroidFallback(() async {
      KitPlatform.override = const KitPlatformOverride(isIOS: true);
      final results = <String?>[];
      await tester.pumpWidget(_hostWithOpener(
        barrierDismissible: false,
        onResult: results.add,
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Delete event?'), findsOneWidget);
      expect(results, isEmpty);
    });
  });

  testWidgets('Android tier renders a stock M3 AlertDialog', (tester) async {
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
    final results = <String?>[];
    await tester.pumpWidget(_hostWithOpener(onResult: results.add));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byType(KitFrostedSurface),
      findsNothing,
      reason: 'the M3 dialog idiom is a plain surface — no frosted panel',
    );
    expect(find.text('Delete event?'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(results, ['deleted']);
  });
}

/// A trivial host that exposes a button which opens the dialog from a real
/// BuildContext (showDialog needs a Navigator ancestor) and forwards the
/// result to [onResult].
Widget _hostWithOpener({
  bool barrierDismissible = true,
  void Function(String?)? onResult,
  VoidCallback? onDelete,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await kitShowNativeDialog<String>(
                context: context,
                title: 'Delete event?',
                message: 'This cannot be undone.',
                barrierDismissible: barrierDismissible,
                actions: [
                  KitNativeDialogAction<String>(
                    label: 'Delete',
                    role: KitDialogActionRole.primary,
                    value: 'deleted',
                    onPressed: onDelete,
                  ),
                  const KitNativeDialogAction<String>(
                    label: 'Cancel',
                    value: 'cancelled',
                  ),
                ],
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}
