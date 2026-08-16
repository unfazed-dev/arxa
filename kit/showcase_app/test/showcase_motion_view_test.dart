// Widget tests for the motion showcase surface. The motion primitives
// themselves are proven in appbox_kit_motion's own tests; these pin the
// showcase wiring that the liquid-glass law depends on — specifically the
// chrome-scaffold migration's padding arithmetic, which no other test covers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'helpers.dart';

void main() {
  setUpAll(registerKitTestServices);
  tearDownAll(() => appBoxKitLocator.reset());

  setUp(() {
    AppBoxKitPlatform.override =
        const AppBoxKitPlatformOverride(isAndroid: true);
  });
  tearDown(AppBoxKitPlatform.reset);

  // The list's top padding must be read from a context BELOW the chrome
  // scaffold (the view wraps its body in a Builder for exactly this): the
  // glass tier's floating chrome raises MediaQuery.padding.top for its body
  // subtree ONLY. Read at the view's own context it is wrong on both tiers —
  // unraised on glass, and the unstripped status bar on boxed.
  group('list top padding resolves below the chrome', () {
    const double statusBar = 44;

    Future<EdgeInsets> pumpAndReadPadding(WidgetTester tester) async {
      // Tall surface so the whole demo list builds — the default 800×600 view
      // leaves the trailing cards outside the lazy ListView's cache extent.
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: statusBar);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(const MaterialApp(home: ShowcaseMotionView()));
      // Past the flutter_animate adapter card's chain: its Animate schedules a
      // restart timer on init, and a bare pump() leaves it pending, which the
      // binding reports as a failure. The components surface has no such card.
      await tester.pump(const Duration(milliseconds: 800));
      return tester
          .widget<AppBoxKitEdgeAwareListView>(
              find.byType(AppBoxKitEdgeAwareListView))
          .padding!
          .resolve(TextDirection.ltr);
    }

    testWidgets(
        'boxed tier takes the bare inset — Scaffold already stripped it',
        (tester) async {
      // setUp's Android override is the boxed branch.
      expect((await pumpAndReadPadding(tester)).top, abxSize16,
          reason: 'a boxed tier that leaks the status bar into the list is the '
              'padding read from above the scaffold');
    });

    testWidgets('glass tier adds the status bar + floating-bar block',
        (tester) async {
      AppBoxKitPlatform.override =
          const AppBoxKitPlatformOverride(isIOS: true, iosMajor: 26);
      expect((await pumpAndReadPadding(tester)).top,
          abxSize16 + statusBar + kAppBoxKitFloatingBarBlockHeight,
          reason: 'missing the raise means the padding was read above the '
              'floating chrome, tucking the first card under the bar');
    });
  });
}
