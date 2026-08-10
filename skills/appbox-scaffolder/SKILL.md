---
name: appbox-scaffolder
description: Use to turn a FROZEN design into the per-surface Flutter file set the coverage gate asserts. Scaffolds app surfaces from structure.json + targets; form factors follow targets (macos -> 3 files/surface, ios/android -> 4), never empty. Trigger on "scaffold the app", "generate the views", "emit the Dart", "why does coverage find no lib/ui/views". Drives `appbox emit scaffold` (the Dart port in appboxd/lib/scaffold.dart).
---

# appbox-scaffolder — produce the Dart tree the gates assert

## Core principle

> **The scaffolder PRODUCES the tree; the gates ASSERT it.** (architecture §16)

The structure gate checks the authored layer (`registry.json` + `ui/views/**`)
against `structure.json`. The coverage gate checks the scaffolded layer
(`lib/ui/views/**`) against `structure.json` + targets. **This skill is the
missing producer between them** — the one the P14 dogfood named (dogfood-report
14.8 / honest-bar #2): until it existed, no tool turned a frozen design into the
Flutter file set, so "scaffold D1" and "coverage of D1" had no target.

It is the **inverse of the structure gate**: where that gate asserts the tree
matches the registry, the scaffolder emits that tree from a frozen
`structure.json`. What it writes is exactly what `gates/coverage` then walks.

## What you produce (and what you do not)

One engine (`appbox emit scaffold`, Dart in `appboxd/lib/scaffold.dart`) reads `structure.json` + the target set and writes,
per frozen surface, **exactly the derived form-factor file set** (architecture
§16, P06):

| `--targets` | derived factors | files / surface |
|---|---|---|
| `macos` | `desktop` | `_view.dart` + `_view.desktop.dart` + `_viewmodel.dart` = **3** |
| `ios,android` | `mobile, tablet` | `_view.dart` + `_view.mobile.dart` + `_view.tablet.dart` + `_viewmodel.dart` = **4** |
| `web` | `mobile, tablet, desktop` | **5** |

The set is read from `pipeline/state/targets.derivation.json` + config
viewports (P06), **never a per-surface literal**. An empty `.mobile`/`.tablet`
is **never** emitted to satisfy a counter — a file that exists, passes the
check, and is never rendered is the stale-green pattern §16 exists to kill.

It also writes `lib/ui/views/.shell-structure.json` — the manifest the coverage
gate reads (`selfContained` shells + the `{shell: {surfaceId: dir}}` map). The
directory name is a scaffolder **decision** (coverage refuses to guess it);
here it is `<shell>_<short>` from the registry id (the stable key, §18),
recorded so the gate can check it. When a frozen surface declares `kits`
(registry → `structure.json`), the scaffolder records them per surface: a
`//   kits (builder wires): <names>` line in each stub header and a `kits`
entry in `.shell-structure.json`. It records, never acts — the builder wires
the modules.

When the design carries `l10n/*.arb` catalogs (`app_<locale>.arb`), the
scaffolder also copies them verbatim into `lib/l10n/`, drops a fixed-contract
`l10n.yaml` at the app root (gen-l10n; `template-arb-file: app_en.arb`, no
synthetic package), and records `"l10n": {"arbDir", "locales"}` in the
manifest so gates never re-derive the locale set. `--check` asserts the
catalog file set + `l10n.yaml` too. A design with no `l10n/` dir gets **no**
l10n artifacts (backward compat). The pubspec side of l10n
(`flutter_localizations`, `intl`, `flutter.generate: true`) is emitted
unconditionally by `appboxd/lib/blueprint.dart`.

**You do not choose dependencies.** The scaffold never reads or writes a
`pubspec.yaml`; the dependency set arrives from the kit and the app template.
This holds for declared `kits` too — the stub header names them for the
builder, but resolving the actual package deps is the builder's wiring step,
not yours.
That means a dependency which cannot be built for a declared target is not
something you can prevent here — it is caught over the assembled app by
[`gates/native_deps`](../../gates/native_deps/README.md), which asserts that
every plugin is packaged for each target's native toolchain (today: Swift
Package Manager on Apple platforms, where Flutter 3.44 warns that an
unmigrated plugin "will become an error in a future version"). If that gate
fires on an app you scaffolded, the remedy is in its README — do not silence it
by dropping a target.

You do **not** produce: widget bodies, business logic, platform
ceremony files (entitlements, Info.plist — those are the deployer/builder's
concern), or anything that is design. Every emitted file is a **minimal valid
Dart skeleton** carrying the class name the builder implements, marked as a
stub. The builder (plan 08) fills the bodies.

- **File structure (canon: `BUILDER_playbook.mdx` → File structure):** every emitted file (view, viewmodel, facade, adapter, repository, widget) carries the semantic library doc comment above `library;` — layer intro → role paragraph → requirements → relationships diagram → history — with locked body sections per kind. Models get the light variant. The scaffolded stubs must include the `library;` directive and a placeholder frontmatter the builder fills in.

## Mode: transliteration by default (Q2)

Two modes, and the default is the conservative one.

**Transliteration (default).** The designer's materialized anatomy is already the
app's shape. You carry it across into the showcase structure with kit widgets —
same nodes, same nesting, same order. You are a translator, not an author. If a
node exists in the anatomy, a widget exists in the output; if it doesn't, nothing
appears. This is the mode that makes the output auditable: a reviewer can diff the
anatomy against the tree and see a one-to-one map.

**Transformation (opt-in).** Restructuring — collapsing nodes, hoisting shared
widgets, splitting a surface — happens **only** when explicitly requested, and each
transformation is recorded in the run artifact with the rule that fired. An
unrecorded transformation is indistinguishable from a bug.

Defaulting to transformation would be the seductive mistake: the output would look
more "designed" and would silently stop corresponding to anything the designer
approved. Transliteration keeps the correspondence checkable.

## The structure contract (Q1)

`kit/showcase_app/lib` is **the contract, not an example.** Its folder layout,
naming, barrels, comment conventions and frontmatter are what you emit — for every
app, not just showcase-shaped ones. 207 `.dart` files across
`app/ ui/views/ ui/widgets/ services/ data/models/ data/schemas/ enums/`.

Naming is `<app>_<feature>_` almost everywhere. The two structural rules people get
wrong:

- **A barrel is named after its bucket kind, never its directory.**
  `ui/widgets/showcase_notes_widgets/` contains `widgets.dart` — *not*
  `showcase_notes_widgets.dart`.
- **`lib/ui/views` has no barrel.** Views are imported by full path. Do not emit
  `views.dart`; the manifest carries that as a negative assertion so a later run
  can't "helpfully" add one.

Deliberate absences are part of the contract. `payments` is absent from showcase,
which is exactly why it is the synthetic feature the golden probe expands.

## Per-surface split (Q3)

A surface is not one file. Per showcase convention every surface splits into a view
plus its **desktop / mobile / tablet** variants, with the base view acting as the
responsive factor. The manifest's `surface-view` and `surface-view-factor` types carry
this; emit all variants a surface declares, never a single collapsed file.

## Seeds and fixtures (Q4)

Seed data lives at **app-root `data/seed/`, not under `lib/`** — and it is the one
bucket where the `<app>_` prefix rule does **not** apply: files are feature-named
(`notes.json`, `notes_folders.json`, `kit_auth_users.json`). The designer's seed mirror
must be *mirror-exact* with these, which is only achievable if both sides use the same
un-prefixed feature naming.

Seeds are a **gated design-time overlay.** They load in design/dev boot and must never
reach a shipped build — un-gated seed data shipping as real user content is precisely
the failure Q4 exists to prevent. `data/generated/` (`supabase_seed.sql`,
`supabase_migration.sql`, `appwrite.tables.json`) is derived from `data/seed/` plus the
schemas and is never hand-edited. `lib/app/app_data.dart` is the data-layer boot that
registers entities + fixtures with `appbox_kit_data`; note that service registration
does *not* live there — it lives in the `@StackedApp` dependencies in `lib/app/app.dart`.

## Inputs: frozen run artifacts (Q10)

Everything derives from versioned `intake/registry.json` through an **immutable run
artifact**. You consume the designer's materialized anatomy plus the registry
version; you never invent scope, and you never re-read live intake mid-run.

The reason is concurrency, not purity: designer and scaffolder run against the same
intake, and a registry that changes underneath a half-finished scaffold produces a
tree that matches no version of anything. The frozen artifact makes a run
reproducible — same artifact id, same bytes out.

If a flow needs something the registry does not declare, that is a **design defect**
to report, not a branch for you to invent.

## The feature recipe (Q8)

`kit/showcase_app/feature-recipe.manifest.json` (schema alongside it) is the SSOT for
paths and names — showcase-adjacent, so both skills read it from one place. It is
**machine-readable on purpose**: the golden-expansion probe
diffs a produced tree against an expansion of the manifest, so agreement is checked
mechanically rather than by prose reading.

The designer loads the same file. That is the whole point — a single manifest is why
the designer's output and your output land on the same tree instead of two plausible
trees that have to be reconciled by hand.

A new feature expands deterministically: shell view (+ derived factor variants),
viewmodel, per-surface views/viewmodels, widget bucket, service facade/adapters/
repositories, models, schemas, enums, and every bucket barrel.

**Form factor is derived, never literal.** `--targets` → `pipeline/state/targets.derivation.json`
→ factors. A factor outside the derived set produces **no file**. Emitting an empty
`.mobile`/`.tablet` to satisfy a counter is the stale-green defect: a file that
exists, passes the count, and renders nothing.

**Gate:** showcase itself must pass expansion (modulo the recorded `exemptions[]`).
If it doesn't, the manifest is wrong — not the showcase.

## Kind resolution (Q7)

`kind-resolution.registry.json` maps the designer's closed kind vocabulary to real
kit-native widgets (`AppBoxKitNativeAppBar`, `AppBoxKitGlassCard`, `AppBoxKitListTile`,
…). Resolve through that table and nowhere else.

**An unresolvable kind is a FAIL that names the kind and the design node.** There is
no silent `Container()` fallback. A silent fallback yields a scaffold that compiles,
looks plausible, and is wrong — precisely the failure the gate stack exists to catch.
When the kit genuinely lacks a widget, use the registry's escape hatch: it emits, but
it warns with a reason, an owner and an expiry, and an expired escape fails the build.

Not every kind resolves to a single class. Three shapes resolve with `widget: null` —
`composedFrom` (a composition the scaffolder emits explicitly, never collapsing it to
one class), `presentation` (a route/overlay mode, not a subtree — this is what `modal`
is), and `variants`. **Every such shape must be named in `resolution.order`**; a shape
that is not listed falls through to FAIL and turns a correctly-authored kind into a
build break.

**Validate after any registry edit:**

```
python3 skills/appbox-scaffolder/scripts/validate-registry.py
```

It checks the registry against its two ground truths — the partials directory
(`appbox-designer/starter-partials/widgets/_<kind>.tsx` *is* the vocabulary; never
hand-maintain a second copy of that list) and the real class names under
`kit/ui_library/lib` — and it rejects duplicate kind keys. That last check is not
theoretical: two entries were authored twice, and because `json.load()` silently keeps
the last duplicate, the careful entry vanished with no error and no merge conflict.
Prose review missed it both times.

## Design vocabulary: copy from kit, never author (Q6, revised)

Tier 1 — colors, spacing, glyphs, fonts, app constants, strings — is
**kit-owned**: `kit/core/lib/common/` is the single SSOT. The stacked CLI
generates `lib/ui/common/` (including its own `app_strings.dart`) in every new
app; the scaffolder **deletes every stacked-generated file in that folder and
replaces them with a verbatim copy of the kit common set**, plus one app-specific
`appbox_kit_app_strings.dart` (`abxStr`-prefixed `const String` named copy,
e.g. `abxStrNotesEmptyTitle` — the kit carries a generic template of the same
file). App code imports its **own
copy**: `package:<app_package>/ui/common/…` — never
`package:appbox_kit_core/common/…`. The registry keeps kit-canonical paths;
rewrite the package prefix to the app's copy at emit time (one rule, no per-app
registry churn). Showcase demonstrates this end-to-end.

**Hand-authoring or hand-editing any copied vocabulary file is a FAIL** — the
only file with app-authored content is `appbox_kit_app_strings.dart`. Emitting
new `*_colors.dart`, `*_spacing.dart` or `*_ui_helpers.dart` variants is a
**FAIL**, not a style preference — duplicated vocabulary is how a design system
silently forks. The copy is refreshed from kit, never edited in place.

### Assets (ratified v2)

The designer authors the app's `assets/` artifact (intake uploads merged over
the passive SSOT `kit/assets_default/`); the scaffolder's job is a **pure
copy-paste** of that folder into the scaffolded app, then wiring driven ONLY
by `assets.manifest.json`:

- **Fonts:** Google Fonts by name — emit the `google_fonts` package and call
  families from the manifest's font roles (`primary`, `monospace`, …); the
  roles name families from the design's `[data-font]` menu, so the app
  requests exactly what the design's css2 link showed (designer law:
  DESIGN-ARCHITECTURE.md "Fonts (Google Fonts by name)"). No
  font binaries, no pubspec `fonts:` block — UNLESS the manifest declares
  `"source": "file"` (user uploaded a custom brand font at intake), in which
  case emit a real `fonts:` block for `assets/fonts/` instead.
- **Brand icons:** wire `flutter_launcher_icons` (dev-dependency + per-app
  config yaml redirected to `assets/brand-icons/`, master from the manifest's
  `brandIcon`) to derive ALL iOS/Android/web launcher icons. **The config
  yaml update is a MANDATORY step of EVERY scaffold — never skipped, never
  left at a template/default path**: on every scaffold (and every re-scaffold
  after a brand-icon change) the scaffolder rewrites the config to point at
  the app's `assets/brand-icons/` master and re-runs icon generation. A
  scaffolded app whose launcher-icons config still points anywhere else is a
  FAIL. Brand only — UI icons still resolve to kit code glyphs
  (`appbox_kit_glyphs.dart`); a hand-authored per-platform icon set is a FAIL.
  The brand icon is ALSO a runtime asset — apps render it in-app (splash
  screen, startup brand logo) — so `assets/brand-icons/` IS registered under
  `flutter: assets:` and the master gets `abxImgBrandIcon` in the app's
  `appbox_kit_assets.dart`. The derived platform icon files (android/ios/web)
  are generated by the tool and **committed** — derived, never hand-edited.
- **Images:** register `assets/images/` (and any sibling type dirs present in
  the copied folder) in `pubspec.yaml`; emit `appbox_kit_assets.dart` into
  `lib/ui/common/` (app-authored copy of the kit generic template, the
  `appbox_kit_app_strings.dart` pattern): every bundled path is an `abxImg*`
  const and emitted code references the NAME, never a loose path string.

- **Web entrypoint (`web/index.html`):** the stacked-cli/Flutter default is a
  starting point, never the shipped file. On EVERY scaffold the scaffolder
  normalizes `web/index.html` to the reference shape
  (`kit/showcase_app/web/index.html` is canon); leaving the cli default is a
  FAIL. The normalized file carries, in order:
  1. `<base href="$FLUTTER_BASE_HREF">` — untouched, build-injected.
  2. `<meta name="description">` = the app's one-line description; iOS meta
     trio + `apple-touch-icon` → `icons/Icon-192.png` (derived by
     `flutter_launcher_icons` from the brand master); `favicon.png`.
  3. **Font-law wiring**: exactly two preconnects —
     `<link rel="preconnect" href="https://fonts.googleapis.com">` and
     `<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>` —
     mirroring the designer's `base.tsx` pair. No `css2` stylesheet link and
     no self-hosted font files: on web the `google_fonts` package fetches
     binaries from `fonts.gstatic.com` at runtime, the preconnects just warm
     the connection (custom `"source": "file"` fonts ship in the Flutter
     bundle and need no HTML wiring).
  4. `<title>` = the app display name; `manifest.json` link.
  5. `flutter_native_splash:create` web output, kept theme-reactive: the
     `#splash-screen-style` block sets `body` background to the kit surface
     pair — `#F5F0E8` light, `#1C1814` dark via `prefers-color-scheme`
     (uppercase hex, matching the native configs) — and the `#splash`
     `<picture>` carries light/dark srcsets (1x–4x) of the brand splash
     derivative. Splash teardown stays the generated
     `removeSplashFromWeb()` script.
  6. The stock `flutter.js` `loadEntrypoint` bootstrap — no custom loader.

Showcase demonstrates end-to-end: `abxImgShowcaseLogo` →
`assets/images/showcase_logo.png`, the full launcher-icon chain:
`assets/brand-icons/appbox-icon.{png,svg}` (copied from
`kit/assets_default/`) + `flutter_launcher_icons` dev-dep + config yaml +
committed derived platform icons + `abxImgBrandIcon` + `assets/brand-icons/`
registered in `pubspec.yaml`, and the normalized web entrypoint
(`kit/showcase_app/web/index.html`).

**Layout tokens are names, never numbers.** Every layout value arriving in
`design.json` is a kit constant name and is emitted verbatim as that
identifier: `abxPad*` for padding, `abxGap*` for gaps (numeric ladder, no tier
aliases), `abxHug` / `abxFill` / `abxFixed` for sizing modes,
`appBoxKitVerticalSpace*` / `appBoxKitHorizontalSpace*` for spacers,
`abxButtonHeight*` / `abxDefault*` for role sizes. Emitting a raw numeric
literal where a kit constant exists is a **FAIL**. A value with no matching
constant is a blocker to surface, not a number to inline — new constants are
added to kit deliberately and always carry the `abx` prefix.
`kit/core/lib/utils/formatters/` remains kit-owned with no per-app copy.

## Frontmatter is normative (Q5)

The semantic library doc comment in showcase files is a contract, not decoration.
Canon: `skills/appbox-builder/BUILDER_playbook.mdx` → *File structure*. Order is
locked, and every file terminates the block with a bare `library;`.

Full kind: layer-intro → role → requirements → relationships → History.
Light kind (models, schemas, enums, consts, barrels): layer-intro → role → History.

You own layer-intro, role and the `History:` line. You leave requirements and
relationships as marked placeholders — those are the builder's. The `History` line is
mechanically derivable (`git log --follow -- <path>`), which is why it is mechanically
gated.

## The generation gap (Q9)

Two ownership classes, and the boundary is declared in the manifest per artifact type:

- **scaffolder-owned** — regenerated every run, byte-identical on unchanged inputs.
  A hand edit here is drift and `--check` fails it.
- **user-owned** — stubbed once, then owned by the builder. Regeneration **never**
  clobbers it.

This needs a persisted baseline, so the first scaffold writes
`pipeline/state/scaffold-baseline.json` (the `.copier-answers` analog): registry
version, run artifact id, target set, and a content hash per emitted file. The
divergence gate checks user-owned files against that baseline, and a 3-way merge uses
it as the common ancestor. Without it, "don't clobber" degrades into "never update",
and the scaffold rots.

Shared join points — barrels, `app.router.dart`, `app.locator.dart`, the shell
structure manifest — are regenerated deterministically with additive-only diffs.

## Inspect identity is stamped, not inferred (Q12)

Every emitted view and widget carries the triple `screenId` / `surfaceId` /
`anatomyNodeId`, stamped **at emit time** from the frozen artifact — the same trick
as Flutter's `--track-widget-creation`.

Studio's inspect mode reads the triple and nothing else: zero DOM heuristics, no
structural guessing. Inspect therefore survives regeneration by construction rather
than by luck.

`screenId` is a verbatim `intake/registry.json` entry id — never a value derived from
a class or file name. `ShowcaseNotesCreateAccountView` carries its shell as a prefix and
belongs to `showcase.createaccount`; convention-matching loses it. That miss is the whole
reason the triple is stamped rather than inferred. `surfaceId` is the surface's own
tree-derived id (`surface.<feature>.<surface>`, or `surface.<feature>.shell` for a shell
view); `anatomyNodeId` is drawn from the CLOSED set at
`kind-resolution.registry.json#/anatomyNodes` (registry v1.3.0).

Note: `kit/showcase_app` was back-stamped at the Q11/Q12 ratification — all 20 view files
carry the triple. Showcase is therefore normative for identity, the golden probe's
showcase corroboration exempts nothing, and a new emit that omits the triple fails
verdict 4 against a showcase that satisfies it.

## Verdicts (Q11)

**Five** verdicts decide whether a run is good — one probe, five verdicts, reusing the
existing `ProbeReport` / `ProbeTarget` plumbing (no new harness). The list is locked;
do not add to it or reorder it:

1. **Golden expansion** — the tree matches the Q8 manifest expansion exactly. Extra or
   missing file = fail.
2. **`dart analyze` clean.**
3. **Second run byte-identical** — **transliteration output ONLY.** Transformation
   output is LLM-touched and is pinned by its frozen run artifact (Q10) and re-verified
   by the non-clobber rule, *not* by byte-identity. Asserting byte-identity on
   transformation output is a misreading of this verdict (Q2↔Q11 audit resolution).
4. **Identity coverage** — every emitted surface carries `inspectAttrs`.
5. **Frontmatter/comment conventions present** — Q5's normative rules, mechanically
   enforced rather than reviewed by eye.

Kit-only vocabulary (no local duplicates; every widget resolves through the kind
registry) is an always-on invariant enforced at emit time by the closed vocabulary —
it is deliberately *not* one of the five verdicts.

The spike runs after **both** skills are refactored, and produces five shells —
`startup`, `unknown`, `auth`, `application` (ceremony shells) + `design` — **plus the
splashscreen**. Surfaces absent from showcase (`auth`, `design`, `splashscreen`) expand
from the manifest exactly like the synthetic `payments` feature; showcase instances
corroborate `application` / `startup` / `unknown`. `splashscreen` is **not a shell**: it
is the mobile-device splash surface, brand logo only. After the spike passes, the rest
of the appbox studio design refactor proceeds (Q13).

## What reaches you from composers (Q14) and what you report (Q15)

Three composers exist upstream — intake interview, design-update, and the feature-add
entry point in studio UI. **None of them ever writes a file, a delta, or a line of your
output.** They emit **registry patches**, validated strictly against the registry schema
(retry on validation failure); deterministic code applies valid patches. What reaches
you is therefore always the same thing: a new registry version and its frozen run
artifact. There is no separate sync path and none is needed — a design-composer creating
a screen emits an intake-level registry patch, and the derived pipeline (diff → run
artifact → designer → your delta run) flows from there.

Consequences for you:

- **Never accept LLM-authored files.** If something proposes emitted content directly,
  that is a bug upstream, not an input.
- For cross-boundary changes the LLM may *propose* a 3-way merge, but a deterministic
  validator applies it (Q9↔Q14). Unvalidated LLM output is never applied.
- The approval gate is not yours to fire and fires **only** when a derived diff touches
  a locked decision. Routine additive changes are gated by probes alone — do not invent
  extra confirmation steps; approval fatigue is the failure being avoided.

Report progress as **structured run events** the studio renders itself (Q15). The studio
viewer draws pipeline progress natively; `genui` / A2UI is explicitly out of scope, since
runtime LLM-composed UI is what Q10/Q14 forbid.

## Studio cutover is parallel-run (Q13)

When the new showcase-anatomy design shell arrives it is generated **alongside** the
current studio design shell behind a flag — never as a replacement. Probes render the
same screens through both and diff. Views flip **one at a time**, each only when its
probe is green; flipping back is a toggle, not a revert. The old shell is deleted only
once every view is flipped and green. Do not emit anything that assumes the old shell is
already gone.

## Route table contract

Besides the file tree, the scaffolder compiles **ONE go_router-shaped route
table** from the project's `intake/registry.json` + `intake/flows.json`
(exact shapes per `appboxd/lib/intake.dart`):

- registry entries: `{id, label, shell, comp, route, surface, states?,
  requiresAuth?, tab?}`
- flows edges: `{from, to, trigger, action}` with typed actions
  `push | replace | back | modal | system`

The compile rules:

- **Typed nav ops only** — `push`, `replace`, `back`; `modal` is a
  presentation flag on the destination, never a fourth verb. `system` edges
  are non-gesture (auth-success, deep-link): they compile to route guards,
  never to buttons.
- **Guards are named predicates** — `requiresAuth: true` entries plus
  `system` edges compile to ONE `redirect`, not per-route copies.
- **Tabs are data** — `tab: true` entries form the bottom-tab shell, in
  registry order.
- **Flow row order is edge-chain order** — a flow's rows appear exactly as
  its edges chain; the table adds no reordering.

One table, derived from the two intake artifacts — a flow needing something
the registry does not declare is a design defect, not a scaffolder branch.

## Procedure

1. **Confirm the design is frozen.** `structure.json` must exist and be in sync
   with the authored layer. The scaffold reads it as the frozen input; it never
   re-derives structure. Check:
   ```sh
   KIT_DESIGN_DIR=<design> appbox emit structure --check
   ```

2. **Scaffold, naming the targets explicitly.**
   ```sh
   appbox emit scaffold \
     --design-dir <design> --app-root <app> --targets macos
   ```
   `--targets` is **required** (or `APPBOX_TARGETS` env). The scaffold never
   reads ambient pipeline state for targets — a run that picked up whatever
   targets happen to be in state is the stale-green defect (§16). Widths and
   factor names come from the derivation table + config, never literals (R3).

3. **Verify the tree matches** (drift check, e.g. after a registry edit):
   ```sh
   appbox emit scaffold \
     --design-dir <design> --app-root <app> --targets macos --check
   ```
   `--check` regenerates the expected set in memory and diffs against disk:
   a missing factor file, a stale manifest, or a hand-edited dir is named and
   fails. This is the same file set `gates/coverage` (C1) walks.

4. **Hand off to the builder.** The scaffold is structure; `appbox-builder`
   implements the widget trees and wires services from the `deps` recorded in
   each stub's header. The coverage gate then asserts the scaffolded layer.

## The guardrail, as a test

The engine's self-test is the proof the guardrail holds:
```sh
appbox emit scaffold --self-test
```
It asserts, negatively (R5): a missing `structure.json` fails naming it; a
frozen surface with no viewmodel fails; a wrong file count fails `--check` and
names the missing file; an unknown target fails; two surfaces colliding on one
directory fail. And positively (§16): `macos` derives exactly `[desktop]` and
emits no `.mobile`/`.tablet`; `ios,android` derives `[mobile, tablet]` and emits
no `.desktop`.

## Common mistakes

- **Emitting an empty factor file to satisfy a count.** If the targets do not
  imply a factor, no file for it exists. That is §16's whole point — the
  self-test guards it.
- **Hardcoding widths or factors.** They come from the derivation table +
  config (P06/R3). Adding a target is a data edit to that table, not a code
  change here.
- **Treating the stub bodies as finished.** They are skeletons. The builder
  replaces them; leaving a stub's placeholder `Text` in a shipped app is a
  missed handoff, not a scaffold defect.
- **Editing scaffolded Dart directly.** That creates a second writer and the
  drift check dies. Edit the registry / authored layer, re-freeze, re-scaffold.
- **Reading targets from ambient state.** Pass `--targets` explicitly. A
  reproducibility run that inherits state targets is the stale-green pattern.
