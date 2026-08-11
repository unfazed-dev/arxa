import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_fab_above_dock.dart';

/// [AppBoxKitFabAboveDock] tests.
///
/// Device symptom (2026-08-11): on the showcase's Components gallery — which
/// pins a chat composer as `Scaffold.bottomSheet` — the gallery FAB sat on top
/// of the composer's trailing mic button. Material's float locations dock the
/// FAB *straddling* a bottom sheet's top edge by design
/// (`fabY = min(fabY, contentBottom - sheetHeight - fabHeight / 2)`), which is
/// right for a transient sheet and wrong for a pinned dock.
void main() {
  const double sheetHeight = 80;
  const double fabSize = 56;

  Widget host(FloatingActionButtonLocation location, {bool withDock = true}) =>
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomSheet: withDock
              ? const SizedBox(height: sheetHeight, child: ColoredBox(color: Color(0xFF00FF00)))
              : null,
          floatingActionButtonLocation: location,
          floatingActionButton: const SizedBox(
            key: Key('fab'),
            width: fabSize,
            height: fabSize,
            child: ColoredBox(color: Color(0xFFFF0000)),
          ),
        ),
      );

  testWidgets('kit.ui-library.fab-above-dock — clears a docked bottom sheet instead of straddling it',
      (tester) async {
    await tester.pumpWidget(host(AppBoxKitFabAboveDock.endFloat));

    final double fabBottom = tester.getRect(find.byKey(const Key('fab'))).bottom;
    final double dockTop =
        tester.getRect(find.byType(Scaffold)).bottom - sheetHeight;

    expect(fabBottom, lessThanOrEqualTo(dockTop),
        reason: 'no part of the FAB may overlap the dock — overlapping its '
            'trailing control is the reported bug');
  });

  testWidgets('kit.ui-library.fab-above-dock — Material endFloat straddles the same dock (the defect)',
      (tester) async {
    // Anti-vacuous companion: proves the assertion above discriminates. If
    // Flutter ever changes endFloat to clear sheets, this fails and the kit
    // location can be deleted.
    await tester.pumpWidget(host(FloatingActionButtonLocation.endFloat));

    final double fabBottom = tester.getRect(find.byKey(const Key('fab'))).bottom;
    final double dockTop =
        tester.getRect(find.byType(Scaffold)).bottom - sheetHeight;

    expect(fabBottom, greaterThan(dockTop),
        reason: 'stock endFloat is expected to overlap the dock — that is why '
            'AppBoxKitFabAboveDock exists');
  });

  testWidgets('kit.ui-library.fab-above-dock — matches endFloat exactly when no dock is present',
      (tester) async {
    // The location is set unconditionally on scaffolds whose dock comes and
    // goes, so with no sheet it must not shift the FAB at all.
    await tester.pumpWidget(host(FloatingActionButtonLocation.endFloat, withDock: false));
    final Rect stock = tester.getRect(find.byKey(const Key('fab')));

    await tester.pumpWidget(host(AppBoxKitFabAboveDock.endFloat, withDock: false));
    final Rect kit = tester.getRect(find.byKey(const Key('fab')));

    expect(kit, stock,
        reason: 'without a bottom sheet this must be a pure pass-through');
  });
}
