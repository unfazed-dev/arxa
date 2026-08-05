// Regression guards for Notes navigation in the STANDALONE app.
//
// 1. Seamless auth gate: signed out, the Notes tab ROOT renders the auth
//    surface (ShowcaseNotesAuthView) — no gate card, no route push. A session
//    appearing swaps to the Folders list in place; a route transition here
//    reads as a visual "jump" and must not return.
// 2. Nested pushes: navigation between Notes children is the notes branch's
//    OWN concern. The original code navigated the ROOT router by absolute
//    path, which pushed a second ShowcaseApplicationShellView (booting at the Home tab)
//    and leaked a back button into every tab's chrome.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_view.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(); // deliberately NOT signed in — the gate is under test
  });

  tearDownAll(teardownShowcase);

  testWidgets('Notes tab root is the auth panel; sign-in swaps in place',
      (tester) async {
    final router = await bootShell(tester);

    // Land on the Notes tab by path — pins the standalone '/' mount.
    unawaited(router.navigateNamed('/notes'));
    await settle(tester);

    expect(find.byType(ShowcaseNotesAuthView), findsOneWidget,
        reason: 'signed out, the Notes tab root must BE the auth surface');
    expect(find.text('Sign in to use Notes'), findsNothing,
        reason: 'the tap-to-navigate gate card must not return — it causes '
            'a route-transition jump');

    await signInEvan();
    await settle(tester);

    expect(find.text('Folders'), findsOneWidget,
        reason: 'a session appearing must swap the auth panel for the '
            'Folders list in place — no push, no pop');
    expect(find.byType(ShowcaseNotesAuthView), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('All Notes push stays inside the notes branch (root untouched)',
      (tester) async {
    await signInEvan(); // independent of the previous test's end state
    final router = await bootShell(tester);

    unawaited(router.navigateNamed('/notes'));
    await settle(tester);
    expect(find.text('All Notes'), findsOneWidget);

    await tester.tap(find.text('All Notes'));
    await settle(tester);

    expect(find.byType(ShowcaseNotesFolderView), findsOneWidget,
        reason: 'tapping All Notes must open the folder view');
    expect(find.byType(ShowcaseApplicationShellView), findsOneWidget,
        reason: 'the push must stay inside the notes branch — a second shell '
            'instance means it landed on the root stack');
    // ignoreChildRoutes: plain canPop() includes nested routers, and the
    // notes branch legitimately CAN pop here — only the root's own stack
    // must stay at one entry.
    expect(router.canPop(ignoreChildRoutes: true), isFalse,
        reason: 'the ROOT stack must be untouched by notes-child navigation; '
            'a root-stack entry is what leaks a back button into every '
            "tab's chrome");
  }, timeout: const Timeout(Duration(minutes: 2)));
}
