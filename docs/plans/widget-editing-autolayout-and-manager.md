# Widget editing: auto-layout resize, text/font/color, per-screen widget manager

Grill record + implementation shape, 2026-08-04. All decisions below were put to
the operator one at a time and confirmed; facts were gathered by five research
agents (three repo sweeps, two web sweeps) before recommendations were made.

## Requirement (operator's intent)

In the design shell viewer, views lens: widgets become editable — auto-layout
resize with handles (Figma semantics: padding/gaps preserved, k-constant
scale), text editing, a font menu (+3 families), and color swatches — with
every change reflecting dynamically on all screens that use the widget,
managed through a proper widget manager. The scaffolder and kit must stay in
sync with everything the designer enforces.

## Decisions (locked)

| # | Decision | Choice |
|---|---|---|
| 1 | Persistence | **Write-through to source.** Edits rewrite the live-read project's files (`~/.appbox/projects/<name>`) via the existing single write channel (`POST /__project_write`); watch reload propagates to every frame; git is undo. Drag gestures preview client-side, commit on release (same shape as panel rail resize). |
| 2 | Resize model | **Figma sizing modes + padding modifiers.** Per-axis Fixed / Hug / Fill (the existing `data-resize-x/y` vocabulary); edge-drag writes Fixed quantized to the k scale; double-click handle → Hug; Option-drag adjusts padding stepping ONLY through k values. Plain resize never changes padding/gap (the auto-layout guarantee, per Figma's own mechanics). |
| 3 | K enforcement | **Scale, not names.** Designer vocabulary steps only through the k numeric scale (4/8/12/16/24…); a lint rejects off-scale values; the scaffolder maps numbers → `kPad*`/`kGap*` inside kit code where their usage is legal. The kit doc's "no external usage" rule stays intact. |
| 4 | Edit target | **Widget definition, always.** Every edit hits the widget's definition (macro/partial) or its token — all screens composing it re-render identically. No instance overrides in v1. |
| 5 | Edit surface | **Views lens only.** Canvas handles on the screen tile + the existing per-screen COMPONENTS container upgraded into the widget manager. Flows/prototype stay read-only. |
| 6 | Row action | **Inline expand + canvas select.** Clicking a component row swaps in that widget's property editor (sizing, pad/gap steps, font, color roles, text) and selects/outlines the widget on the tile; two-way (canvas click expands the row). |
| 7 | Composer inputs | **Two inputs** in the components container: an edit composer (LLM edits) and a separate plan editor (never touches markup). |
| 8 | Composer scope | **Selection narrows it.** No selection → whole screen; widget selected → that widget's definition only. Placeholder states scope + cross-screen consequence ("Editing card — used on 4 screens"). |
| 9 | Fonts | **Space Grotesk, Lora, JetBrains Mono** join the default (Lexend family). All OFL, on Google Fonts, `google_fonts`-supported; vendored woff2 design-side. |
| 10 | Color model | **Token swatches only.** 5 swatches — one per accent — each holding **5 semantic roles**; widgets/screens re-point at roles, switch swatches wholesale; never free hex. |
| 11 | Swatch anatomy | **5 semantic roles** (Radix/M3 method): accent solid, accent-soft, hue-tinted surface (natural-pairing neutral), text-high, text-muted/border — each role a light+dark pair. |
| 12 | Accent SSOT | **Designer 5 wins: cyan, violet, blue, ember, moss.** `kitAccentOptions` (6-color unconsumed stub) is rewritten to these 5 as 5-role bundles. |
| 13 | Plan storage | **Per-screen sidecar in the project** (e.g. `design/plans/<screen-id>.md`), versioned with the project; the edit composer reads it as context. |
| 14 | Text targets | **Both kinds, routed by provenance.** ARB-keyed chrome copy → writes the ARB value; seed-bound data → writes the seed SSOT (fixtures regenerate). Editor shows which kind is being touched. Template-inline literals are never written (i18n rule holds). |
| 15 | Edit arming | **Hybrid.** Edit toggle on the tile hover toolbar flips the tile into edit mode (interact-in-place pauses; handles + selection appear); typing in that screen's edit composer auto-arms it. Esc/toggle restores interact-in-place. |
| 16 | Sync depth | **Schema + kit API, no codegen.** `structure.json@2` gains `widgets` (definitions + layout/sizing/pad/gap), `theme` (5 swatches × 5 roles), `fonts`; scaffolder placeholders become token-exact emissions; kit gains consuming API. Flutter widget-tree codegen stays the builder's job — a named next increment. |

## Load-bearing facts (from research)

- **k constants** live in `kit/core/lib/common/kit_app_constants.dart` (`kPad1–80`, `kGap0–100` even ramp, `kFont2–80` + semantic aliases, `kRad*`, `kSize*`); `kit/ui_library/ui-library-usage-appendix.md:546-551` marks `kPad*`/`kGap*`/etc. **kit-internal only** → decision 3. Designer's 4/8/12/16/24 steps sit inside the kit scale 1:1.
- **Auto Layout contract** already exists design-side (`DESIGN-ARCHITECTURE.md` "Auto Layout"; CSS in `widgets.css:40-88`): `data-layout`, `data-flow`, `data-gap`, `data-pad`, `data-resize-x/y` (hug|fill|fixed), `data-layout-ignore`. **No Flutter translation code exists** — only the docs mapping (`ui-recipes.md` ~879: Row/Column + Expanded/SizedBox; Stack+Positioned for ignore).
- **Rail resize precedent** (`drag.js` `attachRail`): client-side preview during drag, commit on release to `POST /design/panel/size/:panel`, server clamps + persists in session. Widget resize copies this gesture shape but commits to project source instead of session.
- **Pipeline**: freeze is hash-locked + human-gated; `structure.json@1` = registry/shellRoots/screens/flows — no widgets/theme/fonts; `appboxd/lib/scaffold.dart:338-345` names the ceiling ("emission lands when the design-side widget map reaches structure.json"). ARB crosses verbatim (`scaffold.dart:360-405`); seeds do NOT cross (design-layer only). Palette/Type emissions are placeholder comments (`scaffold.dart:290-322`).
- **Kit theming**: Material 3, explicit `ColorScheme.copyWith` (not fromSeed); `kitLightTheme/kitDarkTheme({Color accent})` derive containers via lerp helpers; `kitAccentOptions` (`kit_colors.dart:57-64`) is an unconsumed 6-color stub; `KitThemeService` manages only ThemeMode. **No fontFamily anywhere in kit; no google_fonts; no bundled text fonts** — fonts need new API surface (a `textTheme`/family param + bundled OFL assets).
- **Live-read project layout**: `intake/` (registry.json, flows.json, answers), `design/` (seeds, surfaces/, l10n/), `build/`, `settings/`; design surfaces overlay artifact templates; project ARB merges over artifact ARB; single write channel `POST /__project_write`.
- **Figma mechanics** (web, official docs): per-axis Fixed/Hug/Fill; corner-drag forces Fixed on both axes; padding/gap never change on plain resize; Option-drag = padding modifiers; no token-quantized drag in Figma — the k-scale quantization is our tightening, precedented by Penpot's token-application step.
- **Palette derivation** (web): M3 seed→tonal roles and Radix 12-step scales both compose accent + hue-matched neutral + text steps; dark mode = tone remap, not invert; components bind to roles, switching swaps modes — basis of decisions 10–12.
- **htmx**: click-to-edit (`hx-get` swap to form, `hx-put` back) is the canonical hypermedia edit pattern; `contenteditable` is not hypermedia-friendly.
- **No widget manager exists today**; the components container (explode column) is the natural host. No design-kind→Kit-widget registry exists (mapping is procedural in `blueprint.dart`/`emit_stage.dart`).

## Architecture shape (v1)

1. **Selection + property rows** (hypermedia): component rows expand via htmx into server-rendered property editors; selection state server-side (like inspector lock); canvas outline via the existing explode/inspect channel.
2. **Handles island work**: widget resize handles = **charter extension of drag.js** (its faculty: pointer gestures with client preview + commit-on-release), ADR-0002 amendment note required. Edit-mode arming per tile; interact-in-place cancellation (canvas.js) pauses while armed.
3. **Editors are htmx**: text = click-to-edit swap; font menu, pad/gap steppers, sizing-mode toggles, swatch/role pickers = server-rendered controls posting write-through edits. No new island for any of them.
4. **Write-through**: all commits route through the project write channel; watch reload re-renders every tile → cross-screen sync is emergent, not plumbed.
5. **Swatch system**: `design/theme.json` (or equivalent SSOT) in the project defines 5 swatches × 5 roles × light/dark; designer CSS custom properties generated from it; widgets carry role bindings, not colors.
6. **Fonts**: vendor woff2 for the three families into the artifact/runtime; font choice persisted as a token; k-scale `kFont*` untouched (sizes come from the existing scale).
7. **Pipeline contract**: `structure.json@2` (widgets, theme, fonts) + scaffolder emits token-exact builder guidance + kit API: `kitAccentOptions` → 5-role bundles (designer-5), `kitLightTheme/kitDarkTheme` gain textTheme/family param, OFL fonts bundled in kit assets with LicenseRegistry registration.
8. **Lints/gates**: k-scale lint (off-scale pad/gap/size rejected), existing no-custom-JS lint stays green, schema validation for structure@2.

## Verification plan

Lens checks per editing flow (arm → resize → verify k-quantized write + reload
→ cross-screen sync visible on a second tile), mutation-falsification of the
k-scale lint and the provenance router (ARB vs seed), design lint, gate --all,
and a kit-side `flutter test` for the new theme/font API.

## Increments (ordering)

1. Swatch SSOT + 5-role token generation (designer CSS) + moss accent.
2. Components-container manager: rows → inline property editors + selection sync.
3. Edit arming + drag.js handles (resize modes, k-quantized, padding modifiers) + ADR amendment.
4. Text editing (provenance-routed) + font menu (vendored families).
5. Edit composer + plan editor (per-screen sidecar).
6. Pipeline: structure@2 schema + scaffolder token-exact emissions + kit API (accents, fonts).
