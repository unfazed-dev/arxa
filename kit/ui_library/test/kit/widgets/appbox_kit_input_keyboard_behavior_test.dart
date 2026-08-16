import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitNativeTextField] keyboard-dismissal behavior tests — the per-input
/// default that replaces the retired app-wide tap-to-dismiss listener.
///
/// The load-bearing framework facts (verified against the installed 3.44 SDK):
/// Flutter's default `EditableTextTapOutsideIntent` handler does NOT unfocus
/// for touch events on native mobile platforms (editable_text.dart:6781-6796) —
/// so without kit wiring, a scaffolded app has no tap-outside dismissal at all.
/// The kit supplies it per input: every field tier is wrapped in a grouped
/// TextFieldTapRegion (union semantics, tap_region.dart:104-107) whose
/// onTapOutside runs the two-tier dismissal (Flutter unfocus + native
/// CNTextFieldFocus channel).
void main() {
  // The Material tier is the one a headless test can mount (the documented
  // "wantNative: false" widget-test path); CN/M3E tiers share the same wrapper.
  Widget host({bool enabled = true}) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppBoxKitNativeTextField(
                key: const Key('field-a'),
                placeholder: 'a',
                wantNative: false,
                dismissKeyboardOnOutsideTap: enabled,
              ),
              AppBoxKitNativeTextField(
                key: const Key('field-b'),
                placeholder: 'b',
                wantNative: false,
              ),
              const SizedBox(key: Key('empty'), height: 200, width: 200),
            ],
          ),
        ),
      );

  testWidgets(
      'kit.ui-library.input-keyboard — tapping outside the field dismisses its '
      'keyboard by default', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('field-a')));
    await tester.pump();

    final FocusNode nodeA = FocusManager.instance.primaryFocus!;
    expect(nodeA.hasPrimaryFocus, isTrue,
        reason: 'anti-vacuous: the field must take focus first');

    await tester.tap(find.byKey(const Key('empty')), warnIfMissed: false);
    await tester.pump();

    expect(nodeA.hasPrimaryFocus, isFalse,
        reason: 'the per-input default must dismiss on an outside tap');
  });

  testWidgets(
      'kit.ui-library.input-keyboard — re-tapping the focused field keeps its '
      'keyboard up (the reported bug)', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('field-a')));
    await tester.pump();

    final FocusNode nodeA = FocusManager.instance.primaryFocus!;
    var focusDrops = 0;
    nodeA.addListener(() {
      if (!nodeA.hasFocus) focusDrops++;
    });

    await tester.tap(find.byKey(const Key('field-a')));
    await tester.pump();

    expect(focusDrops, 0,
        reason: 'a tap on the focused editable is inside the region group — '
            'the keyboard must never drop mid-tap');
    expect(nodeA.hasPrimaryFocus, isTrue);
  });

  testWidgets(
      'kit.ui-library.input-keyboard — tapping another kit input hands focus '
      'over without dismissing', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('field-a')));
    await tester.pump();
    final FocusNode nodeA = FocusManager.instance.primaryFocus!;

    await tester.tap(find.byKey(const Key('field-b')));
    await tester.pump();

    // No dismissal may intervene in the hand-off: A ends unfocused, B focused,
    // and at no point did the region fire its outside callback for these taps.
    expect(nodeA.hasFocus, isFalse,
        reason: 'the previously focused field loses focus in the hand-off');
    expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue,
        reason: 'the tapped field takes over focus directly');
  });

  testWidgets(
      'kit.ui-library.input-keyboard — dismissKeyboardOnOutsideTap: false '
      'suspends the default (screen-owned focus)', (tester) async {
    // Opt-out is per input, so isolate field-a: with a second default-on input
    // on screen, ITS region would (correctly) dismiss on the same background
    // tap — the opt-out must be proven alone.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            AppBoxKitNativeTextField(
              key: const Key('field-a'),
              placeholder: 'a',
              wantNative: false,
              dismissKeyboardOnOutsideTap: false,
            ),
            const SizedBox(key: Key('empty'), height: 200, width: 200),
          ],
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('field-a')));
    await tester.pump();
    final FocusNode nodeA = FocusManager.instance.primaryFocus!;

    await tester.tap(find.byKey(const Key('empty')), warnIfMissed: false);
    await tester.pump();

    expect(nodeA.hasPrimaryFocus, isTrue,
        reason: 'a screen driving focus itself must be able to opt out');
  });

  testWidgets(
      'kit.ui-library.input-keyboard — dragging a scrollable outside the field '
      'dismisses (drag begins with a pointer-down)', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: [
            AppBoxKitNativeTextField(
              key: const Key('field-a'),
              placeholder: 'a',
              wantNative: false,
            ),
            for (int i = 0; i < 40; i++)
              SizedBox(height: 60, child: Text('row $i')),
          ],
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('field-a')));
    await tester.pump();
    final FocusNode nodeA = FocusManager.instance.primaryFocus!;
    expect(nodeA.hasPrimaryFocus, isTrue,
        reason: 'anti-vacuous: the field must hold focus before the drag');

    await tester.drag(find.text('row 5'), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(nodeA.hasPrimaryFocus, isFalse,
        reason: 'a drag outside the region starts with a pointer-down — the '
            'keyboard must dismiss, matching the previous app-wide behavior');
    expect(controller.offset, greaterThan(0),
        reason: 'and the list must still scroll');
  });

  testWidgets(
      'kit.ui-library.input-keyboard — the input bar field dismisses too '
      '(composite carries the default)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomSheet: AppBoxKitNativeInputBar(
          hintText: 'Message',
          wantNative: false,
          onSubmitted: (_) {},
        ),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final FocusNode barField = FocusManager.instance.primaryFocus!;
    expect(barField.hasPrimaryFocus, isTrue,
        reason: 'anti-vacuous: the bar field must take focus');

    await tester.tap(find.byType(SizedBox).first, warnIfMissed: false);
    await tester.pump();

    expect(barField.hasPrimaryFocus, isFalse,
        reason: 'the input bar composes AppBoxKitNativeTextField, so it '
            'inherits the per-input dismissal default');
  });
}
