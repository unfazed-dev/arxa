import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The modal-depth auto-bracket pin: `CNTabBarRouteObserver`'s `_isAnyModal`
/// matches every `PopupRoute`, so ANY modal route — a raw `showDialog`
/// included — bumps `anyModalDepth` for its lifetime with NO manual
/// `markAnyModalActive/Inactive` at the call site, as long as the observer is
/// registered on the presenting navigator (the kit registration inherits into
/// the nested tab routers via StackedTabsRouter's default
/// `inheritNavigatorObservers: true`). This is what keeps native chrome from
/// compositing above a modal (the ghost-chrome class). The kit's own
/// sheet/dialog/overlay functions keep their explicit brackets as
/// defense-in-depth for the non-route case (Overlay entries the observer
/// cannot see).
void main() {
  testWidgets(
      'kit.ui-library.modal-depth — a raw dialog route self-brackets the modal depth while presented',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [CNTabBarRouteObserver()],
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(title: Text('raw dialog')),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    final baseline = CNTabBarRouteObserver.anyModalDepth.value;

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('raw dialog'), findsOneWidget);
    expect(CNTabBarRouteObserver.anyModalDepth.value, baseline + 1,
        reason: 'a DialogRoute is a PopupRoute — the observer brackets it '
            'with no call-site marks');

    // Dismiss via the barrier; the observer defers the broad decrement until
    // the exit animation reports dismissed (vendor Issue #37 halo), so the
    // assertion runs after the settle.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('raw dialog'), findsNothing);
    expect(CNTabBarRouteObserver.anyModalDepth.value, baseline,
        reason: 'the bracket releases when the route finishes dismissing — '
            'no leak across presentations');
  });
}
