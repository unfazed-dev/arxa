# appbox-studio artifact inventory

Scope: everything under `designs/appbox-studio/`. Purpose: establish what the
existing studio artifact already models (screens, panels, pipeline stages,
data spine) so a new **scaffold** shell/screens can be slotted in correctly.
All claims below are quoted or line-referenced against the actual files in
this worktree.

---

## 1. Shell/screen registry — every entry

Source: `designs/appbox-studio/models/screens_model/registry.json` (326
lines), cross-checked against `designs/appbox-studio/structure.json` (476
lines, which adds `shellDir`/`viewmodel`/`deps` per screen but the same `id`
set). Registry entries carry exactly these fields: `id`, `label`, `surface`,
`shell`, `comp`, `labelKey`, `route` — **there is no `kits` field anywhere in
this artifact's registry** (`grep -n kit` against `registry.json` and
`_d_meta.json` returns nothing); kit consumption, if any, lives elsewhere
(likely the `appbox-designer`/`appbox-scaffolder` skills, not this data file).

| id | label | shell | route | comp | surface / viewmodel |
|---|---|---|---|---|---|
| app.splash | Splash | app | /splash | AppSplash | app_shell_app_splash_view — `ui/views/app_shell/splash/splash_viewmodel.js` |
| app.startup | Startup | app | /startup | AppStartup | app_shell_app_startup_view — `.../startup/startup_viewmodel.js` |
| app.access | Access | app | /auth | AppAccess | app_shell_app_access_view — `.../auth/auth_viewmodel.js` |
| app.dashboard | Dashboard | app | /dashboard | AppDashboard | app_shell_app_dashboard_view — `.../dashboard/dashboard_viewmodel.js` |
| intake.interview | Interview | intake | /intake | IntakeInterview | main_shell_intake_interview_view — `ui/views/main_shell/intake/interview/interview_viewmodel.js` |
| intake.personas | Personas | intake | /intake/personas | IntakePersonas | .../intake/personas/personas_viewmodel.js |
| intake.surfaces | Surfaces | intake | /intake/surfaces | IntakeSurfaces | .../intake/surfaces/surfaces_viewmodel.js |
| intake.flows | Flows | intake | /intake/flows | IntakeFlows | .../intake/flows/flows_viewmodel.js |
| intake.mapping | Mapping | intake | /intake/map | IntakeMapping | .../intake/mapping/mapping_viewmodel.js |
| intake.direction | Direction | intake | /intake/direction | IntakeDirection | .../intake/direction/direction_viewmodel.js |
| intake.live | Live Map | intake | /intake/live | IntakeLive | **surface: null, viewmodel: null** — declared, undesigned |
| intake.brief | Brief | intake | /intake/brief | IntakeBrief | .../intake/brief/brief_viewmodel.js |
| intake.moodboard | Moodboard | intake | /intake/moodboard | IntakeMoodboard | .../intake/moodboard/moodboard_viewmodel.js |
| design.prototype | Prototype | design | /design | DesignPrototype | main_shell_design_prototype_view — `.../design/prototype/prototype_viewmodel.js` |
| design.chat | Chat | design | /design/chat | DesignChat | .../design/chat/chat_viewmodel.js |
| design.freeze | Freeze | design | /design/freeze | DesignFreeze | .../design/freeze/freeze_viewmodel.js |
| **chat.chat2** | Chat Stage | chat | /chat/chat2 | ChatChat2 | **null / null** — undesigned |
| **shell.composer** | Composer Panel | shell | /shell/composer | ShellComposer | **null / null** — undesigned |
| **shell.footer** | Footer Panel | shell | /shell/footer | ShellFooter | **null / null** — undesigned |
| build.loop | Loop | build | /build | BuildLoop | main_shell_build_loop_view — `.../build/loop/loop_viewmodel.js` |
| build.gates | Gates | build | /build/gates | BuildGates | **null / null** — undesigned |
| build.visual | Visual | build | /build/visual | BuildVisual | **null / null** — undesigned |
| source.git | Git | source | /source/git | SourceGit | null / null |
| source.files | Files | source | /source/files | SourceFiles | null / null |
| flows.canvas | Canvas | flows | /flows/canvas | FlowsCanvas | null / null |
| ship.deploy | Deploy | ship | /ship/deploy | ShipDeploy | null / null |
| first.showcase | Showcase | first | /first/showcase | FirstShowcase | null / null |
| first.honesty | Honesty | first | /first/honesty | FirstHonesty | null / null |
| workspace.projects2 | Projects | workspace | /workspace/projects2 | WorkspaceProjects2 | null / null |
| workspace.settings | Settings | workspace | /workspace | WorkspaceSettings | workspace_shell_workspace_settings_view — `ui/views/workspace_shell/settings/settings_viewmodel.js` |
| workspace.credentials | Credentials | workspace | /workspace/credentials | WorkspaceCredentials | `.../credentials/credential_viewmodel.js` |
| workspace.config | Config | workspace | /workspace/config | WorkspaceConfig | `.../config/config_viewmodel.js` |
| website.site | Site | website | /website/site | WebsiteSite | null / null |
| website.docs | Docs | website | /website/docs | WebsiteDocs | null / null |
| website.showcase2 | Showcase | website | /website/showcase2 | WebsiteShowcase2 | null / null |
| website.download | Download | website | /website/download | WebsiteDownload | null / null |

33 entries total, spanning 10 declared shells (`app`, `intake`, `design`,
`chat`, `shell`, `build`, `source`, `flows`, `ship`, `first`, `workspace`,
`website` — 12 actually, several with zero designed screens). Only **5**
shells have a `shellRoot` and are wired into navigation at all: `intake`,
`design`, `build`, `app`, `workspace` (`designs/appbox-studio/app.routes.js:17-23`
and `structure.json:4-10`, identical sets). **There is no `scaffold` shell id
anywhere in the registry or structure.json.**

---

## 2. The panel chrome contract — five panels, what drives them

Canonical vocabulary lives in `designs/appbox-studio/ui/common/_integration_panels.md`
and is restated as always-loaded context in the `appbox-designer` skill's
system prompt: *"A shell is built from panels; a panel is built from
sections. Five panels per shell, named by role and never by position —
header, composer, main, activity, footer — and any of them can be off,
rendering nothing in its place."* Each panel has up to five sections (top,
side-start, body, side-end, bottom); only `body` is required
(`panels.css` grid-template-areas comment block).

| panel | file | role | driven by |
|---|---|---|---|
| header | `ui/views/main_shell/shared/widgets/header_panel.html` (thin `_panel.html` instance, BODY only, forced-off top/sides/bottom) | top strip: drawer, brand, project cluster, shell links, daemon channel, theme toggle, overflow | content lives in `chrome.html`'s `headerBody(activeShell, prefs, project)` macro — `chrome.html:17-76` |
| composer | `ui/views/main_shell/shared/widgets/composer_panel.html` | the shell's chat rail, shared across every stage; top section carries the stage eyebrow + pinned-context chips | each stage's viewmodel/facade supplies `chips`, thread messages — e.g. `freeze_viewmodel.js` (`send`, `context`, `model`) via `design_facade.js` |
| main | `ui/views/main_shell/shared/widgets/main_panel.html` | the single render destination for all content: file viewer (6 modes — code/doc/image/svg/pdf/video, macro-picked from extension via `services/facades/file_views.js`) or the stage's own canvas (freeze cards, build timeline, intake item cards) | `f = { path, mode, modeName, lang, body?, html?, src?, backHref }`; mode picked server-side |
| activity | `ui/views/main_shell/shared/widgets/activity_panel.html` | the shell's multi-view panel: top = active view label, body = caller content, bottom = views carousel. Each shell registers its own views: design → screens/artifacts/files; build → runs/commits/files; intake → thread/artifacts/files | opened/closed via `pa.open(A)`/`pa.close(A)` macros, `A = spec` built per-viewmodel |
| footer | `ui/views/main_shell/shared/widgets/footer_panel.html` | bottom strip; BODY only. Its body is the `.timeline` `<ol>` — footer panel owns the skeleton, `timeline.html` supplies the `<li>` items | `main_shell_view.html:22-26` sets `FP = { bodyTag: 'ol', bodyClass: 'timeline', bodyId: 'timeline' }`, block `footer` filled per-shell |

`ui/views/main_shell/main_shell_view.html` (27 lines) mounts **only** header
and footer directly (lines 16-18, 25-26); it explicitly documents that "the
main, activity and composer panels are mounted by the hosted shells (intake /
design / build), each in its own composition file. A panel this shell does
not mount does not exist in it" (`main_shell_view.html:11-15`). So a new
scaffold shell must supply its own composition file wiring main/activity/composer,
exactly as `design/_shared.html` and `intake/_shared.html` do today (both
present, 207 and 322 lines respectively — the per-shell "assemble the three
hosted panels" glue).

The sixth widget, `ui/views/main_shell/shared/widgets/mini_panel.html`, is a
bottom-docked single-row bar (lens toggle / fullscreen / undo-redo controller
+ device-rung picker) that rides inside the main/activity area on
canvas-bearing stages (design, and — per its comment — intake's filmstrip
column); it is not one of the five canonical panels, it's a widget nested
inside them.

Navigation chrome itself (`chrome.html:18-23` and again at `:85-90`, both the
compact `headerBody` and `offCanvas` macros) hardcodes exactly **four**
`destinations`: `intake` (`/intake`), `design` (`/design`), `build` (`/build`),
`workspace` (`/workspace`). There is no fifth entry for a scaffold stage in
either destinations array, and no `tab.scaffold` label key exists in
`l10n/app_en.arb` (only `tab.intake`/`tab.design`/`tab.build`/`tab.settings`,
lines 13-16).

---

## 3. Pipeline stage modeling — intake → design → build, and the scaffold gap

The three-shell pipeline is real at the navigation layer (`chrome.html`
destinations, `app.routes.js` shellRoots) and at the flow-graph layer
(`models/screens_model/flows.json`, mirrored verbatim into
`structure.json:373-475`):

- `flow-intake` walks `app.dashboard → intake.interview → intake.personas →
  intake.surfaces → intake.flows → intake.mapping → intake.direction →
  intake.brief → design.prototype` (`flows.json:3-51`).
- `flow-build` walks `design.prototype → design.freeze → build.loop →
  build.gates → ship.deploy` (`flows.json:52-79`).

**The design→build edge is the gap the team is asking about.** Its edge
record is:

```json
{ "from": "design.freeze", "to": "build.loop", "trigger": "Scaffold" }
```
(`flows.json:63-67`, duplicated in `structure.json:435-439` and again in
`models/intake_model/intake.json:1927-1931`). The edge's own `trigger` label
is literally the word "Scaffold" — but there is no `scaffold.*` screen id
in the registry between `design.freeze` and `build.loop` for that trigger to
land on. The jump is direct, single-hop, in the data model.

At the UI/route layer the jump is even flatter than the flow graph implies:
`design/freeze/freeze_viewmodel.js` has no handler that navigates anywhere —
approving the manifest only appends a chat confirmation and flips a boolean
(`services/facades/design_facade.js:1265-1274`, `approveManifest`: *"The
human gate: approving the frozen manifest unlocks the Build stage"* — it sets
`d.approved = true` and pushes an agent chat line, nothing else). There is no
POST route, no redirect, no scaffold-run trigger anywhere in
`design/routes.design.js`. The user reaches `/build` purely by clicking the
Build tab in `chrome.html`'s destinations — and lands on a `build.loop` page
that is **already** mid-run.

That's because `build.loop`'s data (`models/build_model/run.en.json`, and its
seed `build_seed.en.json`) already contains a full 7-stage timeline baked in
as fixture content: `intake`(n=1) → `design`(n=2) → `freeze`(n=3) →
**`scaffold`(n=4)** → `coverage`(n=5) → `review`(n=6) → `deploy`(n=7)
(`run.en.json:17-124`). The scaffold stage entry itself:

```json
{ "id": "scaffold", "n": 4, "label": "Scaffold", "kind": "auto", "state": "green",
  "duration": "2m 10s", "durationSec": 130,
  "summary": "44 files · 11 surfaces × 4 per ios target",
  "detail": "View/ViewModel extension points emitted per surface; nothing empty." }
```
(`run.en.json:58-70`). So "scaffold" already has a fully-imagined narrative —
but only as **one row in build.loop's single-screen timeline list**, alongside
six other stages, all rendered by the one `loop_view.html`/`loop_viewmodel.js`
pair. There is no dedicated scaffold screen, route, or viewmodel; no way to
open, inspect, pause, or re-run just the scaffold step; no per-surface
progress view (despite the summary boasting "11 surfaces × 4 per ios
target" — that per-surface detail is not surfaced anywhere navigable).
`services/repositories/build_repository.js:9-11` further notes *"Nothing in
appboxd writes build evidence yet, so EVERY project reads empty today"* — the
entire scaffold narrative above is demo/seed content for the studio artifact
itself, not live-wired to a real scaffolder run.

Corroborating evidence that "scaffold" is a recognized-but-unserved concept:
`intake_model/intake.json:1846-1863` defines persona `persona-developer` ("The
Developer") whose first stated goal is literally **"Scaffold from a frozen
design"** (line 1851) — a persona goal with no screen built to satisfy it.
Separately, "the scaffolder" also names an unrelated *external* tool
referenced in comments (`app.routes.js:13`: *"Required and non-empty — the
scaffolder cannot derive it"*; `services/repositories/project_repository.js:121-123`:
*"the scaffolder's shell group — same source the route table will read"*) —
that tool consumes `registry.json`/`structure.json` to emit the actual Dart
tree (per the `appbox-scaffolder` skill: *"the scaffolder PRODUCES the tree;
the gates ASSERT it"*). These are two distinct meanings of "scaffold" already
in play: (a) a build-stage row inside build.loop's timeline, and (b) an
external code-generation tool the registry feeds. **Neither has a studio
screen of its own** — which is precisely the slot a new scaffold shell needs
to fill.

---

## 4. The data spine — models, seeds, generate.mjs, repositories/facades

Uniform three-tier pattern, one instance per stage model
(`app_model`, `intake_model`, `build_model`, plus the cross-cutting
`screens_model`):

1. **Seed** (`*_seed.<locale>.json`, hand-authored, one per locale: en/pl/qps-ploc)
   — the ground truth a human edits.
2. **Generator** (`generate.mjs`, co-located) — a pure, deterministic
   transform: seed → locale-specific fixture (`<model>.<locale>.json`) +
   an unsuffixed `en`-alias file. Comment banner is identical across all
   three: *"Never hand-edit `*.json` fixtures; edit the seed and re-run: node
   generate.mjs"* (`app_model/generate.mjs:8`, `build_model/generate.mjs:8`,
   `intake_model/generate.mjs` — same pattern). Each does denormalization
   the templates shouldn't have to do at render time — e.g.
   `build_model/generate.mjs:22-39` groups findings by gate and precomputes
   chart-bar percentages; `app_model/generate.mjs:18-22` precomputes chart
   bar heights and a deterministic decorative QR matrix (`qrFor`,
   lines 24-57, explicitly non-scannable, seeded PRNG off the pairing code —
   no `Math.random`).
3. **Repository** (`services/repositories/*_repository.js`) — the only layer
   that touches the JSON on disk, via the shared `fixture_reader.js`
   (69 lines): `readFixture` for the **artifact's own** design content
   (cached, `models/**`), `readProjectFixture`/`readOptionalProjectFixture`
   for the **current project's** live-overlaid content
   (`~/.appbox/projects/<name>/...`, served at `/project/<rel>` by the design
   server — `fixture_reader.js:6-11`), and `writeProjectFixture` (lines 50-69)
   which POSTs to `/__project_write` for the one thing the studio actually
   mutates on a project: flow confirms, tile reorders, membership.
   Repositories degrade to sane empties rather than throwing — e.g.
   `build_repository.js:14-52` defines an `EMPTY` sentinel object and
   `hasEvidence()` (line 52) so `build.loop` never 500s on a project with no
   build evidence yet, it renders the honest empty state
   (`loop_viewmodel.js:11-26`, the `empty`/`emptyPage` pair every handler
   checks first).
4. **Facade** (`services/facades/*_facade.js`) — the business-logic/context
   layer a viewmodel calls; owns session mutation and cross-repository
   composition (e.g. `design_facade.js`, 1280 lines, is the largest file in
   the artifact — `approveManifest` at line 1265-1274 is one of dozens of
   such context builders). Per the architecture doc excerpt surfaced during
   research: *"A ViewModel never renders a template string itself and never
   touches a repository — both are boundary violations"* — the facade is the
   only thing standing between a viewmodel and a repository.
5. **Viewmodel** (`*_viewmodel.js`, co-located with `*_view.html`) — route
   handlers only, `(c, h) => ...`, calling the facade and picking a response
   shape (`h.render` full page vs. named-fragment vs. `h.noContent`) keyed
   off `HX-Request`. E.g. `loop_viewmodel.js` (146 lines): every handler
   starts with the same `empty(c,h)` guard before touching `facade.*`.

`screens_model` is the one exception with no seed/generator pair — `registry.json`
and `flows.json` are hand-authored SSOT directly (no `*_seed.json`, no
`generate.mjs` in that directory), consistent with `screens_repository.js:4-5`'s
comment: *"reads the surface registry. The registry IS the screens model
(app-architecture contract)."*

---

## 5. Files a new scaffold shell/screens would touch

Based on the pattern every existing shell (`intake`, `design`, `build`)
follows, adding a scaffold stage as a first-class shell/screen set means
touching:

**Data spine (SSOT, must change first):**
- `designs/appbox-studio/models/screens_model/registry.json` — add one or
  more `scaffold.*` entries (id/label/surface/shell/comp/labelKey/route),
  inserted logically between the `design.freeze` block (currently
  lines 137-145) and `build.loop` (currently lines 173-181).
- `designs/appbox-studio/structure.json` — mirror the same entries
  (`shellDir`, `viewmodel`, `deps`) in its `screens` array (lines 11-372),
  add a `scaffold` key to `shellRoots` (currently lines 4-10, only
  intake/design/build/app/workspace).
- `designs/appbox-studio/models/screens_model/flows.json` — replace the
  single `design.freeze → build.loop` "Scaffold"-triggered edge
  (lines 63-67) with two edges through the new screen(s), and update the
  duplicate copy embedded in `structure.json:435-439` and
  `models/intake_model/intake.json:1927-1931` / `intake_seed.en.json:1455-1459`
  (all three currently carry the same stale direct edge).
- Possibly a new `scaffold_model/` directory (`scaffold_seed.<locale>.json` +
  `generate.mjs` + `scaffold.<locale>.json`), following the `build_model`
  pattern exactly, if the new screens need their own fixture data (e.g. a
  per-surface scaffold progress list) rather than reusing/refactoring the
  `scaffold` stage row that currently lives inside `build_model/run*.json`
  (`build_seed.en.json:41`, `run.en.json:58-70`) and its `build_repository.js`
  getters (`stage(id, locale)`, line 56).

**Views/routes/viewmodels (new directory, mirroring `design/freeze/` or
`build/loop/`):**
- New `designs/appbox-studio/ui/views/main_shell/scaffold/` directory:
  `scaffold_view.html` + `scaffold_viewmodel.js` at minimum (parallel to
  `ui/views/main_shell/build/loop/loop_view.html` /
  `loop_viewmodel.js`), possibly a `routes.scaffold.js` route table
  (parallel to `ui/views/main_shell/design/routes.design.js`,
  `ui/views/main_shell/intake/routes.intake.js`) if it needs its own route
  fan-out.
- `designs/appbox-studio/app.routes.js` — import and spread the new route
  table (pattern at lines 9-11, 27-28), add the `scaffold` key to the
  exported `shellRoots` (lines 17-23).
- A per-shell composition/shared file analogous to
  `ui/views/main_shell/design/_shared.html` (207 lines) or
  `ui/views/main_shell/intake/_shared.html` (322 lines) to assemble
  main/activity/composer for the new screen(s), since `main_shell_view.html`
  only mounts header+footer (lines 11-18).

**Repository/facade layer:**
- Either extend `services/repositories/build_repository.js` (currently reads
  `build/models/build_model/run.<locale>.json` wholesale, lines 38-48) with a
  scaffold-specific getter, or add
  `services/repositories/scaffold_repository.js` following the same
  `fixture_reader.js`-based pattern (`build_repository.js` is the closest
  template — note its `EMPTY` sentinel/`hasEvidence()` idiom at lines 14-52
  must be replicated so a project with no scaffold evidence degrades
  gracefully instead of 500ing).
- A `services/facades/scaffold_facade.js` (or new exports inside
  `design_facade.js`/`build_facade.js`) providing the context builder(s) the
  new viewmodel calls — following `design_facade.js:1265-1274`
  (`approveManifest`) as the template for "the CTA that actually advances the
  pipeline," which today does nothing but mutate session state and post a
  chat line. A real scaffold-trigger action would need to live here.

**Navigation chrome (currently hardcodes exactly 4 destinations):**
- `designs/appbox-studio/ui/views/main_shell/shared/widgets/chrome.html` —
  add a `scaffold` entry to the `destinations` array in **both**
  `headerBody` (lines 18-23) and `offCanvas` (lines 85-90) macros, and (if
  it's meant to be a top-level tab rather than a design/build sub-stage) an
  entry in `shellNames` (line 24).
- `designs/appbox-studio/l10n/app_en.arb` (+ `app_pl.arb`, `app_qps-ploc.arb`)
  — add a `tab.scaffold` key (siblings currently at lines 13-16: only
  `tab.intake`/`tab.design`/`tab.build`/`tab.settings` exist).

**CSS (only if the new screen needs a pattern not already in the shared
widget set):** `assets/css/build.css` (build.loop's own stylesheet) is the
closest existing precedent if scaffold stays a sub-view of Build; a new
`assets/css/scaffold.css` would be needed only if it becomes its own shell
with bespoke layout beyond the five-panel/`_panel.html` contract.

**Not expected to need changes:** `ui/common/base.html`,
`ui/common/widgets/primitives.html`, `ui/common/_integration_panels.md` (the
panel contract itself is stage-agnostic), `assets/fonts/`, `assets/media/`,
`evidence/` (screenshot evidence is captured after screens exist, not
before).

---

## Summary (for the return message)

Registry/structure/flows/chrome all agree: the studio models exactly three
navigable pipeline shells — `intake`, `design`, `build` — plus `app` and
`workspace`. The `design.freeze → build.loop` edge is single-hop, its trigger
literally named `"Scaffold"` (`flows.json:63-67`), but no `scaffold.*` screen
exists to receive that trigger. `design/freeze_viewmodel.js`'s approval
handler does nothing but flip a session boolean and post a chat line
(`design_facade.js:1265-1274`) — there's no route, redirect, or trigger that
actually invokes scaffolding. Meanwhile `build_model/run.en.json` already
carries a fully-imagined "scaffold" stage as row 4 of 7 inside build.loop's
single timeline (`run.en.json:58-70`, "44 files · 11 surfaces × 4 per ios
target") — but it's baked-in demo fixture data (`build_repository.js:9-11`:
no project has real build evidence yet), buried in one screen among six
other stages, with no dedicated route/viewmodel/progress view of its own.
Even the intake persona whose whole job is scaffolding ("The Developer",
`intake.json:1846-1863`) has no screen serving that goal. This is the exact
gap: navigation chrome (`chrome.html:18-23,85-90`), the shell registry
(`registry.json`), structure.json, flows.json, and route tables all currently
skip straight from design/freeze to build/loop with zero scaffold-stage
surface area — the new scaffold shell needs a registry entry, a structure.json
entry, split flow edges, a routes/view/viewmodel triad, a repository/facade
pair (or an extension of `build_repository.js`), a chrome destination, and an
l10n key.
