---
name: appbox-designer
description: "Use when the user asks to design, mock up, prototype, wireframe or visualize an application, product view or user flow that will be scaffolded into a real app — the artifact is a server-rendered htmx app in a genuine MVVM structure, enhanced on the client by the three legal ADR-0009 forms (categorized vendored libraries, first-party islands, artifact app modules): app shells, views, dashboards, interactive prototypes and wireframes, authored at every viewport in the active ladder. Consumes the versioned intake/registry.json (+ intake/flows.json, the flows SSOT) as the pipeline's only authoring surface and materializes a derived registry.json, an inspectAttrs triple on every surface and a route table the freeze step reads; output is structurally isomorphic to kit/showcase_app/lib so the scaffolder transliterates rather than interprets. Not for slide decks or printable documents."
---

# appbox-designer

> Per-skill playbook (the folded canon for this phase): [`DESIGNER_playbook.mdx`](DESIGNER_playbook.mdx)

The design stage of the appbox pipeline. Every artifact is a Hono + htmx
MVVM app whose **backbone stays server-rendered** — URL in, HTML out, always
crawlable and lens-capturable. Client JavaScript is legal in exactly **three
forms** (ADR-0009): **categorized vendored libraries** (runtime/vendor/:
htmx, Alpine, GSAP, <model-viewer>, rive, three, leaflet… — SRI-pinned in
manifest.json, every row carrying a category: hypermedia, state-framework,
motion-framework, rich-media, data-viz, reactive-primitive); **first-party
islands** (named, scoped, no-globals data-attribute modules with a
why-this-exists header: canvas.js, drag.js, inspect.js…); and **artifact app
modules** (assets/app/*.js — per-artifact authored wiring that connects
vendored libraries to markup; same island discipline: named, headered,
lint-resolved). Still banned and linted: inline event handlers, scripts that
resolve to nothing, flow state living only in client JS — if losing it breaks
a flow, it belongs in the viewmodel, the URL, or the server. A commission may
declare a per-artifact JS weight ceiling (client-js.json); the lint enforces
it over what the HTML actually loads. The MVVM structure is what the
scaffolder later emits as Flutter — client JS is design simulation, never
flow state — which is why the prototype can carry structure rather than
pixels.

**What makes this skill different from a generic design tool:** the prototype
you produce is a *typed input to a build pipeline*. Structure is authored while
designing, never back-filled. See
[`references/app-architecture.md`](references/app-architecture.md).

## Pipeline position

Stage 2 of `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Upstream (feeds this skill):** `appbox-intake` — the brief (or a hand-written one) + seeded `intake/registry.json` (the emitted `## Layout template` section is consumed **verbatim**) + `intake/flows.json`, the flows SSOT — with the registry, the pipeline's only authoring surface: intake elicits/derives + confirms the flows, and the design viewer live-reads AND edits that same file (never a copy; DESIGN-ARCHITECTURE "The output triad"). `appbox-moodboarder` output reaches this skill ONLY through `appbox design commission` — the compiled, selected, scored mandate (§0).
- **Downstream (consumes this skill's output):** `appbox-scaffolder` — the FROZEN `structure.json` this stage emits is its only input; `appbox-lens` captures the evidence; a stage-6 review REJECT rewinds the FSM back here.

**The triad output.** Every artifact is *three switchable lenses over one
view registry* — **prototype** (wired navigation over each entry's `route`),
**flows** (journeys as an edge graph), and **views** (the tile inventory) —
never three separate artifacts. Flows are authored as **data**: `{from, to,
trigger}` edges over registry ids carried through the data spine and rendered
by a server template / named island — never bespoke per-flow markup, never a
separate file format. The freeze threads an optional top-level `flows` array
into `structure.json` (absent = no flows lens, valid for small artifacts); the
scaffolder emits surfaces from the registry views, the builder wires
navigation from the edges. Binding contract:
[`DESIGN-ARCHITECTURE.md`](DESIGN-ARCHITECTURE.md) "The output triad".

## How to use this skill

**0. Consume the commission — it is a binding contract, not inspiration.**
Run `appbox design commission <app-dir>` (or verify `design/commission.md` +
`design/commission-prompt.md` already exist and match the current intake).
The commission compiles the brief + direction + ONLY the selected, scored
moodboard references; it is the anti-blandness seam. Rules with teeth:

- **Locked requirements are non-deferrable.** If the commission locks
  `animated-3d`, the hero MOVES in this artifact (CSS/WebGL in the design
  layer, vendored island in the build) — deferring it to "a build-stage
  upgrade" is a gate failure, not a style choice. When intake locks motion,
  your lens verification captures at TWO settle states and the stills must
  differ.
- **Selected references are your visual context.** Consult their shots on
  disk (`moodboard/shots/…`) before choosing any palette, type pairing, or
  motion pattern; cross-pollinate (layout from one, palette from another,
  motion from a third) — never clone one reference.
- **Craft contract** (see this skill's LICENSE for lineage): no default-
  token design (no Inter/Roboto/Arial as the identity face, no blue-purple
  gradient heroes, ONE elevation vocabulary); a named type pairing with real
  contrast; bold direction — pick an extreme of the commission's tone
  adjectives and give every surface one memorable element; real copy only
  (concrete claims in the brand voice, never "Empower your team" filler);
  3 distinct variants for the hero/key surface before committing; serve +
  screenshot + console-check before presenting anything.
- A missing or stale commission (moodboard unapproved, locked criterion
  unfed) means STOP and run the moodboard stage — designing without the
  mandate is how bland sites happen.

**0b. Load the structure contract and identify your input.**
Two files govern everything below and win over any prose elsewhere in this
skill:

- [`references/showcase-anatomy.md`](references/showcase-anatomy.md) —
  `kit/showcase_app/lib` is **the structure contract, not an example**. Folder
  layout, the `<app>_<feature>_` naming law, the five-file per-surface split,
  barrels, the two-tier widget placement law, the closed 15-kind widget
  vocabulary, the mandatory `///` frontmatter and comment conventions, and the
  deterministic expansion recipe for a feature showcase doesn't have.
- [`references/delta-runs.md`](references/delta-runs.md) — where your input
  comes from and what you may touch.

Then establish **which kind of run this is**, because it changes what you are
allowed to write:

| input | run | you materialize |
|---|---|---|
| a pinned `intake/registry.json` version, no prior scaffold | full run | every feature |
| a frozen run artifact for a diff between registry versions | **feature-scoped delta run** | **only** the new/changed feature |

In a delta run, **already-designed features are never regenerated.** Leave
their files untouched; the divergence gate verifies them, it does not rewrite
them. Shared join points (registry, routes, root barrels, locator) are
scaffolder-owned, regenerated deterministically, additive-only — never
hand-edit one. Any cross-feature touch must be declared in the delta scope and
carries 3-way merge plus human approval; an undeclared one is a gate failure.

You **never author a second source of truth.** `intake/registry.json` is the
only authoring surface; composers write it, you consume it. The artifact's
`models/screens_model/registry.json` is *derived* from the run artifact — a
projection, regenerated, never edited to disagree with its source. If you find
yourself wanting to write design instructions somewhere other than a registry
patch, stop: that is the failure this rule exists to prevent.

**1. Load the methodology.** Read [`system-prompt.md`](system-prompt.md) — the
core design process and craft standards. Follow it for the whole job.
**Consume the brief when one is handed to you.** If the intake stage produced
a design brief, read its **Layout Template** section (the named containers +
per-rung `grid-template-areas`) and consume it **without rewriting** — surfaces
compose into those named containers as given; it is the structure, not a
suggestion.

**2. Load the architecture contract.** Read
[`DESIGN-ARCHITECTURE.md`](DESIGN-ARCHITECTURE.md) — the **binding** contract
for the data spine (seed SSOT → generated fixtures → repositories → facades →
viewmodels/views), the registry canon, the motion vocabulary mapped to CSS/htmx
mechanisms, provenance-not-shape fixtures, and **feedback & state placement**
("Feedback & state placement") — loading, retry, error and toast/snackbar
placement is decided automatically from the registry and flow edges on
*every* artifact this skill produces, never left for the brief to request.
Then read
[`references/app-architecture.md`](references/app-architecture.md) for the
authored layer the pipeline consumes. When the brief mentions
maps/payments/auth/deploy or any kit capability, also read
[`references/kit-catalog.md`](references/kit-catalog.md) — the designer-side
mirror of the kit (declaring `kits`, credentials by name, design-time islands).

**3. Load the viewport ladder.** Read
[`references/viewport-ladder.md`](references/viewport-ladder.md). **Which widths
you author at is derived from the project's targets and read from config — never
assumed, never hardcoded.** Authoring at phone width only is the single most
expensive mistake available here: everything the prototype omits gets invented
downstream by someone who never saw the design.

**4. Load the harness tool reference once.**
[`references/harness-tools.md`](references/harness-tools.md) maps capabilities
(asking questions, previewing, screenshots, verifying) to your harness's tools.

**5. Load the artifact contract.** Read
[`runtime/README.md`](runtime/README.md) and skim
[`examples/hello-hda/`](examples/hello-hda/) — the reference artifact. This is
how every artifact is structured (MVVM: Surface = view template + co-located
ViewModel), served, and kept JS-free.

**6. Load the right built-in skill(s)** from `built-in-skills/` (full list at
the bottom of `system-prompt.md`):
- **Declare structure** (always, while designing) → `declare-structure.md`
  (declare `kits` on surfaces that need a kit module — see its `kits` field section)
- **Wireframes / low-fi** → `wireframe.md`
- **Default (hi-fi / interactive)** → `hi-fi-design.md` + `interactive-prototype.md`
- **Mobile form factor** → `mobile-prototype.md`
- **Design system** setup/use → `design-system-authoring-guide.md` / `use-design-system.md`
- **Eject / productionize** an artifact → `productionize.md`

**7. Ask clarifying questions** (`AskUserQuestion`) for new or ambiguous work —
context, fidelity, variations (see "Asking questions" in `system-prompt.md`).

**8. Set up the output folder.** Ask **where to save** and **which design
system(s) to use**. Repo mode (an `appbox.json` marker above cwd): the default
is the app dir's `design/` stage folder — `<app-dir>/design/` — never a fresh
`designs/<name>/` at the repo root (that layout is pre-law). Native mode
(`~/.appbox` project): default `designs/<descriptive-project-name>/` as before.
Start every artifact by copying `examples/hello-hda/` and renaming; never
scatter design files in the repo root. Serve the artifact with the Dart
design server — `appbox design serve <artifact-dir> [--port N] [--json]`
(`appboxd/lib/design_server.dart`; artifact JS runs in a headless-Chrome
worker over CDP) — which works without referencing the skill path. Older
designs may still carry a `serve.mjs` shim at the artifact root: it is dead
(the Node runtime it delegated to is archived), so serve those with
`appbox design serve` too; new artifacts do not carry the shim. Import design systems with
`appbox design ds-import` and record deliverables with
`appbox design record-asset` as in `built-in-skills/use-design-system.md`.

**9. Build widgets-first, then serve and verify.** Before composing any
surface, author the artifact's widget library: inventory the design's
repeated patterns and define them as widgets at the tier their consumers
require — **two tiers only**: `ui/widgets/common/<group>/` cross-shell,
`ui/widgets/<app>_<feature>_widgets/` for everything else (see
[`references/showcase-anatomy.md`](references/showcase-anatomy.md) §2; the old
three-tier `shared/widgets/` + `<surface>/widgets/` law is superseded and those
paths are illegal). Each widget declares a `kind` from the **closed** 15-kind
vocabulary — the file list of `starter-partials/widgets/`; a kind outside it is
a gate failure on both sides, **never improvise a mapping**. Start from
[`references/ui-recipes.md`](references/ui-recipes.md)
and the drop-in widgets in `starter-partials/widgets/` — surfaces compose
only from that library. **Composition is enforced (W9), not encouraged**:
in view templates (`ui/views/**`) EVERY element is a Capitalized
widget-library invocation. A raw HTML element of any kind fails
`design lint` (W9) — text-bearing, interactive, media, AND the
structural wrappers (rung mounts, section scaffolding, form elements, slot
outlets): a view that authors markup authors presentation, and presentation
lives in the library. This holds even when the element carries
`data-el`/`inspectAttrs` identity (W7's floor); that identity is legal
only INSIDE widget files, where the presentation markup belongs. Slot
passes (`{children}`), list maps, and grouping ride widgets or fragments
— composition never authors markup. **Composition files are banned in ui/views/ (W1)**: no *_view.sections.tsx - a multi-section body is a composition widget in the library (home_body.tsx), invoked by the view.

Design **against the kit as always-available**: colors, spacing, glyphs, fonts,
constants and strings come from the generated kit mirror, never from a local
duplicate. (In the Flutter tree, each app's `lib/ui/common/` is a verbatim
scaffold-time copy of kit common plus the app's `appbox_kit_app_strings.dart` —
refreshed from kit, never hand-edited.) If the mirror lacks a symbol, extend
the generator — do not define the value locally. Fonts specifically are never
vendored: families come from the Google Fonts CDN by name — see
DESIGN-ARCHITECTURE.md "Fonts (Google Fonts by name)".
`AppBoxKitNative*` and `appbox_kit_ui_library` are **not** mirrored: you design
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
`appbox_kit_app_strings.*`). Names describe the module's role in showcase
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
`appBoxKitVerticalSpace*` / `appBoxKitHorizontalSpace*` — e.g. `"layout":
{ "pad": "abxPad16", "gap": "abxGap8", "width": "abxFill", "height": "abxHug" }`
(DESIGN-ARCHITECTURE, "Kit token binding"). An off-ladder value is a request to
add a kit constant (always `abx`-prefixed), never a literal to inline. **You compose; you never resolve** (DESIGN-ARCHITECTURE,
"Compositions are recipes"): a `kind` may land on one kit widget, on a variant
you must name, on several widgets, or on a presentation mode — so name the
variant and author the recipe (parts, slots, arrangement) in design terms.
`widget: null` in the resolution registry means *composed*, never *unbuildable*.
Then build the artifact per the contract, serve it with
`appbox design serve <artifact-dir> --port 4319` (background), then
verify: `appbox design lint <artifact-dir>` (no-ad-hoc-JS / named-islands),
`appbox lens check http://localhost:4319/…` (console
clean), and `appbox lens shoot http://localhost:4319/<route>` (**every width in the active ladder**, plus overflow and failed-request checks). Fix
before surfacing; give the user the served URL.

**10. Productionize on request.** `appbox design eject <artifact-dir>
<out-dir>` ejects a self-contained, hardened Hono app — see
`built-in-skills/productionize.md`.

## Requirements

The designer runtimes are **Dart** — the `appbox design` and `appbox lens`
commands (served, linted, captured over the Dart design server + the lens).
Run `appbox design doctor` to preflight the toolchain the gates use. This
requirement applies to the *designer's* machine only — the shipped
appbox desktop app serves prototypes without Node.

## Deliberately absent capabilities

These are JS-bound by nature — do not recreate them:
- **design-canvas pan/zoom** → use `starter-partials/artboards.tsx` (static
  side-by-side comparison surface)
- **animation timeline engine**, **animated video**, **video export** → use
  scroll-driven CSS motion studies (`starter-partials/motion.css`)
- **image-slot drag/drop** → use a static placeholder plus the artifact's
  `assets/` folder

Slide decks and printable documents are out of scope. This skill designs
applications.

## Notes

- `system-prompt.md` is the craft SSOT; `runtime/README.md` is the artifact
  contract; `references/ui-recipes.md` is the widget catalog; `CONTEXT.md`
  is the vocabulary; `docs/adr/` holds the runtime decisions.
- **i18n**: when an artifact is localized, every chrome/surface string lives in
  `l10n/app_<locale>.arb` and renders via the `t` prop — never hardcode copy
  in views. Jargon variants are key suffixes (`keyPlain`/`keyTechnical`).
  Localized content is per-locale seeds (`<name>_seed.<locale>.json` is the
  SSOT) generating `<name>_fixtures.<locale>.json`. `appbox design pseudolocalize`
  derives the `qps-ploc` pseudo-locale from English — run it to catch
  truncation and hardcoded strings. Full contract: runtime/README.md "L10n".
- Keep artifacts self-contained: copy every referenced asset into the artifact
  folder; client libraries come only from the runtime's vendored, SRI-pinned set
  (`runtime/vendor/`).
- Licensed MIT — this skill is a fork. See `LICENSE` and the repository's
  `THIRD-PARTY-NOTICES.md`.
