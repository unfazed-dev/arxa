import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_motion/arxa_kit_motion.dart';
import 'package:arxa_kit_motion/arxa_kit_testing.dart';

double _opacityOf(WidgetTester tester, Key key) {
  final fade = tester.widget<FadeTransition>(
    find
        .ancestor(of: find.byKey(key), matching: find.byType(FadeTransition))
        .first,
  );
  return fade.opacity.value;
}

void main() {
  group('ArxaKitGestureDriver scrub', () {
    testWidgets('kit.motion.gesture-driver — horizontal drag maps to 0→1 progress, wake tracks it',
        (tester) async {
      final driver = ArxaKitGestureDriver(vsync: tester);
      addTearDown(driver.dispose);
      var recordedDelta = 0.0;

      await tester.pumpWidget(MaterialApp(
        home: ArxaKitMotionScope(
          driver: driver,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) {
                recordedDelta += d.primaryDelta ?? 0;
                driver.scrubBy((d.primaryDelta ?? 0) / 300);
              },
              child: Container(
                width: 300,
                height: 300,
                color: Colors.blue,
                child: const Center(
                  child: ArxaKitWake(
                    order: 0,
                    child: SizedBox(key: Key('w'), height: 10),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.drag(find.byType(GestureDetector), const Offset(120, 0));
      await tester.pump();
      // Scrub maps drag deltas onto the 0→1 timeline exactly.
      expect(driver.value, closeTo(recordedDelta / 300, 1e-9));
      expect(driver.value, greaterThan(0.0));
      expect(driver.value, lessThan(1.0));
      // The wake choreography rides the same driver (default spec:
      // easeOutCubic over the whole timeline at order 0).
      expect(
        _opacityOf(tester, const Key('w')),
        closeTo(Curves.easeOutCubic.transform(driver.value), 1e-9),
      );

      // Dragging past the closed end clamps at 0.
      await tester.drag(find.byType(GestureDetector), const Offset(-600, 0));
      await tester.pump();
      expect(driver.value, 0.0);
      expect(_opacityOf(tester, const Key('w')), 0.0);
    });

    test('kit.motion.gesture-driver — scrubTo clamps both ends', () {
      final driver = ArxaKitGestureDriver(vsync: const TestVSync());
      addTearDown(driver.dispose);
      driver.scrubTo(1.4);
      expect(driver.value, 1.0);
      driver.scrubTo(-0.2);
      expect(driver.value, 0.0);
      driver.scrubBy(0.25);
      expect(driver.value, 0.25);
    });
  });

  group('ArxaKitGestureDriver settle', () {
    Future<ArxaKitGestureDriver> pumpDriver(
      WidgetTester tester, {
      double initialValue = 0.0,
      SpringDescription? settleSpring,
      double? completionThreshold,
    }) async {
      final driver = ArxaKitGestureDriver(
        vsync: tester,
        initialValue: initialValue,
        settleSpring: settleSpring ?? ArxaKitSprings.snappy,
        completionThreshold: completionThreshold ?? 0.5,
      );
      addTearDown(driver.dispose);
      await tester.pumpWidget(MaterialApp(
        home: ArxaKitMotionScope(driver: driver, child: const SizedBox()),
      ));
      return driver;
    }

    testWidgets('kit.motion.gesture-driver — fling velocity sign picks the end state', (tester) async {
      final driver = await pumpDriver(tester, initialValue: 0.2);

      driver.settle(velocity: 4.0); // flung toward open despite low position
      await tester.pumpAndSettle();
      // SpringSimulation.isDone leaves the value within tolerance of the
      // target — it does not snap exactly onto it.
      expect(driver.value, closeTo(1.0, 0.005));

      driver.settle(velocity: -4.0); // flung back closed from settled-open
      await tester.pumpAndSettle();
      expect(driver.value, closeTo(0.0, 0.005));
    });

    testWidgets('kit.motion.gesture-driver — near-stationary release falls back to completionThreshold',
        (tester) async {
      final driver = await pumpDriver(tester, initialValue: 0.7);

      driver.settle();
      await tester.pumpAndSettle();
      expect(driver.value, closeTo(1.0, 0.005)); // past halfway → open

      driver.scrubTo(0.3);
      driver.settle();
      await tester.pumpAndSettle();
      expect(driver.value, closeTo(0.0, 0.005)); // below halfway → closed
    });

    testWidgets('kit.motion.gesture-driver — custom completionThreshold re-tunes the fallback',
        (tester) async {
      final driver = await pumpDriver(
        tester,
        initialValue: 0.7,
        completionThreshold: 0.8,
      );
      driver.settle();
      await tester.pumpAndSettle();
      expect(driver.value, closeTo(0.0, 0.005)); // 0.7 < 0.8 → closed
    });

    testWidgets('kit.motion.gesture-driver — explicit `to` overrides velocity and threshold',
        (tester) async {
      final driver = await pumpDriver(tester, initialValue: 0.9);
      driver.settle(to: 0.0, velocity: 5.0);
      await tester.pumpAndSettle();
      expect(driver.value, closeTo(0.0, 0.005));
    });

    testWidgets('kit.motion.gesture-driver — settle carries release velocity into the spring',
        (tester) async {
      final driver = await pumpDriver(tester, initialValue: 0.5);
      driver.settle(to: 1.0, velocity: 20.0);
      // First pump after Ticker.start() reports zero elapsed — warm it up,
      // then advance.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      // A carried fling velocity covers more ground in the first frames than
      // a stationary release would (snappy spring from rest is slower here).
      final flung = driver.value;

      final rested = await pumpDriver(tester, initialValue: 0.5);
      rested.settle(to: 1.0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(flung, greaterThan(rested.value));
      // Let both springs run out so no ticker is active at test end.
      await tester.pumpAndSettle();
    });

    testWidgets('kit.motion.gesture-driver — scrub cancels an in-flight settle (re-grab mid-flight)',
        (tester) async {
      final driver = await pumpDriver(tester, initialValue: 0.5);
      driver.settle(to: 1.0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(driver.value, greaterThan(0.5)); // settle is running

      driver.scrubTo(0.4); // finger comes back down
      await tester.pump(const Duration(milliseconds: 500));
      expect(driver.value, 0.4); // settle never resumes
    });
  });

  group('ArxaKitSprings presets', () {
    double zeta(SpringDescription s) =>
        s.damping / (2 * math.sqrt(s.mass * s.stiffness));

    test('kit.motion.gesture-driver — snappy and gentle are critically damped, bouncy underdamped', () {
      expect(zeta(ArxaKitSprings.snappy), closeTo(1.0, 1e-9));
      expect(zeta(ArxaKitSprings.gentle), closeTo(1.0, 1e-9));
      expect(zeta(ArxaKitSprings.bouncy), inInclusiveRange(0.5, 0.99));
    });

    test('kit.motion.gesture-driver — gentle settles softer than snappy (lower stiffness)', () {
      expect(
          ArxaKitSprings.gentle.stiffness, lessThan(ArxaKitSprings.snappy.stiffness));
    });

    test('kit.motion.gesture-driver — ArxaKitGestureDriver defaults to ArxaKitSprings.snappy', () {
      final driver = ArxaKitGestureDriver(vsync: const TestVSync());
      addTearDown(driver.dispose);
      expect(driver.settleSpring, ArxaKitSprings.snappy);
    });

    test('kit.motion.gesture-driver — spec presets resolve alongside the spring vocabulary', () {
      expect(ArxaKitMotionSpec.standard.staggerFraction, 0.06);
      expect(ArxaKitMotionSpec.subtle.staggerFraction, 0.04);
      expect(ArxaKitMotionSpec.energetic.scale, 0.96);
    });
  });

  group('gestureArxaKitMotionScope (testing helper)', () {
    testWidgets('kit.motion.gesture-driver — pins gesture-driven choreography at t', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: gestureArxaKitMotionScope(
          t: 0.0,
          child: const ArxaKitWake(
              order: 0, child: SizedBox(key: Key('g'), height: 10)),
        ),
      ));
      expect(_opacityOf(tester, const Key('g')), 0.0);

      await tester.pumpWidget(MaterialApp(
        home: gestureArxaKitMotionScope(
          t: 1.0,
          child: const ArxaKitWake(
              order: 0, child: SizedBox(key: Key('g'), height: 10)),
        ),
      ));
      expect(_opacityOf(tester, const Key('g')), 1.0);
    });

    testWidgets('kit.motion.gesture-driver — no settle in flight — value stays parked across pumps',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: gestureArxaKitMotionScope(
          t: 0.5,
          child: const SizedBox(key: Key('g'), height: 10),
        ),
      ));
      final scope =
          tester.state<ArxaKitMotionScopeState>(find.byType(ArxaKitMotionScope));
      expect(scope.driver.value, 0.5);
      await tester.pump(const Duration(seconds: 1));
      expect(scope.driver.value, 0.5);
    });
  });
}
