// Whole-matrix guard for route-transition occlusion (NATIVE_COMPONENTS.md
// "Route transitions"): EVERY AppBoxKitNative* widget that mounts a native iOS
// Liquid Glass platform view MUST hide it during a route slide, or the
// hybrid-composition view floats over the transition (glass, or a flat panel if
// merely de-tinted — device-confirmed). The kit does this by wrapping the
// glass tier in AppBoxKitNativeChromeGate — via the `.chromeGated()` sugar or the
// widget directly. The hide RENDERS as a single-frame `IndexedStack` index flip
// — never a fade or scale: animating alpha over a platform view is unsupported
// (flutter#93757, flutter#24164) and is what made glass zoom back in after a
// back-navigation. Either way the gate wrap is what every glass widget must
// ship, which is what this file enforces. This
// test is the "doesn't miss any" backstop: if a new glass widget lands (or a
// refactor strips the wrap), it fails here instead of leaking on device. A
// widget with a genuine reason to stay unwrapped opts out with a
// `// transition-exempt: <reason>` comment.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'kit.ui-library.glass-transition-gate — every native-glass widget transition-gates its platform view',
      () {
    // ALL of `lib/`, recursively — not just `lib/widgets`.
    //
    // The old scan was `Directory('lib/widgets').listSync()`: one directory,
    // non-recursive. It missed a real, reachable leak — `CNToast` mounts a
    // `LiquidGlassContainer` through a bare `OverlayEntry`, and the call site
    // that reaches it lives in `lib/services/notifications/`, outside the
    // walk. A rule enforced over a fraction of the package is a rule that
    // reports green while the hole is somewhere else.
    final dir = Directory('lib');
    expect(dir.existsSync(), isTrue,
        reason: 'run from the ui_library package root');

    // Constructors that mount a real iOS platform view (UiKitView) — the ones
    // that leak during a transition. `\b…\b` so CNButtonData / CNButtonConfig /
    // CNButtonStyle / CNSymbol (data + enums, not platform views) don't match.
    //
    // `CNToast` and `CNIcon` added after the sweep that found the toast leak:
    // both reach a platform view (toast.dart:503 wraps its body in a
    // LiquidGlassContainer; icon.dart:292 is a UiKitView), and neither was
    // listed, so calling either was invisible to this test twice over —
    // wrong directory AND absent from the pattern.
    final platformView = RegExp(
      r'\b(CNButton|CNTextField|CNSwitch|CNSlider|CNRangeSlider'
      r'|CNSegmentedControl|CNSearchBar|CNPopupMenuButton|CNGlassButtonGroup'
      r'|CNSplitButton|CNTabBar|CNFloatingIsland|CNToast|CNIcon'
      r'|LiquidGlassContainer)\s*[.(]',
    );
    final optOut = RegExp(r'//\s*transition-exempt:');

    // Both the platform-view scan and the gated check run over CODE ONLY.
    //
    // This is load-bearing, not tidiness. The check used to read the raw
    // source, so a file could satisfy it by merely MENTIONING `.chromeGated()`
    // in prose — which is how a genuinely ungated `CNToast` call site first
    // reported green here: a comment explaining the leak silenced the test
    // about the leak. The inverse bit too, with doc comments naming widget
    // types flagging files that construct nothing.
    //
    // Whole-line comments only (`//`, `///`). Deliberately not stripping
    // trailing comments — that would need to respect string literals
    // (`'https://…'`), and every case seen so far is a whole line.
    String codeOnly(String src) => src
        .split('\n')
        .where((String line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    final missing = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      final code = codeOnly(src);
      if (!platformView.hasMatch(code)) continue; // no glass platform view here
      // The opt-out is matched against the RAW source: it IS a comment.
      if (optOut.hasMatch(src)) continue; // deliberate exception
      final gated = code.contains('.chromeGated(') ||
          code.contains('AppBoxKitNativeChromeGate(');
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
