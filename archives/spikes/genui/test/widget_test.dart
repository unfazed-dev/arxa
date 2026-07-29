import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui_spike/main.dart';

void main() {
  testWidgets('basic catalog surface renders text/card/button', (
    tester,
  ) async {
    await tester.pumpWidget(const SpikeApp());

    await tester.enterText(find.byKey(const Key('chat-input')), 'hello');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    expect(find.text('Pipeline summary (basic catalog)'), findsOneWidget);
    expect(find.text('Retry stage: freeze'), findsOneWidget);

    // Fire the button action and verify the round-trip reaches the transport
    // (visible in the on-screen event log).
    await tester.tap(find.text('Retry stage: freeze'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('ACTION round-trip received by transport'),
      findsOneWidget,
    );
    expect(find.textContaining('retry_stage'), findsWidgets);
  });

  testWidgets('custom BuildStageCard renders and DataModel write re-renders', (
    tester,
  ) async {
    await tester.pumpWidget(const SpikeApp());

    await tester.enterText(find.byKey(const Key('chat-input')), 'show stage');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('build-stage-card')), findsOneWidget);
    expect(find.text('freeze'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);

    // DataModel round-trip: "Mark done" writes through the DataContext and
    // the bound card re-renders with status=done.
    await tester.tap(find.byKey(const Key('mark-done-button')));
    await tester.pumpAndSettle();
    expect(find.text('done'), findsOneWidget);
  });
}
