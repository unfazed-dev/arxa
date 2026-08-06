import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/material.dart';

/// Shared helpers for native kit widget tests (Material-3-Expressive + Liquid
/// Glass). Import this instead of re-deriving [withAndroidFallback] per file —
/// its restore placement is load-bearing (see below).

/// Wraps a native kit widget with the ancestors it needs to build in tests
/// (Directionality + Material/Scaffold).
Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// Forces `cupertino_native_better` widgets to take their pure-Material
/// fallback for the duration of [body], so a native UiKitView is never
/// constructed. A UiKitView can't render in a headless flutter_test on this
/// macOS-26 host, where CN's `shouldUseNativeGlass` is true.
///
/// `debugDefaultTargetPlatformOverride` MUST be null again before the test body
/// returns: flutter_test's `_verifyInvariants` (which asserts all foundation
/// debug vars are unset) runs *before* `addTearDown`/`tearDown`, so the restore
/// can't live in a tearDown callback. try/finally within the body is the only
/// correct placement — hence this helper rather than a setUp/tearDown pair.
///
/// This diverts ONLY the CN-internal render path. The kit's own gate
/// (AppBoxKitPlatform.supportsComposeM3E → M3E tier) is unaffected and is asserted
/// independently per widget via `find.byType(<M3E widget>)`.
Future<void> withAndroidFallback(Future<void> Function() body) async {
  final saved = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = saved;
  }
}
