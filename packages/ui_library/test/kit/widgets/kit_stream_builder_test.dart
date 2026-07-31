import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';
import 'package:ui_library/widgets/kit_stream_builder.dart';

import 'native_test_helpers.dart';

void main() {
  testWidgets(
    'BehaviorSubject seeds the first frame synchronously (no loading flash)',
    (tester) async {
      final subject = BehaviorSubject<int>.seeded(1);
      addTearDown(subject.close);

      await tester.pumpWidget(
        host(
          KitStreamBuilder<int>(
            stream: subject,
            builder: (context, data) => Text('value: $data'),
          ),
        ),
      );

      expect(
        find.text('value: 1'),
        findsOneWidget,
        reason:
            'ValueStream initialData should resolve before the first pump, '
            'skipping the loading state entirely.',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('plain StreamController shows loading then data',
      (tester) async {
      final controller = StreamController<int>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        host(
          KitStreamBuilder<int>(
            stream: controller.stream,
            builder: (context, data) => Text('value: $data'),
          ),
        ),
      );

      expect(
        find.text('value: 1'),
        findsNothing,
        reason: 'A cold, un-seeded stream has no initial data yet.',
      );

      controller.add(1);
      await tester.pump();

      expect(find.text('value: 1'), findsOneWidget);
    },
  );

  testWidgets('error path renders errorBuilder', (tester) async {
    final controller = StreamController<int>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      host(
        KitStreamBuilder<int>(
          stream: controller.stream,
          builder: (context, data) => Text('value: $data'),
          errorBuilder: (context, error) => Text('error: $error'),
        ),
      ),
    );

    controller.addError('boom');
    await tester.pump();

    expect(
      find.text('error: boom'),
      findsOneWidget,
      reason: 'Stream errors should route through errorBuilder.',
    );
  });
}
