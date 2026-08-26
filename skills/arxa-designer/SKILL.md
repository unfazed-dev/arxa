---
name: arxa-designer
description: "Use when the user asks to design, mock up, prototype, wireframe or visualize an application, product view or user flow that will be scaffolded into a real app — the artifact is a server-rendered htmx app in a genuine MVVM structure, enhanced on the client by the three legal ADR-0009 forms (categorized vendored libraries, first-party islands, artifact app modules): app shells, views, dashboards, interactive prototypes and wireframes, authored at every viewport in the active ladder. Consumes the versioned intake/registry.json (+ intake/flows.json, the flows SSOT) as the pipeline's only authoring surface and materializes a derived registry.json, an inspectAttrs triple on every surface and a route table the freeze step reads; output is structurally isomorphic to kit/showcase_app/lib so the scaffolder transliterates rather than interprets. Not for slide decks or printable documents."
---

# arxa-designer

> Per-skill playbook (the folded canon for this phase): [`DESIGNER_playbook.mdx`](DESIGNER_playbook.mdx)

**What makes this skill different from a generic design tool:** the prototype
you produce is a *typed input to a build pipeline*. Structure is authored while
designing, never back-filled. See
[`references/app-architecture.md`](references/app-architecture.md).

## Pipeline position

Stage 2 of `arxa-orchestrator` (Ø, front door) → `arxa-story-mapper / arxa-moodboarder` (0, optional) → `arxa-intake` (1) → `arxa-designer` (2) → `arxa-scaffolder` (3) → `arxa-builder` (4) → `arxa-tester` (5) → `arxa-reviewer` (6) → `arxa-deployer` (9) — cross-cutting: `arxa-lint` (7), `arxa-lens` (8), `arxa-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/arxa-system-map.md`; the CLI FSM phases: `arxa/lib/phases.dart`.

- **Upstream (feeds this skill):** `arxa-intake` — the brief (or a hand-written one) + seeded `intake/registry.json` (the emitted `## Layout template` section is consumed **verbatim**) + `intake/flows.json`, the flows SSOT — with the registry, the pipeline's only authoring surface: intake elicits/derives + confirms the flows, and the design viewer live-reads AND edits that same file (never a copy; DESIGN-ARCHITECTURE "The output triad"). `arxa-moodboarder` output reaches this skill ONLY through `arxa design commission` — the compiled, selected, scored mandate (§0).
- **Downstream (consumes this skill's output):** `arxa-scaffolder` — the FROZEN `structure.json` this stage emits is its only input; `arxa-lens` captures the evidence; a stage-6 review REJECT rewinds the FSM back here.

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
Run `arxa design commission <app-dir>` (or verify `design/commission.md` +
`design/commission-prompt.md` already exist and match the current intake).
The commission compiles the brief + direction + ONLY the selected, scored
moodboard references; it is the anti-blandness seam. Rules with teeth:

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
system(s) to use**. Repo mode (an `arxa.json` marker above cwd): the default
is the app dir's `design/` stage folder — `<app-dir>/design/` — never a fresh
`designs/<name>/` at the repo root (that layout is pre-law). Native mode
(`~/.arxa` project): default `designs/<descriptive-project-name>/` as before.
Start every artifact by copying `examples/hello-hda/` and renaming; never
scatter design files in the repo root. Serve the artifact with the Dart
design server — `arxa design serve <artifact-dir> [--port N] [--json]`
(`arxa/lib/design_server.dart`; artifact JS runs in a headless-Chrome
worker over CDP) — which works without referencing the skill path. Older
designs may still carry a `serve.mjs` shim at the artifact root: it is dead
(the Node runtime it delegated to is archived), so serve those with
`arxa design serve` too; new artifacts do not carry the shim. Import design systems with
`arxa design ds-import` and record deliverables with
`arxa design record-asset` as in `built-in-skills/use-design-system.md`.

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


Then build the artifact per the contract, serve it with
`arxa design serve <artifact-dir> --port 4319` (background), then
verify: `arxa design lint <artifact-dir>` (no-ad-hoc-JS / named-islands),
`arxa lens check http://localhost:4319/…` (console
clean), and `arxa lens shoot http://localhost:4319/<route>` (**every width in the active ladder**, plus overflow and failed-request checks). Fix
before surfacing; give the user the served URL.

**10. Productionize on request.** `arxa design eject <artifact-dir>
<out-dir>` ejects a self-contained, hardened Hono app — see
`built-in-skills/productionize.md`.

## Requirements

The designer runtimes are **Dart** — the `arxa design` and `arxa lens`
commands (served, linted, captured over the Dart design server + the lens).
Run `arxa design doctor` to preflight the toolchain the gates use. This
requirement applies to the *designer's* machine only — the shipped
arxa desktop app serves prototypes without Node.

## Notes

- `system-prompt.md` is the craft SSOT; `runtime/README.md` is the artifact
  contract; `references/ui-recipes.md` is the widget catalog; `CONTEXT.md`
  is the vocabulary; `docs/adr/` holds the runtime decisions.

- Keep artifacts self-contained: **copy** every referenced asset into the
  artifact folder — never reference an absolute path, the Desktop, Downloads,
  or any location outside the artifact. Rename the copy to the artifact's
  convention (original basename kept, extension lowercased:
  `IMG_1155.JPG` → `assets/images/<owner>/IMG_1155.jpg`) and never move,
  rename, or delete the original — the copy is what ships. Client libraries
  come only from the runtime's vendored, SRI-pinned set (`runtime/vendor/`).
- Licensed MIT — this skill is a fork. See `LICENSE` and the repository's
  `THIRD-PARTY-NOTICES.md`.

## References

- [`references/js-forms-and-mvvm.md`](references/js-forms-and-mvvm.md) — load for the full ADR-0009 legal-JS-forms rule and the MVVM/server-render rationale.
- [`references/commission-craft-contract.md`](references/commission-craft-contract.md) — load when executing step 0 (locked requirements, selected references, craft contract bullets).
- [`references/delta-run-and-registry-law.md`](references/delta-run-and-registry-law.md) — load when running a feature-scoped delta run, or when unsure where a design instruction may legally live.
- [`references/locked-laws.md`](references/locked-laws.md) — load before emitting any file: kit-mirror sourcing, vocabulary/filename/styles/widget-barrel/hub laws, inspectAttrs/frontmatter/Auto Layout/kit-token-binding rules.
- [`references/scope-boundaries.md`](references/scope-boundaries.md) — load when asked for canvas pan/zoom, an animation timeline, video export, or drag/drop — capabilities this skill deliberately doesn't provide.
- [`references/i18n-and-localization.md`](references/i18n-and-localization.md) — load when the artifact is localized.
- [`references/app-architecture.md`](references/app-architecture.md) — load for the authored layer the pipeline consumes (step 0/2).
- [`references/delta-runs.md`](references/delta-runs.md) — load to identify run kind / delta-run input scope (step 0b).
- [`references/harness-tools.md`](references/harness-tools.md) — load once per session to map capabilities to your harness's tools (step 4).
- [`references/kit-catalog.md`](references/kit-catalog.md) — load when the brief mentions maps/payments/auth/deploy or any kit capability (step 2).
- [`references/showcase-anatomy.md`](references/showcase-anatomy.md) — load before authoring any file: structure contract, naming law, widget tiers (step 0b, step 9).
- [`references/ui-recipes.md`](references/ui-recipes.md) — load when building the widget library (step 9).
- [`references/viewport-ladder.md`](references/viewport-ladder.md) — load to determine which widths to author at (step 3).
