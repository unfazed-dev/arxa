import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSheetGeometryProbe;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/services/sheet/appbox_kit_bottom_sheet_service.dart';
import 'package:stacked_services/stacked_services.dart';

import '../widgets/appbox_kit_native_test_helpers.dart';

/// AppBoxKitBottomSheetService presents stacked sheets through appBoxKitShowNativeSheet.
/// Assertions are branch-taken (right tier's widget appears) + contract-held
/// (completer response comes back through the returned future).
void main() {
  tearDown(AppBoxKitPlatform.reset);

  Widget hostApp() => MaterialApp(
        // The service resolves its context from StackedService.navigatorKey
        // (Get.key) — wire it exactly like app.router.dart does.
        navigatorKey: StackedService.navigatorKey,
        home: const Scaffold(body: SizedBox()),
      );

  testWidgets('showCustomSheet renders the registered builder and returns '
      'the completer response', (tester) async {
    await withAndroidFallback(() async {
      final service = AppBoxKitBottomSheetService()
        ..setCustomSheetBuilders({
          'notice': (context, request, completer) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(request.title!),
                  TextButton(
                    onPressed: () =>
                        completer(SheetResponse(confirmed: true)),
                    child: const Text('confirm'),
                  ),
                ],
              ),
        });
      await tester.pumpWidget(hostApp());

      final future =
          service.showCustomSheet(variant: 'notice', title: 'hello');
      await tester.pumpAndSettle();

      expect(find.text('hello'), findsOneWidget,
          reason: 'the registered builder must render inside the sheet');
      expect(find.byType(CNSheetGeometryProbe), findsOneWidget,
          reason: 'default tier presents through CNBottomSheet.show');

      await tester.tap(find.text('confirm'));
      await tester.pumpAndSettle();

      final response = await future;
      expect(response?.confirmed, isTrue,
          reason: 'the completer response must resolve the future');
    });
  });

  testWidgets('Android tier presents via plain showModalBottomSheet',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    final service = AppBoxKitBottomSheetService()
      ..setCustomSheetBuilders({
        'notice': (context, request, completer) => Text(request.title!),
      });
    await tester.pumpWidget(hostApp());

    service.showCustomSheet(variant: 'notice', title: 'droid');
    await tester.pumpAndSettle();

    expect(find.text('droid'), findsOneWidget);
    expect(find.byType(CNSheetGeometryProbe), findsNothing,
        reason: 'Android tier uses plain showModalBottomSheet');
  });

  testWidgets('showBottomSheet renders title/description and confirm '
      'completes with confirmed: true', (tester) async {
    await withAndroidFallback(() async {
      final service = AppBoxKitBottomSheetService();
      await tester.pumpWidget(hostApp());

      final future = service.showBottomSheet(
        title: 'General',
        description: 'body text',
        confirmButtonTitle: 'Go',
      );
      await tester.pumpAndSettle();

      expect(find.text('General'), findsOneWidget);
      expect(find.text('body text'), findsOneWidget);

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      final response = await future;
      expect(response?.confirmed, isTrue);
    });
  });
}
