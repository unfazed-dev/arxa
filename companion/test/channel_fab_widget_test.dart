import 'package:app_box_companion/channel/channel_state.dart';
import 'package:app_box_companion/widgets/channel_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_config.dart';

/// The FAB must render the channel state — never infer it from the WebView.
/// These tests pin the visual per state so a regression (e.g. the FAB showing
/// green while the channel is dead) fails loudly.
void main() {
  final config = testConfig();

  Future<void> pumpFab(
    WidgetTester tester,
    ChannelState state, {
    ValueNotifier<Offset>? position,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: const Key('fab-host'),
            width: 390,
            height: 844,
            child: ChannelFab(
              state: state,
              config: config,
              positionNotifier: position,
            ),
          ),
        ),
      ),
    );
    // One frame is enough to lay out; deliberately NOT pumpAndSettle — the
    // reconnecting state animates an indeterminate spinner forever, which
    // pumpAndSettle would reject as a never-settling animation.
    await tester.pump();
  }

  testWidgets('LIVE renders the live icon', (tester) async {
    await pumpFab(tester, ChannelState.live);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  testWidgets('RECONNECTING renders the reconnecting spinner', (tester) async {
    await pumpFab(tester, ChannelState.reconnecting);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('DEAD renders the warning and no spinner (the FAB truth)',
      (tester) async {
    await pumpFab(tester, ChannelState.dead);
    expect(find.byIcon(Icons.warning), findsOneWidget);
    // No spinner when dead — it is not "trying", it is gone.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('drag clamps above the home-indicator keepout (12.10)',
      (tester) async {
    final position = ValueNotifier<Offset>(Offset.zero);
    await pumpFab(tester, ChannelState.live, position: position);

    await tester.timedDrag(
      find.byIcon(Icons.bolt),
      const Offset(0, 5000),
      const Duration(milliseconds: 100),
    );
    await tester.pump();

    final body = tester.getSize(find.byKey(const Key('fab-host')));
    expect(
      position.value.dy,
      lessThanOrEqualTo(
          body.height - 28.0 /* radius */ - config.fabHomeIndicatorKeepout),
      reason: 'FAB must never park over the home indicator',
    );
  });

  testWidgets('drag snaps to a horizontal edge (edge-dock, 12.10)',
      (tester) async {
    final position = ValueNotifier<Offset>(Offset.zero);
    await pumpFab(tester, ChannelState.live, position: position);

    // Drag toward the left edge, release — it should dock left.
    await tester.timedDrag(
      find.byIcon(Icons.bolt),
      const Offset(-400, 0),
      const Duration(milliseconds: 100),
    );
    await tester.pump();

    final body = tester.getSize(find.byKey(const Key('fab-host')));
    final leftDock = 28.0 + config.fabEdgeDockInset;
    final rightDock = body.width - 28.0 - config.fabEdgeDockInset;
    final nearerLeft = (position.value.dx - leftDock).abs() <
        (position.value.dx - rightDock).abs();
    expect(nearerLeft, true, reason: 'must dock to the nearer edge');
  });
}
