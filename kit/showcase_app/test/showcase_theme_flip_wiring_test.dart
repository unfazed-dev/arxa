// Regression guard for the native-glass theme desync (device clips 08-11
// 11:29 and 19:57).
//
// Symptom: flip the in-app theme and Flutter-painted surfaces go light
// immediately while native glass — the "Glass CTA" pill, the split button —
// stays dark for what read as seconds, then snaps.
//
// Cause, measured rather than reasoned: `ThemeData.lerp` fades colours
// continuously but `brightness` is a STEP at t=0.5, and a native platform
// view's only appearance lever is a boolean `setBrightness`. So a theme
// ANIMATION is something half this UI cannot join. Probed on `CNButton`, one
// flip: with the default 200ms animation `setBrightness` reached the wire at
// 96ms and the widget fired 26 channel round-trips (the tint guard compares a
// lerping value, so every animation frame sent a fresh `setStyle`); with
// `Duration.zero`, 0ms and 5 round-trips. On device that per-frame storm is
// multiplied by every native widget on screen, which is why the stale window
// read as seconds rather than the ~100ms the step alone costs.
//
// This is a one-line property with no visible surface of its own, so nothing
// else in the suite would notice it being dropped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/main.dart' show ShowcaseApp;

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);

  testWidgets(
      'shell-demos.browse-the-application-shell — the app flips its '
      'theme instantly, so native glass and Flutter surfaces change together',
      (tester) async {
    await tester.pumpWidget(const ShowcaseApp());
    // One pump only: settling would run the startup view's post-frame boot.

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp).first);

    expect(app.themeAnimationDuration, Duration.zero,
        reason: 'a non-zero theme animation desyncs the two halves of this UI: '
            'ThemeData.lerp steps `brightness` at t=0.5, so every native '
            'platform view holds its old appearance for half the duration '
            'while Flutter surfaces cross-fade immediately');

    // Anti-vacuous: the property is only meaningful if both themes exist and
    // actually differ in brightness — otherwise there is no flip to desync.
    expect(app.theme?.brightness, Brightness.light);
    expect(app.darkTheme?.brightness, Brightness.dark);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
