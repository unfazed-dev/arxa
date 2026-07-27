# tokens.json — the design→code seam (W3C DTCG 2025.10)

> The seam between design and code. Every prod design pipeline consumes tokens; none scrape HTML
> for style. The Designer emits an **authoritative** `tokens.json`; `transform_tokens` turns it into
> iOS Swift / Android Kotlin / web Dart (replacing the lossy `extract_tokens` HTML-scrape). See
> `tokens.template.json` for the skeleton. Precedence: Designer tokens win, else scrape.

## Format — W3C Design Tokens Format Module (2025.10, first stable)
Two parts per token: `$value` (raw) + `$type` (color/dimension/number/fontFamily/duration/cubicBezier/
shadow…). Groups nest. The `$extensions` object carries **vendor metadata** — this is where
platform-awareness rides.

```json
{
  "color": {
    "brand": {
      "$type": "color",
      "$value": "#C04A1A",
      "$extensions": {
        "org.w3c.dtcg": { "description": "primary brand accent" },
        "com.apple.liquid-glass": { "tint": "#C04A1A", "variant": "regular" },
        "com.google.material3":   { "scheme": "primary", "expressiveShape": "medium" },
        "io.shadcn":              { "oklch": "oklch(0.62 0.18 38)" }
      }
    }
  }
}
```

## Three tiers (primitive → semantic → component)
1. **Primitive** — raw values (`color.brand.500`, `radius.md`, `space.4`).
2. **Semantic** — role-bound (`color.bg.surface`, `color.fg.muted`, `elevation.card`).
3. **Component** — tied to a primitive component (`button.primary.bg`, `input.border.radius`).

The crew's `transform_tokens` maps semantic→platform role; component tier carries the exact
`$extensions` each platform's native themer reads.

## The closed token-name vocabulary (the contract)
`transform_tokens` resolves token **names** against a fixed vocabulary. Author only these names;
an unrecognized name is dropped silently. The vocabulary mirrors `catalogs/primitives-canonical.json`
plus the token groups: `color.*`, `radius.*`, `space.*`, `typography.*`, `border.*`, `shadow.*`,
`motion.*`. When in doubt, copy a name from `tokens.template.json` — do not invent.

## Platform `$extensions` (the native-target awareness none of the sources had)
The Designer knows the targets are **iOS Liquid Glass / Android Material 3 Expressive / Web shadcn**,
and emits the right vendor block so the platform themer doesn't have to guess:

| Platform | Extension key | Carries |
|---|---|---|
| iOS Liquid Glass | `com.apple.liquid-glass` | `tint` (RGBA hex), `variant` (`regular`/`clear`/`prominent`), the WWDC25 #219 spec |
| Android M3 Expressive | `com.google.material3` | HCT seed → `scheme` role (`primary`/`secondary`/etc.), `expressiveShape` (`ShapeFamily`), motion `easing.*`/`duration.*` |
| Web shadcn | `io.shadcn` | `oklch` (shadcn v3 native form), the role alias for `--radius`/`--primary` |

**Liquid Glass is the navigation/functional layer only** — never glass list rows or scroll content
(over-glassing is a documented crew mistake). Glass tokens carry the tint; content tokens stay opaque.

## The `--status-bar-bg` token (the reactive overlay)
Dark screens need a status-bar background that tracks the screen, not a fixed system color. Author a
`color.status-bar-bg` semantic token; the emitted overlay reads it. Without it, dark screens get a
jarring light status bar. (This is the reactive overlay — atlet's dark detail screen needs it.)

## Motion group (lean — see `motion.md`)
Three rise tokens ride the Token layer, NOT a parallel motion system:
- `motion.rise.duration` (`$type: duration`) → `kRiseMs`
- `motion.rise.curve` (`$type: cubicBezier`) → `kRiseCurve`
- `motion.rise.dy` (`$type: dimension`) → `kRiseDy`
These are **captured from the design's CSS entrance** (`capture_design.entrance_styles`). A miss
surfaces as `kRiseMs=0` (NO animation) — never an Atlet fallback. Author them only if your design
actually animates an entrance; omitting is honest and correct.

## Forbidden: a parallel token system
Do NOT emit a GSAP/anime/`motion-*` token tree. The crew's 5-item motion enum + `motion.dart` +
device-verified gates (`parity.py`, `motion_device.py`) are more rigorous than anything rebuilt here.
The token layer carries only the 3 rise values + color/radius/space/type/border/shadow.

## Coherence rules (the freeze gate enforces)
- Every `$extensions` vendor key must map to a real catalog field the crew reads.
- Semantic color tokens must resolve to a primitive in the same file (no dangling refs).
- `--status-bar-bg` is mandatory if any screen is dark.
- Motion rise tokens are optional, but if present, all three (duration/curve/dy) — never a partial set.
