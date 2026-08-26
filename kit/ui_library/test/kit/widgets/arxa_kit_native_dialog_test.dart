import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_frosted_surface.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_button.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_dialog.dart';

import 'arxa_kit_native_test_helpers.dart';

/// arxaKitShowNativeDialog tests. Two tiers:
///
/// - **iOS / default tier**: a [ArxaKitFrostedSurface] panel with stacked
///   full-width [ArxaKitNativeButton] actions. The buttons delegate to CNButton,
///   which embeds a real UiKitView on iOS/macOS 26+ — a UiKitView can't
///   render in a headless flutter_test, so the iOS-tier tests run inside
///   [withAndroidFallback] to make CNButton take its pure-Material fallback.
/// - **Android tier** (kit gate: `ArxaKitPlatformOverride(isAndroid: true)`): a
///   stock M3 [AlertDialog] — no CN widgets at all, so no platform override
///   is needed (same pattern as the sheet test's Android case).
void main() {
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.native-dialog — presenting never notifies modal-depth '
      'listeners mid-build', (tester) async {
    // Device crash this reproduces:
    //
    //   setState() or markNeedsBuild() called during build.
    //   This CNTextField widget cannot be marked as needing to build...
    //   The widget which was currently being built ... was: Builder
    //
    // `ArxaKitFrostedAlertDialog` bumps the shared depth from its initState,
    // which the framework runs *during* the build phase. `anyModalDepth` is a
    // ValueNotifier, so that bump notifies synchronously, and every listener
    // that calls setState — CNTextField (`text_field.dart:194-195`),
    // ArxaKitNativeChromeGate, ArxaKitScrollOcclusionGate — is marked dirty
    // mid-build. Any of them already built earlier in the same frame (a native
    // field on the *host* page, e.g. the showcase's input bar) is illegal to
    // dirty, and the framework throws.
    //
    // Asserted as the scheduler phase at notification time rather than by
    // mounting a CNTextField: the widget under the real fault is a UiKitView
    // that cannot render headless, and the defect is the notification timing
    // itself — it endangers every listener, not just that one.
    final List<SchedulerPhase> phases = <SchedulerPhase>[];
    void record() => phases.add(SchedulerBinding.instance.schedulerPhase);
    CNTabBarRouteObserver.anyModalDepth.addListener(record);
    addTearDown(
        () => CNTabBarRouteObserver.anyModalDepth.removeListener(record));

    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(isIOS: true);
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    });

    expect(phases, isNotEmpty,
        reason: 'the dialog must still move the shared depth at all — a test '
            'that observes nothing would pass vacuously');
    expect(
      phases,
      isNot(contains(SchedulerPhase.persistentCallbacks)),
      reason: 'notifying while widgets are being built marks host-page '
          'listeners dirty mid-frame, which throws',
    );
  });

  testWidgets(
      'kit.ui-library.native-dialog — iOS tier renders the frosted panel with title + message',
      (tester) async {
    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(isIOS: true);
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byType(ArxaKitFrostedSurface),
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

  testWidgets(
      'kit.ui-library.native-dialog — iOS tier stacks actions in order, primary filled first',
      (tester) async {
    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(isIOS: true);
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

      final deleteButton = tester.widget<ArxaKitNativeButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(ArxaKitNativeButton),
        ),
      );
      expect(
        deleteButton.style,
        ArxaKitButtonStyle.prominentGlass,
        reason: 'the primary role renders as the filled accent pill',
      );
      final cancelButton = tester.widget<ArxaKitNativeButton>(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(ArxaKitNativeButton),
        ),
      );
      expect(
        cancelButton.style,
        ArxaKitButtonStyle.glass,
        reason: 'the secondary role renders as the subdued glass pill',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-dialog — tapping an action runs onPressed and pops with its value',
      (tester) async {
    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(isIOS: true);
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

  testWidgets(
      'kit.ui-library.native-dialog — barrier tap dismisses (null result) when dismissible',
      (tester) async {
    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(isIOS: true);
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

  testWidgets(
      'kit.ui-library.native-dialog — barrierDismissible false ignores barrier taps',
      (tester) async {
    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(isIOS: true);
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

  testWidgets(
      'kit.ui-library.native-dialog — Android tier renders a stock M3 AlertDialog',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    final results = <String?>[];
    await tester.pumpWidget(_hostWithOpener(onResult: results.add));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byType(ArxaKitFrostedSurface),
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
              final result = await arxaKitShowNativeDialog<String>(
                context: context,
                title: 'Delete event?',
                message: 'This cannot be undone.',
                barrierDismissible: barrierDismissible,
                actions: [
                  ArxaKitNativeDialogAction<String>(
                    label: 'Delete',
                    role: ArxaKitDialogActionRole.primary,
                    value: 'deleted',
                    onPressed: onDelete,
                  ),
                  const ArxaKitNativeDialogAction<String>(
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
