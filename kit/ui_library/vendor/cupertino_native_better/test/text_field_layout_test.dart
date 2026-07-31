import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'CNTextField survives unbounded height (Column in SingleChildScrollView)',
      (tester) async {
    // Regression: the bare UiKitView (and its pre-creation SizedBox.expand
    // placeholder) sized to constraints.biggest → infinite height →
    // "RenderConstrainedBox object was given an infinite size during layout".
    // CNTextField must own a bounded height like CNSearchBar does.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [CNTextField(placeholder: 'Email')],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(CNTextField));
    expect(size.height.isFinite, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });
}
