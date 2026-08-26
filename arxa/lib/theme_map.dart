// theme_map — Dart port of stages/theme_map.py.
//
// W3C DTCG tokens.json (parsed) → a Dart ThemeData fragment mapping the
// design's resolved semantic color tokens (color.<group>.<leaf>) to a
// Stacked ThemeData. Pure token→config map, zero LLM (ADR-0006). The
// fragment is a partial app_theme.dart body the operator merges into the
// emitted theme. Returns '' if no color tokens are present.
//
// Deterministic: same tree → same fragment. Pure Dart (no deps beyond SDK).

/// `tokensTree` (parsed tokens.json, W3C DTCG) → a Dart ThemeData fragment.
///
/// Walks `color.<group>.<leaf>` entries whose `$type` is `"color"`, validates
/// the hex `$value` (`#RRGGBB` → prepend `FF` alpha; `#AARRGGBB` → keep
/// as-is), and emits `ThemeData(...)` with a `// <name> → Color(0xARGB)`
/// comment per token. Returns `''` if there are no color tokens.
String themeMap(Map<String, dynamic> tokensTree) {
  final colorGroup = tokensTree['color'];
  final lines = <String>[]; // formatted "// name → Color(0xARGB)" lines

  if (colorGroup is Map<String, dynamic>) {
    colorGroup.forEach((grpName, grp) {
      if (grp is! Map<String, dynamic>) return;
      grp.forEach((tokName, tok) {
        if (tok is! Map<String, dynamic>) return;
        if (tok[r'$type'] != 'color') return;
        final hexv = tok[r'$value'];
        if (hexv is! String || !hexv.startsWith('#')) return;
        final h = hexv.substring(1);
        if (int.tryParse(h, radix: 16) == null) return; // not hex digits → skip
        // #RRGGBB → alpha FF; #AARRGGBB → alpha already there; else skip.
        final argb = h.length == 6
            ? 'FF${h.toUpperCase()}'
            : (h.length == 8 ? h.toUpperCase() : null);
        if (argb == null) return; // not a plain 6/8-digit hex
        lines.add('    // $grpName.$tokName → Color(0x$argb)');
      });
    });
  }

  if (lines.isEmpty) return '';
  return 'ThemeData(\n'
      '    // design-token-derived (theme_map, ADR-0014 stage 4)\n'
      '${lines.join('\n')}\n'
      '  )  // TODO operator: wire these into colorScheme / extensions\n';
}
