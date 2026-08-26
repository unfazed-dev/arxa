import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/services/notifications/arxa_kit_notification_service.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_frosted_surface.dart';

/// ArxaKitNotificationService ask-surface tests (confirm / prompt / alert /
/// notice) — the kit-rendered verbs that let apps drop stacked dialog/sheet
/// variant registration.
///
/// Tested on the Android (M3) tier — stock AlertDialog / modal sheet are
/// deterministic in headless flutter_test; the iOS frosted tier shares
/// [arxaKitShowNativeDialog]/[arxaKitShowSheet], whose own routing is
/// asserted in the native widget tests. Pre-boot (no context anywhere) is
/// asserted to no-op, never throw.
void main() {
  late ArxaKitNotificationService service;

  setUp(() {
    service = ArxaKitNotificationService();
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
  });

  tearDown(() {
    ArxaKitPlatform.reset();
    arxaKitLocator.reset();
  });

  /// Pumps a host with a 'go' button that invokes [call] with its context,
  /// taps it, and lets the dialog/sheet settle in.
  Future<void> pumpCaller(
    WidgetTester tester,
    Future<void> Function(BuildContext context) call,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => call(context),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'kit.ui-library.notification-service — confirm resolves true on the action, false on cancel',
      (tester) async {
    bool? result;
    await pumpCaller(tester, (context) async {
      result = await service.confirm(
        title: 'Delete note?',
        actionLabel: 'Delete',
        destructive: true,
        context: context,
      );
    });
    expect(find.text('Delete note?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await pumpCaller(tester, (context) async {
      result = await service.confirm(title: 'Delete note?', context: context);
    });
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets(
      'kit.ui-library.ask-surfaces — the prompt dialog panel is opaque and '
      'platform-view-safe: its action buttons are CN platform views on the '
      'glass tier, so no BackdropFilter saveLayer may sit behind them '
      '(flutter#175048). Pinned on the iOS 18 tier — Cupertino fallbacks pump '
      'headless; the wiring is unconditional, so the glass tier inherits it.',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isIOS: true, iosMajor: 18);
    await pumpCaller(tester, (context) async {
      await service.prompt(title: 'New Folder', context: context);
    });

    final surface = tester
        .widget<ArxaKitFrostedSurface>(find.byType(ArxaKitFrostedSurface));
    expect(surface.platformViewSafe, isTrue,
        reason: 'the saveLayer-free vibrant-fill branch, same as the sheet and '
            'alert dialog (native_sheet.dart:370-372, native_dialog.dart:218)');
    expect(surface.tint?.a, 1.0,
        reason: 'fully opaque base — nothing behind the dialog shows through, '
            'so the glass buttons read at one luminance');
    expect(
      find.descendant(
          of: find.byType(Dialog), matching: find.byType(BackdropFilter)),
      findsNothing,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  test(
      'kit.ui-library.notification-service — confirm pre-boot resolves false, never throws',
      () async {
    expect(await service.confirm(title: 'Sure?'), isFalse);
    expect(await service.prompt(title: 'Name'), isNull);
    await service.alert(title: 'Hi');
    await service.notice(title: 'Hi', message: 'there');
  });

  testWidgets(
      'kit.ui-library.notification-service — prompt resolves the trimmed entry on save, null on cancel and on empty entry',
      (tester) async {
    String? result = 'untouched';
    await pumpCaller(tester, (context) async {
      result = await service.prompt(
        title: 'New Folder',
        placeholder: 'Name',
        context: context,
      );
    });
    await tester.enterText(find.byType(TextField), '  Trips  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, 'Trips');

    await pumpCaller(tester, (context) async {
      result = await service.prompt(title: 'New Folder', context: context);
    });
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    result = 'untouched';
    await pumpCaller(tester, (context) async {
      result = await service.prompt(title: 'New Folder', context: context);
    });
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets(
      'kit.ui-library.notification-service — alert shows a single action and dismisses',
      (tester) async {
    await pumpCaller(tester, (context) async {
      await service.alert(
          title: 'Saved', message: 'All good', context: context);
    });
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('All good'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets(
      'kit.ui-library.notification-service — notice presents a modal sheet with title and message',
      (tester) async {
    await pumpCaller(tester, (context) async {
      await service.notice(
        title: 'Native sheet',
        message: 'Presented by the kit',
        context: context,
      );
    });
    expect(find.text('Native sheet'), findsOneWidget);
    expect(find.text('Presented by the kit'), findsOneWidget);
  });
}
