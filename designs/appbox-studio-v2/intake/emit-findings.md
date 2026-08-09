# appbox-studio-v2 — emit findings

STARTED 2026-08-09T05:31:46Z

Running record of the smoke-test emit. Per the brief: drift from the showcase
recipe is a **skill/recipe bug** — report, never hand-patch.

## Inputs resolved

- Recipe SSOT: `kit/showcase_app/feature-recipe.manifest.json`
  (`structureContract.root` = `kit/showcase_app/lib`, 25 `artifactTypes`).
- Exemplar tree: `kit/showcase_app/lib/ui/views/…`.
- Rulings: `docs/plans/designer-scaffolder-grill-decisions.md` Q-v2-1…5.
- Brief: `intake/design-brief.md`.

## Mechanical translation table (Dart build medium → studio design medium)

Manifest `pathTemplate` prefix `lib/` is a Dart-medium prefix; anatomy §1 maps
it to the **artifact root** (Q-v2-4 as amended). Extension map per Q-v2-4.

| artifactType | manifest pathTemplate | manifest nameTemplate | studio path (root-anchored) |
|---|---|---|---|
| shell-view | `lib/ui/views/<app>_<feature>_shell/` | `<app>_<feature>_shell_view.dart` | `ui/views/studio_<f>_shell/studio_<f>_shell_view.tsx` |
| shell-view-factor | ″ | `…_shell_view.<factor>.dart` | `…_shell_view.{desktop,tablet,mobile}.tsx` |
| shell-viewmodel | ″ | `<app>_<feature>_shell_viewmodel.dart` | `…_shell_viewmodel.js` |
| shell-design-note | ″ | `design-system.md` | `ui/views/studio_<f>_shell/design-system.md` |
| surface-view | `lib/ui/views/<app>_<feature>_shell/<app>_<surface>/` | `<app>_<surface>_view.dart` | `ui/views/studio_<f>_shell/studio_<s>/studio_<s>_view.tsx` |
| surface-view-factor | ″ | `<app>_<surface>_view.<factor>.dart` | `…_view.{desktop,tablet,mobile}.tsx` |
| surface-viewmodel | ″ | `<app>_<surface>_viewmodel.dart` | `…_viewmodel.js` |
| widget | `lib/ui/widgets/<app>_<feature>_widgets/` | `<app>_<name>_widget.dart` | `ui/widgets/studio_<f>_widgets/studio_<n>_widget.tsx` |
| shared-widget | `lib/ui/widgets/common/<widgetGroup>/` | `<app>_<name>_widget.dart` | `ui/widgets/common/<group>/studio_<n>_widget.tsx` |
| shared-consts | ″ | `<app>_<name>_consts.dart` | `ui/widgets/common/<group>/studio_<n>_consts.js` |
| facade-service | `lib/services/<app>_<feature>_services/facades/` | `<app>_<feature>_facade_service.dart` | `services/studio_<f>_services/facades/studio_<f>_facade_service.js` |
| adapter-service | `…/adapters/` | `<app>_<feature>_<name>_adapter_service.dart` | `services/studio_<f>_services/adapters/….js` |
| repository-service | `…/repositories/` | `<app>_<feature>_repository_service.dart` | `services/studio_<f>_services/repositories/….js` |
| model | `lib/data/models/<app>_<feature>_models/` | `<app>_<name>_model.dart` | `data/models/studio_<f>_models/studio_<n>_model.js` |
| schema | `lib/data/schemas/<app>_<feature>_schemas/` | `<app>_<name>_schema.dart` | `data/schemas/studio_<f>_schemas/studio_<n>_schema.js` |
| enum | `lib/enums/<app>_<feature>_enums/` | `<app>_<name>_enum.dart` | `enums/studio_<f>_enums/studio_<n>_enum.js` |
| bucket-barrel | `lib/<bucketDir>/` | `<bucketKind>.dart` | `widgets.js` / `enums.js` / `models.js` / `schemas.js` / `facades.js` / `adapters.js` / `repositories.js` |
| root-barrel | `lib/<rootDir>/` | `<rootDir>.dart` | `data/data.js`, `enums/enums.js`, … |
| seed-data | `data/seed/` | `<feature>.json` | `data/seed/<feature>.json` (no `lib/` in source ⇒ unchanged) |
| data-boot / app-join-points | `lib/app/` | `app_data.dart`, `app.router.dart`, … | `app/…` — **but see F2** |
| app-entrypoint | `lib/` | `main.dart` | root — **see F2** |
| seed-generated, shell-structure-manifest, generated-baseline | — | — | **scaffolder-owned; NOT emitted by design stage** |

Corroboration that the root (not `lib/`) is correct: `seed-data`'s manifest
path is already `data/seed/` with no `lib/` prefix, so stripping `lib/` is the
only translation that keeps `data/models/` and `data/seed/` siblings as the
exemplar has them.

## Roster derived (Q-v2-1 + Q-v2-3 × recipe grammar)

The exemplar settles the apparent Q-v2-3/recipe mismatch: in
`kit/showcase_app`, **every** `*_shell/` carries its own `_shell_view` *and* at
least one surface subdir (`showcase_search_shell/showcase_search/`), while the
hub `showcase_application_hub/` has **no** `_shell` suffix and **no** surface
subdirs. So Q-v2-3's `studio_startup_view` is the *surface* view inside
`studio_startup_shell/studio_startup/` — identical in shape to
`showcase_startup_shell/showcase_startup/`. No drift.

Factors: the exemplar ships `.desktop` + `.tablet` + `.mobile` for every view;
Q-v2-3 confirms studio is recipe-conforming with no desktop-only exception.

## VERDICT: BLOCKED — emit not started, zero surfaces written

**F0 below is a missing required input, not recoverable inside the design
stage.** Per the brief's smoke-test discipline ("report it and stop") and the
skill's own prohibition, no surface files were emitted. The translation table
and roster above are the completed derivation work, ready to execute the moment
F0 clears.

## Findings

- **F0 — BLOCKER: `intake/registry.json` does not exist and the designer is
  forbidden from creating it.**
  - The skill's run-kind table admits exactly two inputs; the one matching this
    run ("no prior scaffold" → full run, every feature) requires *a pinned
    `intake/registry.json` version*. Neither input is present:
    `find designs -name registry.json -path '*intake*'` returns nothing, and
    v1 (`designs/appbox-studio/intake/`) has none either.
  - `references/delta-runs.md` §1 is unambiguous: "**`intake/registry.json` is
    the only authoring surface in the pipeline**… The designer **does not**
    write `intake/registry.json`. Composers do." The skill further states that
    wanting to write design instructions anywhere other than a registry patch
    *is itself* the failure the rule exists to prevent.
  - This is not a cosmetic gap. The recipe manifest defines
    `inspectAttrs.screenIdSource` as "intake/registry.json entry ids,
    **verbatim**. A screenId outside that set is a gate failure." Every
    `inspectAttrs` triple stamped across the ~60 planned surfaces would carry
    ids with no legitimate source ⇒ guaranteed gate failure, and inventing the
    ids would fabricate a second source of truth ⇒ declared gate failure on the
    other side. Both roads are red.
  - **Required to unblock:** a composer-authored, pinned `intake/registry.json`
    (+ `intake/flows.json`) for the six-entry studio-v2 roster. The design
    brief is *not* a substitute — it is prose intake, not the pinned authoring
    surface, and it explicitly defers "exact names and per-shell view/widget
    rosters" to the decision log rather than supplying registry entry ids.

- **F1 — root anchoring confirmed, no action.** `lib/` strip is corroborated by
  three independent sources (anatomy §1, `design_server.dart` `resolveArtifact`
  requiring `<candidate>/app.routes.js`, `gate_design_widgets.dart` scanning
  `<artifactDir>/ui/views`) plus the `data/seed/` sibling argument above.

- **F2 — OPEN: `lib/app/` join points have no ratified design-medium home.**
  `app-entrypoint` (`lib/main.dart`), `data-boot` (`lib/app/app_data.dart`) and
  `app-join-points` (`app.dart`, `app.router.dart`, `app.locator.dart`,
  `kit_platform_router.dart`) are `scaffolder`/`shared-join-point` ownership.
  Q-v2-4 names only `app.routes.js` at the root. Root-stripping would put an
  `app/` dir at the artifact root, which nothing in the tooling asks for.
  Treating these as scaffolder-owned and emitting only `app.routes.js` is the
  reading consistent with ownership; recorded rather than silently resolved.

- **F3 — SECOND BLOCKER (verified, not assumed): the Q-v2-5 inspect rename has
  not landed.** Measured spellings across `appboxd/`, the skill and `kit/`:

  | spelling | occurrences |
  |---|---|
  | `data-inspect-role` | 26 |
  | `data-inspect-fn` | 20 |
  | `data-inspect-style` | 12 |
  | `data-inspect-overlay` | 5 |
  | `data-inspect-node` / `-motion` / `-armed` | 3 each |
  | `data-inspect-surface` | 2 |
  | **`data-inspect-screen`** | **2** — `appboxd/lib/probes/studio/probe_inspect.dart`, `references/app-architecture.md` |
  | **`data-inspect-view`** | **0** |
  | **`data-inspect-widget`** | **0** |

  Task #19 ("extend probe_inspect.dart + amend app-architecture.md:180 in ONE
  commit") is marked completed, but that was **Q13 anatomy scope**, a different
  change — the Q-v2-5 rename to `(viewId, surfaceId, widgetId)` is still
  outstanding. The brief directs the emit to use the NEW vocabulary, so the
  shipped probe and gate would fail against a correct emit. Per brief
  §Inspect identity this rename must land in ONE commit *with* the emit, so it
  has to be sequenced by the operator, not worked around here.
  **Do not "fix" `screenIdSource` in the recipe manifest** — Q-v2-4 rules the
  Q8 manifest stays Dart-only and untouched. It is logged here as a recipe-SSOT
  bug to be resolved by the same operator-owned rename.

- **F4 — OPEN: 6 of the 7 Q-v2-3 widgets have no kind in the closed 15-kind
  vocabulary.** `starter-partials/widgets/` ships exactly 15 kinds: appbar,
  bottom-sheet, card, chip, cta-link, dialog, empty-state, form-field,
  list-row, modal, nav-rail, panel-activity, tabbar, tabs, toast. Of the
  Q-v2-3 widget roster only `activity` maps cleanly (→ `panel-activity`).
  `design_canvas`, `inspector_panel`, `composer_slider_panel`,
  `needs_you_strip`, `interview_thread`, `asset_upload_dropzone` have no kind.
  Per `references/showcase-anatomy.md`, `null` in `kind-resolution.registry.json`
  legitimately means **composed** (never "unbuildable"), so these are most
  likely compositions — but that resolution is *declared in the registry*,
  which is exactly the artifact missing per F0. Improvising the mapping is a
  gate failure on both sides, so it is deferred to the registry, not guessed.

- **F5 — tooling invocation.** `appbox` is not on `PATH`. The package is
  `appboxd` (`appboxd/pubspec.yaml`) with entrypoints `appboxd/bin/appbox.dart`
  and `appboxd/bin/appboxd.dart`; `dart` is at
  `/Users/unfazed-mac/fvm/default/bin/dart`. Brief gate commands
  (`appbox design lint …`, `appbox design serve …`, `appbox lens …`) must be
  issued as `dart run` against `appboxd/bin/appbox.dart`.

  **Toolchain preflighted and GREEN** —
  `dart run appboxd/bin/appbox.dart design doctor` (exit 0):
  dart ≥ 3.12 (found 3.12), chrome headless, ffmpeg,
  `runtime/vendor/htmx.min.js`, `runtime/ladder.json`
  (rungs: compact, medium, expanded) — "all present — render and console gates
  can run". So the blockers are purely missing upstream input, not a broken
  harness.

  Note for the eventual emit: the ladder rungs are named
  **compact / medium / expanded**, while the recipe's view factors are
  **desktop / tablet / mobile**. Both vocabularies are legitimate and live in
  different layers (viewport ladder vs. Flutter factor suffixes); flagged so the
  emit does not silently conflate them.

## Recommended next action (operator)

1. Have a **composer** author + pin `intake/registry.json` (+ `flows.json`) for
   the six-entry roster (hub, startup, unknown, auth, intake, design shells),
   including the widget `kind` declarations that resolve F4.
2. Land the **Q-v2-5 inspect rename** (`probe_inspect.dart`,
   `app-architecture.md`, and the manifest's `screenIdSource` wording) so the
   gates assert the ratified triple — sequenced per the both-trees ONE-commit
   rule with the emit.
3. Re-run this emit. The derivation above (translation table + roster +
   hub/shell/surface reconciliation) is complete and needs no rework; only
   steps 1–2 are blocking.
