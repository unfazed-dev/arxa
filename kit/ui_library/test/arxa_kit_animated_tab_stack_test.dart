// A visited-but-hidden tab stays mounted and painting (platform-view
// containment — the alpha/translate idiom) but must not TICK: a perpetual
// animator in a hidden tab would otherwise schedule frames on every vsync
// for a tab nobody is looking at (showcase idle-warmth class of bug).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ArxaKitPlatform.reset);

  Widget stack(int active) => Directionality(
        textDirection: TextDirection.ltr,
        child: ArxaKitAnimatedTabStack(
          activeIndex: active,
          children: const [
            _Probe(key: ValueKey('a')),
            _Probe(key: ValueKey('b')),
            _Probe(key: ValueKey('c')),
          ],
        ),
      );

  bool ticking(WidgetTester tester, String id) => TickerMode.valuesOf(
          tester.element(find.byKey(ValueKey(id), skipOffstage: false)))
      .enabled;

  testWidgets(
    'kit.ui_library.animated-tab-stack — visited-but-hidden tabs are ticker-muted (iOS cross-cut)',
    (tester) async {
      ArxaKitPlatform.override =
          const ArxaKitPlatformOverride(isIOS: true, iosMajor: 26);
      await tester.pumpWidget(stack(0));
      expect(ticking(tester, 'a'), isTrue);
      // Unvisited tabs are not even inflated (lazy keep-alive).
      expect(find.byKey(const ValueKey('b'), skipOffstage: false),
          findsNothing);

      await tester.pumpWidget(stack(1));
      await tester.pump();
      expect(ticking(tester, 'a'), isFalse,
          reason: 'hidden tab must not schedule frames');
      expect(ticking(tester, 'b'), isTrue);

      await tester.pumpWidget(stack(2));
      await tester.pump();
      expect(ticking(tester, 'a'), isFalse);
      expect(ticking(tester, 'b'), isFalse);
      expect(ticking(tester, 'c'), isTrue);
    },
  );

  testWidgets(
    'kit.ui_library.animated-tab-stack — exiting tab ticks through the exit, then mutes (animated tier)',
    (tester) async {
      ArxaKitPlatform.override =
          const ArxaKitPlatformOverride(isAndroid: true);
      await tester.pumpWidget(stack(0));
      await tester.pumpWidget(stack(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // mid-run (220ms)
      expect(ticking(tester, 'a'), isTrue,
          reason: 'the exiting tab is still on screen mid-run');
      expect(ticking(tester, 'b'), isTrue);
      await tester.pump(const Duration(milliseconds: 200)); // run completes
      await tester.pump();
      expect(ticking(tester, 'a'), isFalse);
      expect(ticking(tester, 'b'), isTrue);
    },
  );
}

class _Probe extends StatelessWidget {
  const _Probe({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
