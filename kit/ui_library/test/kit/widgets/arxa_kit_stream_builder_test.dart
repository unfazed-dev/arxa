import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_stream_builder.dart';

import 'arxa_kit_native_test_helpers.dart';

void main() {
  testWidgets(
    'kit.ui-library.stream-builder — BehaviorSubject seeds the first frame synchronously (no loading flash)',
    (tester) async {
      final subject = BehaviorSubject<int>.seeded(1);
      addTearDown(subject.close);

      await tester.pumpWidget(
        host(
          ArxaKitStreamBuilder<int>(
            stream: subject,
            builder: (context, data) => Text('value: $data'),
          ),
        ),
      );

      expect(
        find.text('value: 1'),
        findsOneWidget,
        reason: 'ValueStream initialData should resolve before the first pump, '
            'skipping the loading state entirely.',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'kit.ui-library.stream-builder — plain StreamController shows loading then data',
    (tester) async {
      final controller = StreamController<int>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        host(
          ArxaKitStreamBuilder<int>(
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

  testWidgets('kit.ui-library.stream-builder — error path renders errorBuilder',
      (tester) async {
    final controller = StreamController<int>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      host(
        ArxaKitStreamBuilder<int>(
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

  testWidgets(
      'kit.ui-library.stream-builder — nullable stream: emitted null reaches the builder, no spinner',
      (tester) async {
    final subject = BehaviorSubject<String?>.seeded(null);
    addTearDown(subject.close);

    await tester.pumpWidget(
      host(
        ArxaKitStreamBuilder<String?>(
          stream: subject,
          builder: (context, data) => Text('data: ${data ?? "null"}'),
        ),
      ),
    );

    expect(
      find.text('data: null'),
      findsOneWidget,
      reason:
          'Role-gated streams emit null on purpose — null is a value, not a '
          'loading state.',
    );

    subject.add('admin');
    await tester.pump();
    expect(find.text('data: admin'), findsOneWidget);
  });
}
