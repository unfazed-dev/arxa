import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSearchBar;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_search_bar.dart';

import 'arxa_kit_native_test_helpers.dart';

/// Bars-tier gate test — mirrors [kit_native_slider_test]'s pattern. The
/// load-bearing assertion is the M3E-tier route: on Android (wantNative) the kit
/// must surface a Material [SearchBar] (M3 motion is theme-driven). The default
/// platform (macOS host) also lands on Material [SearchBar], and [onChanged] is
/// wired end-to-end via text entry.
void main() {
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.native-search-bar — Android wantNative routes to Material SearchBar',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const ArxaKitNativeSearchBar()));

    expect(
      find.byType(SearchBar),
      findsOneWidget,
      reason:
          'supportsComposeM3E → kit must route to a Material SearchBar on Android',
    );
  });

  testWidgets(
      'kit.ui-library.native-search-bar — default platform builds clean',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitNativeSearchBar(hint: 'Find')));

    expect(
      find.byType(SearchBar),
      findsOneWidget,
      reason: 'fallback tier renders a Material SearchBar',
    );
    expect(find.text('Find'), findsOneWidget);
  });

  testWidgets(
      'kit.ui-library.native-search-bar — onChanged is wired (text entered via the controller-backed field)',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    final controller = TextEditingController();
    String? fired;
    await tester.pumpWidget(host(ArxaKitNativeSearchBar(
      controller: controller,
      onChanged: (v) => fired = v,
    )));

    expect(find.byType(SearchBar), findsOneWidget);
    // SearchBar hosts an internal TextField — driving it fires our onChanged.
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    expect(
      fired,
      'hello',
      reason: 'onChanged must fire when text is entered through the controller',
    );
    controller.dispose();
  });

  // The trailing action is opt-in: with no actionLabel/onAction (the default
  // both existing call sites rely on) the field renders bare — no trailing
  // button of any kind.
  testWidgets(
      'kit.ui-library.native-search-bar — default (no action) renders no trailing button',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const ArxaKitNativeSearchBar()));

    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byType(TextButton), findsNothing,
        reason: 'no action → bare field, no trailing button');
  });

  // actionLabel + onAction renders the field + a generic tier-native text
  // button in a Row. Tested on the Material tier (TextButton); the iOS
  // CupertinoButton tier is code-verified only — a native UiKitView can't
  // render in a headless test.
  testWidgets(
      'kit.ui-library.native-search-bar — actionLabel renders a TextButton that fires onAction',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    var fired = 0;
    await tester.pumpWidget(host(ArxaKitNativeSearchBar(
      actionLabel: 'Cancel',
      onAction: () => fired++,
    )));

    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(fired, 1, reason: 'tapping the trailing button must fire onAction');
  });

  // Either param null (here actionLabel set, onAction omitted) must NOT render a
  // button — both are required. Guards the half-set footgun.
  testWidgets(
      'kit.ui-library.native-search-bar — actionLabel without onAction renders no button',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(
        host(const ArxaKitNativeSearchBar(actionLabel: 'Cancel')));

    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  // The CN tier is reached via the iOS-26 kit override; withAndroidFallback
  // diverts only the CN-internal render path so no UiKitView is constructed
  // headless.
  testWidgets(
      'kit.ui-library.native-search-bar — inside a scrollable keeps the native tier',
      (tester) async {
    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(
        isIOS: true,
        iosMajor: 26,
      );
      await tester.pumpWidget(host(const SingleChildScrollView(
        child: ArxaKitNativeSearchBar(),
      )));
      final cn = tester.widget<CNSearchBar>(find.byType(CNSearchBar));
      expect(
        cn.preferFlutterTier,
        isFalse,
        reason: 'a Scrollable ancestor must not demote the tier — the slab '
            'artifacts are compositional and law-gate-enforced away, so '
            'in-scroll controls stay native.',
      );
    });
  });
}
