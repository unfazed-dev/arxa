# Palette generation — HCT seed → token set (the net-new contribution)

> No source skill generates palettes. This is the Designer's generative capability: a single brand
> seed color → a full tonal scheme → W3C DTCG color tokens, with platform `$extensions`. The
> generator lives at `scripts/palette.py`. This file is the **authoring guide** — what to
> generate, the quality bars, and how it lands in `tokens.json`.

## The hybrid model (curated seed + algorithmic expansion)
Purely algorithmic palettes (a hue rotated 5×) read as generic. Purely curated palettes can't fill a
full tonal range (0–100 lightness per HCT). The Designer's model is **hybrid**:
1. **Curated seed** — one brand color chosen for meaning (the logo/brand color from
   `core-asset-protocol.md`, or a designer-picked direction from `design-directions.md`).
2. **Algorithmic expansion** — the seed → a full tonal scheme in **HCT** (Hue/Chroma/Tone, Google's
   perceptual space via `material-color-utilities`), giving tonal stops 0→100 that are perceptually even.
3. **Curation re-enters** — accent/neutral choices are curated (a single accent, per the anti-slop
   "single accent carried throughout" rule), not all 5 HCT secondaries.

This matches coolors/colorhunt's UX (one seed, a generated ramp, curated accents) but outputs tokens.

## The generation path
```
seed (hex) → HCT(H, C, T) → tonal stops (0,10,…,100) held at the seed's hue
   → W3C DTCG tokens.json color.* group
   → platform $extensions (Liquid Glass tint, M3 scheme role, shadcn oklch)
```
`scripts/palette.py` implements this **pure stdlib** (no npm, no `material-color-utilities`, no
`culori`) — the crew's discipline is hermetic-no-deps, and the palette output feeds the crew's
token layer, so it must run anywhere Python runs with zero install. HCT is color-space math; the
tone ramp renders by gamma-correct blend toward black/white along the seed's hue line (the move
coolors/material tonal palettes make), binary-searched to hit each target L*. Contrast is APCA
(WCAG 3 Lc, not the old 4.5:1 ratio). Run it: `python3 scripts/palette.py #C04A1A --out design/tokens.json`.

## Quality bars (the gate)
- **APCA contrast, not WCAG ratio.** Body text ≥ Lc75; small text ≥ Lc90. APCA is perceptually
  accurate for both polarities (dark-on-light vs light-on-dark); the old 4.5:1 ratio mis-rates dark
  backgrounds. Every text/background pairing the Designer emits must clear these.
- **HCT → OKLCH round-trip fidelity (risk #5).** HCT (M3) and OKLCH (shadcn) differ in
  gamut-mapping; naive sRGB translation distorts edge colors (high chroma). `palette.py` emits the
  OKLCH as *metadata* (the `$value` is the hex, which `transform_tokens` reads as the source); the
  oklch is derived from Lab and is close-but-not-canonical. If a platform themer consumes the oklch
  directly, verify the round-trip (seed → oklch → sRGB) within tolerance before shipping — the hex
  `$value` is always authoritative, the oklch is a hint.
- **Single accent.** The anti-slop rule holds: one warm/cool ground + one accent. Multi-color
  clusters only if the data genuinely has ≥3 categories (and then the colors are *semantic*, not decorative).

## Accessibility basics (huashu has none — added)
- **44×44 hit targets** (Apple HIG / WCAG 2.5.5) — buttons, icons, list rows.
- **APCA contrast** — Lc75 body, Lc90 small (above).
- **Focus visibility** — a visible focus ring on every interactive element (don't rely on hover alone).
- **ARIA where it carries meaning** — a chart needs `role="img"` + `aria-label`; a live region needs
  `aria-live`. Decorative SVG gets `aria-hidden`.
These ride the tokens (the 44px becomes a `space.target` token) and the JSX (ARIA on the elements).

## How it lands in tokens.json (see `tokens.md`)
The generated palette fills the `color.*` group:
- `color.brand.{0..900}` — the seed's tonal ramp (HCT tone stops).
- `color.bg.surface` / `color.fg.muted` / `color.fg.on-accent` — semantic roles (curated from the ramp).
- `color.status-bar-bg` — mandatory if any dark screen.
Each carries `$extensions` for the 3 platforms (Liquid Glass tint, M3 scheme role, shadcn oklch).

## When to generate vs. curate
- **Brand exists** (core-asset-protocol ran) → use the brand seed; generate the ramp around it.
- **No brand, chose a direction** (design-directions ran) → the direction's signature color is the
  seed (Kenya Hara terracotta #C04A1A, Sagmeister magenta, etc.); generate around it.
- **Operator gave a palette** → don't generate; freeze theirs into tokens, validate contrast only.

Never generate a palette to *avoid* finding the brand color — the core-asset-protocol always wins.
