# design-system — studio_shell_studio_session_view

> arxa-scaffolder: STRUCTURE ONLY. The builder (plan 08) fills the real intent.

- **surface:** `studio_shell_studio_session_view`  (studio.session)
- **shell:**  studio_shell
- **derived form factors:** mobile, tablet

## Palette

The ramp is `ArxaKitColors` (light) / `ArxaKitDarkColors` (dark). The brand
accent is NOT a constant — it is a user setting, so read it through the
swatch API and never hard-code one of the hexes below.

- **authored swatches:** `canvas`, `ink`, `terracotta`, `charcoal`, `connected`, `blocked`, `bubble`
- **default:** `terracotta` — `arxaKitAccentByName('terracotta')`, or `arxaKitDefaultAccent` for the same value
- **read a swatch:** `arxaKitAccentByName(name).forBrightness(Theme.of(context).brightness)` — the 5 roles are
  `.accent` `.soft` `.surface` `.text` `.muted`
- **theme:** `arxaKitLightTheme(accent: …)` / `arxaKitDarkTheme(accent: …)` —
  `accent` is a `Color`, not a swatch: pass a role off the swatch
  (e.g. `arxaKitAccentByName(n).forBrightness(b).accent`)

<!-- builder: which of the 5 roles this surface uses, and where -->

## Type

Sizes come from the abx-scale (the theme's `TextTheme` roles) — the font
block chooses the FACE only, never the size.

- **declared families:** `ui-sans`, `display-serif`
- **default:** `ui-sans` — `arxaKitFontById('ui-sans').cssName`
- **apply:** pass that css name to `arxaKitLightTheme(fontFamily: …)` / `arxaKitDarkTheme(fontFamily: …)`
- **NOTE:** a family name whose binary is not bundled falls back to
  the platform default SILENTLY — check `arxaKitFontIsBundled` before
  trusting a face, and call `registerArxaKitFontLicenses()` once bundled

<!-- builder: TextTheme roles this surface uses -->

## Spacing
<!-- builder: spacing tokens (no ad-hoc SizedBox gaps) -->

## Motion
<!-- builder: ArxaKitMotionSpec.* presets/curves/durations -->

## Forbidden
- `Icons.*` (use `ArxaKitGlyphs.*`)
- ad-hoc `Color(0x…)` (use `ArxaKitColors.*`)
- stock `ElevatedButton`/`FilledButton`/`TextButton` CTAs (use `ArxaKitNativeButton`)
