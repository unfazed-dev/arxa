import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_opaque_bar_base.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_frosted_surface.dart';

/// [AppBoxKitOpaqueBarBase] — the opaque pinned-strip base extracted from
/// [AppBoxKitNativeInputBar] so any strip docked above/around pinned chrome
/// (pending-attachment rows, accessory bars) paints the same opaque,
/// platform-view-safe base instead of leaving content to scroll visibly
/// through the gap.
void main() {
  testWidgets(
      'kit.ui-library.opaque-bar-base — paints an opaque platform-view-safe base around its child',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: AppBoxKitOpaqueBarBase(child: SizedBox(width: 100, height: 40, child: Text('x')))),
      ),
    ));

    final surface = tester.widget<AppBoxKitFrostedSurface>(
        find.byType(AppBoxKitFrostedSurface));
    expect(surface.platformViewSafe, isTrue,
        reason: 'the base may host CN platform views — BackdropFilter is banned');
    expect(surface.borderRadius, 0,
        reason: 'the base is a full-bleed strip, not a card');
    expect(surface.tint?.a, 1.0,
        reason: 'the tint must be fully opaque — content never shows through');
    expect(find.text('x'), findsOneWidget,
        reason: 'the child renders inside the base');
  });
}