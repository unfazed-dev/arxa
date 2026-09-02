// Route-push contract: threads open in place. The app theme mounts the
// pushed route untouched — no slide/fade entrance — while the platform
// default would wrap it in a Cupertino slide.
import 'package:arxa_studio_mobile/ui/app_transitions.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpPushUnderTheme(WidgetTester tester, ThemeData theme) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: const Scaffold(body: Text('threads root')),
  ));
  tester.state<NavigatorState>(find.byType(Navigator)).push(
    MaterialPageRoute(builder: (_) => const Scaffold(body: Text('a thread'))),
  );
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the app theme pushes routes with no entrance animation',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpPushUnderTheme(tester,
          ThemeData(pageTransitionsTheme: arxaNoPushTransitionsTheme));

      expect(find.text('a thread'), findsOneWidget);
      expect(find.byType(CupertinoPageTransition), findsNothing,
          reason:
              'the pushed thread mounts untouched — fully there on frame one');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the platform default, by contrast, slides the push in',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpPushUnderTheme(tester, ThemeData(useMaterial3: true));

      expect(find.byType(CupertinoPageTransition), findsOneWidget,
          reason: 'the pre-change behavior: a slide entrance on push');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
