// Liquid-glass-law gate (docs/liquid-glass-allowlist.md — THE liquid-glass
// law, ratified 2026-08-13). Sibling of the transition gate: mechanical
// source scans over the kit's widget layer, so a refactor that violates a
// law rule fails HERE instead of shimmering on device. Two rules are
// mechanically checkable today:
//
// 1. Composition rule 1 — no saveLayer effect may wrap a subtree that may
//    host platform views. In kit terms: the saveLayer widgets
//    (BackdropFilter / ImageFiltered / ShaderMask) are confined to the files
//    that own a platform-view-safe branch. A new saveLayer usage anywhere
//    else in the widget layer is guilty until proven safe with a
//    `// glass-law-exempt: <reason>` comment.
// 2. Slide-never-fade — the floating chrome must animate with slides
//    (AnimatedSlide/transform), never Opacity family widgets: partial alpha
//    over platform views lands as per-frame native mutations (glyph
//    washout, ghosts — clip 12-48's resolved residual).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'kit.ui-library.liquid-glass-law-gate — saveLayer widgets stay confined '
      'to their platform-view-safe homes', () {
    final dir = Directory('lib/widgets');
    expect(dir.existsSync(), isTrue,
        reason: 'run from the ui_library package root');

    final saveLayer = RegExp(r'\b(BackdropFilter|ImageFiltered|ShaderMask)\s*\(');
    final optOut = RegExp(r'//\s*glass-law-exempt:');
    // Files whose saveLayer usage is the platform-view-safe machinery itself:
    // the frosted surface's blur branch is only reachable when
    // platformViewSafe is false / pre-glass tiers, and the scroll edge
    // effect's filter is tier-gated to frosted tiers (pinned by
    // appbox_kit_scroll_edge_effect_tier_test).
    const safeHomes = {
      'appbox_kit_frosted_surface.dart',
      'appbox_kit_scroll_edge_effect.dart',
    };

    final offenders = <String>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (safeHomes.contains(name)) continue;
      final src = entity.readAsStringSync();
      if (!saveLayer.hasMatch(src)) continue;
      if (optOut.hasMatch(src)) continue;
      offenders.add(name);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'saveLayer effects over subtrees that may host platform views '
          'drop or ghost Flutter content per frame (law composition rule 1, '
          'flutter#175048). Route the effect through AppBoxKitFrostedSurface '
          '(platformViewSafe) or add `// glass-law-exempt: <reason>`. '
          'Offenders: $offenders',
    );
  });

  test(
      'kit.ui-library.liquid-glass-law-gate — floating chrome animates by '
      'slide, never by alpha', () {
    final src =
        File('lib/widgets/appbox_kit_native_floating_bar.dart').readAsStringSync();
    expect(RegExp(r'\b(AnimatedOpacity|Opacity|FadeTransition)\s*\(').hasMatch(src),
        isFalse,
        reason: 'partial alpha over the bar\'s native actions is the law\'s '
            'forbidden shape (composition rule 1) — tuck and hide must remain '
            'slides');
    expect(src.contains('AnimatedSlide('), isTrue,
        reason: 'the slide machinery is the ratified motion — its absence '
            'means the chrome was rebuilt on a different mechanism without '
            'updating the law');
  });
}
