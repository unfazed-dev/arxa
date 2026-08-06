import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_bottom_nav_scaffold.dart';

void main() {
  // flutter#145680: extendBody inflates the body's MediaQuery *padding* by the
  // bar height, but FloatingActionButtonLocation lifts FABs by *viewPadding*
  // (raw device inset) — a nested Scaffold's FAB parks behind the bar.
  // AppBoxKitExtendBodyFabLift mirrors padding into viewPadding so the FAB clears it.
  testWidgets('kit.ui-library.extend-body-fab-lift — nested-scaffold FAB floats clear of the extendBody bar',
      (tester) async {
    const screen = Size(400, 800);
    const barHeight = 80.0;
    const deviceInset = 34.0; // iOS home indicator

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: screen,
            padding: EdgeInsets.only(bottom: deviceInset),
            viewPadding: EdgeInsets.only(bottom: deviceInset),
          ),
          child: Scaffold(
            extendBody: true,
            bottomNavigationBar: const SizedBox(height: barHeight),
            body: AppBoxKitExtendBodyFabLift(
              child: Scaffold(
                floatingActionButton: FloatingActionButton(
                  onPressed: () {},
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final fabBottom = tester
        .getBottomRight(find.byType(FloatingActionButton))
        .dy;
    // Layout height comes from the test surface, not the synthetic MediaQuery.
    final screenBottom = tester.getRect(find.byType(Scaffold).first).bottom;
    final barTop = screenBottom - barHeight;
    // endFloat contract: FAB bottom = bar top - kFloatingActionButtonMargin.
    // Without the lift it would sit at screenBottom - deviceInset - margin,
    // i.e. behind the bar.
    expect(fabBottom, barTop - kFloatingActionButtonMargin);
  });
}
