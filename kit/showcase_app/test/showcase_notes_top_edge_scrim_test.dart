// Gate: the signed-out Notes branches keep their top-edge scrim.
//
// The two auth branches are deliberately BAR-LESS Scaffolds — no floating
// chrome, so nothing carries the status-bar dissolve for them and their hero
// heading garbles with the clock / Dynamic Island. Each one therefore mounts
// ArxaKitTopEdgeScrim itself.
//
// This is a SOURCE scan, in the same idiom as the kit's liquid-glass law
// gate, and it is honest about what it proves: that the wiring is still
// present at both call sites, not that it renders correctly. Pumping the view
// for real needs the auth/session/router service stack; the visual contract
// (ramp geometry, opacity, pointer transparency) is pinned where the widget
// lives, in arxa_kit_native_floating_bar_test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'showcase.notes.top-edge-scrim — both signed-out branches still mount '
      'the scrim, with a ramp sized to their own content inset', () {
    final file = File('lib/ui/views/showcase_notes_shell/showcase_notes/'
        'showcase_notes_view.mobile.dart');
    expect(file.existsSync(), isTrue,
        reason: 'run from the showcase_app package root');
    final src = file.readAsStringSync();

    // Two branches: the create-account panel and the sign-in panel.
    expect(
      RegExp(r'ArxaKitTopEdgeScrim\(').allMatches(src).length,
      2,
      reason: 'the auth and create-account branches are both bar-less and '
          'both need the scrim — losing one silently restores the '
          'Dynamic-Island garbling on that branch only',
    );

    // The ramp must NOT be left at the default bar-block extent here. These
    // panels rest their hero 24pt down, so a 52pt ramp would lay a ~54%
    // background wash over a heading that never scrolls — trading a garbling
    // bug for a washed-out one.
    expect(
      RegExp(r'ArxaKitTopEdgeScrim\(fadeExtent: abxSize24\)')
          .allMatches(src)
          .length,
      2,
      reason: 'a bar-less host must size the ramp to its own top inset',
    );
  });
}
