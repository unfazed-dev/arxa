import 'package:flutter/widgets.dart';

import 'arxa_kit_glyphs_lucide_map.g.dart';

export 'arxa_kit_glyphs_lucide_map.g.dart';

/// Lucide icon namespace — resolves a Lucide design name (kebab-case, as on
/// lucide.dev, e.g. `'arrow-left'`) to its [IconData]. Reached as
/// `ArxaKitGlyphs.lucide('arrow-left')`.
///
/// Backed by `lucide_flutter`; the name→glyph map ([arxaKitLucideGlyphMap]) is
/// GENERATED from that package's own source by `tools/gen_lucide_glyphs.py`
/// and committed — regenerate it on a lucide_flutter bump. Adding a third
/// icon library means one more generated map + one more namespace class like
/// this one (exposed as another `ArxaKitGlyphs.<library>` accessor) — no
/// call-site changes.
///
/// Unknown names: an unknown name asserts in debug builds (a typo'd design
/// name is a build-time bug and should be loud), and falls back to the
/// `circle` glyph in release — it never crashes a release build and never
/// renders blank. The kit's Material catalog has no by-name lookup to mirror,
/// so this is the documented policy for every by-name namespace.
final class ArxaKitLucideGlyphs {
  const ArxaKitLucideGlyphs();

  static const _fallback = 'circle';

  /// The glyph for Lucide design name [name] (see class docs for the
  /// unknown-name policy).
  IconData call(String name) {
    final icon = arxaKitLucideGlyphMap[name];
    assert(icon != null, 'ArxaKitGlyphs.lucide: unknown Lucide icon "$name"');
    return icon ?? arxaKitLucideGlyphMap[_fallback]!;
  }
}
