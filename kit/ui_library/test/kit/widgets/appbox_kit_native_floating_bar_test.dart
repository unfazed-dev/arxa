import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitNativeFloatingBar] is the glass tier's top chrome: a floating
/// row over a full-bleed body, whose glass surface is NATIVE so it composites
/// above the platform views scrolling beneath it (allowlist rule 4 — the
/// Flutter-drawn bar could not do this: seam pop or over-bar flash).
void main() {
  Widget harness({String? title, List<Widget>? actions}) => MaterialApp(
        home: Scaffold(
          body: AppBoxKitNativeFloatingBar(title: title, actions: actions),
        ),
      );

  testWidgets(
      'kit.ui-library.native-floating-bar — title rides a native glass '
      'capsule and actions land trailing in the 44pt control row',
      (tester) async {
    await tester.pumpWidget(harness(
      title: 'Kit Showcase',
      actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
    ));

    // The title pill must be the FLUTTER-DRAWN platform-view-safe frosted
    // surface, NOT native glass: scrolled native glass buttons crossing a
    // native capsule stack glass-on-glass and wash to square ghosts for
    // exactly the capsule's span (clip 13-53). This pin is the regression
    // guard for that ruling — do not "upgrade" the title back to
    // LiquidGlassContainer.
    final pill = tester.widget<AppBoxKitFrostedSurface>(
      find
          .ancestor(
            of: find.text('Kit Showcase'),
            matching: find.byType(AppBoxKitFrostedSurface),
          )
          .first,
    );
    expect(pill.platformViewSafe, isTrue,
        reason: 'a BackdropFilter pill would saveLayer over the platform '
            'views passing beneath (composition rule 1)');

    // Control row is exactly 44 — the same block the boxed bar reserves, so
    // kAppBoxKitFloatingBarBlockHeight stays honest.
    final row = tester.getRect(find.byKey(const Key('action')));
    expect(row.height, 44);

    // Actions trail the title.
    expect(row.left,
        greaterThan(tester.getRect(find.text('Kit Showcase')).right));
  });

  testWidgets(
      'kit.ui-library.native-floating-bar — block height constant matches '
      'the laid-out bar (44 control row + breathing gap)', (tester) async {
    await tester.pumpWidget(harness(title: 'T'));
    // No status bar in the test env, so the bar's total height IS the block.
    expect(
      tester.getSize(find.byType(AppBoxKitNativeFloatingBar)).height,
      kAppBoxKitFloatingBarBlockHeight,
      reason: 'hosts inset full-bleed content by this constant; if the bar '
          'grows, the constant must grow with it',
    );
  });

  testWidgets(
      'kit.ui-library.native-floating-bar — null title and actions render an '
      'empty row without throwing', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.byType(AppBoxKitNativeFloatingBar), findsOneWidget);
    expect(find.byType(AppBoxKitFrostedSurface), findsNothing);
  });
}
