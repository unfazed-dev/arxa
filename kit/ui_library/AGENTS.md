# ui_library/ — AGENTS.md

Nested schema for the UI tier. Repo-wide contract: `../AGENTS.md`; the verified
map: `../skills/_kit-system.md`. This file owns the native-first widget rules.
The component inventory is `COMPONENTS.md`; the canonical tier matrix + ban
list is `../core/NATIVE_COMPONENTS.md` — read it before reaching for any
primitive.

## Native-first (the rule)

- Reach for the `KitNative*` widget or `kitShowNative*` function **before** any
  stock Flutter widget — real Liquid Glass on iOS 26, real M3 Expressive on
  Android, a kit-owned fallback elsewhere. The gates enforce every ✅ matrix
  row (`../skills/kit-designer/scripts/enforce_design.dart` 4f/4g,
  `../skills/kit-reviewer/scripts/review_checklist.sh` 1c–1y): a stock
  `AppBar`, `TextField`, `Switch`, `showModalBottomSheet(`, … in an app
  surface fails the gate.
- Content surfaces (tile / card / banner / panel) compose on **`KitGlassCard`**
  — never a hand-rolled `Material(color:)` or decorated `Container(` card
  (gate: `no_raw_card_surface`).
- Deliberate plain Flutter opts out per-widget with a
  `// flutter-only: <reason>` comment (→ `wantNative: false`) or per-surface
  with the designer's `--flutter-only`. Native-first is otherwise the default.

## The KitNative* wrapping pattern

- Three tiers per widget: iOS (vendored `cupertino_native_better`, self-gates
  real glass on iOS 26) → Android M3E (`m3e_collection`, resolved to the
  vendored `*_m3e` forks via root `dependency_overrides`) → Flutter fallback
  (Cupertino/Material stock). The widget's own doc comment names its tiers.
- Public surfaces are **primitives only** (labels, glyphs, values, callbacks)
  — hosts never import `m3e_collection` or `cupertino_native_better`.
- `wantNative` is the host opt-out; a `null` callback disables the control on
  every tier.
- Icons go through `glyph: KitGlyphs.<x>` — one token pairing the Material
  icon with its SF Symbol; raw `icon:`/`sfSymbol:` are per-call overrides.
- No native tier exists → the widget is named `Kit*`, **never** `KitNative*`
  (the `no_invented_native_widgets` allowlist; `KitImage` is the example).

## Vendored forks — never consumed directly

`vendor/` holds six packages (ADR-0002): `cupertino_native_better` and
`text_field_m3e` (path deps) plus `fab_m3e`, `split_button_m3e`,
`toolbar_m3e`, `navigation_rail_m3e` (reached transitively through the
`m3e_collection` umbrella via root `dependency_overrides`). Consume them
**only** through the `KitNative*` family — never by direct import, never by
path-dep'ing a fork from an app.

## Theme

Host apps take light/dark themes from `kitLightTheme()` / `kitDarkTheme()`
(`../core/lib/common/kit_colors.dart`) driven by `KitThemeService`
(`../core/lib/services/theme/kit_theme_service.dart`); M3E motion cascades
from the expressive theme set once at the app top. Do not hand-build
`ThemeData` in a kit app.

## Adding a native surface

One row in `../core/NATIVE_COMPONENTS.md` **and** one ban row in
`_nativeSurfaceBans` (`enforce_design.dart`) — matrix and guard stay in
lockstep — plus the widget, the `lib/ui_library.dart` barrel export, and a
`COMPONENTS.md` row.

## Testing

`lib/testing.dart` ships scriptable fakes — `FakeKitNotificationService`,
`FakeKitBottomSheetService`, `FakeKitNavigationControllerService`. Register
them in the locator; tests never touch a navigator, an `Overlay`, or platform
channels.
