import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTextFieldFocus;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_input_tap_behavior.dart';

/// `arxaKitDismissKeyboard` tests — the two-tier dismissal function the
/// per-input tap region calls.
///
/// The load-bearing fact: a `CNTextField` is a platform view with no
/// [FocusNode], so `FocusManager.instance.primaryFocus?.unfocus()` — what
/// every published tap-to-dismiss recipe does — cannot close the keyboard it
/// raised. The function therefore fires both paths.
///
/// The app-wide Listener wrapper these tests used to cover is retired (the
/// re-tap regression); the per-input behavior contracts live in
/// arxa_kit_input_keyboard_behavior_test.dart.
void main() {
  tearDown(CNTextFieldFocus.debugReset);

  testWidgets(
      'kit.ui-library.input-keyboard — dismisses the Flutter tier by '
      'unfocusing the primary focus', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(key: Key('field'))),
    ));
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    final FocusNode node = FocusManager.instance.primaryFocus!;
    expect(node.hasPrimaryFocus, isTrue,
        reason: 'anti-vacuous: the field must hold focus first');

    arxaKitDismissKeyboard();
    await tester.pump();

    expect(node.hasPrimaryFocus, isFalse,
        reason: 'the Flutter tier dismissal is the primary-focus unfocus');
  });

  testWidgets(
      'kit.ui-library.input-keyboard — also dismisses the native tier, '
      'which has no FocusNode', (tester) async {
    // A CNTextField cannot be mounted headless (UiKitView), so the native side
    // is stood in for by its channel: this asserts the dismisser reaches
    // CNTextFieldFocus at all — the step every stock recipe omits.
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

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Container()),
    ));
    arxaKitDismissKeyboard();
    await tester.pump();

    expect(calls, contains('unfocus'),
        reason: 'the native field holds the keyboard and no FocusNode; only '
            'its own channel can close it');
    expect(CNTextFieldFocus.hasFocus, isFalse);
  });

  testWidgets(
      'kit.ui-library.input-keyboard — safe no-op when nothing is '
      'focused on either tier', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Container()),
    ));
    // No editable focused, no native channel: must not throw. (It DOES
    // unfocus the navigator scope — unfocus walks scopes — which is benign:
    // the retired app-wide listener did exactly that on every background tap.)
    arxaKitDismissKeyboard();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>(),
        reason: 'no editable gained or lost anything; only the scope settled');
  });
}
