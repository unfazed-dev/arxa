// Regression: a Flutter-side theme flip must reach an already-created native
// platform view.
//
// Every CN platform view pins its own appearance on the Swift side with
// `container.overrideUserInterfaceStyle = isDark ? .dark : .light`. That call
// deliberately isolates the view from the window's trait collection, so the
// view can NEVER learn about an app-level theme change by inheritance — the
// only channel is an explicit `setBrightness` invocation from Dart.
//
// `CNTextField` and `CNSearchBar` passed `isDark` as a creation parameter and
// then never sent it again, so they kept their creation-time appearance until
// the platform view happened to be recreated. On device that read as "some
// glass UI is still dark after switching to light, and it fixes itself a while
// later while navigating" — the "while" being the time until recreation.
//
// The Swift handlers already existed (CupertinoTextFieldPlatformView.swift:135,
// CupertinoSearchBarPlatformView.swift:133); only the Dart call was missing.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupertino_native_better/cupertino_native_better.dart';

/// Drives the `UiKitView` creation handshake and then spies on the per-view
/// method channel the widget opens.
///
/// The platform-view id counter is **global and monotonic across a test file**,
/// so the channel name is not `<viewType>_0` for every test — the second test
/// in a file gets `_1`, and so on. Hard-coding `_0` makes every later test
/// silently observe a channel nobody talks on, which reads exactly like "the
/// fix doesn't work". So the id is read back from the `create` call instead of
/// assumed.
class _PlatformViewHarness {
  final List<MethodCall> calls = <MethodCall>[];
  int? _viewId;
  String? _viewType;
  MethodChannel? _spied;

  void installCreateHandler() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views,
            (MethodCall call) async {
      if (call.method == 'create') {
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        _viewId = args['id'] as int;
        _viewType = args['viewType'] as String;
        return _viewId;
      }
      return null;
    });
  }

  /// Call after the first pump, once `create` has run and the real id is known.
  void spyOnViewChannel() {
    expect(_viewId, isNotNull,
        reason: 'platform view was never created — the widget has no channel '
            'and every assertion about it would be vacuous');
    final MethodChannel channel = MethodChannel('${_viewType}_$_viewId');
    _spied = channel;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return null;
    });
  }

  /// Every `isDark` value pushed via `setBrightness`, in order.
  List<bool> get brightnessPushes => calls
      .where((MethodCall c) => c.method == 'setBrightness')
      .map((MethodCall c) => (c.arguments as Map)['isDark'] as bool)
      .toList();

  void dispose() {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    if (_spied != null) messenger.setMockMethodCallHandler(_spied!, null);
  }
}

/// Builds [child] under an explicit [brightness] so the flip is driven by the
/// app theme (what the user toggles), not by the platform brightness.
Widget _app(Brightness brightness, Widget child) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );

/// Sets [debugDefaultTargetPlatformOverride] for the duration of [body].
///
/// The restore must happen before the test body returns — flutter_test's
/// invariant check runs before `tearDown` and fails the test with "a foundation
/// debug variable was changed by the test" otherwise. Same helper and same
/// reason as `rebuild_stability_test.dart:76`.
Future<void> _withIOS(Future<void> Function() body) async {
  final TargetPlatform? saved = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = saved;
  }
}

void main() {
  late _PlatformViewHarness harness;

  setUp(() {
    harness = _PlatformViewHarness()..installCreateHandler();
  });

  tearDown(() {
    harness.dispose();
  });

  testWidgets(
      'cn.text-field — an app theme flip pushes setBrightness to the '
      'already-created native view', (WidgetTester tester) async {
    await _withIOS(() async {
      await tester.pumpWidget(_app(Brightness.light, const CNTextField()));
      await tester.pumpAndSettle();

      // The platform view must really exist, or the widget holds no channel and
      // the assertions below would pass for the wrong reason.
      expect(find.byType(UiKitView), findsOneWidget);
      harness.spyOnViewChannel();

      await tester.pumpWidget(_app(Brightness.dark, const CNTextField()));
      await tester.pumpAndSettle();

      expect(harness.brightnessPushes, <bool>[true],
          reason: 'theme flip did not reach the native text field — it would '
              'keep its creation-time appearance until the view was recreated');

      // Flip back: the native side must return to light too. A one-way test
      // would pass against a fix that hard-coded `true`.
      await tester.pumpWidget(_app(Brightness.light, const CNTextField()));
      await tester.pumpAndSettle();

      expect(harness.brightnessPushes, <bool>[true, false],
          reason: 'flip back to light did not reach the native text field');
    });
  });

  testWidgets('cn.text-field — rebuilding at the same brightness sends nothing',
      (WidgetTester tester) async {
    await _withIOS(() async {
      await tester.pumpWidget(_app(Brightness.dark, const CNTextField()));
      await tester.pumpAndSettle();
      harness.spyOnViewChannel();

      await tester.pumpWidget(
          _app(Brightness.dark, const CNTextField(placeholder: 'changed')));
      await tester.pumpAndSettle();

      // Guards the `_lastIsDark` short-circuit: without it every dependency
      // change would fire a channel round-trip on every rebuild.
      expect(harness.brightnessPushes, isEmpty,
          reason: 'a same-brightness rebuild must not touch the channel');
    });
  });

  testWidgets(
      'cn.search-bar — an app theme flip pushes setBrightness to the '
      'already-created native view', (WidgetTester tester) async {
    await _withIOS(() async {
      await tester.pumpWidget(_app(Brightness.light, const CNSearchBar()));
      await tester.pumpAndSettle();

      expect(find.byType(UiKitView), findsOneWidget);
      harness.spyOnViewChannel();

      await tester.pumpWidget(_app(Brightness.dark, const CNSearchBar()));
      await tester.pumpAndSettle();

      expect(harness.brightnessPushes, <bool>[true],
          reason: 'theme flip did not reach the native search bar — it would '
              'keep its creation-time appearance until the view was recreated');
    });
  });
}
