# Designer/Scaffolder refactor grill — decision log (in progress)

Session goal: refactor `skills/appbox-designer` and `skills/appbox-scaffolder` so both
produce/consume exactly the `kit/showcase_app/lib` structure, deterministically, across runs.
Studio context: appbox is driven ~99% of the time inside appbox studio via composers connected
to LLMs (intake interviews, design updates, feature additions). FSM phases (`lib/phases.dart`):
intake → prototype → design → scaffold → review → build → deploy, per-phase gates, human checkpoints.

## Locked decisions

- **Q1 — Scaffolder relationship to showcase structure:** strict structural isomorphism with
  showcase anatomy; showcase is the structure contract, not an example. `<app>_<feature>_` prefix
  naming; scaffolder is primarily a transliterator of frozen design structure.
- **Q2 — Transliteration vs transformation:** scaffolder covers both transliteration and
  transformation, with **default = transliteration**.
- **Q3 — Per-surface split:** per-surface widget/view split per showcase conventions
  (desktop/mobile/tablet view variants) — locked as recommended.
- **Q4 — Seeds/fixtures:** gated design-time overlay; designer seed data mirror-exact with
  showcase seed conventions; seeds/fixtures live per showcase structure.
- **Q5 — Shared anatomy SSOT + guards:** semantic frontmatter + comment conventions in showcase
  files are normative; designer + scaffolder must both know them; guards enforce.
- **Q6 — Kit awareness in designer (two tiers, natives excluded):**
  - Tier 1: generated, parity-gated JS mirror of kit-core `common/` design vocabulary only
    (colors, spacing/ui_helpers, app constants, glyphs, fonts) — same symbol names, generated
    from Dart, `kitCatalogMirrorCheck` extended to gate parity.
  - Tier 2: service kits (auth, payments, maps…) exposed via `kit-catalog.md` + `runtime/kit-facades/*.js`.
  - `AppBoxKitNative*` / ui_library widgets are **excluded** from the designer mirror: designer
    designs web (baoyu design core fork, ejects production web); natives are scaffolder
    transliteration targets only.
- **Q7 — Designed-widget → kit-native mapping contract (both-sides, closed):** designer artifacts
  declare a widget `kind` from a closed vocabulary (its starter-partials kinds: appbar, tabbar,
  bottom-sheet, dialog, toast, card, chip, list-row, nav-rail, form-field, empty-state, cta-link…);
  scaffolder owns a closed resolution registry kind→`appbox_kit` widget/recipe. Gates on both
  sides; unmapped kind = fail, never improvise. Adding a widget kind = deliberate two-registry change.
- **Q8 — Feature recipe SSOT:** machine-readable path-template manifest, showcase-adjacent
  (`kit/showcase_app/`): artifact-type → path template + naming template + frontmatter/comment
  requirements (shell, views, widgets, services facades/adapters/repositories, models, schemas,
  enums, barrels). Both skills load the same manifest. Gate: golden-expansion probe — expand for
  synthetic feature (`payments`), diff produced tree vs expansion; extra or missing file = fail.
  Showcase itself must pass the expansion. Manifest schema classifies every path
  **scaffolder-owned vs user-owned** (generation-gap boundary declared up front).
- **Q9 — Post-scaffold feature addition (no new stage; new process = feature-scoped delta runs):**
  existing phases re-enterable scoped to one feature. Per research doc
  `docs/research/post-scaffold-iteration-practices.md`: design stays SSOT; generation-gap boundary
  default; LLM-mediated 3-way merge (Copier/Cruft pattern) for cross-boundary changes.
  - Existing feature files: untouched; divergence gate *verifies* against last-generated baseline.
  - Shared join points (`registry.json`, `app.routes.js`, root barrels, locator/DI): scaffolder-owned,
    deterministically regenerated; unchanged inputs ⇒ byte-identical entries; additive-only diff.
    Idempotence asserted by golden probe (regen with unchanged feature set = no-op diff).
  - Cross-feature touches must be declared in delta scope; go through 3-way merge + human approval.
  - Obligations on current refactor: scaffolder persists last-generated baseline (`.copier-answers`
    analog) from first scaffold; manifest carries owned/user classification.

- **Q10 — Intake→designer contract for deltas (locked):** single versioned `intake/registry.json`
  (+ `intake/flows.json`) is the **only authoring surface**, pinned by a content-addressed version id.
  Designer deltas are **computed by diff between approved versions and frozen as immutable run
  artifacts under run ids**; the designer consumes the run artifact. Composers write the registry,
  **never** deltas. Per-feature intake artifacts rejected: they would create a second authoring
  surface, contradicting Q8 (feature-scoped delta runs presume derived deltas) and the Q6/Q7
  derived-mirror pattern. Evidence: Copier `.copier-answers.yml` + `copier update` 3-way merge,
  OpenSpec ephemeral `changes/` proposals, Terraform state/plan, oasdiff — one truth, derived
  change scope; Flyway/Alembic per-change files are a journal of applied changes, not an
  authoring surface.

## Audit resolutions (Q1–Q9 consistency check, locked)

- **Q2 ↔ Q11 (idempotence scope):** the "second run byte-identical" verdict applies **strictly to
  transliteration output**. Transformation output (LLM-touched, non-default) is pinned by its
  frozen run artifact (Q10) and re-verified by the non-clobber verdict, not byte-identity.
- **Q9 ↔ Q14 (merge ordering):** for cross-boundary changes the **LLM proposes** the 3-way merge,
  a **deterministic validator applies** it, and the Q14 approval gate fires only when the merge
  touches a locked decision. LLM output is never applied unvalidated.

## Open questions (remaining grill)
- **Q11 — Spike test definition (locked):** refactor both skills first, then spike: designer +
  scaffolder produce **five shells** — startup, unknown, auth, application (ceremony shells) +
  design — **plus the splashscreen** (not a shell: the mobile-device splash surface, brand logo
  only). **One probe, five verdicts**, reusing existing `ProbeReport`/`ProbeTarget` plumbing
  (no new harness):
  1. Golden tree matches the **Q8 manifest expansion** (surfaces absent from showcase — auth,
     design, splashscreen — expand from the manifest exactly like the synthetic `payments`
     feature; showcase instances corroborate application/startup/unknown).
  2. `dart analyze` clean.
  3. Second run byte-identical — **transliteration output only** (per Q2↔Q11 audit resolution).
  4. Every emitted surface carries `inspectAttrs`.
  5. Frontmatter/comment conventions present (Q5's normative rules mechanically enforced).
  After the spike passes: continue with the rest of the appbox studio design refactoring (Q13).
- **Q12 — Inspector/studio tie-in (locked):** identity is **stamped at emit time, never inferred
  at runtime** (Flutter `--track-widget-creation` pattern). Designer/scaffolder emit `inspectAttrs`
  derived from registry ids as the triple **(screenId, surfaceId, anatomy-node id)** on every
  surface (presence enforced by Q11 verdict 4). Studio inspect mode reads the triple only — hover
  tint, tags, and both icon buttons (visually-edit-in-auto-layout, add-widget-to-slider-panel
  composer) key off it. Zero DOM heuristics; inspect mode survives regeneration by construction.
- **Q13 — Studio refactor scope/sequence (locked): parallel-run.** After the Q11 spike passes,
  the new showcase-anatomy design shell is generated **alongside** the current studio design shell
  behind a flag. Probes render the same screens through both and diff the results. Cut over
  **view-by-view** — a view flips to the new shell only when its probe is green against it; flip
  back = toggle, not revert. Old shell deleted only when every view is flipped and green.
  (Rejected: big-bang — no isolation of failures; strangler-fig/branch-by-abstraction —
  incremental but produce no old-vs-new comparison evidence.)
- **Q14 — Composer/LLM touchpoints (locked):** three composers updated — (1) intake interview
  (intake deltas), (2) design-update, (3) feature-add entry point in studio UI. Composers never
  write files or deltas: they emit **registry patches** validated against the registry schema
  (strict, retry on validation failure); deterministic code applies valid patches (per Q9↔Q14
  audit resolution). Approval gate fires **only** when the derived diff touches a locked decision;
  routine additive changes are gated by probes alone (no approval fatigue).
  - **No sync mechanism exists or is needed:** a design-composer creating a new screen emits an
    intake-level registry patch (design stage is another door into the same single authoring
    surface, Q10); the derived pipeline (diff → run artifact → designer → scaffolder delta run,
    Q9) then flows automatically. Scope changes (new screen/feature) patch intake scope; design-only
    changes (layout/styling of existing screens) patch design-owned registry sections. Same
    validation + gate for both.

- **Q15 — Live-generation viewer (locked):** appbox studio renders pipeline progress itself —
  the Flutter `genui` package / A2UI stays **out** of the studio viewer (genui is alpha,
  Flutter-side, and built for LLM-composed UI at runtime, which Q10/Q14 forbid — our pipeline is
  deterministic after the registry patch). The A2UI *pattern* (constrained catalog +
  skeleton-then-fill incremental streaming) is honored studio-natively:
  1. Registry patch accepted → viewer immediately renders an **exact accent-tinted skeleton** of
     the new screen/tile derived from the patch (full anatomy is known upfront — right slots,
     right placement, `inspectAttrs`-addressable — not a generic shimmer).
  2. Pipeline emits progress events per materialized unit (`screen-started`,
     `widget-materialized`, `screen-complete`) over the studio's existing stream channel.
  3. Viewer swaps each tinted slot for the real widget live as its event arrives; tint clears on
     `screen-complete`.
  4. Failure mid-run: unfilled slots stay tinted — a visual diff of what didn't materialize
     (consistent with Q13 parallel-run verdict philosophy).
  - `genui`/A2UI remains a candidate only for *generated apps themselves* wanting runtime GenUI —
    a separate concern from the studio viewer.

## Q7 vocabulary closure — reconciliation ruling (user-confirmed)

Registry mapped 12/15 derived kinds; three resolved as follows, restoring closure (15/15, asserted mechanically against `starter-partials/widgets/_*.tsx`):

- **tabs** → `AppBoxKitAnimatedTabStack` (promoted from `tabbar.companions`; `tabbar` = in-surface strip, `tabs` = animated content stack).
- **modal** → kept as a distinct kind (vocabulary is mechanically derived; deleting it would mean deleting the partial). Resolves to a **presentation mode**, not a widget subtree: route-flag + `AppBoxKitOverlayService`/`AppBoxKitFrostedSurface`. `dialog` remains separate.
- **panel-activity** → COMPOSITION (`AppBoxKitGlassCard` + `AppBoxKitListSection` + `AppBoxKitNotificationRecord`), recorded debt pending a first-class kit activity widget.

**Composition rule (user directive):** every composition is a designer RECIPE — the designer always composes (panels included) for any design; the scaffolder emits compositions explicitly and never resolves them to one class. Recipe knowledge lives with the designer; the registry records the resolved target set.

## Q11/Q12 spike ratifications (user-confirmed)

Four decisions surfaced by the Q11 shell spike (`docs/plans/q11-shell-spike.md`, probe at `tool/spike-q11-shells/`), all confirmed as recommended:

- **(a) inspectAttrs Dart shape + anatomy-node-id vocabulary.** The Dart triple (`screenId`, `surfaceId`, anatomy node id) is ratified into kit core; the anatomy-node-id vocabulary is CLOSED in the kind-resolution registry (versioned, machine-read by both skills — same authority pattern as kinds). `app-architecture.md:169`'s JS form and the Dart shape must stay 1:1.
- **(b) Showcase is BACK-STAMPED with `inspectAttrs`** — not exempted. Showcase is normative; every emitted surface carries the triple, so the exemplar carries it too. Resolves the collision flagged at scaffolder SKILL.md:270.
- **(c) `showcase_notes_shell/design-system.md` gets a TYPED artifact entry** in the Q8 feature-recipe manifest (not an exclusion), so the manifest fully round-trips showcase (closes the Verdict-1 warn).
- **(d) `showcase_notes_shell_viewmodel.dart` is FIXED** — add the missing `Relationships:` frontmatter (19/20 viewmodels already comply). The manifest stays strict; no relaxation for trivial viewmodels.

**Also ratified from spike F1:** emitted pubspecs MUST carry kit/data's three dependency_overrides (`win32 ^6.0.1`, `device_info_plus ^13.0.0`, `package_info_plus ^10.0.0`) — the obligation moves from kit/data prose into the manifest/scaffolder rules (without it every scaffolded app fails version solving).

**Sequencing:** contract edits (registry vocabulary, kit core shape, showcase back-stamp, manifest artifact type + override rule, viewmodel fix) land only AFTER the shell-spike agent's completion report — not while its transliterator is reading the exemplar. Then the Q11 probe re-runs for five ratified verdicts (V4 no longer provisional).

## Per-app common copy + named strings (user-confirmed)

Reverses the Q6 "lib/ui/common deleted, import kit core directly" mechanism. The anti-fork goal is unchanged; the mechanism flips from *import* to *scaffold-time copy*:

- **Stacked replacement recipe.** The stacked CLI (used by appbox for apps/views/widgets/services) generates `lib/ui/common/` (incl. its own `app_strings.dart`). The scaffolder **deletes every stacked-generated file there and refills the folder with a verbatim copy of `kit/core/lib/common/`**, plus one app-authored `appbox_kit_app_strings.dart`. Kit remains the single SSOT; copies are refreshed from kit, never hand-edited (hand-editing any copied file is a FAIL; only `appbox_kit_app_strings.dart` carries app-authored content).
- **Imports.** App code imports its own copy — `package:<app_package>/ui/common/…`, never `package:appbox_kit_core/common/…`. Showcase rewired (3 files, 5 import lines) as the exemplar; `kit/showcase_app/lib/ui/common/` now carries the 8-file kit copy + demo strings file.
- **Registry.** `kind-resolution.registry.json` import targets stay kit-canonical (`package:appbox_kit_core/common/…` — SSOT location, validator unchanged); the scaffolder rewrites the package prefix to the app's copy **at emit time**. One rule, no per-app registry churn, no version bump needed.
- **Named strings vocabulary.** Prefix ratified as **`abxStr`** (`abx` = kit constants style, `Str` = string copy), e.g. `abxStrNotesEmptyTitle`. Every user-facing fixed string is a named const; design.json stores the name; studio inspector edits copy by rewriting the value behind the name; runtime data is never named and never copy-editable. Generic template: `kit/core/lib/common/appbox_kit_app_strings.dart`; per-app file demoed in showcase.
- **Doc surfaces updated:** scaffolder SKILL.md (Q6 section), designer SKILL.md, DESIGN-ARCHITECTURE.md (name-collision note), references/showcase-anatomy.md (§4, two spots), references/kit-catalog.md.
- **ARB reconciliation (ruled, confirm A).** Studio widget-editing plan Decision 14 ("ARB-keyed chrome copy") amended: `abxStr` is the authoring SSOT for copy; ARB is derived-only (keys mechanically from const names, consts swapped for l10n lookups only at an app's i18n gate). No ARB exists in kit/showcase today; the only `.arb` files are appbox-studio's own UI localization. Amendment recorded in `widget-editing-autolayout-and-manager.md` below the decisions table.
- **Pending:** portalo (and any future app) follows the same recipe at scaffold time. (Studio-side `abxStr` reference: done — the widget-editing plan is the studio inspector's doc surface; `appbox-studio/README.md` has no copy/inspector section to update.)

## Amendment — sizing-mode tokens join the abx vocabulary (ratified)

`design.json` layout slots carry kit constant names only. Sizing modes are now
first-class kit constants: `abxHug` / `abxFill` / `abxFixed` (`const String`s in
`appbox_kit_app_constants.dart`), replacing the bare keywords `"hug"` /
`"fill"` / `"fixed"`. Standing rule: **every** new constant, whatever its
concern, carries the `abx` prefix. Bound in DESIGN-ARCHITECTURE.md ("Kit token
binding"), designer SKILL.md (compose-time rule), scaffolder SKILL.md
(emit-time FAIL on raw literals). Showcase common copy re-synced from kit.


## Assets ruling (user-confirmed)

- **Apps = B, type-first, the way Flutter manages assets.** `assets/` beside
  `lib/`, sibling type dirs only on real need, registered as pubspec
  directories. UI icons are kit code glyphs (`appbox_kit_glyphs.dart`) — never
  asset files. (Font handling superseded below: Google Fonts, no binaries.)
- **Named-asset vocabulary:** `appbox_kit_assets.dart` — generic kit template
  in `kit/core/lib/common/` + app-authored copy in `lib/ui/common/`
  (the `appbox_kit_app_strings.dart` pattern). Consts are `abxImg*`; code and
  designs reference the name, never a loose path. Showcase seed:
  `abxImgShowcaseLogo` → `assets/images/showcase_logo.png`.
- **Studio exception (A, user-ratified as exception):** the studio design tree
  is ownership-scoped — `designs/appbox-studio-v2/assets/{studio,portalo}/`,
  `portalo/` feature-scoped internally — because the studio hosts two owners:
  its own chrome and the design it simulates (portalo). This exception is
  studio-only; generated apps never use ownership folders.
- **Studio v2 root (ratified):** `designs/appbox-studio-v2/{lib,assets}` —
  everything code under `lib/` mirroring the showcase recipe
  (hub > shells > views > widgets), assets as above.


## Assets ruling v2 (user-confirmed, supersedes font/ownership parts above)

- **SSOT = kit, passive (option B).** `kit/assets_default/` holds inert raw
  material + declarations that BOTH designer and scaffolder read — same rules,
  no drift. "Consolidate the kit, don't clean it": management *code* lives in
  the skills; the kit holds files + the manifest only.
- **Taxonomy (ratified):** `assets/{brand-icons/, fonts/, images/}` +
  `assets.manifest.json`. Defaults shipped: `brand-icons/appbox-icon.png` +
  `appbox-icon.svg` (moved from repo root 2026-08-09).
- **Fonts = Google Fonts by name, no binaries.** Designer resolves via
  CDN/CSS; scaffolder emits the `google_fonts` package. `appbox_kit_fonts.dart`
  is a pure catalogue: `abxFont*` → Google family name. Font *roles*
  (`primary`, `monospace`, …) in the manifest, not raw family lists — swapping
  a family at intake retouches nothing downstream. `assets/fonts/` holds files
  only when a user uploads a custom brand font at intake (then scaffolder
  emits a real pubspec `fonts:` block instead of a google_fonts call).
- **Brand icons = brand identity ONLY** (launcher/app icons), distinct from UI
  glyph management. Scaffolder wires `flutter_launcher_icons` (dev-dep +
  per-app config yaml redirecting to `assets/brand-icons/`) covering
  iOS/Android/web. **Standing rule: updating that config yaml is a mandatory
  step of every scaffold and every re-scaffold after a brand-icon change —
  the scaffolder always rewrites it to the app's `assets/brand-icons/` master
  and re-runs generation; a config left at a default/template path is a
  FAIL.** One master image; platform variants always derived, never
  hand-authored. Intake ALWAYS asks for brand png + svg (svg optional).
- **Flow:** intake uploads (organized per taxonomy) → designer merges uploads
  over `kit/assets_default/` (user-provided entries REPLACE defaults in the
  emitted folder) → designer emits merged `assets/` + manifest with the design
  → scaffolder pure copy-paste of the folder, reading ONLY the manifest to
  wire google_fonts, flutter_launcher_icons config, pubspec registration, and
  the app's `appbox_kit_assets.dart` (`abxImg*` consts).
- No uploads → the appbox defaults ship as-is (appbox brand icon, Inter/
  JetBrains Mono via Google Fonts).


## Studio v2 — hub + shell roster (Q-v2-1, user-confirmed)

- **Prefix A: `studio_`** — one-word app prefix, same convention as
  `showcase_`.
- **Roster (derived from studio function, v1 views were candidates only):**
  ```
  lib/ui/views/
    studio_application_hub/    hub — routes/nav host (showcase recipe)
    studio_startup_shell/      ceremony: boot/loading
    studio_unknown_shell/      ceremony: 404/unknown route
    studio_auth_shell/         ceremony: sign-in
    studio_intake_shell/       intake interview + uploads (brand assets, Q10 door)
    studio_design_shell/       working surface: canvas + inspector + composer
                               slider panel (portalo renders here)
  ```
- Splashscreen = surface, not a shell (standing ruling). Portalo is NOT a
  shell — it is the simulated design rendered inside `studio_design_shell`,
  assets under `assets/portalo/`.
- **Pipeline ↔ shell coherence (user-ruled):** the appbox pipeline must
  reflect each shell and its **declared input/output** — every stage a shell
  fronts (intake → design → scaffold/eject) names the artifact it consumes
  and the artifact it produces, so the shell roster and the pipeline stay one
  vocabulary.
- **Per-shell manual triggers (user-ruled):** appbox studio provides a manual
  "proceed to next stage" trigger per shell in the studio design — stage
  advancement is user-gated, never implicit, maintaining appbox coherence.

## Q-v2-2 — shell↔pipeline mapping (DEFERRED)
- User ruling 2026-08-09: defer. The studio is a UI to operate on the pipeline; the FSM (`appboxd/lib/pipeline_fsm.dart`, 7 phases, human gate on prototype) stays SSOT untouched.
- Not decided: registry `pipeline` section, all-phase manual advance, which shell fronts machine phases. Reopen when studio v2 wires stage controls.

## Q-v2-3 — views/widgets per shell + surface capability ladder (user-confirmed)

- Shell → views → widgets per showcase recipe. Inspector and composer are **widgets/panels,
  never views** (only routable things are views).
  - `studio_application_hub/` — hub view only (routes/nav host)
  - `studio_startup_shell/` → `studio_startup_view`
  - `studio_unknown_shell/` → `studio_unknown_view`
  - `studio_auth_shell/` → `studio_auth_view`
  - `studio_intake_shell/` → `studio_intake_view` (widgets: interview_thread, asset_upload_dropzone)
  - `studio_design_shell/` → `studio_design_view` (widgets: design_canvas [portalo renders here],
    inspector_panel, composer_slider_panel, needs_you_strip, activity)
- **Studio is recipe-conforming — NO desktop-only exception.** Every studio view emits
  desktop/mobile/tablet variants like any showcase app (appbox functions remotely).
- **Preview containment rule:** a studio surface previews only designs of its own device class
  or smaller — desktop ⊇ tablet ⊇ mobile.
  - desktop (default): canvas previews portalo desktop/tablet/mobile; inspector panel,
    composer slider panel, needs-you strip, activity — everything.
  - tablet: canvas previews tablet + mobile designs only; composer + activity as drawers.
  - mobile: portalo's mobile design full-screen as canvas/viewer; composer + activity as drawers.
- **Inspect works on ALL surfaces including mobile** (user-ruled): interaction is hover on
  desktop, tap on touch; the Q12 emit-time triple is pointer-agnostic. On tablet/mobile the
  inspector presents as a drawer like composer/activity.

## Q-v2-4 — recipe→web mapping for studio v2 (user-confirmed: A)

- Studio v2 uses the Q8 manifest's folder/naming grammar verbatim under
  `designs/appbox-studio-v2/lib/`, with a declared artifact-type → extension map for web:
  view → `.tsx` (per-surface `*.desktop.tsx` / `*.tablet.tsx` / `*.mobile.tsx`),
  viewmodel → `.js`, services/facades → `.js`.
- **Barrels follow the showcase category-name convention, NOT `index.js`** (user-ruled):
  barrel file named for the folder's artifact category exactly as showcase does
  (`widgets.dart`/`enums.dart`/`models.dart`/`data.dart`) → studio `widgets.js`,
  `enums.js`, `models.js`, `services.js`.
- Q5 frontmatter/comment conventions apply verbatim; Q12 `inspectAttrs` stamped at emit.
- The Q8 manifest itself stays Dart-only and untouched — the studio *follows* the recipe
  as discipline; only apps are *generated* from it. Extension map lives here + studio README.

## Q-v2-5 — v1→v2 cutover (user-confirmed: A, amended)

- v2 built fresh at `designs/appbox-studio-v2/` per Q-v2-1…4; v1 untouched and running
  throughout; v1 views are candidates only, never copied wholesale.
- **No flip/toggle mechanism** (user-ruled): probe green is a precondition, but a shell goes
  live only on explicit **user validation** — manual, per shell. No automated flip, nothing
  to flip back.
- Cutover order: ceremony shells first (startup, unknown, auth), then intake, then design
  shell last. v1 deleted only when every shell is user-validated. No back-stamping of v1.
- **Inspect attrs rename to the ratified vocabulary** (user-ruled): the emit-time triple
  becomes (viewId, surfaceId, widgetId) → `data-inspect-view | data-inspect-surface |
  data-inspect-widget`. screen/page stays out of vocabulary; shell is derivable from the
  view (inspector operates on widgets-in-a-view only, per standing ruling).
  `probe_inspect.dart` + app-architecture doc updated together in ONE commit when v2 emit
  lands (both-trees rule).
- Carry-over: probe-side plumbing and Q13 findings (fragment-export constraints, viewmodel
  cutover unit) carry as contracts/knowledge, not files.

## GRILL COMPLETE
Q1–Q15, audit resolutions, ratifications, and Q-v2-1…5 locked (Q-v2-2 deferred, reopen
point recorded). Next: execute studio v2 build-out per this log.
