# m3-expressive — style SPEC (Material 3 Expressive)

> Compiled from energize component-craft.md (R7/R8/R9a–R9p) + component-specs.md
> (material-web tokens v0.192 + Flutter constants). SSOT stays in energize;
> overlay.css is the gate-proven implementation; conflicts are bugs.
> m3 is gated on ABSOLUTE px — the tokens are machine-readable authoritative.

## Sources

material-web `tokens/versions/v0_192/_md-comp-*.scss` (Google-generated,
"Design system version: v0.192") — 🔥 authoritative. Date/time anatomy from
Flutter `calendar_date_picker.dart` / `time_picker.dart` (Google's own M3
implementation).

## Tokens

Container-step tonal layering, NO shadows (our no-shadow law: elevation is
expressed by the container step). Roles: primary / onPrimary / primaryContainer
/ secondaryContainer (#D8E8E7 light, #2A3B3A dark) / surfaceContainerHigh /
onSurfaceVariant / error (#B3261E light, #F2B8B5 dark). Corners: full → 28px
extra-large → 16 large → 8 small → 4 extra-small. Type: Roboto/Fira stack,
weights per M3 roles. Dark = token-level variant (R8), instant swap.

## Numbers (asserted — the geometry gate pins these)

| member | value |
|---|---|
| switch track | 52 × 32, corner-full, 2px outline off |
| switch handle | 16 unselected → **24 selected (it grows)**, state layer 40 |
| checkbox | 18 × 18, corner 2px, outline 2px off / 0 on |
| radio | 20 icon, state layer 40 |
| filled text field | 4px TOP-only corners, 1px active indicator, icons 24 |
| outlined text field | 4px corners, 1px outline |
| list item | 56 one-line / 72 two-line / 88 three-line; avatar 40, icon 24 |
| navigation bar | 80 tall; active indicator 64 × 32 full-round; icon 24 |
| navigation rail | 80 wide; indicator 56 × 32 |
| navigation drawer | 360 wide; indicator 336 × 56 full-round |
| top app bar (small) | 64 |
| primary tab | 48 (64 icon+label); indicator 3px |
| date picker | container 360 × 456 r16; header 64; sub-header 52; nav buttons 108; day row 48 (40 circle + 4 inner pad); h-pad 12; month/year chip 40 |
| time picker | dial dialog 310 × 468 r28 elev6; input 312 × 252; hour/minute fields 96 × 80 r8; display-large 57; AM/PM 52 × 80 r8 1px outline; dial 256; handle 48; centre 8; hand 2; outer ring r100; inner r72 |
| menu | surfaceContainerHigh, 4px corners, 48px items |

Not asserted: the 456/310 whole-dialog totals (our specimen renders the docked
grid / dial, not the modal chrome); time-picker field↔colon gap (positioned in
a Flutter RenderObject — no token exists).

## Families — m3 truths

- **menus** — surfaceContainerHigh, 4px corners, tonal only (no shadow),
  selected = secondaryContainer wash + checkmark, 48px item height, danger
  #B3261E on error-container-hover. Single-line items; all eight dropdown
  laws (R9n/o/p) apply cross-style.
- **segmented** — SegmentedButton: outline, 40px, selected =
  secondaryContainer wash + ✓ swap at 150ms linear (M3 has NO sliding thumb
  here). Labels never change typography on selection (R9c).
- **tabs** — primary tabs: active carries a 3px rounded indicator bar under
  the label + label/icon in primary; inactive onSurfaceVariant; badges legal.
- **switch** — M3: track outline when off, thumb 16→24 morph rides CSS
  effects ALONGSIDE the position spring (MOVE preset), state layer 40.
- **checkbox/radio** — real boxes/circles (M3 keeps them): 18px r2 / 20px.
- **text fields** — filled: 4px top-only + 1px active indicator (the
  focus indicator is the 2px bottom border — restated INSIDE the later
  filled block at (0,3,0); the clobber scar: same-specificity-later killed
  the focus rule and the field showed a 1px hairline while focused, R9m).
  Outlined: 4px, 1px outline. Indicator exclusivity law applies (error
  outranks focus).
- **dialogs** — 28px corners (extra-large), surfaceContainerHigh, headline
  24px, text-only buttons right-aligned; alert same + icon. Bottom sheet:
  28px top corners, drag handle 32×4, tonal.
- **calendar** — header w/ selected-date headline; day cells 40px; selection
  full-round primary circle w/ onPrimary; today = outline ring; range =
  secondaryContainer band w/ round ends. Time picker = dial + input chips
  (render the input-chip form).
- **snackbar** — inverse surface (dark chip light / light chip dark), 4px
  corners, optional single accent action.
- **FAB** — 16px rounded square (full-round variants legal; we take
  standard), tonal primary container.
- **spinner** — M3 circular: the border-dash ring idiom (NOT glass's
  8-blade); linear progress w/ stop indicator.
- **time picker** — full dial anatomy in the numbers table; the geometry
  gate asserts the parts, never the whole-dialog total.
- **iconography** — Lucide sprite, `--ic` 24 (M3 ships 24px icons — the
  reason label-cluster assertions must be idiom-independent, R9o scar).

## Motion

| class | constant |
|---|---|
| press | spring k=800, c=33.9 (SpatialFast 800/ζ0.6); scales 0.94/0.96/0.98 |
| move | spring k=380, c=24.7 (SpatialDefault 380/ζ0.8) |
| effects | 180ms linear (ζ=1.0 by platform law) |
| disclosure | 150ms linear (segmented class-toggle); ease only, never springs |
| direct manipulation | 1:1 pointer, no inertia |

## Gate contract

Same four gates; for m3 the geometry gate asserts the ABSOLUTE px table
above against component-specs.md. Contrast per family per theme ≥ 4.5:1
composited; interact smoke incl. the cross-style dropdown/field laws.
