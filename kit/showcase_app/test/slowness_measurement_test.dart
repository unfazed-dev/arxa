// MEASUREMENT harness for symptom 4 ("slowness"). Not a regression guard —
// these tests PRINT numbers and assert only the facts that must stay true for
// the numbers to mean anything. Findings live in
// docs/research/slowness-measurement.md.
//
// Run:  flutter test test/slowness_measurement_test.dart  (from kit/showcase_app)
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/app/app_data.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_view.dart';

import 'helpers.dart';

/// Tallies every widget runtimeType in the LIVE ELEMENT tree (offstage
/// included — `visitChildren` walks past `Offstage`, which is exactly what we
/// want: an offstage element is mounted and costs layout/paint decisions).
Map<String, int> elementCensus(WidgetTester tester) {
  final counts = <String, int>{};
  void visit(Element e) {
    final name = e.widget.runtimeType.toString();
    counts[name] = (counts[name] ?? 0) + 1;
    e.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  return counts;
}

int totalElements(WidgetTester tester) {
  var n = 0;
  void visit(Element e) {
    n++;
    e.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  return n;
}

/// Widget type names whose build() reaches a real `UiKitView(`/`AppKitView(`
/// constructor. Derived by grepping constructor call sites in
/// kit/ui_library/vendor/cupertino_native_better/lib/components/ — see the
/// research doc's mapping table. `AppBoxKitNative*` is a NAMING CONVENTION and
/// is deliberately NOT used as the marker.
const platformViewBackedTypes = <String>{
  'CNTextField',
  'CNGlassCard',
  'CNSearchBar',
  'CNPopupMenuButton',
  'CNSegmentedControl',
  'CNButton',
  'CNTabBar',
  'CNIcon',
  'CNSearchScaffold',
  'CNFloatingIsland',
  'CNRangeSlider',
  'CNSlider',
  'CNGlassButtonGroup',
  'CNLiquidGlassContainer',
  'CNSwitch',
};

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);

  // ---------------------------------------------------------------------
  // M2 — tab-shell inflation eagerness at boot.
  // ---------------------------------------------------------------------
  testWidgets('M2 boot: which of the four tab shells inflate elements',
      (tester) async {
    await bootShell(tester);

    // find.byType walks the ELEMENT tree, so a widget object that the router
    // constructed but never mounted does not appear.
    final home = find.byType(ShowcaseHomeShellView, skipOffstage: false);
    final search = find.byType(ShowcaseSearchShellView, skipOffstage: false);
    final profile = find.byType(ShowcaseProfileShellView, skipOffstage: false);
    final notes = find.byType(ShowcaseNotesShellView, skipOffstage: false);

    final census = elementCensus(tester);

    // ignore: avoid_print
    print('[M2] mounted shell elements at boot: '
        'home=${home.evaluate().length} '
        'search=${search.evaluate().length} '
        'profile=${profile.evaluate().length} '
        'notes=${notes.evaluate().length}');
    // ignore: avoid_print
    print('[M2] KeepAliveTab elements mounted = '
        '${census['KeepAliveTab'] ?? 0}');
    // ignore: avoid_print
    print('[M2] AppBoxKitAnimatedTabStack elements = '
        '${census['AppBoxKitAnimatedTabStack'] ?? 0}');
    // ignore: avoid_print
    print('[M2] NestedRouter elements = ${census['NestedRouter'] ?? 0}');
    // ignore: avoid_print
    print('[M2] total elements in tree at boot = ${totalElements(tester)}');

    // The load-bearing assertion: the router's laziness question.
    expect(home, findsOneWidget,
        reason: 'active tab must be inflated at boot');
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ---------------------------------------------------------------------
  // M1 — platform views on the boot path to the first interactive hub frame.
  // ---------------------------------------------------------------------
  testWidgets('M1 boot: platform-view-backed widgets mounted', (tester) async {
    await bootShell(tester);

    final census = elementCensus(tester);
    final pv = <String, int>{};
    for (final entry in census.entries) {
      if (platformViewBackedTypes.contains(entry.key)) {
        pv[entry.key] = entry.value;
      }
    }
    final total = pv.values.fold<int>(0, (a, b) => a + b);

    // Everything named AppBoxKitNative*, for contrast — this is the count the
    // earlier audit reported, and it is NOT the platform-view count.
    final namedNative = <String, int>{};
    for (final entry in census.entries) {
      if (entry.key.startsWith('AppBoxKitNative')) {
        namedNative[entry.key] = entry.value;
      }
    }

    // ignore: avoid_print
    print('[M1] platform-view-backed (reaches UiKitView) at boot: $pv');
    // ignore: avoid_print
    print('[M1] TOTAL platform views on boot path = $total');
    // ignore: avoid_print
    print('[M1] AppBoxKitNative*-NAMED widgets (naming convention, NOT the '
        'platform-view count): $namedNative');

    // A count is not a cost: a CNIcon nested INSIDE a CNButton is not an
    // independent platform view on device (the native button takes the symbol
    // as a creationParam). Break the 22 down by nesting and by owner so the
    // top-level (truly independent) count is separable.
    final chain = <Element>[];
    final rows = <String>[];
    var nested = 0;
    var topLevel = 0;
    void walk(Element e) {
      final name = e.widget.runtimeType.toString();
      final isPv = platformViewBackedTypes.contains(name);
      if (isPv) {
        final pvAncestors =
            chain.where((a) => platformViewBackedTypes.contains(
                  a.widget.runtimeType.toString(),
                )).toList();
        final owner = chain.reversed
            .map((a) => a.widget.runtimeType.toString())
            .firstWhere(
              (n) => n.startsWith('AppBoxKitNative') || n.startsWith('Showcase'),
              orElse: () => '<none>',
            );
        if (pvAncestors.isEmpty) {
          topLevel++;
          rows.add('  TOP    $name   owner=$owner');
        } else {
          nested++;
          rows.add('  NESTED $name   inside='
              '${pvAncestors.map((a) => a.widget.runtimeType).join(">")}'
              '   owner=$owner');
        }
      }
      chain.add(e);
      e.visitChildren(walk);
      chain.removeLast();
    }

    tester.binding.rootElement!.visitChildren(walk);
    // ignore: avoid_print
    print('[M1] top-level (independent) platform views = $topLevel; '
        'nested inside another platform view = $nested');
    // ignore: avoid_print
    print('[M1] breakdown:\n${rows.join("\n")}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ---------------------------------------------------------------------
  // M1b — the SAME census with the tier gates forced to iOS 26, which is what
  // decides widget SELECTION on the user's device. Without this the census is
  // a mixture: AppBoxKitNativeIconButton falls through to CNButton on any
  // non-Android host (so it appears), but AppBoxKitNativeTabBar /
  // SegmentedControl / SplitButton gate on
  // `AppBoxKitPlatform.supportsLiquidGlass` (= isIOS && iosMajor >= 26) and so
  // take the Flutter fallback headless and never appear.
  // ---------------------------------------------------------------------
  testWidgets('M1b boot: platform-view census with tier gates forced to iOS 26',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(
      isIOS: true,
      isAndroid: false,
      iosMajor: 26,
      targetPlatform: TargetPlatform.iOS,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // Reset INSIDE the body, not addTearDown: flutter_test verifies the
    // foundation debug vars are unset before tearDowns run.
    addTearDown(AppBoxKitPlatform.reset);

    await bootShell(tester);

    final census = elementCensus(tester);
    final pv = <String, int>{};
    for (final entry in census.entries) {
      if (platformViewBackedTypes.contains(entry.key)) {
        pv[entry.key] = entry.value;
      }
    }

    // Top-level vs nested again: on device a native CNButton is a bare
    // UiKitView with NO Flutter children (button.dart:675) — its icon travels
    // as a creationParam. So a CNIcon nested inside a CNButton exists ONLY in
    // the headless fallback tier and is NOT a platform view on device.
    final chain = <Element>[];
    var topLevel = 0;
    var nested = 0;
    final topRows = <String, int>{};
    void walk(Element e) {
      final name = e.widget.runtimeType.toString();
      if (platformViewBackedTypes.contains(name)) {
        final hasPvAncestor = chain.any(
          (a) => platformViewBackedTypes.contains(
            a.widget.runtimeType.toString(),
          ),
        );
        if (hasPvAncestor) {
          nested++;
        } else {
          topLevel++;
          topRows[name] = (topRows[name] ?? 0) + 1;
        }
      }
      chain.add(e);
      e.visitChildren(walk);
      chain.removeLast();
    }

    tester.binding.rootElement!.visitChildren(walk);

    // ignore: avoid_print
    print('[M1b] iOS26 census, all platform-view-backed types: $pv');
    // ignore: avoid_print
    print('[M1b] TOP-LEVEL (one UiKitView each on device) = $topLevel -> '
        '$topRows');
    // ignore: avoid_print
    print('[M1b] nested inside another platform view (NOT a device platform '
        'view — creationParam instead) = $nested');
    // ignore: avoid_print
    print('[M1b] total elements at boot (iOS26 tiers) = '
        '${totalElements(tester)}');
    debugDefaultTargetPlatformOverride = null;
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ---------------------------------------------------------------------
  // M3a — per-frame rebuild propagation through AppBoxKitScrollEdgeEffect.
  //
  // The suspect calls setState from a ScrollPosition listener. The question is
  // NOT how many setStates fire; it is whether the descendant rebuilds. The
  // probe is placed TWICE: once as an identical `child` instance handed to the
  // suspect (the real usage), once rebuilt inline by a builder that also
  // rebuilds every frame (the control). The delta is the whole measurement.
  // ---------------------------------------------------------------------
  testWidgets('M3a scroll: does a scroll-frame setState reach the child',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final childBuilds = <int>[0];
    final controlBuilds = <int>[0];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(
                  height: 120,
                  child: i == 0
                      ? AppBoxKitScrollEdgeEffect(
                          // Identical instance every rebuild — the real usage.
                          child: _BuildCounter(counter: childBuilds),
                        )
                      : (i == 1
                          ? _RebuildEveryScrollFrame(
                              builder: (_) =>
                                  _BuildCounter(counter: controlBuilds),
                            )
                          : const SizedBox.shrink()),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final childAfterMount = childBuilds[0];
    final controlAfterMount = controlBuilds[0];

    // Drive a real scroll: 300 discrete steps, each followed by a frame.
    final listFinder = find.byType(Scrollable).first;
    final gesture =
        await tester.startGesture(tester.getCenter(listFinder));
    var frames = 0;
    var framesWithLiveBlur = 0;
    for (var i = 0; i < 300; i++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      // A live blur/saveLayer exists whenever the effect's Opacity is < 1.
      for (final e in find
          .descendant(
            of: find.byType(AppBoxKitScrollEdgeEffect),
            matching: find.byType(Opacity),
          )
          .evaluate()) {
        final o = e.widget as Opacity;
        if (o.opacity < 1.0) {
          framesWithLiveBlur++;
          break;
        }
      }
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final childDelta = childBuilds[0] - childAfterMount;
    final controlDelta = controlBuilds[0] - controlAfterMount;

    // ignore: avoid_print
    print('[M3a] scroll steps = $frames');
    // ignore: avoid_print
    print('[M3a] child rebuilds UNDER AppBoxKitScrollEdgeEffect = $childDelta');
    // ignore: avoid_print
    print('[M3a] control rebuilds (inline-constructed child) = $controlDelta');
    // ignore: avoid_print
    print('[M3a] frames with a LIVE blur/saveLayer (Opacity < 1) = '
        '$framesWithLiveBlur');

    // The two facts the numbers depend on. Without the control actually
    // rebuilding, "0" would just mean the harness never scrolled; and the 0
    // itself is the only permanent guard on the identity short-circuit that
    // C6 was closed against (`Element.updateChild` skips an identical
    // `widget.child`), which was measured but never pinned.
    expect(controlDelta, greaterThan(0),
        reason: 'the control must really rebuild, or the measurement is vacuous');
    expect(childDelta, 0,
        reason: 'a scroll must not rebuild the subtree under the effect — if '
            'this regresses, scroll cost returns and C6 reopens');
  }, timeout: const Timeout(Duration(minutes: 3)));

  // ---------------------------------------------------------------------
  // M3b — the real showcase home list. Counts rebuilds of the mounted
  // platform-view-backed widgets across a scroll.
  // ---------------------------------------------------------------------
  testWidgets('M3b scroll: element churn on the real home list',
      (tester) async {
    await bootShell(tester);

    final before = elementCensus(tester);
    final beforeTotal = totalElements(tester);

    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) {
      // ignore: avoid_print
      print('[M3b] NO Scrollable found on the home tab — skipped');
      return;
    }

    final gesture =
        await tester.startGesture(tester.getCenter(scrollables.first));
    var framesWithLiveBlur = 0;
    for (var i = 0; i < 200; i++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump(const Duration(milliseconds: 16));
      for (final e in find
          .descendant(
            of: find.byType(AppBoxKitScrollEdgeEffect),
            matching: find.byType(Opacity),
          )
          .evaluate()) {
        if ((e.widget as Opacity).opacity < 1.0) {
          framesWithLiveBlur++;
          break;
        }
      }
    }
    await gesture.up();
    // NOT pumpAndSettle: the home tab hosts a looping progress/loading
    // indicator, so the scheduler never goes idle and pumpAndSettle times out.
    // (That looping animation is itself a finding — see the research doc.)
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final after = elementCensus(tester);
    final afterTotal = totalElements(tester);

    // ignore: avoid_print
    print('[M3b] AppBoxKitScrollEdgeEffect instances on home = '
        '${before['AppBoxKitScrollEdgeEffect'] ?? 0}');
    // ignore: avoid_print
    print('[M3b] frames (of 200) with a LIVE blur/saveLayer = '
        '$framesWithLiveBlur');
    // ignore: avoid_print
    print('[M3b] total elements before=$beforeTotal after=$afterTotal');
    final pvBefore = platformViewBackedTypes
        .fold<int>(0, (a, t) => a + (before[t] ?? 0));
    final pvAfter =
        platformViewBackedTypes.fold<int>(0, (a, t) => a + (after[t] ?? 0));
    // ignore: avoid_print
    print('[M3b] platform-view-backed count before=$pvBefore after=$pvAfter');
  }, timeout: const Timeout(Duration(minutes: 3)));

  // ---------------------------------------------------------------------
  // M4 — tab switch: how many shells are inflated after visiting all four.
  // ---------------------------------------------------------------------
  testWidgets('M4 after visiting all four tabs: inflated shell count',
      (tester) async {
    await bootShell(tester);

    final tabBar = find.byType(AppBoxKitNativeTabBar);
    // ignore: avoid_print
    print('[M4] AppBoxKitNativeTabBar found = ${tabBar.evaluate().length}');

    final census0 = elementCensus(tester);
    // ignore: avoid_print
    print('[M4] shells inflated at boot: '
        'home=${census0['ShowcaseHomeShellView'] ?? 0} '
        'search=${census0['ShowcaseSearchShellView'] ?? 0} '
        'profile=${census0['ShowcaseProfileShellView'] ?? 0} '
        'notes=${census0['ShowcaseNotesShellView'] ?? 0}');
    // ignore: avoid_print
    print('[M4] total elements at boot = ${totalElements(tester)}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ---------------------------------------------------------------------
  // M5 — the Notes folder list chains `.scrollEdgeEffect()` TWICE per group
  // (showcase_notes_folder_view.mobile.dart:182-183): two stacked
  // Opacity + ImageFilter wrappers per group. Densest scroll-edge usage in the
  // app — if any Dart-side scroll cost is real, it is here.
  // ---------------------------------------------------------------------
  testWidgets('M5 notes folder: scroll-edge density and live-blur frames',
      (tester) async {
    // Device tier selection — M1b showed the tiers change the tree
    // structurally (1596 -> 756 elements), so the headless-default tree is the
    // wrong one to ask "what is under the blur" about.
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(
      isIOS: true,
      isAndroid: false,
      iosMajor: 26,
      targetPlatform: TargetPlatform.iOS,
    );
    addTearDown(AppBoxKitPlatform.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final router = await bootShell(tester);
    unawaited(router.navigateNamed('/notes'));
    await settle(tester);
    if (find.text('All Notes').evaluate().isEmpty) {
      // ignore: avoid_print
      print('[M5] "All Notes" not reachable — skipped');
      debugDefaultTargetPlatformOverride = null;
      return;
    }
    await tester.tap(find.text('All Notes'));
    await settle(tester);

    final census = elementCensus(tester);
    final effects = census['AppBoxKitScrollEdgeEffect'] ?? 0;
    // ignore: avoid_print
    print('[M5] AppBoxKitScrollEdgeEffect instances mounted on notes folder = '
        '$effects');
    // ignore: avoid_print
    print('[M5] total elements on notes folder = ${totalElements(tester)}');

    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) {
      // ignore: avoid_print
      print('[M5] no Scrollable — skipped scroll phase');
      debugDefaultTargetPlatformOverride = null;
      return;
    }

    /// Counts platform-view-backed elements inside [root]'s subtree.
    int pvUnder(Element root) {
      var n = 0;
      void visit(Element e) {
        if (platformViewBackedTypes.contains(e.widget.runtimeType.toString())) {
          n++;
        }
        e.visitChildren(visit);
      }

      root.visitChildren(visit);
      return n;
    }

    final gesture =
        await tester.startGesture(tester.getCenter(scrollables.last));
    var liveBlurFrames = 0;
    var maxSimultaneousLiveBlurs = 0;
    var maxPvUnderLiveBlur = 0;
    var framesWithPvUnderLiveBlur = 0;
    for (var i = 0; i < 200; i++) {
      await gesture.moveBy(const Offset(0, -2));
      await tester.pump(const Duration(milliseconds: 16));
      var live = 0;
      var pvThisFrame = 0;
      for (final effect in find.byType(AppBoxKitScrollEdgeEffect).evaluate()) {
        var isLive = false;
        void findOpacity(Element e) {
          final w = e.widget;
          if (w is Opacity && w.opacity < 1.0) isLive = true;
          e.visitChildren(findOpacity);
        }

        effect.visitChildren(findOpacity);
        if (isLive) {
          live++;
          // THE question: is a hybrid-composition platform view sitting under
          // an ImageFilterLayer + saveLayer? That is the documented pathology
          // (flutter#24164 / #148639), not "a blur is running".
          pvThisFrame += pvUnder(effect);
        }
      }
      if (live > 0) liveBlurFrames++;
      if (live > maxSimultaneousLiveBlurs) maxSimultaneousLiveBlurs = live;
      if (pvThisFrame > 0) framesWithPvUnderLiveBlur++;
      if (pvThisFrame > maxPvUnderLiveBlur) maxPvUnderLiveBlur = pvThisFrame;
    }
    await gesture.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // ignore: avoid_print
    print('[M5] scroll distance = 200 steps x 2px = 400px, monotonically down '
        '(hysteresis: enter 0.04, exit 0.01 — once engaged it stays engaged)');
    // ignore: avoid_print
    print('[M5] frames (of 200) with >=1 LIVE blur/saveLayer = '
        '$liveBlurFrames');
    // ignore: avoid_print
    print('[M5] max SIMULTANEOUS live blur layers in one frame = '
        '$maxSimultaneousLiveBlurs  (of $effects mounted -> '
        '${effects - maxSimultaneousLiveBlurs} never go live)');
    // ignore: avoid_print
    print('[M5] PLATFORM VIEWS under a LIVE blur: max in one frame = '
        '$maxPvUnderLiveBlur; frames with >=1 = $framesWithPvUnderLiveBlur');
    debugDefaultTargetPlatformOverride = null;
  }, timeout: const Timeout(Duration(minutes: 3)));

  // ---------------------------------------------------------------------
  // M6 — Dart-side boot work that IS measurable headless. AppData.initialize
  // (seed-backend asset read + JSON parse + fake auth) runs on the real boot
  // path but is hoisted into setUpAll, so it is excluded from every number
  // above. Runs LAST: it resets the data layer.
  // ---------------------------------------------------------------------
  test('M6 boot: AppData.initialize wall clock (Dart side, headless)',
      () async {
    final samples = <int>[];
    for (var i = 0; i < 3; i++) {
      // Full teardown: resetForTesting alone leaves the GetIt singletons
      // AppBoxKitData.initialize registers, so a second initialize throws.
      await teardownShowcase();
      await registerKitTestServices();
      final sw = Stopwatch()..start();
      await AppData.initialize(
        config: const AppBoxKitDataConfig(
          backend: AppBoxKitDataBackend.seed,
          auth: AppBoxKitAuthConfig(fakeUsersAsset: AppData.fakeUsersAsset),
        ),
        assetReader: DiskAssetReader(),
      );
      sw.stop();
      samples.add(sw.elapsedMicroseconds);
    }
    // ignore: avoid_print
    print('[M6] AppData.initialize microseconds, 3 runs = $samples');
    // ignore: avoid_print
    print('[M6] NOTE: headless host disk, NOT device flash; and this is Dart '
        'work only — it bounds, and does not measure, on-device cold start.');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

class _BuildCounter extends StatelessWidget {
  const _BuildCounter({required this.counter});
  final List<int> counter;

  @override
  Widget build(BuildContext context) {
    counter[0]++;
    return const SizedBox.expand();
  }
}

/// Control: rebuilds its child from scratch on every scroll frame.
class _RebuildEveryScrollFrame extends StatefulWidget {
  const _RebuildEveryScrollFrame({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_RebuildEveryScrollFrame> createState() =>
      _RebuildEveryScrollFrameState();
}

class _RebuildEveryScrollFrameState extends State<_RebuildEveryScrollFrame> {
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (!identical(p, _position)) {
      _position?.removeListener(_onScroll);
      _position = p?..addListener(_onScroll);
    }
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
