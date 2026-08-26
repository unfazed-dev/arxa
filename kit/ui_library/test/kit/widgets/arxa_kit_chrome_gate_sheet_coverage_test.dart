// Sheet coverage is NOT a hide channel — closed the other way.
//
// `ArxaKitNativeChromeGate` used to hide on `anyModalDepth > _mountDepth`
// and, later, on rect-overlap with the published sheet rect. Both channels
// blanked native glass that was still plainly visible behind or beside a
// sheet — a sheet is `opaque: false`, the page below it stays live for the
// sheet's whole lifetime, and iOS keeps the platform views interactive under
// its own sheets (WWDC21-10063: content behind a medium detent stays
// rendered). Hiding on modal signals IS the "glass vanishes, then pops back"
// defect, reached through the modal branch instead of the transition branch.
//
// Today the gate's single hide authority is a real opaque route transition
// (`CNTransitionObserver.hasActiveTransitionAbove`). These tests pin the
// modal branch shut: no combination of modal depth and published rects may
// blank a gate, anywhere on the surface, at any coverage.
import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_chrome_gate.dart';

/// Paint decision of the gate wrapping [text]. 0 = placeholder (hidden).
bool _hidden(WidgetTester tester, String text) {
  final IndexedStack stack = tester.widget<IndexedStack>(
    find
        .ancestor(
          of: find.text(text, skipOffstage: false),
          matching: find.byType(IndexedStack, skipOffstage: false),
        )
        .first,
  );
  return stack.index == 0;
}

/// Two gates on one 800x600 test surface, at known y bands:
///   top-glass  y   0..100
///   (spacer)   y 100..300
///   mid-glass  y 300..400
///   (gap)      y 400..600   <- deliberately empty
///
/// The bands let the tests publish rects that overlap one gate, both, or
/// neither — and assert the answer is always the same: painted.
Widget _page() {
  return const MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 100,
            child: ArxaKitNativeChromeGate(child: Text('top-glass')),
          ),
          Spacer(),
          SizedBox(
            height: 100,
            child: ArxaKitNativeChromeGate(child: Text('mid-glass')),
          ),
          SizedBox(height: 200),
        ],
      ),
    ),
  );
}

void main() {
  tearDown(() {
    CNTabBarRouteObserver.publishTopModalRect(null);
    while (CNTabBarRouteObserver.anyModalDepth.value > 0) {
      CNTabBarRouteObserver.markAnyModalInactive();
    }
  });

  testWidgets(
      'kit.ui-library.chrome-gate-sheet — a sheet rect never blanks the chrome '
      'it overlaps, at any coverage', (WidgetTester tester) async {
    await tester.pumpWidget(_page());
    expect(_hidden(tester, 'top-glass'), isFalse);
    expect(_hidden(tester, 'mid-glass'), isFalse);

    CNTabBarRouteObserver.markAnyModalActive();

    // A short sheet occupying the bottom 250pt: overlaps mid-glass (300..400),
    // nowhere near top-glass (0..100).
    CNTabBarRouteObserver.publishTopModalRect(
      const Rect.fromLTRB(0, 350, 800, 600),
    );
    await tester.pump();
    expect(_hidden(tester, 'mid-glass'), isFalse,
        reason: 'the sheet is translucent glass over a LIVE page — blanking '
            'the chrome under it is the dematerialize/pop-back defect');
    expect(_hidden(tester, 'top-glass'), isFalse);

    // The sheet grows to full-screen coverage.
    CNTabBarRouteObserver.publishTopModalRect(
      const Rect.fromLTRB(0, 0, 800, 600),
    );
    await tester.pump();
    expect(_hidden(tester, 'mid-glass'), isFalse,
        reason: 'coverage is not a hide signal — only a real opaque route '
            'transition is');
    expect(_hidden(tester, 'top-glass'), isFalse);

    // Dismissed: nothing changed, so nothing "comes back".
    CNTabBarRouteObserver.publishTopModalRect(null);
    CNTabBarRouteObserver.markAnyModalInactive();
    await tester.pump();
    expect(_hidden(tester, 'mid-glass'), isFalse);
    expect(_hidden(tester, 'top-glass'), isFalse);
  });

  testWidgets(
      'kit.ui-library.chrome-gate-sheet — a modal that publishes NO rect hides '
      'nothing either', (WidgetTester tester) async {
    // The old "safety fallback" inverted. A plain `showModalBottomSheet`, a
    // dialog, or any presentation without the geometry probe used to fail
    // toward hiding — which blanked every gate on screen for a dialog the
    // size of a postage stamp. Non-opaque presentations keep the page below
    // fully composited, so there is nothing to protect and everything to lose.
    await tester.pumpWidget(_page());
    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();

    expect(_hidden(tester, 'top-glass'), isFalse,
        reason: 'no rect, no hide — depth alone is not a channel');
    expect(_hidden(tester, 'mid-glass'), isFalse,
        reason: 'no rect, no hide — depth alone is not a channel');
  });

  testWidgets(
      'kit.ui-library.chrome-gate-sheet — a gate mounted INSIDE the sheet never '
      'hides itself', (WidgetTester tester) async {
    // A gate built inside the sheet's own content overlaps the sheet rect by
    // definition. It must come up painted — trivially true now that modal
    // signals hide nothing, and kept as a canary in case a coverage channel
    // ever returns.
    CNTabBarRouteObserver.markAnyModalActive();
    CNTabBarRouteObserver.publishTopModalRect(
      const Rect.fromLTRB(0, 400, 800, 600),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 200,
              child: ArxaKitNativeChromeGate(child: Text('sheet-glass')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_hidden(tester, 'sheet-glass'), isFalse,
        reason: "the sheet's own chrome must stay painted inside its own "
            'presentation');
  });
}
