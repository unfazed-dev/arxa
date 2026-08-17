// Widget tests for the progress-and-loading demo card's idle thermal
// discipline: perpetual indeterminate spinners schedule a frame every vsync,
// and on the hybrid-composition glass tier (iOS 26) every frame recomposites
// the whole scene of native views — the idle-warmth mechanism. The demo must
// show the animation, then stop it.
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_home_widgets/showcase_progress_loading_card_widget.dart';

import 'helpers.dart';

void main() {
  setUpAll(registerKitTestServices);
  tearDownAll(() => appBoxKitLocator.reset());
  tearDown(AppBoxKitPlatform.reset);

  TickerMode nearestTicker(WidgetTester tester, Finder child) =>
      tester.widget<TickerMode>(find
          .ancestor(of: child, matching: find.byType(TickerMode))
          .first);

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ShowcaseProgressLoadingCardWidget()))));
    await tester.pump();
  }

  group('[Progress demo] — idle thermal discipline', () {
    testWidgets(
      '[Progress demo] — indeterminate demos auto-stop after the demo window (iOS 26 glass tier)',
      (tester) async {
        AppBoxKitPlatform.override =
            const AppBoxKitPlatformOverride(isIOS: true, iosMajor: 26);
        await pumpCard(tester);
        final spinners = find.byType(CupertinoActivityIndicator);
        expect(spinners, findsNWidgets(2),
            reason: 'circular progress + loading indicator both render');
        // The demo spins on appearance…
        expect(nearestTicker(tester, spinners.first).enabled, isTrue,
            reason: 'demo window runs on mount');
        // …then goes idle: no frames scheduled on a static gallery surface.
        await tester.pump(const Duration(seconds: 6));
        await tester.pump();
        expect(nearestTicker(tester, spinners.first).enabled, isFalse,
            reason: 'perpetual spinners must not tick past the demo window');
      },
    );

    testWidgets(
      '[Progress demo] — replay restarts the demo window on demand (Flutter fallback tier)',
      (tester) async {
        AppBoxKitPlatform.override =
            const AppBoxKitPlatformOverride(isIOS: true, iosMajor: 18);
        await pumpCard(tester);
        final spinners = find.byType(CupertinoActivityIndicator);
        expect(spinners, findsNWidgets(2));
        // Idle past the window, then replay must restart it.
        await tester.pump(const Duration(seconds: 6));
        await tester.pump();
        expect(nearestTicker(tester, spinners.first).enabled, isFalse);
        await tester.tap(find.text('Replay'));
        await tester.pump();
        expect(nearestTicker(tester, spinners.first).enabled, isTrue,
            reason: 'replay restarts the demo window');
        // And it auto-stops again — teardown must find no pending timer.
        await tester.pump(const Duration(seconds: 6));
        await tester.pump();
        expect(nearestTicker(tester, spinners.first).enabled, isFalse);
      },
    );
  });
}
