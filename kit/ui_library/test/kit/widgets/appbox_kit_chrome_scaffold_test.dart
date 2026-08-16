import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitChromeScaffold] is the liquid-glass law's reuse unit: hosts get
/// the ratified chrome from one widget, tier branch inside. These pins are
/// the law's guard against hand-assembly drifting back in.
void main() {
  Widget harness({
    bool? forceGlass,
    AppBoxKitFloatingBarBehavior? behavior,
    Widget? leading,
    Widget? bottomSheet,
    Widget? drawer,
    bool resizeToAvoidBottomInset = true,
  }) =>
      MaterialApp(
        home: AppBoxKitChromeScaffold(
          debugForceGlassTier: forceGlass,
          behavior: behavior ?? AppBoxKitFloatingBarBehavior.minimize,
          leading: leading,
          drawer: drawer,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          title: 'Kit Showcase',
          actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
          floatingActionButton:
              const SizedBox(key: Key('fab'), width: 56, height: 56),
          bottomSheet: bottomSheet,
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
    await tester.pumpWidget(
        harness(forceGlass: true, behavior: AppBoxKitFloatingBarBehavior.hide));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).appBar, isNull,
        reason: 'a boxed bar over full-bleed native glass is the exact '
            'arrangement the law forbids (rule 4)');
    final chrome = tester
        .widget<AppBoxKitFloatingChrome>(find.byType(AppBoxKitFloatingChrome));
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
          .widget<AppBoxKitFloatingChrome>(find.byType(AppBoxKitFloatingChrome))
          .behavior,
      AppBoxKitFloatingBarBehavior.minimize,
    );
  });

  // -----------------------------------------------------------------------
  // leading + bottomSheet (ratified 2026-08-13): pushed routes now get their
  // chrome from THIS widget instead of hand-assembling Scaffold + appBar, so
  // both slots must survive the tier branch.
  // -----------------------------------------------------------------------

  const leadingProbe = SizedBox(key: Key('leading'), width: 44, height: 44);

  testWidgets(
      'kit.ui-library.chrome-scaffold — boxed tiers hand leading to the '
      'native app bar and suppress the implied back button', (tester) async {
    await tester.pumpWidget(harness(leading: leadingProbe));
    final bar = tester
        .widget<AppBoxKitNativeAppBar>(find.byType(AppBoxKitNativeAppBar));
    expect(bar.leading, same(leadingProbe));
    expect(bar.automaticallyImplyLeading, isFalse,
        reason: 'a supplied leading IS the back affordance — implying a '
            'second one would double it');
    expect(find.byKey(const Key('leading')), findsOneWidget);
  });

  testWidgets(
      'kit.ui-library.chrome-scaffold — a null leading keeps the boxed tier '
      'implying its own back button (pre-ruling behavior)', (tester) async {
    await tester.pumpWidget(harness());
    expect(
      tester
          .widget<AppBoxKitNativeAppBar>(find.byType(AppBoxKitNativeAppBar))
          .automaticallyImplyLeading,
      isTrue,
    );
  });

  testWidgets(
      'kit.ui-library.chrome-scaffold — glass tier hands leading to the '
      'floating bar', (tester) async {
    await tester.pumpWidget(harness(forceGlass: true, leading: leadingProbe));
    expect(
      tester
          .widget<AppBoxKitFloatingChrome>(find.byType(AppBoxKitFloatingChrome))
          .leading,
      same(leadingProbe),
    );
    expect(
      find.descendant(
          of: find.byType(AppBoxKitNativeFloatingBar),
          matching: find.byKey(const Key('leading'))),
      findsOneWidget,
      reason: 'it must land in the floating BAR, not loose in the body',
    );
  });

  testWidgets(
      'kit.ui-library.chrome-scaffold — bottomSheet reaches Scaffold on both '
      'tiers', (tester) async {
    for (final glass in [false, true]) {
      await tester.pumpWidget(harness(
        forceGlass: glass,
        bottomSheet: const SizedBox(key: Key('sheet'), height: 80),
      ));
      expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).bottomSheet, isNotNull,
          reason: 'bottomSheet dropped on ${glass ? 'glass' : 'boxed'} tier');
      expect(find.byKey(const Key('sheet')), findsOneWidget);
    }
  });

  testWidgets(
      'kit.ui-library.chrome-scaffold — drawer and resizeToAvoidBottomInset '
      'reach Scaffold on both tiers', (tester) async {
    // A pushed route hosting a keyboard-riding bottomSheet needs both: the
    // drawer is a surface feature no tier branch affects, and
    // resizeToAvoidBottomInset:false is what keeps that sheet's bottom padding
    // (Scaffold's `removeBottomPadding: _resizeToAvoidBottomInset`).
    for (final glass in [false, true]) {
      await tester.pumpWidget(harness(
        forceGlass: glass,
        drawer: const Drawer(child: SizedBox(key: Key('drawer'))),
        resizeToAvoidBottomInset: false,
      ));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final tier = glass ? 'glass' : 'boxed';
      expect(scaffold.drawer, isNotNull,
          reason: 'drawer dropped on $tier tier');
      expect(scaffold.resizeToAvoidBottomInset, isFalse,
          reason: 'resizeToAvoidBottomInset dropped on $tier tier');
    }
  });
}
