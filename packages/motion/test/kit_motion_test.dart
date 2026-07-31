import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_motion/testing.dart';

Widget _host({
  required Animation<double> driver,
  required Widget child,
  KitMotionSpec? spec,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: KitMotionScope(driver: driver, spec: spec, child: child),
      ),
    ),
  );
}

double _opacityOf(WidgetTester tester, Key key) {
  final fade = tester.widget<FadeTransition>(
    find
        .ancestor(of: find.byKey(key), matching: find.byType(FadeTransition))
        .first,
  );
  return fade.opacity.value;
}

void main() {
  late AnimationController driver;

  setUp(() {
    driver = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 300),
    );
  });

  tearDown(() => driver.dispose());

  group('KitWake stagger', () {
    testWidgets('later orders wake later on the timeline', (tester) async {
      driver.value = 0.12;
      await tester.pumpWidget(_host(
        driver: driver,
        child: const Column(children: [
          KitWake(order: 0, child: SizedBox(key: Key('a'), height: 10)),
          KitWake(order: 5, child: SizedBox(key: Key('b'), height: 10)),
        ]),
      ));
      final early = _opacityOf(tester, const Key('a'));
      final late_ = _opacityOf(tester, const Key('b'));
      expect(early, greaterThan(0.0));
      expect(late_, 0.0); // order 5 starts at 0.30 > 0.12
      expect(early, greaterThan(late_));
    });

    testWidgets('settles to identity at driver == 1', (tester) async {
      driver.value = 1.0;
      await tester.pumpWidget(_host(
        driver: driver,
        spec: const KitMotionSpec(scale: 0.9),
        child: const KitWake(
            order: 3, child: SizedBox(key: Key('a'), height: 10)),
      ));
      expect(_opacityOf(tester, const Key('a')), 1.0);
      final slide = tester.widget<SlideTransition>(find
          .ancestor(
              of: find.byKey(const Key('a')),
              matching: find.byType(SlideTransition))
          .first);
      expect(slide.position.value, Offset.zero);
      final scale = tester.widget<ScaleTransition>(find
          .ancestor(
              of: find.byKey(const Key('a')),
              matching: find.byType(ScaleTransition))
          .first);
      expect(scale.scale.value, 1.0);
    });

    testWidgets('set-down scrubs in reverse with the driver', (tester) async {
      driver.value = 1.0;
      await tester.pumpWidget(_host(
        driver: driver,
        child: const KitWake(
            order: 2, child: SizedBox(key: Key('a'), height: 10)),
      ));
      expect(_opacityOf(tester, const Key('a')), 1.0);

      driver.value = 0.3; // scrub back mid-flight (swipe-to-pop)
      await tester.pump();
      final mid = _opacityOf(tester, const Key('a'));
      expect(mid, lessThan(1.0));

      driver.value = 0.0;
      await tester.pump();
      expect(_opacityOf(tester, const Key('a')), 0.0);
    });

    testWidgets('auto-claims sequential orders in build order',
        (tester) async {
      driver.value = 0.1;
      await tester.pumpWidget(_host(
        driver: driver,
        child: const Column(children: [
          KitWake(child: SizedBox(key: Key('first'), height: 10)),
          KitWake(child: SizedBox(key: Key('second'), height: 10)),
        ]),
      ));
      final first = _opacityOf(tester, const Key('first'));
      final second = _opacityOf(tester, const Key('second'));
      expect(first, greaterThan(second)); // slot 0 leads slot 1
    });

    testWidgets('maxStartFraction budgets late orders', (tester) async {
      driver.value = 0.55;
      await tester.pumpWidget(_host(
        driver: driver,
        child: const KitWake(
            order: 99, child: SizedBox(key: Key('a'), height: 10)),
      ));
      // 99 * 0.06 would start at 5.94 (never); clamp to 0.5 keeps it alive.
      expect(_opacityOf(tester, const Key('a')), greaterThan(0.0));
    });
  });

  group('safe degrades', () {
    testWidgets('reduce-motion renders children untouched', (tester) async {
      driver.value = 0.0;
      await tester.pumpWidget(_host(
        driver: driver,
        disableAnimations: true,
        child: const KitWake(
            order: 0, child: SizedBox(key: Key('a'), height: 10)),
      ));
      expect(
        find.descendant(
            of: find.byType(KitWake),
            matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(find.byKey(const Key('a')), findsOneWidget);
    });

    testWidgets('spec.enabled == false renders children untouched',
        (tester) async {
      driver.value = 0.0;
      await tester.pumpWidget(_host(
        driver: driver,
        spec: const KitMotionSpec(enabled: false),
        child: const KitWake(
            order: 0, child: SizedBox(key: Key('a'), height: 10)),
      ));
      expect(
        find.descendant(
            of: find.byType(KitWake),
            matching: find.byType(FadeTransition)),
        findsNothing,
      );
    });

    testWidgets('no scope above renders children untouched', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: KitWake(order: 0, child: SizedBox(key: Key('a'), height: 10)),
      ));
      // MaterialApp's route animation is not consulted without a scope.
      expect(find.byKey(const Key('a')), findsOneWidget);
    });
  });

  group('extensions', () {
    testWidgets('.wake() wraps in KitWake', (tester) async {
      driver.value = 1.0;
      await tester.pumpWidget(_host(
        driver: driver,
        child: const SizedBox(key: Key('a'), height: 10).wake(order: 1),
      ));
      expect(find.byType(KitWake), findsOneWidget);
      expect(_opacityOf(tester, const Key('a')), 1.0);
    });

    testWidgets('.wakeAll() assigns sequential explicit orders',
        (tester) async {
      driver.value = 0.1;
      await tester.pumpWidget(_host(
        driver: driver,
        child: Column(
          children: const <Widget>[
            SizedBox(key: Key('w0'), height: 10),
            SizedBox(key: Key('w1'), height: 10),
            SizedBox(key: Key('w2'), height: 10),
          ].wakeAll(),
        ),
      ));
      final wakes =
          tester.widgetList<KitWake>(find.byType(KitWake)).toList();
      expect(wakes.map((w) => w.order), [0, 1, 2]);
      expect(
        _opacityOf(tester, const Key('w0')),
        greaterThan(_opacityOf(tester, const Key('w2'))),
      );
    });
  });

  group('KitMotionAdapter', () {
    testWidgets('drives flutter_animate effects from the scope driver',
        (tester) async {
      driver.value = 0.0;
      await tester.pumpWidget(_host(
        driver: driver,
        child: Builder(builder: (context) {
          return const SizedBox(key: Key('a'), height: 10)
              .animate(adapter: KitMotionAdapter.of(context, order: 0))
              .fadeIn();
        }),
      ));
      // Flush Animate's zero-delay init timer before asserting.
      await tester.pump(const Duration(milliseconds: 16));
      expect(_opacityOf(tester, const Key('a')), 0.0);

      driver.value = 1.0;
      await tester.pump();
      expect(_opacityOf(tester, const Key('a')), 1.0);

      driver.value = 0.0; // reverse scrub reaches Animate too
      await tester.pump();
      expect(_opacityOf(tester, const Key('a')), 0.0);
    });

    testWidgets('degrades to settled without a scope', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return const SizedBox(key: Key('a'), height: 10)
              .animate(adapter: KitMotionAdapter.of(context))
              .fadeIn();
        }),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_opacityOf(tester, const Key('a')), 1.0);
    });
  });

  group('testing helpers', () {
    testWidgets('staticKitMotionScope pins the timeline', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: staticKitMotionScope(
          t: 0.0,
          child: const KitWake(
              order: 0, child: SizedBox(key: Key('a'), height: 10)),
        ),
      ));
      expect(_opacityOf(tester, const Key('a')), 0.0);

      await tester.pumpWidget(MaterialApp(
        home: staticKitMotionScope(
          child: const KitWake(
              order: 0, child: SizedBox(key: Key('b'), height: 10)),
        ),
      ));
      expect(_opacityOf(tester, const Key('b')), 1.0);
    });
  });

  group('KitMotionSpec', () {
    test('startFor staggers and clamps', () {
      const spec = KitMotionSpec();
      expect(spec.startFor(0), 0.0);
      expect(spec.startFor(2), closeTo(0.12, 1e-9));
      expect(spec.startFor(99), 0.5);
    });

    test('lerp interpolates continuous channels', () {
      final mid = const KitMotionSpec()
          .lerp(const KitMotionSpec(offset: Offset(0, 0.16)), 0.5);
      expect(mid.offset.dy, closeTo(0.12, 1e-9));
    });

    test('theme extension resolution falls back to standard', () {
      expect(
        ThemeData().extension<KitMotionSpec>(),
        isNull,
      );
    });
  });
}
