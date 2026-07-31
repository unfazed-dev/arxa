// Whole-matrix guard for route-transition occlusion (NATIVE_COMPONENTS.md
// "Route transitions"): EVERY KitNative* widget that mounts a native iOS
// Liquid Glass platform view MUST hide it during a route slide, or the
// hybrid-composition view floats over the transition (glass, or a flat panel if
// merely de-tinted — device-confirmed). The kit does this by wrapping the
// glass tier in KitNativeChromeGate — via the `.chromeGated()` sugar or the
// widget directly. Per ADR 0010 the hide RENDERS as a dematerialize (fade +
// slight scale, Apple's `effect = nil` semantic) rather than an instant
// alpha-0, but the gate wrap is still what every glass widget must ship. This
// test is the "doesn't miss any" backstop: if a new glass widget lands (or a
// refactor strips the wrap), it fails here instead of leaking on device. A
// widget with a genuine reason to stay unwrapped opts out with a
// `// transition-exempt: <reason>` comment.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every native-glass widget transition-gates its platform view', () {
    final dir = Directory('lib/widgets');
    expect(dir.existsSync(), isTrue,
        reason: 'run from the ui_library package root');

    // Constructors that mount a real iOS platform view (UiKitView) — the ones
    // that leak during a transition. `\b…\b` so CNButtonData / CNButtonConfig /
    // CNButtonStyle / CNSymbol (data + enums, not platform views) don't match.
    final platformView = RegExp(
      r'\b(CNButton|CNTextField|CNSwitch|CNSlider|CNRangeSlider'
      r'|CNSegmentedControl|CNSearchBar|CNPopupMenuButton|CNGlassButtonGroup'
      r'|CNSplitButton|CNTabBar|CNFloatingIsland|LiquidGlassContainer)\s*[.(]',
    );
    final optOut = RegExp(r'//\s*transition-exempt:');

    final missing = <String>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      if (!platformView.hasMatch(src)) continue; // no glass platform view here
      if (optOut.hasMatch(src)) continue; // deliberate exception
      final gated =
          src.contains('.chromeGated(') || src.contains('KitNativeChromeGate(');
      if (!gated) missing.add(entity.path.split(Platform.pathSeparator).last);
    }

    expect(
      missing,
      isEmpty,
      reason: 'These render a native Liquid Glass platform view but never '
          'transition-gate it — add `.chromeGated()` to the glass tier (or a '
          '`// transition-exempt: <reason>` comment). They will leak over route '
          'slides. Offenders: $missing',
    );
  });
}
