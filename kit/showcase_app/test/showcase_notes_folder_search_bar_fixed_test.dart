// Regression guard for the folder view's search chrome (device report
// 2026-08-17: "when scrolling the search bar moves — it must not").
//
// The bar used to ride INSIDE the CustomScrollView as a pinned
// SliverPersistentHeader with minExtent 56 < maxExtent 72 — the first 16px
// of scroll shrank the header, sliding/squeezing the native glass bar, and a
// UiKitView in a scrollable is out of the vendored contract (jitter/clips
// against sliver-culled rows). The bar is now FIXED chrome above the list:
// its geometry must be scroll-invariant.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitNativeSearchBar;
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);

  testWidgets(
      'search-and-attachments.search.search-notes-by-text — the search bar '
      'is fixed chrome: scrolling the note list does not move or reshape it',
      (tester) async {
    final router = await bootShell(tester);
    // Shorten the surface so the seeded All Notes list definitely overflows —
    // the scroll below must be real, not a no-op on a non-scrollable list.
    tester.view.physicalSize = const Size(1170, 1500); // 390×500 logical

    unawaited(router.navigateNamed('/notes'));
    await settle(tester);
    await tester.tap(find.text('All Notes'));
    await settle(tester);
    expect(find.byType(ShowcaseNotesFolderView), findsOneWidget,
        reason: 'anti-vacuous: the folder view must be on screen');

    final searchBar = find.byType(ArxaKitNativeSearchBar);
    expect(searchBar, findsOneWidget,
        reason: 'anti-vacuous: the search bar must be on screen');

    final listView = find.descendant(
      of: find.byType(ShowcaseNotesFolderView),
      matching: find.byType(CustomScrollView),
    );
    expect(listView, findsOneWidget);
    // The outer Scrollable owns the list's scroll position (a nested inner
    // Scrollable exists deeper in the sliver tree — DFS hits the outer first).
    final outerScrollable = find
        .descendant(of: listView, matching: find.byType(Scrollable))
        .first;

    final before = tester.getRect(searchBar);

    await tester.drag(listView, const Offset(0, -250));
    await settle(tester);

    final pixels =
        tester.state<ScrollableState>(outerScrollable).position.pixels;
    expect(pixels, greaterThan(0),
        reason: 'anti-vacuous: the list must actually have scrolled, or the '
            'geometry comparison below proves nothing');

    final after = tester.getRect(searchBar);
    expect(after.top, before.top,
        reason: 'fixed chrome: the bar must not slide with the scroll');
    expect(after.height, before.height,
        reason: 'fixed chrome: the bar must not shrink/squeeze on scroll '
            '(the pinned-sliver min<max extent defect)');
    expect(tester.takeException(), isNull,
        reason: 'a squeezed fixed bar overflowed its slot on scroll');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
