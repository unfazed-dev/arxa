// Sheet coverage — the all-or-nothing modal ceiling, closed (law rule 11).
//
// `AppBoxKitNativeChromeGate` used to hide on `anyModalDepth > _mountDepth`
// alone, so opening ANY sheet dematerialized EVERY native glass surface behind
// it — including the ones still plainly visible in the clear space above a
// short bottom sheet — and materialized them all back on dismiss. That is the
// same "glass vanishes, then pops back" defect as the back-swipe, reached
// through the modal branch instead of the transition branch.
//
// `CNBottomSheet` already publishes the sheet's live rect for exactly this
// reason (its probe comment: "measuring the route would tear down native
// chrome sitting in the clear space above a short sheet"). The kit published
// that rect and then ignored it. These tests pin the narrowed predicate.
import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_chrome_gate.dart';

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
/// The trailing gap matters: a gate flush against the bottom edge would be
/// overlapped by ANY bottom sheet, making "the sheet has not reached it yet"
/// untestable. mid-glass sits clear of the edge so coverage can be toggled.
Widget _page() {
  return const MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 100,
            child: AppBoxKitNativeChromeGate(child: Text('top-glass')),
          ),
          Spacer(),
          SizedBox(
            height: 100,
            child: AppBoxKitNativeChromeGate(child: Text('mid-glass')),
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
      'kit.ui-library.chrome-gate-sheet — a short sheet hides only the chrome it '
      'actually covers', (WidgetTester tester) async {
    await tester.pumpWidget(_page());
    expect(_hidden(tester, 'top-glass'), isFalse);
    expect(_hidden(tester, 'mid-glass'), isFalse);

    // A sheet occupying the bottom 250pt of the 600pt-tall surface: it
    // overlaps mid-glass (300..400) and comes nowhere near top-glass (0..100).
    CNTabBarRouteObserver.markAnyModalActive();
    CNTabBarRouteObserver.publishTopModalRect(
      const Rect.fromLTRB(0, 350, 800, 600),
    );
    await tester.pump();

    expect(_hidden(tester, 'mid-glass'), isTrue,
        reason: 'chrome the sheet covers must still leave the frame — a '
            'platform view composites above the Flutter scene and would '
            'punch through the sheet');
    expect(_hidden(tester, 'top-glass'), isFalse,
        reason: 'chrome in the CLEAR SPACE above a short sheet must stay '
            'painted: leaving the frame is what makes iOS 26 Liquid Glass '
            're-materialize when the sheet closes');
  });

  testWidgets(
      'kit.ui-library.chrome-gate-sheet — a sheet that grows to cover a gate '
      'hides it as it arrives', (WidgetTester tester) async {
    await tester.pumpWidget(_page());
    CNTabBarRouteObserver.markAnyModalActive();

    // The probe republishes every frame while the sheet slides up, so coverage
    // is a moving decision, not a one-shot at open.
    CNTabBarRouteObserver.publishTopModalRect(
      const Rect.fromLTRB(0, 500, 800, 600),
    );
    await tester.pump();
    expect(_hidden(tester, 'mid-glass'), isFalse,
        reason: 'sheet (500..600) has not reached mid-glass (300..400) yet');

    CNTabBarRouteObserver.publishTopModalRect(
      const Rect.fromLTRB(0, 350, 800, 600),
    );
    await tester.pump();
    expect(_hidden(tester, 'mid-glass'), isTrue,
        reason: 'sheet now overlaps mid-glass');
    expect(_hidden(tester, 'top-glass'), isFalse,
        reason: 'and still does not reach the top one');

    // Dismissed: everything comes back.
    CNTabBarRouteObserver.publishTopModalRect(null);
    CNTabBarRouteObserver.markAnyModalInactive();
    await tester.pump();
    expect(_hidden(tester, 'mid-glass'), isFalse);
    expect(_hidden(tester, 'top-glass'), isFalse);
  });

  testWidgets(
      'kit.ui-library.chrome-gate-sheet — a modal that publishes NO rect still '
      'hides everything', (WidgetTester tester) async {
    // The safety fallback. A plain `showModalBottomSheet`, a dialog, or any
    // presentation without the geometry probe cannot describe itself, so the
    // original bleed-free behaviour must be preserved verbatim — narrowing is
    // an optimisation for sheets that CAN describe themselves, never a
    // weakening of the default.
    await tester.pumpWidget(_page());
    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();

    expect(_hidden(tester, 'top-glass'), isTrue,
        reason: 'no published rect → fail toward hiding');
    expect(_hidden(tester, 'mid-glass'), isTrue,
        reason: 'no published rect → fail toward hiding');
  });

  testWidgets(
      'kit.ui-library.chrome-gate-sheet — a gate mounted INSIDE the sheet never '
      'hides itself', (WidgetTester tester) async {
    // The mount-depth baseline: a gate built inside the sheet's own content
    // overlaps the sheet rect by definition, so rect-awareness must not make
    // it self-destruct. Depth is bumped BEFORE it mounts, exactly as a real
    // presentation does.
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
              child: AppBoxKitNativeChromeGate(child: Text('sheet-glass')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_hidden(tester, 'sheet-glass'), isFalse,
        reason: 'the sheet\'s own chrome sits inside the sheet rect; the '
            'mount-depth baseline is what stops it hiding itself');
  });
}
