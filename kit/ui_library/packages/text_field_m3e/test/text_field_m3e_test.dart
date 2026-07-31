import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_field_m3e/text_field_m3e.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

BoxDecoration _decorationOf(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer).first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('renders placeholder and accepts input', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _wrap(TextFieldM3E(controller: controller, placeholder: 'Email')),
    );
    expect(find.text('Email'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hi@example.com');
    expect(controller.text, 'hi@example.com');
  });

  testWidgets('morphs corner radius on focus and back on unfocus',
      (tester) async {
    await tester.pumpWidget(_wrap(const TextFieldM3E(placeholder: 'Email')));

    final resting = _decorationOf(tester).borderRadius as BorderRadius;
    expect(
      resting.topLeft.x,
      TextFieldM3ESize.md.outerRoundRadius,
      reason: 'round md resting radius',
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final focused = _decorationOf(tester).borderRadius as BorderRadius;
    expect(focused.topLeft.x, TextFieldM3ESize.md.focusedRadius);
    expect(_decorationOf(tester).border, isNotNull,
        reason: 'focus ring visible');

    // Unfocus → morph back.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final restored = _decorationOf(tester).borderRadius as BorderRadius;
    expect(restored.topLeft.x, TextFieldM3ESize.md.outerRoundRadius);
  });

  testWidgets('square shape uses square resting radius', (tester) async {
    await tester.pumpWidget(
      _wrap(const TextFieldM3E(shape: TextFieldM3EShape.square)),
    );
    final resting = _decorationOf(tester).borderRadius as BorderRadius;
    expect(resting.topLeft.x, TextFieldM3ESize.md.outerSquareRadius);
  });

  testWidgets('sizes map to token heights', (tester) async {
    for (final size in TextFieldM3ESize.values) {
      await tester.pumpWidget(_wrap(TextFieldM3E(size: size)));
      // The state is reused across loop iterations, so the implicit height
      // animation must settle before measuring.
      await tester.pumpAndSettle();
      final box = tester.getSize(find.byType(AnimatedContainer).first);
      expect(box.height, size.height, reason: 'height for $size');
    }
  });

  testWidgets('error state shows supporting text and error border',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const TextFieldM3E(errorText: 'Required field')),
    );
    expect(find.text('Required field'), findsOneWidget);
    final deco = _decorationOf(tester);
    expect(deco.border, isNotNull);
    final theme = ThemeData();
    expect(
      (deco.border! as Border).top.color,
      theme.colorScheme.error,
    );
  });

  testWidgets('disabled field ignores input', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _wrap(TextFieldM3E(controller: controller, enabled: false)),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('external focus node is respected and not disposed',
      (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(_wrap(TextFieldM3E(focusNode: node)));
    node.requestFocus();
    await tester.pumpAndSettle();
    final focused = _decorationOf(tester).borderRadius as BorderRadius;
    expect(focused.topLeft.x, TextFieldM3ESize.md.focusedRadius);

    // Unmount: the external node must survive (not disposed by the widget)
    // and remain usable.
    await tester.pumpWidget(_wrap(const SizedBox()));
    await tester.pumpWidget(_wrap(TextFieldM3E(focusNode: node)));
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
  });

  testWidgets('leading icon and trailing widget render', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TextFieldM3E(
          leadingIcon: Icons.search,
          trailing: Icon(Icons.clear),
        ),
      ),
    );
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);
  });
}
