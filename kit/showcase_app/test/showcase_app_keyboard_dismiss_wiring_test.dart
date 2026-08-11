// The app-wide keyboard dismisser is one line in `main.dart`, and every other
// showcase test boots through `bootShell`, which pumps `MaterialApp.router`
// directly and never builds `ShowcaseApp`. So nothing covered the wiring that
// makes "tap out anywhere to dismiss" true for every shell and view — delete
// that line and the whole suite stayed green.
//
// The behaviour itself is proven in the kit
// (`appbox_kit_dismiss_keyboard_test.dart`: tap-outside, drag-to-dismiss, the
// tap is not swallowed, and the native CNTextField tier is reached). This test
// asserts only the thing that file cannot: that the showcase actually installs
// it, above the router, so it covers every route.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/main.dart' show ShowcaseApp;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitDismissKeyboard;

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);

  testWidgets('shell-demos.browse-the-application-shell — the app installs the '
      'keyboard dismisser above its router', (tester) async {
    await tester.pumpWidget(const ShowcaseApp());
    // One pump only: settling would run the startup view's post-frame boot.

    final Finder dismisser = find.byType(AppBoxKitDismissKeyboard);
    expect(dismisser, findsOneWidget,
        reason: 'without this every shell and view loses tap-to-dismiss');

    expect(
      find.descendant(of: dismisser, matching: find.byType(MaterialApp)),
      findsOneWidget,
      reason: 'it must sit ABOVE the router — installed underneath, it would '
          'cover only whatever route happened to build it',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
