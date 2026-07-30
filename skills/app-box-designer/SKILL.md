---
name: app-box-designer
description: >-
  Design an application prototype whose structure the app_box pipeline
  consumes — server-rendered htmx + CSS with zero custom client-side
  JavaScript (one named island exception: canvas.js, pan/zoom for the
  design canvas), in a genuine MVVM structure: app screens, shells,
  dashboards, interactive prototypes and wireframes, authored at every
  viewport in the active ladder. Use when the user asks to design, mock up,
  prototype, wireframe or visualize an application, product screen or user
  flow that will be scaffolded into a real app. Produces an authored
  `registry.json`, a `surfaceId` in every viewmodel and a route table the
  freeze step can read. Not for slide decks or printable documents.
---

# app-box-designer

The design stage of the app_box pipeline. Every artifact is a Hono + htmx MVVM
app with **zero custom client-side JavaScript** — one named island exception:
`canvas.js`, the dependency-free pan/zoom module for the design canvas
(ADR-0002 amendment) — the same structure the
scaffolder later emits as Flutter, which is why the prototype can carry
structure rather than pixels.

**What makes this skill different from a generic design tool:** the prototype
you produce is a *typed input to a build pipeline*. Structure is authored while
designing, never back-filled. See
[`references/app-architecture.md`](references/app-architecture.md).

## How to use this skill

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
mechanisms, and provenance-not-shape fixtures. Then read
[`references/app-architecture.md`](references/app-architecture.md) for the
authored layer the pipeline consumes.

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
- **Wireframes / low-fi** → `wireframe.md`
- **Default (hi-fi / interactive)** → `hi-fi-design.md` + `interactive-prototype.md`
- **Mobile form factor** → `mobile-prototype.md`
- **Design system** setup/use → `design-system-authoring-guide.md` / `use-design-system.md`
- **Eject / productionize** an artifact → `productionize.md`

**7. Ask clarifying questions** (`AskUserQuestion`) for new or ambiguous work —
context, fidelity, variations (see "Asking questions" in `system-prompt.md`).

**8. Set up the output folder.** Ask **where to save** (default
`designs/<descriptive-project-name>/`) and **which design system(s) to use**.
Start every artifact by copying `examples/hello-hda/` and renaming; never
scatter design files in the repo root. The copy carries a `serve.mjs` at the
artifact root — `node serve.mjs [--port N] [--json]` from inside the design
serves it without referencing the skill path. Keep it; never delete it. Import design systems with
`agents/import-design-system.mjs` and record deliverables with
`agents/record-asset.mjs` as in `built-in-skills/use-design-system.md`.

**9. Build components-first, then serve and verify.** Before composing any
surface, author the artifact's component library: inventory the design's
repeated patterns and define them as macros/partials in `ui/common/` +
`ui/widgets/`, starting from [`references/ui-recipes.md`](references/ui-recipes.md)
and the drop-in partials in `starter-partials/components/` — surfaces compose
only from that library. **Auto Layout is default-ON for every component in
the library** (DESIGN-ARCHITECTURE, "Auto Layout"): each macro's container
carries the `data-layout` attribute set and its children size with
`data-resize-x` / `data-resize-y`. To turn it off per frame, omit
`data-layout` (art-directed frames); to exempt a single child, give it
`data-layout-ignore`. Then build the artifact per the contract, serve it with
`node <skill>/runtime/serve.mjs <artifact-dir> --port 4319` (background), then
verify: `node <skill>/runtime/lint.mjs <artifact-dir>` (zero-custom-JS),
`node <skill>/runtime/console-check.mjs http://localhost:4319/…` (console
clean), and `node <skill>/runtime/shoot.mjs http://localhost:4319/<route>` (**every width in the active ladder**, plus overflow and failed-request checks). Fix
before surfacing; give the user the served URL.

**10. Productionize on request.** `node <skill>/runtime/eject.mjs <artifact-dir>
<out-dir>` ejects a self-contained, hardened Hono app — see
`built-in-skills/productionize.md`.

## Requirements

This skill needs **Node** on `PATH` (Hono, nunjucks) and **Playwright** for the
render and console checks. Run `node <skill>/runtime/doctor.mjs` to check. This requirement applies to the *designer's* machine only — the shipped
app_box desktop app serves prototypes without Node.

## Deliberately absent capabilities

These are JS-bound by nature — do not recreate them:
- **design-canvas pan/zoom** → use `starter-partials/artboards.html` (static
  side-by-side comparison page)
- **animation timeline engine**, **animated video**, **video export** → use
  scroll-driven CSS motion studies (`starter-partials/motion.css`)
- **image-slot drag/drop** → use a static placeholder plus the artifact's
  `assets/` folder

Slide decks and printable documents are out of scope. This skill designs
applications.

## Notes

- `system-prompt.md` is the craft SSOT; `runtime/README.md` is the artifact
  contract; `references/ui-recipes.md` is the component catalog; `CONTEXT.md`
  is the vocabulary; `docs/adr/` holds the runtime decisions.
- **i18n**: when an artifact is localized, every chrome/surface string lives in
  `l10n/app_<locale>.arb` and renders via the `t` global — never hardcode copy
  in templates. Jargon variants are key suffixes (`keyPlain`/`keyTechnical`).
  Localized content is per-locale seeds (`<name>_seed.<locale>.json` is the
  SSOT) generating `<name>_fixtures.<locale>.json`. `runtime/pseudolocalize.mjs`
  derives the `qps-ploc` pseudo-locale from English — run it to catch
  truncation and hardcoded strings. Full contract: runtime/README.md "L10n".
- Keep artifacts self-contained: copy every referenced asset into the artifact
  folder; client libraries come only from the runtime's vendored, SRI-pinned set
  (`runtime/vendor/`).
- Licensed MIT — this skill is a fork. See `LICENSE` and the repository's
  `THIRD-PARTY-NOTICES.md`.
