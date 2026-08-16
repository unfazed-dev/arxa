import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_directional_tab_transition.dart';

// The child handed to AppBoxKitDirectionalTabTransition is an IndexedStack that
// retains visited tabs. If the transition rebuilds that child on a switch, the
// stack resets and every tab loses its state (scroll, forms, viewmodels). This
// counts child State creations: a preserved child inits exactly once across
// switches. Regression guard for the "wrappers inserted only on the first
// switch rebuild the stack" bug.
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

  testWidgets(
      'kit.ui-library.directional-tab-transition — retains the tabs-stack element across tab switches',
      (tester) async {
    Widget frame(int index) => Directionality(
          textDirection: TextDirection.ltr,
          child: AppBoxKitDirectionalTabTransition(
            activeIndex: index,
            animation: const AlwaysStoppedAnimation<double>(1),
            child: const _Probe(),
          ),
        );

    await tester.pumpWidget(frame(0));
    expect(_probeInits, 1, reason: 'child built once at startup');

    // First switch (0 -> 1): the transition must NOT rebuild its child, or the
    // whole IndexedStack resets and every retained tab loses its state.
    await tester.pumpWidget(frame(1));
    await tester.pump();
    expect(_probeInits, 1,
        reason: 'the tabs stack must survive the first switch, not re-init');

    // Later switch (1 -> 0) must also preserve it.
    await tester.pumpWidget(frame(0));
    await tester.pump();
    expect(_probeInits, 1,
        reason: 'the tabs stack must survive later switches');
  });
}
