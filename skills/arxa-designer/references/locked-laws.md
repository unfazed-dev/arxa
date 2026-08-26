# Locked Laws

Design **against the kit as always-available**: colors, spacing, glyphs, fonts,
constants and strings come from the generated kit mirror, never from a local
duplicate. (In the Flutter tree, each app's `lib/ui/common/` is a verbatim
scaffold-time copy of kit common plus the app's `arxa_kit_app_strings.dart` —
refreshed from kit, never hand-edited.) If the mirror lacks a symbol, extend
the generator — do not define the value locally. Fonts specifically are never
vendored: families come from the Google Fonts CDN by name — see
DESIGN-ARCHITECTURE.md "Fonts (Google Fonts by name)".
`ArxaKitNative*` and `arxa_kit_ui_library` are **not** mirrored: you design
web, and which native a `kind` resolves to is the scaffolder's call, not yours
to pre-empt. See `references/showcase-anatomy.md` §4.

**Vocabulary law (locked).** The design vocabulary is **hub > shell > view >
widgets**. "screen" and "page" are out of vocabulary as *structural nouns* —
prose, file/folder names, DOM attributes, emitted copy. Do not mint new
identifiers containing them. Carve-outs (not violations): browser mechanics
("full-page reload", "page load"), external vocabularies quoted as-is (Figma
pages, `aria-current="page"`, `window.screen`, "screen reader"), and factual
references to the v1 Dart medium (`screens.dart`). Legacy ratified identifiers
(`screenId` in the `inspectAttrs` triple, `screenIdSource`,
`models/screens_model/`) survive only until their coordinated rename lands
with a gate re-run — see `docs/plans/screen-vocabulary-identifier-rename.md`.

**Filename law (locked).** Designer-emitted filenames follow the showcase-app
naming conventions (`references/showcase-anatomy.md`), with two absolute bans:
no filename starts with `_` (there is no "private module" convention in the
emitted tree — `_panel.tsx` was illegal; the base is `panel.tsx`), and no
filename carries a version or era prefix (`v1_strings.tsx` was illegal —
strings ride in the kit-mirror name the scaffolder will emit,
`arxa_kit_app_strings.*`). Names describe the module's role in showcase
vocabulary, nothing about its history or visibility. Applies to every file the
designer writes into an artifact — code, styles, docs alike. Ruled 2026-08-09;
rationale trail in `docs/plans/design-filename-law.md`. The mechanical check
rides the naming gate (see the single-letter identifier law's gate). Every emitted artifact includes an
artifact-root `tsconfig.json` produced at emit time (jsx via
`jsxImportSource: "hono/jsx"`, no react types), and the artifact must
type-check clean (`npx tsc -p <artifact>`) before gates report. A missing or
hand-authored tsconfig is an emit defect.

**Styles law (locked).** Artifact CSS lives only in `ui/styles/<owner>/` —
`common/` plus one folder per shell and one for the application hub, folder
names matching their `ui/views/` entries. Each folder carries a `styles.css`
barrel (`@import` by absolute `/ui/styles/…` URL, cascade order); `base.tsx`
links one barrel per folder (common first) and no other stylesheet. No `.css`
outside `ui/styles/`; rules consumed by two-plus owners promote to `common/`;
dead selectors are deleted, not parked. Ruled 2026-08-09. See
DESIGN-ARCHITECTURE "Styles (ui/styles)".

**Widget barrel law (locked).** Every `ui/widgets/` leaf folder carries a
`widgets.tsx` barrel; external consumers import through the barrel only.
Folders are `<app>_<feature>_widgets/` named after the owning `ui/views/`
entry; cross-shell groups live under `ui/widgets/common/<group>/`. Ruled
2026-08-09.

**Hub law (locked).** Two-plus shells, exactly **one** application hub per app —
more only when the intake, design, or scaffold stage explicitly states so. The
hub sits flat at `ui/views/<app>_application_hub/` (no `_shell` suffix, no
nested surface directory) with the showcase five-file set (`<hub>_view.tsx`,
`.desktop`/`.tablet`/`.mobile` variants, `<hub>_viewmodel.js`); hub widgets in
`ui/widgets/<app>_application_hub_widgets/`. Ruled 2026-08-09. See
DESIGN-ARCHITECTURE "One application hub".

Every emitted surface carries the `inspectAttrs` triple
`(screenId, surfaceId, anatomy-node id)` derived from registry ids — stamped at
emit time, mechanically enforced, never inferred at runtime. Every emitted view
and viewmodel carries the `///` frontmatter block (role sentence, Requirements
with registry ids, Relationships diagram, `History:` line) per
`references/showcase-anatomy.md` §3. **Auto Layout is default-ON for every widget in
the library** (DESIGN-ARCHITECTURE, "Auto Layout"): each component's container
carries the `data-layout` attribute set and its children size with
`data-resize-x` / `data-resize-y`. To turn it off per frame, omit
`data-layout` (art-directed frames); to exempt a single child, give it
`data-layout-ignore`. Layout values in `design.json` are **kit constant names,
never raw numbers or bare keywords**: `abxPad*` / `abxGap*` (numeric ladder, no
tier aliases), sizing modes `abxHug` / `abxFill` / `abxFixed`, spacers
`arxaKitVerticalSpace*` / `arxaKitHorizontalSpace*` — e.g. `"layout":
{ "pad": "abxPad16", "gap": "abxGap8", "width": "abxFill", "height": "abxHug" }`
(DESIGN-ARCHITECTURE, "Kit token binding"). An off-ladder value is a request to
add a kit constant (always `abx`-prefixed), never a literal to inline. **You compose; you never resolve** (DESIGN-ARCHITECTURE,
"Compositions are recipes"): a `kind` may land on one kit widget, on a variant
you must name, on several widgets, or on a presentation mode — so name the
variant and author the recipe (parts, slots, arrangement) in design terms.
`widget: null` in the resolution registry means *composed*, never *unbuildable*.
