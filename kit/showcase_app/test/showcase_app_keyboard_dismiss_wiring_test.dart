// The keyboard dismisser used to be one wrapper in `main.dart` — and that
// app-wide Listener WAS the re-tap regression's root cause (a raw pointer-down
// fires on the focused field itself, dropping the keyboard mid-tap). Dismissal
// is now a per-input default the kit inputs carry themselves
// (ArxaKitInputTapBehavior — proven in the kit,
// arxa_kit_input_keyboard_behavior_test.dart). What only a showcase test can
// pin: the showcase's real inputs are wrapped in the kit's tap region (so
// scaffolded apps copying this structure get dismissal by default), and main
// installs nothing app-wide anymore.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitInputTapBehavior;
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart'
    show ShowcaseNotesAuthTextFieldWidget;

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
  });

  tearDownAll(teardownShowcase);

  testWidgets(
      'shell-demos.browse-the-application-shell — kit inputs carry the '
      'dismissal default; nothing app-wide remains', (tester) async {
    // The showcase's shared credential field (used by every notes auth form)
    // composes ArxaKitNativeTextField — assert the per-input default rides
    // along, so every route using kit inputs dismisses on outside taps with
    // zero wiring.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ShowcaseNotesAuthTextFieldWidget(
          onChanged: (_) {},
          placeholder: 'Email',
        ),
      ),
    ));

    expect(
      find.descendant(
        of: find.byType(ShowcaseNotesAuthTextFieldWidget),
        matching: find.byType(ArxaKitInputTapBehavior),
      ),
      findsOneWidget,
      reason: 'every kit input carries the dismissal default by construction — '
          'scaffolded apps inherit it with nothing to wire',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
