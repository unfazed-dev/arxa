import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitChromeScaffold] is the liquid-glass law's reuse unit: hosts get
/// the ratified chrome from one widget, tier branch inside. These pins are
/// the law's guard against hand-assembly drifting back in.
void main() {
  Widget harness({bool? forceGlass, AppBoxKitFloatingBarBehavior? behavior}) =>
      MaterialApp(
        home: AppBoxKitChromeScaffold(
          debugForceGlassTier: forceGlass,
          behavior: behavior ?? AppBoxKitFloatingBarBehavior.minimize,
          title: 'Kit Showcase',
          actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
          floatingActionButton:
              const SizedBox(key: Key('fab'), width: 56, height: 56),
          body: const SizedBox(key: Key('body')),
        ),
      );

  testWidgets(
      'kit.ui-library.chrome-scaffold — boxed tiers get Scaffold.appBar with '
      'the native bar and an unwrapped body', (tester) async {
    // Test env is a boxed tier (no Liquid Glass) — the default branch.
    await tester.pumpWidget(harness());
    expect(find.byType(AppBoxKitNativeAppBar), findsOneWidget);
    expect(find.byType(AppBoxKitFloatingChrome), findsNothing,
        reason: 'boxed tiers must not stack the floating chrome');
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).appBar, isNotNull);
    expect(find.byKey(const Key('fab')), findsOneWidget);
  });

  testWidgets(
      'kit.ui-library.chrome-scaffold — glass tier drops Scaffold.appBar and '
      'wraps the body in floating chrome with the behavior forwarded',
      (tester) async {
    await tester.pumpWidget(harness(
        forceGlass: true, behavior: AppBoxKitFloatingBarBehavior.hide));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).appBar, isNull,
        reason: 'a boxed bar over full-bleed native glass is the exact '
            'arrangement the law forbids (rule 4)');
    final chrome = tester.widget<AppBoxKitFloatingChrome>(
        find.byType(AppBoxKitFloatingChrome));
    expect(chrome.behavior, AppBoxKitFloatingBarBehavior.hide);
    expect(chrome.title, 'Kit Showcase');
    expect(find.byType(AppBoxKitNativeAppBar), findsNothing);
    expect(
      find.descendant(
          of: find.byType(AppBoxKitFloatingChrome),
          matching: find.byKey(const Key('body'))),
      findsOneWidget,
    );
    expect(find.byKey(const Key('fab')), findsOneWidget);
  });

  testWidgets(
      'kit.ui-library.chrome-scaffold — glass default behavior is the '
      'ratified full minimize', (tester) async {
    await tester.pumpWidget(harness(forceGlass: true));
    expect(
      tester
          .widget<AppBoxKitFloatingChrome>(
              find.byType(AppBoxKitFloatingChrome))
          .behavior,
      AppBoxKitFloatingBarBehavior.minimize,
    );
  });
}
