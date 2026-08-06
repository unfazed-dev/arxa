import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_tab_switch_transition.dart';

// The child handed to AppBoxKitTabSwitchTransition is an IndexedStack that retains
// tabs. If the transition rebuilds that child on a switch, the stack resets
// and every tab loses its state (scroll, forms, viewmodels). This counts
// child State creations: a preserved child inits exactly once across switches.
int _probeInits = 0;

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _probeInits++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUp(() => _probeInits = 0);

  testWidgets('retains the tabs-stack element across tab switches',
      (tester) async {
    Widget frame(int index) => Directionality(
          textDirection: TextDirection.ltr,
          child: AppBoxKitTabSwitchTransition(
            activeIndex: index,
            child: const _Probe(),
          ),
        );

    await tester.pumpWidget(frame(0));
    expect(_probeInits, 1, reason: 'child built once at startup');

    await tester.pumpWidget(frame(1));
    await tester.pump();
    expect(_probeInits, 1,
        reason: 'the tabs stack must survive the first switch, not re-init');

    await tester.pumpWidget(frame(0));
    await tester.pump();
    expect(_probeInits, 1, reason: 'the tabs stack must survive later switches');
  });

  testWidgets('no phantom motion before the first switch', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AppBoxKitTabSwitchTransition(
          activeIndex: 0,
          child: SizedBox.shrink(),
        ),
      ),
    );
    final slide = tester.widget<SlideTransition>(find.byType(SlideTransition));
    expect(slide.position.value, Offset.zero,
        reason: 'startup parks the controller at 1.0 — zero offset');
  });

  testWidgets('direction helper: higher index enters from trailing edge, '
      'lower from leading (LTR)', (tester) async {
    Widget frame(int index) => Directionality(
          textDirection: TextDirection.ltr,
          child: AppBoxKitTabSwitchTransition(
            activeIndex: index,
            child: const _Probe(),
          ),
        );

    await tester.pumpWidget(frame(0));
    await tester.pumpWidget(frame(2)); // forward
    await tester.pump();
    var slide = tester.widget<SlideTransition>(find.byType(SlideTransition));
    // Mid-animation: positive dx — the incoming tab is still right of home.
    expect(slide.position.value.dx, greaterThan(0),
        reason: 'forward switch slides in from the trailing edge');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(frame(0)); // backward
    await tester.pump();
    slide = tester.widget<SlideTransition>(find.byType(SlideTransition));
    expect(slide.position.value.dx, lessThan(0),
        reason: 'backward switch slides in from the leading edge');

    await tester.pump(const Duration(milliseconds: 300));
    expect(slide.position.value, Offset.zero,
        reason: 'the entrance settles home');
  });

  testWidgets('fade stays off by default (platform-view safety)',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AppBoxKitTabSwitchTransition(
          activeIndex: 0,
          child: SizedBox.shrink(),
        ),
      ),
    );
    expect(find.byType(FadeTransition), findsNothing,
        reason: 'opacity-animating platform-view subtrees ghosts '
            '(flutter#148639) — fade must be opt-in');
  });
}
