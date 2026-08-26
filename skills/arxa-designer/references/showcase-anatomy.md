# Showcase anatomy — the structure contract

`kit/showcase_app/lib` is **the structure contract, not an example** (Q1). Every
surface this skill designs must be structurally isomorphic to it, so the
scaffolder can act as a *transliterator* rather than an interpreter (Q2,
default = transliteration).

Read this before authoring any surface. When this file and prose elsewhere in
the skill disagree, the exemplar tree wins — verify with
`find kit/showcase_app/lib -type f`.

---

## 1. The tree

Design medium (this skill, JS/web) mirrors build medium (Flutter) one-to-one.
Only the extension and the language change.

| build medium (`showcase_app/lib/…`) | design medium (artifact root) | holds |
|---|---|---|
| `app/app.dart`, `app.router.dart`, `app.locator.dart` | `app/app.routes.js` | route table, DI registration |
| `ui/views/<app>_<shell>_shell/` | same | one shell |
| `ui/views/<app>_<shell>_shell/<app>_<surface>/` | same | one surface inside that shell |
| `ui/widgets/<app>_<feature>_widgets/` | same | feature-scoped widgets + `widgets.dart` barrel |
| `ui/widgets/common/<group>/` | same | cross-shell widgets, grouped |
| `ui/snackbars/` | `ui/snackbars/` | toast/snackbar registration |
| `services/<app>_<feature>_services/{facades,adapters,repositories}/` | same | the data spine |
| `data/models/<app>_<feature>_models/` | same | models + `models.dart` barrel |
| `data/schemas/<app>_<feature>_schemas/` | same | schemas + `schemas.dart` barrel |
| `enums/<app>_<feature>_enums/` | same | enums + `enums.dart` barrel |
| `extensions/` | `extensions/` | shared extensions |

Design-medium-only, with **no** build-medium counterpart (do not look for one,
do not ask the scaffolder to emit one): `ui/common/base.tsx` (HTML head +
boilerplate), `runtime/`, `models/screens_model/registry.json`, `l10n/`,
`assets/`.

### Naming

Every file and every symbol carries the `<app>_<feature>_` prefix. In showcase
`<app>` is `showcase`; in a generated app it is the project's app token.

```
ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.dart
ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.desktop.dart
ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.mobile.dart
ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.tablet.dart
ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart
```

A shell's own surface sits one level up, beside its children:
`ui/views/<shell>/<shell>_view.dart` (+ `.desktop/.mobile/.tablet`) and
`<shell>_viewmodel.dart`.

### Per-surface split (Q3)

Every view is **five files**: the dispatcher `_view.dart`, three variants
`.desktop.dart` / `.mobile.dart` / `.tablet.dart`, and `_viewmodel.dart`.
Authoring only one variant is the single most expensive mistake available
here — the widths you *don't* author get invented downstream. Which widths map
to which variant comes from `references/viewport-ladder.md`, read from the
project's targets, never assumed.

### Barrels

Every leaf folder carries a barrel named for its kind — `widgets.dart`,
`models.dart`, `schemas.dart`, `enums.dart`, `facades.dart`, `adapters.dart`,
`repositories.dart` — and each parent level re-exports its children
(`data/data.dart`, `enums/enums.dart`, `services/services.dart`).

Barrels export by **full package URI**, never a relative path:

```dart
export 'package:arxa_kit_showcase_app/ui/widgets/showcase_home_widgets/showcase_glass_cta_button_widget.dart';
```

Barrels are scaffolder-owned join points (Q9): regenerated deterministically,
additive-only, byte-identical when inputs are unchanged. Never hand-edit one in
a delta run.

---

## 2. Widget placement law (two tiers)

Superseded the old three-tier law; `ui/common/widgets/`,
`ui/views/<shell>/shared/widgets/` and `<surface>/widgets/` **do not exist in
the exemplar** and are illegal.

| scope | path |
|---|---|
| cross-shell (2+ shells) | `ui/widgets/common/<group>/` |
| everything else (one feature, any number of its surfaces) | `ui/widgets/<app>_<feature>_widgets/` |

A widget used by exactly one surface still lives in its feature's widgets
folder — there is no per-surface tier to demote it to. Promotion to
`common/<group>/` is earned by a second *shell* consumer, proven by the include
graph in both directions, never by intent.

Placement is only half the law; the other half is **composition (W9)**: view
templates (`ui/views/**`) are Capitalized widget-library invocations, and
nothing else. A raw HTML element of any kind fails `design lint` — bearing
text, interactive, rendering media, or purely structural (rung mounts,
section scaffolding, slot outlets): a view that authors markup authors
presentation. This holds even when the element carries
`data-el`/`inspectAttrs` identity — identity markup lives inside widget
files, where the presentation belongs. Views compose; widgets render.

Both tiers are read off the exemplar, which has
`ui/widgets/common/showcase_gallery_chrome/` and
`ui/widgets/common/showcase_tabs_shared/` alongside seven
`showcase_<feature>_widgets/` folders. `common/` is **grouped, never flat**:
each `<group>/` carries its own `widgets.dart` and `common/widgets.dart`
re-exports the groups.

One naming exception exists and is deliberate: `ui/widgets/mouse_transforms/`
drops the `<app>_` prefix because its widgets
(`scale_on_hover_widget.dart`, `translate_on_hover_widget.dart`) are
app-agnostic behavior wrappers, not `showcase` features. Follow it only for
genuinely app-agnostic groups; everything feature-shaped takes the prefix.

Bare `<shell>/widgets/` remains illegal.

### Widget kinds (Q7 — closed vocabulary)

Every designed widget declares a `kind` drawn from exactly this set. The set is
**mechanically derived, not hand-listed**: it is the file list of
`starter-partials/widgets/*.tsx`, stripping the leading `_` and the `.tsx`
suffix. That directory is the vocabulary's SSOT; the names below are a
convenience echo of it, and if they ever disagree, the directory wins.

`appbar` · `bottom-sheet` · `card` · `chip` · `cta-link` · `dialog` ·
`empty-state` · `form-field` · `list-row` · `modal` · `nav-rail` ·
`panel-activity` · `tabbar` · `tabs` · `toast`

`modal` and `dialog` are **distinct kinds** and are not merged here; the
scaffolder's resolution registry decides what each becomes natively. A widget
whose kind is absent from this list is a **gate failure on both sides — never
improvise a mapping**. Adding a kind is a deliberate two-registry change:
this vocabulary *and* the scaffolder's kind→`arxa_kit` resolution registry,
in the same change.

**Where resolution lives (do not duplicate it here).** The kind→widget mapping
is owned solely by `skills/arxa-scaffolder/kind-resolution.registry.json`
(`sharedWith.consumedBy` names this skill). Designers name kinds; they never
name `ArxaKit*` widgets. An unmapped kind exits non-zero via that file's
`resolution.failureContract` — `Container()`, `SizedBox.shrink()`,
`Placeholder()` and any silent substitution are forbidden fallbacks.

> **Closed at registry v1.0.0 (Q7); resolver-reachable at v1.1.0.** All 15 kinds
> resolve: 12 land 1:1 on
> a kit widget, 2 are compositions (`empty-state`, `panel-activity`) and 1 is a
> presentation mode (`modal`). Zero unresolved, and no kind was ever dropped to
> get there.
>
> Do not repeat the mistake this note used to make. `modal` and `panel-activity`
> were correctly authored from the registry's first commit; reading their
> `widget: null` as "unmapped" was a *misreading of the encoding*, not a real
> gap. One defect was real — `tabs`' class sat in `tabbar.companions` — and
> v1.1.0's substantive fix was reachability, not coverage: `composedFrom` and
> `presentation` were missing from `resolution.order`, so entries that were
> correct on the view would still have hit `FAIL` in the resolver.
>
> **Never settle a coverage question in prose — this note was wrong twice.**
> Run `arxa gate kind_registry` (the promoted Python port,
> `arxa/lib/gate_kind_registry.dart`). It derives
> the vocabulary from the partials directory (the SSOT), checks every target
> against real class names under `kit/ui_library/lib`, verifies every
> `widget: null` shape is reachable from `resolution.order`, and catches
> duplicate kind keys — which `json.load()` silently swallows, and which review
> by reading has already missed twice.
>
> **A kind resolving to more than one widget is normal, not a gap.** Do not
> read `widget: null` as unbuildable. It means the kind is composed or
> presented, and the design carries the recipe — see "Compositions are recipes"
> in `DESIGN-ARCHITECTURE.md`. Designers still never name `ArxaKit*` widgets;
> a recipe is authored in design terms (parts, slots, arrangement), and the
> registry does the resolving.

---

## 3. Frontmatter and comment conventions (Q5 — normative)

These are mechanically enforced (Q11 verdict 5), not style advice. Every
emitted `.dart` file opens with a `///` block, then `library;`, then imports.

**The header has three tiers — do not apply the full block to every file.**
Measured over the exemplar's 207 `.dart` files:

| Tier | Files | Header carries |
|---|---|---|
| **Behavioral** — views, viewmodels, widgets, services, facades | ~151 | role sentence, `Requirements:`, `History:`, `library;`; `Relationships:` on views/viewmodels (optional on widgets) |
| **Barrel** — `widgets.dart`, `screens.dart`, `services.dart`, … (24 files) | 24 | one-line `Barrel for …` sentence, `History:`, `library;` — **no** `Requirements:`, **no** `Relationships:` |
| **Data-shaped** — enums, models, schemas, consts | ~32 | a single `///` line naming the type's job. **No** `library;`, **no** `History:`, **no** `Requirements:` |

Counts behind this: 162 files carry `library;`, 161 `History:`, 151
`Requirements:` (`user interface` 128 / `business logic` 20), 140
`Relationships:`. The 56 files without `Requirements:` are exactly the barrels,
the data-shaped files, and Stacked's generated `app.router.dart` /
`app.locator.dart` — generated files are never hand-headed at all.

A Q11 mechanical check must therefore branch on tier; a flat "every file needs
`Requirements:`" rule fails on 56 legitimately-compliant exemplar files.

**View / viewmodel** — five parts, in order:

```dart
/// <What this file is, and its MVVM role in one or two sentences. A view reads
/// streams out and calls actions in; a viewmodel never touches the view.>
///
/// This is the <user interface|business logic> for <surface>. <What it lays
/// out, or what state it holds.>
///
/// Requirements:
/// 1. [<Requirement name>] — <requirement id from the registry>
/// <One line restating the requirement in plain language.>
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │        home view         │
///   └──────────────────────────┘
///   ┌──────────────────────────┐
///   │      home viewmodel      │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
/// <Narration of the edges, or an explicit "No actions or streams yet".>
///
/// History: git log --follow -- <repo-relative path to this file>
library;
```

- `This is the user interface for …` opens a **view**; `This is the business
  logic for …` opens a **viewmodel**. The phrasing is fixed.
- A viewmodel's first line names its route: `(route `/showcase/home-shell/home`)`.
- The `Requirements:` trace id is the registry requirement id — this is what
  makes a surface auditable back to intake. Bare `[Name]` with no id is allowed
  only where no registry requirement exists yet.
- The `Relationships:` ASCII diagram uses `════ abxAction ════` for
  view→viewmodel calls and a stream edge back for reads. When there is nothing
  to draw, say so explicitly rather than omitting the section.
- `History:` is always the last line, always `git log --follow -- <path>`.

**Widget** — the same block minus the mandatory Relationships section. A
Relationships diagram is **optional** on a widget: present when it has actions
or streams worth narrating (38 of showcase's 48 widgets carry one), omitted for
a purely presentational widget like the example below. It is *not* a marker of
widget-ness — the opening sentence is.

```dart
/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for <what it shows>. <One or two sentences.>
///
/// Requirements:
/// 1. [<Requirement name>]
/// <One line.>
///
/// History: git log --follow -- <path>
library;
```

The opening sentence is boilerplate and is reproduced verbatim — it is the
mechanical marker that the file is a widget.

---

## 3b. Seeds and fixtures (Q4 — gated design-time overlay)

Seed data arrives with every other design instruction through the single
authoring surface (`intake/registry.json`, Q10). The designer never invents
seeds and never writes a second seed source.

**Seeds live outside `lib/`.** The exemplar puts them at the app root, so they
are data the app loads, never Dart the app compiles.

> **Two directories are named `data/` — keep them apart.**
> `<app>/data/` (app root, sibling of `lib/`) is **seed JSON and generated
> SQL**, shipped as assets. `<app>/lib/data/` is **Dart** —
> `lib/data/models/<app>_<feature>_models/…` and its schemas. A path with no
> `lib/` prefix in this section always means the app-root one.

```
<app>/data/                # app root — NOT lib/data/
  seed/                    # hand-authored, the SSOT for seed content
    notes.json
    notes_folders.json
    kit_auth_users.json
  generated/               # derived — never hand-edited
    supabase_seed.sql
    supabase_migration.sql
    appwrite.tables.json
```

Rules, mirror-exact with showcase:

- One file per entity, `data/seed/<entity>.json`, **plural snake_case, no app
  prefix** — `notes.json`, not `showcase_notes.json`. This is the one place the
  `<app>_` prefix rule does *not* apply, because the file names an entity, not
  a Dart symbol.
- `data/generated/` is derived from `data/seed/` plus the registry schemas. It
  is a build output: regenerate, never hand-edit. Treat a diff there the way
  you would treat a diff in `app.router.dart`.
- Seeds are a **design-time overlay and are gated** — they populate the
  prototype and the probe run, and must not be reachable in a production build.
  The gate lives in the app's startup path, not in the widget that renders the
  data.
- A new feature's seed file is part of its generation recipe. `payments` below
  emits `<app>/data/seed/payments.json` alongside its Dart — which is a
  different tree from that feature's `lib/data/models/…` model classes.

---

## 4. Kit awareness (Q6 — two tiers, natives excluded)

The designer designs **against the kit as always-available** and never invents
a local duplicate of anything the kit provides. Every scaffolded app carries
`lib/ui/common/` as a **verbatim copy of `kit/core/lib/common/`** (the stacked
CLI generates that folder; the scaffolder wipes its generated files and refills
it from kit, adding one app-authored `arxa_kit_app_strings.dart`). The copy
is refreshed from kit, never hand-edited — a hand-maintained divergent copy is
the drift this rule exists to prevent.

**Assets (ratified).** `assets/` sits beside `lib/`, type-first the way
Flutter manages it — the only app-owned class is images/media
(`assets/images/`, more type folders only when a real need lands), registered
as directories in `pubspec.yaml`. Fonts ship inside the kit package
(`arxa_kit_fonts.dart`); icons are kit code glyphs (`arxa_kit_glyphs.dart`)
— an app declares NO font or icon assets. Every bundled path is named as an
`abxImg*` const in `arxa_kit_assets.dart` (kit generic template +
app-authored copy, the `arxa_kit_app_strings.dart` pattern); designer and
scaffolder emit the NAME, never a loose path. Exception (studio-only,
user-ratified): arxa studio's design tree keeps ownership-scoped
`assets/studio/` + `assets/portalo/` (portalo feature-scoped) because the
studio hosts two owners — itself and the design it simulates.

**Tier 1 — design vocabulary mirror.** A **generated**, parity-gated JS mirror
of `kit/core/lib/common/`, same symbol names, generated from the Dart:

| Dart source | mirrors |
|---|---|
| `arxa_kit_colors.dart` | colors |
| `arxa_kit_ui_helpers.dart` | spacing / ui helpers |
| `arxa_kit_app_constants.dart` | app constants |
| `arxa_kit_glyphs.dart`, `arxa_kit_glyphs_lucide.dart` | glyphs |
| `arxa_kit_fonts.dart` | fonts |
| `arxa_kit_assets.dart` | bundled-asset names |

**Never hand-author these files.** They are generated from Dart and gated by
`kitCatalogMirrorCheck`; a hand-written copy is exactly the drift the
copy-from-kit rule forbids in `lib/ui/common`. If the mirror is missing a
symbol you need, the fix is to extend the generator, not to define the value
locally.

**Tier 2 — service kits** (auth, payments, maps, …) reach the design medium
through `references/kit-catalog.md` plus `runtime/kit-facades/*.js`. Declare
them with the `kits` field on the surface that needs them.

**Excluded:** `ArxaKitNative*` and `arxa_kit_ui_library` widgets are **not**
mirrored. The designer designs web (web-first design core; ejects production web);
natives are the scaffolder's transliteration targets. Do not reach for a native
primitive while designing, and do not pre-empt which native a `kind` resolves
to — that boundary is what keeps eject-to-web and emit-to-native both honest.

---

## 5. Generation recipe — worked example: a `payments` feature

**The expansion below is illustrative, not authoritative.** Q8 puts the
artifact-type → path template → naming template → frontmatter requirements →
owner (scaffolder-owned vs user-owned) mapping in exactly **one**
machine-readable file, `feature-recipe.manifest.json`, authored by
arxa-scaffolder and consumed by this skill. Read the templates from that
manifest; the listing here is a rendering of it kept for human orientation, and
the manifest wins on any disagreement. Never transcribe its templates inline
into a design — reference it.

> **Path debt (live).** That manifest's final home is
> `kit/showcase_app/feature-recipe.manifest.json`, showcase-adjacent so both
> skills can read it. It is currently staged in the scaffolder's skill
> directory and is moved by the orchestrator at commit time. Resolve it by
> filename at whichever of the two locations exists rather than hard-coding the
> staging path, and do not treat a missing file at the final path as license to
> improvise templates — it is a hard stop until the move lands.

A feature absent from showcase expands deterministically from the anatomy. This
is the expected expansion the golden-expansion probe (Q8) diffs against, for an
app token of `showcase` and a feature of `payments` with two surfaces
(`payments` list, `payment_method` detail) inside one new shell:

```
ui/views/showcase_payments_shell/showcase_payments_shell_view.dart
ui/views/showcase_payments_shell/showcase_payments_shell_view.desktop.dart
ui/views/showcase_payments_shell/showcase_payments_shell_view.mobile.dart
ui/views/showcase_payments_shell/showcase_payments_shell_view.tablet.dart
ui/views/showcase_payments_shell/showcase_payments_shell_viewmodel.dart
ui/views/showcase_payments_shell/showcase_payments/showcase_payments_view.dart
ui/views/showcase_payments_shell/showcase_payments/showcase_payments_view.desktop.dart
ui/views/showcase_payments_shell/showcase_payments/showcase_payments_view.mobile.dart
ui/views/showcase_payments_shell/showcase_payments/showcase_payments_view.tablet.dart
ui/views/showcase_payments_shell/showcase_payments/showcase_payments_viewmodel.dart
ui/views/showcase_payments_shell/showcase_payment_method/…            (same five)
ui/widgets/showcase_payments_widgets/showcase_payment_method_row_widget.dart
ui/widgets/showcase_payments_widgets/widgets.dart
services/showcase_payments_services/facades/showcase_payments_facade_service.dart
services/showcase_payments_services/facades/facades.dart
services/showcase_payments_services/adapters/adapters.dart
services/showcase_payments_services/repositories/showcase_payments_repository_service.dart
services/showcase_payments_services/repositories/repositories.dart
data/models/showcase_payments_models/showcase_payment_model.dart
data/models/showcase_payments_models/models.dart
data/schemas/showcase_payments_schemas/showcase_payment_schema.dart
data/schemas/showcase_payments_schemas/schemas.dart
enums/showcase_payments_enums/showcase_payments_facade_op_enum.dart
enums/showcase_payments_enums/enums.dart
```

All paths above are relative to `lib/`. The feature also emits its seed file
outside `lib/` (§3b), named for the entity with no app prefix:

```
<app>/data/seed/payments.json
```

Plus **regenerated join points** (scaffolder-owned, additive-only):
`app/app.router.dart`, `app/app.locator.dart`, and the parent barrels
`data/models/models.dart`, `data/schemas/schemas.dart`, `enums/enums.dart`,
`services/services.dart`.

Empty tiers are never created speculatively: `adapters/` appears above only
because the feature has an adapter. A feature with no adapter emits no
`adapters/` folder and no `adapters.dart`.

**Canonical manifest.** The machine-readable path-template manifest that this
expansion is checked against is showcase-adjacent, under `kit/showcase_app/`,
and is loaded by **both** this skill and the scaffolder. It classifies every
path **scaffolder-owned vs user-owned** (the generation-gap boundary, declared
up front). This document is its prose companion; the manifest is the SSOT for
the paths. See "Unresolved" in `references/delta-runs.md`.
