import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';

/// Regression test (exit-animation gap, 2026-07-21): a route-driven
/// AppBoxKitMotionScope must scrub AppBoxKitWake children back down while its route pops.
/// If opacity stays pinned at 1 during the pop, the set-down is broken.
void main() {
  for (final kind in [_RouteKind.material, _RouteKind.cupertino]) {
    testWidgets('kit.motion.route-setdown — route pop scrubs the wake back down (${kind.name})',
        (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => navKey.currentState!.push(
                kind == _RouteKind.material
                    ? MaterialPageRoute<void>(builder: (_) => const _WakePage())
                    : CupertinoPageRoute<void>(
                        builder: (_) => const _WakePage()),
              ),
              child: const Text('push'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      double wakeOpacity() => tester
          .widget<FadeTransition>(find.descendant(
              of: find.byType(AppBoxKitWake), matching: find.byType(FadeTransition)))
          .opacity
          .value;
      expect(wakeOpacity(), 1.0, reason: 'settled after push');

      navKey.currentState!.pop();
      // Mid-transition sample: the pop runs ~300ms; sample at ~1/3 and ~2/3.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid1 = wakeOpacity();
      await tester.pump(const Duration(milliseconds: 100));
      final mid2 = wakeOpacity();
      await tester.pumpAndSettle();

      expect(mid1, lessThan(1.0),
          reason: 'set-down must be scrubbing at 1/3 of the pop');
      expect(mid2, lessThan(mid1),
          reason: 'set-down must keep scrubbing at 2/3 of the pop');
    });
  }
}

enum _RouteKind { material, cupertino }

class _WakePage extends StatelessWidget {
  const _WakePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBoxKitMotionScope(
        child: const SizedBox(width: 10, height: 10).wake(order: 0),
      ),
    );
  }
}
