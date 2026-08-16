// The showcase's brand accent: the app root wires the authored 'moss' swatch
// (theme.json SSOT, mirrored in appbox_kit_core) into BOTH theme constructors,
// instead of the kit-default studio violet (AppBoxKitColors.accent).
//
// This is a one-line property with no visible surface of its own (the accent
// reaches every chrome surface through Theme.of(context).colorScheme), so
// nothing else in the suite would notice it being dropped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/main.dart' show ShowcaseApp;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitColors, appBoxKitAccentByName;

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);

  testWidgets(
      'shell-demos.home-and-application-shells.browse-the-application-shell — '
      'the app wears the moss accent in both modes, not the studio violet '
      'default', (tester) async {
    await tester.pumpWidget(const ShowcaseApp());
    // One pump only: settling would run the startup view's post-frame boot.

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp).first);

    final moss = appBoxKitAccentByName('moss');
    expect(app.theme?.colorScheme.primary, moss.light.accent,
        reason: 'light mode must carry the moss swatch light accent');
    expect(app.darkTheme?.colorScheme.primary, moss.dark.accent,
        reason: 'dark mode must carry the moss swatch dark accent');

    // Anti-vacuous: moss must actually differ from the kit-default violet the
    // theme constructors fall back to, or the assertions above prove nothing.
    expect(moss.light.accent, isNot(AppBoxKitColors.accent));
    expect(moss.dark.accent, isNot(AppBoxKitColors.accent));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
