import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_chrome_gate.dart';

/// Counts initState calls — a remount detector. keepAlive mode must never
/// re-init the child (that re-init IS the reappear jank on iOS: new platform
/// view + raster/platform thread merge); unmount mode re-inits by design.
class _InitSpy extends StatefulWidget {
  const _InitSpy({required this.onInit, required this.child});
  final VoidCallback onInit;
  final Widget child;
  @override
  State<_InitSpy> createState() => _InitSpyState();
}

class _InitSpyState extends State<_InitSpy> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  int depth() => CNTabBarRouteObserver.anyModalDepth.value;

  tearDown(() {
    // Drain any depth a test left behind — the counter is a static global
    // (same discipline as kit_native_overlay_test.dart).
    while (depth() > 0) {
      CNTabBarRouteObserver.markAnyModalInactive();
    }
  });

  const childKey = Key('gated-child');
  const gateKey = Key('gate');

  var initCount = 0;
  setUp(() => initCount = 0);

  Widget host({
    Duration showDuration = const Duration(milliseconds: 180),
    Duration hideDuration = const Duration(milliseconds: 160),
    AppBoxKitChromeHideMode hideMode = AppBoxKitChromeHideMode.keepAlive,
  }) {
    return Center(
      child: AppBoxKitNativeChromeGate(
        key: gateKey,
        showDuration: showDuration,
        hideDuration: hideDuration,
        hideMode: hideMode,
        child: _InitSpy(
          onInit: () => initCount++,
          child: const SizedBox(key: childKey, width: 120, height: 50),
        ),
      ),
    );
  }

  double fadeValue(WidgetTester tester) => tester
      .widget<FadeTransition>(find.descendant(
          of: find.byKey(gateKey), matching: find.byType(FadeTransition)))
      .opacity
      .value;

  double scaleValue(WidgetTester tester) => tester
      .widget<ScaleTransition>(find.descendant(
          of: find.byKey(gateKey), matching: find.byType(ScaleTransition)))
      .scale
      .value;

  bool ignoring(WidgetTester tester) => tester
      .widget<IgnorePointer>(find.descendant(
          of: find.byKey(gateKey), matching: find.byType(IgnorePointer)))
      .ignoring;

  testWidgets('visible at depth 0: alpha 1, scale 1, pointers live',
      (tester) async {
    await tester.pumpWidget(host());
    expect(find.byKey(childKey), findsOneWidget);
    expect(fadeValue(tester), 1.0);
    expect(scaleValue(tester), 1.0);
    expect(ignoring(tester), isFalse);
  });

  testWidgets(
      'keepAlive hide: dematerializes — fade + slight scale animates out over '
      'hideDuration; child stays mounted, footprint intact', (tester) async {
    await tester.pumpWidget(host());
    final shownSize = tester.getSize(find.byKey(gateKey));

    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump(); // hide-decision frame: reverse() starts
    expect(ignoring(tester), isTrue,
        reason: 'alpha-0-bound widgets are still hit-testable without this');

    await tester.pump(const Duration(milliseconds: 60)); // mid-dematerialize
    expect(fadeValue(tester), lessThan(1.0),
        reason:
            'ADR 0010 dematerialize: the hide animates, no instant alpha-0');
    expect(fadeValue(tester), greaterThan(0.0));
    expect(scaleValue(tester), lessThan(1.0));
    expect(scaleValue(tester), greaterThan(0.95));

    await tester.pump(const Duration(milliseconds: 200)); // settle
    expect(fadeValue(tester), 0.0,
        reason: 'at alpha 0 the platform view leaves the native hierarchy');
    expect(scaleValue(tester), 0.95,
        reason: 'hidden state rests at the slight dematerialize scale');
    expect(find.byKey(childKey), findsOneWidget,
        reason: 'keepAlive: hidden at paint level, NOT unmounted');
    expect(tester.getSize(find.byKey(gateKey)), shownSize,
        reason: 'scale is paint-time only — zero layout shift');
    expect(initCount, 1);
  });

  testWidgets(
      'hideDuration: Duration.zero keeps the legacy instant alpha-0 hide '
      '(escape hatch for hosts still presenting a blur overlay)',
      (tester) async {
    await tester.pumpWidget(host(hideDuration: Duration.zero));
    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();
    expect(fadeValue(tester), 0.0,
        reason: 'zero hideDuration = same-frame hide');
    expect(find.byKey(childKey), findsOneWidget);
    expect(initCount, 1);
  });

  testWidgets(
      'keepAlive restore: fades the SAME live child back in — zero remounts '
      'across the full cycle (the anti-jank guarantee)', (tester) async {
    await tester.pumpWidget(host());
    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();

    CNTabBarRouteObserver.markAnyModalInactive();
    await tester.pump();
    expect(fadeValue(tester), lessThan(1.0),
        reason: 'restore starts transparent to mask native reattach');

    await tester.pump(const Duration(milliseconds: 250));
    expect(fadeValue(tester), 1.0);
    expect(scaleValue(tester), 1.0,
        reason: 'restore also reverses the dematerialize scale');
    expect(ignoring(tester), isFalse);
    expect(initCount, 1,
        reason: 'child must NEVER re-init in keepAlive mode — a remount '
            'means a new platform view + thread-merge stall (the jank)');
  });

  testWidgets('showDuration: Duration.zero restores at alpha 1 instantly',
      (tester) async {
    await tester.pumpWidget(host(showDuration: Duration.zero));
    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();
    CNTabBarRouteObserver.markAnyModalInactive();
    await tester.pump();
    expect(fadeValue(tester), 1.0);
    expect(initCount, 1);
  });

  testWidgets(
      'unmount mode (escape hatch): child destroyed, exact-size placeholder, '
      'restore remounts + fades', (tester) async {
    await tester.pumpWidget(host(hideMode: AppBoxKitChromeHideMode.unmount));
    final shownSize = tester.getSize(find.byKey(gateKey));

    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();
    expect(find.byKey(childKey), findsNothing,
        reason: 'unmount mode really unmounts');
    expect(tester.getSize(find.byKey(gateKey)), shownSize,
        reason: 'measured placeholder holds the footprint');

    CNTabBarRouteObserver.markAnyModalInactive();
    await tester.pump();
    expect(find.byKey(childKey), findsOneWidget);
    expect(fadeValue(tester), lessThan(1.0));
    await tester.pump(const Duration(milliseconds: 250));
    expect(fadeValue(tester), 1.0);
    expect(initCount, 2, reason: 'remount is inherent to this mode');
  });

  testWidgets(
      'mount-depth snapshot: a gate mounted INSIDE an open modal does not '
      'self-destroy, but hides when depth grows past its baseline',
      (tester) async {
    CNTabBarRouteObserver.markAnyModalActive(); // depth 1 BEFORE mount
    await tester.pumpWidget(host());
    expect(fadeValue(tester), 1.0,
        reason: 'baseline is the mount-time depth, not zero');

    CNTabBarRouteObserver.markAnyModalActive(); // depth 2 > baseline 1
    await tester.pump();
    await tester
        .pump(const Duration(milliseconds: 200)); // dematerialize settle
    expect(fadeValue(tester), 0.0);

    CNTabBarRouteObserver.markAnyModalInactive(); // back to baseline
    await tester.pump(); // ticker start-time stamp frame
    await tester.pump(const Duration(milliseconds: 250));
    expect(fadeValue(tester), 1.0);
    expect(initCount, 1);
  });
}
