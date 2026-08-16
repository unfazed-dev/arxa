# The appbox pipeline, end to end, and the scaffold stage's contract

Scope: every stage from client idea to a shipped app, with each stage's input
artifact, output artifact, and the skill/tool that runs it; the scaffold
stage's exact position and its exact read/write contract; and the docs that
prove the design output already carries everything scaffold needs. Every
claim below is a file path + line reference into this worktree.

## 1. Ordered pipeline stages

The FSM phase order is `intake → prototype → design → scaffold → review →
build → deploy` (`appboxd/lib/phases.dart`, restated at
`docs/appbox-system-map.md:1` under "2. Pipeline stages and user-interaction
checkpoints", and again in `pipeline/README.md:1`: "the phase FSM is
`appboxd/lib/phases.dart` (+ `pipeline_fsm.dart`): intake → prototype →
design → scaffold → review → build → deploy, with the current phase tracked
in `pipeline/state/default.state.json`"). `appboxd/lib/engine.dart` derives
the deterministic stage runner from `gateOrder` (`appboxd/lib/gate_runner.dart`).

The system map's stage diagram (`docs/appbox-system-map.md`, "2. Pipeline
stages...") groups the FSM phases with their gates and human checkpoints
(marked ⧗ — an agent can reach these, never pass them):

| # | FSM phase | gate(s) | human checkpoint |
|---|---|---|---|
| 1 | intake | `gate: intake` — registry ↔ answers/brief traceability | intake interview + confirm steps (`/intake`, `/intake/{personas,surfaces,flows,direction}`) |
| 2 | prototype | `gate: freeze` — inputs + `approval.lock` + clean renders; writes `designHash` | design chat refine loop (`/design/chat`); **HUMAN GATE 1**: manifest approval (`/design/freeze` → `freeze --approve` mints `approval.lock`) |
| 3 | design | `gate: structure` — `structure.json` sync + `designHash` fresh | — |
| 4 | scaffold | `gates: scaffold S0–S10 + coverage C1–C5` + entitlement (machine-bound JWT, fail-closed — paywall lives here since 2026-08-05, `0a9c87b`) | — |
| 5 | review | `gates: review` (arch_guard + ponytail + manifest hash) + memory | **HUMAN GATE 2**: review verdict (`POST /api/review/approve\|reject`) |
| 6 | build | `gates: native_deps + lens` (design-vs-built goldens) | build gate decisions (`POST /build/gates/decide`); stage controls (`/build/stages/:id/control`) |
| 7 | deploy | `gates: deploy` (triple, fail-closed — licence check retired with the move to scaffold) + advertise | **HUMAN GATE 3**: `deploy --approval` token, human-supplied, never minted by code |

Review REJECT rewinds the FSM to `design` (same diagram, `p5 -.->|"review
REJECT rewinds FSM to design"| p3`).

### Stage-by-stage: skill, input artifact, output artifact

**Ø. Orchestration (front door, optional)**
- Skill: `skills/appbox-orchestrator/SKILL.md`.
- Position: stage Ø — the operator’s front door, before everything. Interactive
  start (asks where + name + targets + locales; runs `appbox project init` /
  `use` verbatim, `appboxd/lib/project_cli.dart`), dispatch to the ONE next
  skill by pipeline state (`projectStage()` in `appboxd/lib/project.dart`),
  and the cross-stage where-are-we view. Never owns a stage, never writes
  artifacts, never enforces ordering — the FSM/gates stay the only enforcer.
  First call after project creation is `appbox-cicd` day-zero bootstrap.

**0. Story mapping / moodboarding (pre-intake, optional)**
- Skill: `skills/appbox-story-mapper/SKILL.md`, `skills/appbox-moodboarder/SKILL.md`.
- Position: "story-mapper → moodboarder → appbox-designer"
  (`skills/appbox-moodboarder/SKILL.md`, opening ASCII diagram). The
  story-mapper is described as "the tail of the intake chain — one chain, one
  brief" (`skills/appbox-story-mapper/SKILL.md`, "Where this sits in the
  appbox pipeline"). Both skills "elicit; do not generate" (architecture §22)
  — they gather and curate, never design.
- Input: a JSON requirements object (`data.json`) for story-mapper; the
  client's visual references for moodboarder.
- Output: `docs/design/story_map.html` + `docs/design/story-map.json` +
  `docs/design/brief.md` (story-mapper, via `appbox emit story-map --input
  data.json --output ... --data-out ... --brief-out ...`, "Step 3: Generate
  the artifacts"); `docs/moodboards/*` + `moodboard.json` (moodboarder).
  When intake answers exist, `--answers <f>` makes the brief the **unified**
  one (intake sections first).

**1. Intake**
- Skill: `skills/appbox-intake/SKILL.md`.
- Input: elicited client answers conforming to
  `skills/appbox-intake/intake.schema.json`, or a hand-written
  `docs/design/brief.md` (`appbox intake seed --brief ...`).
- Output ("What you produce (and what you do not)"): `answers.json`,
  `brief.md`, `registry.json`, `flows.json`, `personas.json`, `map.json`,
  `moodboard.json`, `direction.json` — written to
  `~/.appbox/projects/<name>/intake/` with `--project`, or the registry
  seeded at the design root (`designs/<app>/models/screens_model/registry.json`,
  or `structure.json`'s `"registry"` field) without it.
- Gate: `gate: intake` — registry ↔ answers/brief traceability (pure Dart,
  `appboxd/lib/gate_intake.dart`; plan 10.6), which "asserts every registry
  entry traces to a brief requirement and back" (SKILL.md "Procedure (2)").
- Hand-off: "The brief and the seed are the inputs to `appbox-designer`... The
  emitted `## Layout template` section is consumed by the designer
  **verbatim**" (SKILL.md "Procedure (2)").

**2. Prototype / Design**
- Skill: `skills/appbox-designer/SKILL.md`, methodology in
  `skills/appbox-designer/system-prompt.md`, binding contract in
  `skills/appbox-designer/DESIGN-ARCHITECTURE.md`, and the pipeline-facing
  layer contract in `skills/appbox-designer/references/app-architecture.md`.
- Input: the intake brief + registry seed (or a hand-written brief); the
  Layout Template section; the viewport ladder
  (`skills/appbox-designer/references/viewport-ladder.md`).
- Output — "the triad output": *three switchable lenses over one screen
  registry* — **prototype** (wired navigation over each entry's `route`),
  **flows** (journeys as an edge graph), **screens** (the tile inventory) —
  "never three separate artifacts" (`skills/appbox-designer/SKILL.md`, opening
  section). Concretely: an authored `models/screens_model/registry.json`, a
  `surfaceId` in every viewmodel, `app.routes.js` (route table +
  `shellRoots`), optional `models/screens_model/flows.json`, and — once frozen
  — a generated `structure.json`.
- Gates spanning this phase: `gate: freeze` (phase "prototype" — "inputs +
  `approval.lock` + clean renders; writes `designHash`") and `gate: structure`
  (phase "design" — "`structure.json` sync + `designHash` fresh"). **HUMAN
  GATE 1** (manifest approval) sits inside `freeze`.
- The three-layer arrow, never reversed
  (`skills/appbox-designer/references/app-architecture.md:13-24`):
  ```
  AUTHORED      models/screens_model/registry.json   ← you write this, by hand
                         ↓
  DERIVED       ui/views/**  +  app.routes.js        ← follows the registry
                         ↓
  GENERATED     structure.json                        ← the freeze emits it
  ```

**3. Scaffold** — see §2 below for the full contract.
- Skill: `skills/appbox-scaffolder/SKILL.md`, `skills/appbox-scaffolder/README.md`.
- Engine: `appboxd/lib/scaffold.dart` (`appbox emit scaffold`).
- Gates: `scaffold S0–S10` (`appboxd/lib/gate_scaffold.dart`) + `coverage
  C1–C5`.

**4. Build (widget implementation)**
- Skill: `skills/appbox-builder/SKILL.md` ("builder — fill extension points by
  composing adaptive primitives").
- Input: the scaffolded stub tree (View/ViewModel extension points) +
  `deps` recorded in each stub's header
  (`skills/appbox-scaffolder/...` "Procedure" step 4: "Hand off to the
  builder. The scaffold is structure; `appbox-builder` implements the widget
  trees and wires services from the `deps` recorded in each stub's header").
- Output: filled View/ViewModel bodies composing
  `lib/ui/primitives.dart` once; the per-platform native family (glass /
  expressive / shadcn) lives in the primitives, not the views.

**5. Test**
- Skill: `skills/appbox-tester/SKILL.md` ("tester — TDD (Ports mocked),
  visual, smoke, E2E").
- Layers: unit → widget → smoke → visual → E2E (cheapest first, escalate
  scope).
- Output: "A passing suite (unit→widget→smoke→visual→E2E) + the freeze. The
  reviewer gates on it."

**6. Review**
- Skill: `skills/appbox-reviewer/README.md`, `skills/appbox-reviewer/SKILL.md`.
- "Runs the design judge. Belongs: review logic. Does not belong: scaffolding
  or deployment" (README.md).
- Gates: `review` (arch_guard + ponytail + manifest hash) + memory.
  **HUMAN GATE 2** (review verdict) sits here; REJECT rewinds the FSM to
  `design`.

**7. Lint (cross-cutting, not phase-bound)**
- Skill: `skills/appbox-lint/SKILL.md` ("keep the knowledge base honest").
- Runs `appbox docs` (Dart port of `lint_kb.py`) plus a semantic
  cross-check across `catalogs/*.json` ↔ `docs/` ↔ `memory/` ↔ code comments,
  resolved per `KNOWLEDGE.md`'s layer hierarchy.

**8. Lens (cross-cutting capture/verification, used by moodboarder, build,
   and review)**
- Skill: `skills/appbox-lens/SKILL.md` ("see appbox with appbox's own eyes").
- Dart library over CDP (`appboxd/lib/lens.dart` over `appboxd/lib/cdp.dart`)
  — "the promoted probe-runner port... never use the archived probe-runner."
- Capabilities: golden capture/compare, console-error checks, DOM/a11y/net
  extraction, motion capture, design-token extraction, native capture
  (adb/simctl/macos/flutter). Used by build's `lens (design-vs-built
  goldens)` gate.

**9. Build (packaging) + Deploy**
- Skill: `skills/appbox-deployer/SKILL.md` ("stores (fastlane) + OTA patches
  (shorebird) + web (Cloudflare Pages/Workers, Vercel)").
- Gates: `native_deps` (phase "build" — asserts every plugin is packaged for
  each target's native toolchain) + `deploy` (triple, fail-closed; the licence
  check moved to the scaffold boundary as the entitlement JWT, 2026-08-05).
  **HUMAN GATE 3**: `deploy --approval` token, human-supplied
  ("Deploy is the only outward-facing pipeline action — confirm with the
  operator before pushing," `skills/appbox-deployer/SKILL.md` "Output").
- Output: "A shipped build (store track), a shorebird patch version, and/or a
  web deployment URL (Pages, Workers or Vercel)."

**10. CI/CD (cross-cutting automation around the tail; not a build stage)**
- Skill: `skills/appbox-cicd/SKILL.md` ("elicit the decisions, then wire the
  pipeline").
- Position: not a build stage — **the frame the build grows inside**:
  invocable at day zero (before intake; `appbox-orchestrator` dispatches here
  first), wrapping ALL gates via `appbox gate --all`; the tail (tester suites,
  reviewer verdicts, deployer gates) runs inside it once artifacts exist
  (`skills/appbox-cicd/SKILL.md` "Pipeline position"). Two modes: **bootstrap**
  (no CI — grill + generate) and **adopt** (CI exists — audit against the
  guardrail list + a report-only PR sweep: read PRs, `gh pr checks`, reproduce
  red checks locally, one feedback report; never bot-comments, never merges).
  Also generates the PR stage convention: `[abx-<skill-name>]` title tags +
  `.github/pull_request_template.md`, warn-not-fail until bedded in.
- Grills nine CI decisions in dependency order (deliverable → repo shape →
  stack → visibility → runner → gates → trunk → agent letter → CD timing) into
  `docs/ci-decisions.md`, then generates `scripts/check.sh` (the one-root
  check: local green = CI green), `.github/workflows/ci.yml`, branch
  protection via `gh api`, and runner setup.
- For appbox-built targets it wires `appbox gate --all` and never
  re-implements a validator; the deploy job PREPARES and HALTS at the
  deployer's approval gate (human gate 3 stands — CI can never mint the
  token).

## 2. The scaffold stage's exact contract

### Position

Scaffold is FSM phase 4 of 7, immediately after `design` and before `review`
(`docs/appbox-system-map.md`, "2. Pipeline stages..."; `pipeline/README.md`).
Its skill states the position as an inversion of an existing gate pair
(`skills/appbox-scaffolder/SKILL.md`, "Core principle"):

> "The scaffolder PRODUCES the tree; the gates ASSERT it." (architecture §16)
> The structure gate checks the authored layer (`registry.json` +
> `ui/views/**`) against `structure.json`. The coverage gate checks the
> scaffolded layer (`lib/ui/views/**`) against `structure.json` + targets.
> **This skill is the missing producer between them** — the one the P14
> dogfood named (dogfood-report 14.8 / honest-bar #2): until it existed, no
> tool turned a frozen design into the Flutter file set...

### What it reads

The scaffold engine (`appboxd/lib/scaffold.dart` — `appbox emit scaffold`)
"reads a FROZEN `structure.json` + the target set and PRODUCES the file set
+ the `.shell-structure.json` manifest the coverage gate reads"
(`appboxd/lib/scaffold.dart:5-20`). It **never re-derives structure**; the
skill's Procedure step 1 requires confirming freeze first (`KIT_DESIGN_DIR=<design>
appbox emit structure --check`).

`structure.json` is generated by `emit_structure.dart` from the authored
layer (`skills/appbox-designer/references/app-architecture.md:11-24`). Its
top-level keys, per `appboxd/lib/emit_structure.dart:334-337`:

```dart
'registry': 'models/screens_model/registry.json',
'shellRoots': shellRoots,
'flows': ?flows,
```

plus, per screen (implicit in the emitted `screen` map, `emit_structure.dart:299-315`
and confirmed by `appboxd/lib/scaffold.dart:338-339` — "its screen records
are id/comp/shellDir/surface/viewmodel/kits"): `id`, `comp`, `shellDir`,
`surface`, `viewmodel`, and optional `kits`.

Each registry entry (`models/screens_model/registry.json`, one entry per
surface — the SSOT for what the app contains) carries the fields documented
in `skills/appbox-designer/references/app-architecture.md:30-67` and
`skills/appbox-designer/DESIGN-ARCHITECTURE.md:49-57` ("Registry canon"):

| key | required | meaning |
|---|---|---|
| `id` | yes | stable dotted identifier `<shell>.<short>`; never renamed once shipped |
| `label` | yes | human title |
| `surface` | yes (or `null`) | the surface file's identity; `null` **is** the exclusion — no parallel exclusions list |
| `shell` | yes | first segment of `id`, denormalized for grouping |
| `comp` | derived | `PascalCase(shell) + PascalCase(short)` — the scaffolder's class name |
| `labelKey` / `route` | no | l10n key for the label; the Surface's URL path |
| `requiresAuth` | no | truthy = compiled route table guards this route |
| `tab` | no | `true` = bottom-tab membership; tab order = registry order |
| `kits` | no | array of kit dir names from `config/kit-registry.json` (`kits[].dir`) that the surface's built app will use |

Concretely what scaffold consumes from each field, per
`skills/appbox-scaffolder/README.md` and
`skills/appbox-scaffolder/SKILL.md` ("What you produce (and what you do
not)"):

- **`--targets` + `pipeline/state/targets.derivation.json` + config
  viewports** → the derived form-factor file set per surface (`macos` →
  `desktop` → 3 files; `ios,android` → `mobile, tablet` → 4 files; `web` →
  `mobile, tablet, desktop` → 5 files). "Never a per-surface literal."
- **the registry's stable `id`** → the scaffolder's directory-naming decision
  `<shell>_<short>` recorded in `.shell-structure.json` (coverage "refuses to
  guess it").
- **`kits` on a frozen surface** → recorded per surface: a `//   kits
  (builder wires): <names>` line in each stub header
  (`appboxd/lib/scaffold.dart:145-159`, `:254-263`) and a `kits` entry in
  `.shell-structure.json` (`appboxd/lib/scaffold.dart:444-451`). "It records,
  never acts — the builder wires the modules."
- **the design's `l10n/*.arb` catalogs** (when present) → copied verbatim
  into `lib/l10n/`, a fixed-contract `l10n.yaml` dropped at the app root
  (`appboxd/lib/scaffold.dart:44`, `:396-405`), and `"l10n":
  {"arbDir","locales"}` recorded in the manifest
  (`appboxd/lib/scaffold.dart:440-441`). A design with no `l10n/` dir gets no
  l10n artifacts (`appboxd/lib/scaffold.dart:376`: "an empty l10n/ dir =
  absent").

It explicitly does **not** read or write `pubspec.yaml` — dependency
resolution for declared `kits` is the builder's wiring step, not the
scaffolder's (`skills/appbox-scaffolder/SKILL.md`, "What you produce...":
"You do not choose dependencies").

### What it emits

Per frozen surface, exactly the derived form-factor file set (view + per-factor
view + viewmodel — 3, 4, or 5 files depending on `--targets`), plus:

1. `lib/ui/views/.shell-structure.json` — the manifest the coverage gate
   reads: `selfContained` shells + the `{shell: {surfaceId: dir}}` map, plus
   optional `l10n` and `kits` sub-maps (`appboxd/lib/scaffold.dart:410-451`).
2. (When `l10n/` exists in the design) `lib/l10n/*.arb` + `l10n.yaml` at the
   app root.
3. The pubspec side of l10n (`flutter_localizations`, `intl`,
   `flutter.generate: true`) — emitted unconditionally, but by
   `appboxd/lib/blueprint.dart`, not the scaffolder.

It does **not** produce widget bodies, business logic, or platform ceremony
files (entitlements, `Info.plist`) — those belong to `appbox-builder` /
`appbox-deployer` (`skills/appbox-scaffolder/SKILL.md`, end of "What you
produce...").

### Verification and hand-off

`appbox emit scaffold --design-dir <design> --app-root <app> --targets
macos --check` regenerates the expected set in memory and diffs against
disk — "a missing factor file, a stale manifest, or a hand-edited dir is
named and fails. This is the same file set `gates/coverage` (C1) walks."
(`skills/appbox-scaffolder/SKILL.md`, "Procedure" step 3). Step 4: "Hand off
to the builder. The scaffold is structure; `appbox-builder` implements the
widget trees and wires services from the `deps` recorded in each stub's
header. The coverage gate then asserts the scaffolded layer."

`appbox emit scaffold --self-test` is the engine's own negative + positive
proof (`skills/appbox-scaffolder/SKILL.md`, "The guardrail, as a test").

## 3. Docs proving the design output already carries everything scaffold needs

- `skills/appbox-designer/references/app-architecture.md:11-24` states the
  one-directional arrow explicitly: `structure.json` is *generated* from the
  registry (never inferred from filenames, never hand-edited), which is
  exactly the frozen input scaffold requires.
- `skills/appbox-designer/DESIGN-ARCHITECTURE.md:29-36` ("output triad"
  section): "Every generated artifact — fixtures, `registry.json`/
  `structure.json`... is a **pure function of checked-in inputs**... Same
  inputs, byte-identical output, on every machine and every run... This is
  what makes the output triad (views / flows / proto) trustworthy as
  pipeline input: regenerating a design never invents drift." This is the
  guarantee that lets scaffold treat `structure.json` as authoritative
  without re-deriving anything.
- `skills/appbox-designer/built-in-skills/declare-structure.md` ("`kits`
  field — declaring kit modules") documents the designer-side authoring rule
  that produces the `kits` array scaffold later threads through: "Names must
  come from `config/kit-registry.json` (`kits[].dir`) — the emitter
  validates them and fails on an unknown name... each name becomes wiring
  the builder must do."
- `appboxd/lib/emit_structure.dart:236-250` is the validation that makes this
  binding: it fails at freeze/structure-emit time if a screen declares a
  `kits` name absent from `config/kit-registry.json`, so by the time
  scaffold reads `structure.json` the `kits` list is already guaranteed
  valid — scaffold does no re-validation, just records it.
- `skills/appbox-scaffolder/README.md`: "Scaffolds app surfaces from a frozen
  structure.json + target set, emitting the per-surface Dart files that
  match the target-DERIVED form-factor set" — stated as the skill's entire
  reason to exist, i.e. structure.json is sufficient input.
- `docs/plans/implementation/05-structure-registry.md` ("05 — `emit_structure`
  reads the registry") documents the historical defect this fixed and step
  5.7: "Emit into `structure.json`, per screen: `id`, `shell`, `comp`,
  `surface`, plus the resolved `viewmodel` path and its declared
  repository/facade dependencies" — i.e. the registry→structure.json handoff
  was purpose-built to carry everything a downstream consumer (scaffold)
  needs, joined on the declared `surfaceId` rather than filename similarity
  (step 5.3, chosen specifically because filename-similarity joins only
  resolved 21 of 37 measured cases).

**Stop condition check**: the scaffold skill and stage exist, are fully
specified, and have a working Dart engine (`appboxd/lib/scaffold.dart`,
`appboxd/lib/gate_scaffold.dart`, `appboxd/lib/scaffold_cli.dart`,
`appboxd/test/scaffold_test.dart`, `appboxd/test/gate_scaffold_test.dart`) —
this is not a missing stage.
