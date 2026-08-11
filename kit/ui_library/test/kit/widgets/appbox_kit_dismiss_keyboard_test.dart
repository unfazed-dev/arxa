import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTextFieldFocus;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_dismiss_keyboard.dart';

/// [AppBoxKitDismissKeyboard] tests.
///
/// The load-bearing fact behind this widget: a `CNTextField` is a platform view
/// with no [FocusNode], so `FocusManager.instance.primaryFocus?.unfocus()` —
/// what every published tap-to-dismiss recipe does — cannot close the keyboard
/// it raised. The widget therefore fires both paths.
void main() {
  tearDown(CNTextFieldFocus.debugReset);

  Widget host({VoidCallback? onButton}) => MaterialApp(
        home: AppBoxKitDismissKeyboard(
          child: Scaffold(
            body: Column(
              children: [
                const TextField(key: Key('field')),
                ElevatedButton(
                  key: const Key('button'),
                  onPressed: onButton,
                  child: const Text('press me'),
                ),
                const SizedBox(key: Key('empty'), height: 200, width: 200),
              ],
            ),
          ),
        ),
      );

  testWidgets('kit.ui-library.dismiss-keyboard — a tap outside the field drops its focus',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();

    final FocusNode fieldNode = FocusManager.instance.primaryFocus!;
    expect(fieldNode.hasPrimaryFocus, isTrue,
        reason: 'anti-vacuous: the field must actually take focus first');

    await tester.tap(find.byKey(const Key('empty')));
    await tester.pump();

    expect(fieldNode.hasPrimaryFocus, isFalse,
        reason: 'a pointer-down anywhere outside must drop the field focus');
  });

  testWidgets('kit.ui-library.dismiss-keyboard — does not swallow the tap it dismisses on',
      (tester) async {
    // The reason this is a Listener and not a GestureDetector: a detector
    // competes in the gesture arena and an ancestor that wins it eats the tap.
    var pressed = 0;
    await tester.pumpWidget(host(onButton: () => pressed++));
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    final FocusNode fieldNode = FocusManager.instance.primaryFocus!;

    await tester.tap(find.byKey(const Key('button')));
    await tester.pump();

    expect(pressed, 1,
        reason: 'the button under the finger must still fire — dismissing the '
            'keyboard must never cost the user their tap');
    expect(fieldNode.hasPrimaryFocus, isFalse,
        reason: 'and the field still loses focus on that same tap');
  });

  testWidgets('kit.ui-library.dismiss-keyboard — enabled: false suspends dismissal',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppBoxKitDismissKeyboard(
        enabled: false,
        child: const Scaffold(
          body: Column(
            children: [
              TextField(key: Key('field')),
              SizedBox(key: Key('empty'), height: 200, width: 200),
            ],
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    final FocusNode fieldNode = FocusManager.instance.primaryFocus!;

    await tester.tap(find.byKey(const Key('empty')));
    await tester.pump();

    expect(fieldNode.hasPrimaryFocus, isTrue,
        reason: 'a screen driving focus itself must be able to opt out');
  });

  testWidgets('kit.ui-library.dismiss-keyboard — also dismisses the native tier, which has no FocusNode',
      (tester) async {
    // The whole point of the widget. A CNTextField cannot be mounted headless
    // (UiKitView), so the native side is stood in for by its channel: this
    // asserts the dismisser reaches CNTextFieldFocus at all, which is the step
    // every stock recipe omits and which no FocusNode assertion can observe.
    const MethodChannel channel = MethodChannel('CNTextField_test');
    final List<String> calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    CNTextFieldFocus.debugSetCurrent(channel);
    expect(CNTextFieldFocus.hasFocus, isTrue,
        reason: 'anti-vacuous: something must be focused to dismiss');

    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('empty')));
    await tester.pump();

    expect(calls, contains('unfocus'),
        reason: 'the native field holds the keyboard and no FocusNode; only '
            'its own channel can close it');
    expect(CNTextFieldFocus.hasFocus, isFalse);
  });
}
