# Lucide-only icon unification

Status: decided (grilled 2026-08-10). Advisor consult skipped — no API key in
`ANTHROPIC_API_KEY` / `~/.config/consult-mode/api-key.json`; plan rests on
primary-source evidence below.

## Problem

Showcase native Apple chrome shows two visibly different icon kinds: crisp SF
Symbols next to pixelated lucide glyphs. Root causes:

1. **Raster bug** — `SVGImageLoader.swift:156` (`performSVGRendering`,
   `kit/ui_library/vendor/cupertino_native_better/ios/...`) renders SVGKit
   images at logical point size, scale 1.0. 24×24 bitmap upscaled on 2x/3x
   displays → pixelation. Same risk on the `customIconBytes` PNG path
   (`CupertinoButtonPlatformView.swift`, priority `imageAsset > customIcon > icon`).
2. **Tri-vocabulary** — `AppBoxKitGlyph(Icons.home, 'house.fill')` pairs
   Material (Android/M3E tier) + SF Symbol (Apple tiers); Lucide is a third
   vocabulary for content (1,994 `LucideIcons.` usages, `lucide_flutter ^1.25.0`
   — the canonical lucide-icons-org package).

Designer (vendored lucide SVGs, kebab-case) and scaffolder (UI icons must
resolve to kit glyph catalog) are already lucide-coherent. Only native chrome
diverges.

## Decisions (user-confirmed)

| Decision | Choice |
|---|---|
| Scope | Lucide everywhere, including native chrome |
| Apple chrome rendering | Custom SF Symbols bundle **generated from our vendored lucide SVGs** (ISC), riding the existing `withSymbolConfiguration` pipeline in `cupertino_native_better` |
| Android/M3E tier | `lucide_flutter` font glyphs, Flutter-rendered; Material vocabulary dies |
| API shape | Keep `AppBoxKitGlyph` type + semantic catalog; back it by a single lucide name that yields IconData (font) + symbol name (Apple bundle) |
| Raster bug | Fix regardless (render at screen scale) — protects any residual SVG/customIcon path |

## Workstreams (order matters)

1. **Fix raster scale bug** (independent, ship first)
   - `performSVGRendering`: render via `UIGraphicsImageRenderer` (inherits
     screen scale) or multiply size by `UIScreen.main.scale` / view
     `backingScaleFactor` (macOS).
   - Audit `customIconBytes` Dart-side rasterization for devicePixelRatio.
   - Check: side-by-side screenshot of chrome icons at 2x before/after.
2. **Symbol bundle generator**
   - Tool converts vendored lucide SVGs → Apple SF Symbol template format
     (custom symbols require the template SVG, not raw SVG) → `.symbolset`s in
     an asset catalog bundled with `cupertino_native_better` (or kit assets).
   - Version-locked to `lucide_flutter` vocabulary; regenerate on package bump.
3. **Glyph catalog rewrite**
   - `AppBoxKitGlyph` internals: one lucide name → `LucideIcons` IconData +
     custom symbol name. ~59 catalog entries remapped Material→lucide
     equivalents; call sites unchanged.
   - Native side: resolve custom symbols via `UIImage(named:in:)` /
     `NSImage(symbolName:bundle:)` before falling back to system symbols.
4. **Guardrails**
   - Lint/probe: no `Icons.`/`CupertinoIcons.` outside generated files; native
     chrome call sites must come through the catalog.

## Native lucide options evaluated

- Chosen: generated custom SF Symbols bundle (SymbolConfiguration weights, vector-crisp, no new dep).
- Rejected: opensymbols.dev prebuilt (version drift, external cadence);
  JakubMazur/lucide-icons-swift SPM (bypasses SymbolConfiguration);
  harispdev/lucide-swiftui (restrictive non-MIT license).
