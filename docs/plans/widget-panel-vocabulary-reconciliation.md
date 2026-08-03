# Widget/panel vocabulary reconciliation — one language across designer, scaffolder, builder

Status: decisions locked (grilling session 2026-08-03), execution pending go-ahead.
Trigger: misaligned chips across studio shells; root cause generalized to "no widget
layer, no placement law, vocabulary drift between designer (components) and
scaffolder (widgets)".

## Locked decisions

### D1 — One term: widget
- **Widget** is canonical everywhere; **component** is retired from all docs and paths.
- `skills/appbox-designer/starter-partials/components/` → `starter-partials/widgets/`.
- `docs/VOCABULARY.md` gains entries: **Widget** (reusable UI piece; HTML macro/partial
  in the design medium, Dart class in the build medium — one concept, two mediums),
  **Panel** (the five roles), and the **placement law** (D5).
- Three-tier placement identical on both mediums:

  | scope | design medium | build medium |
  |---|---|---|
  | cross-shell (2+ shells) | `ui/common/widgets/` | `lib/ui/widgets/` (new) |
  | intra-shell (2+ surfaces) | `ui/views/<shell>/shared/widgets/` | `<shell>/shared/widgets/` |
  | per-surface (1 surface) | `<surface>/widgets/` | `<view>/widgets/` |

  Bare `<shell>/widgets/` remains illegal on both sides. Empty tiers are never
  created speculatively.

### D2 — The chip contract
- One base `.chip`: `display:inline-flex; align-items:center; border-radius:999px`,
  sized by shared tokens `--chip-font / --chip-pad-y / --chip-pad-x / --chip-gap`.
- Borders normalized to **inset box-shadow only** (no 2px height drift).
- Variants are modifiers: size (`chip--sm`), tone (`chip--accent`, `chip--muted`),
  state (`is-set`). No new chip classes, ever (enforced by W5).
- Ships in the kit: `starter-partials/widgets/_chip.html` + chip rules in kit CSS
  (kit currently has **zero** chip primitive — that absence caused the drift).
- Studio: `statusPill()`/`typeBadge()` and friends collapse into one `chip()` macro
  family in `ui/common/widgets/`.
- Migrate all 11 classes: `.chip, .pri-chip, .prov-chip, .type-badge, .thread-badge,
  .dv-chip, .qr-chip, .ctx-chip, .cs-ctx-chip, .cs-el-chip, .status-pill` →
  `.chip` + modifiers. Semantic names survive only as zero-CSS hooks where an
  island/probe targets them.
- Bug fixes folded in: duplicate `.qr-chip` definition (intake.css:37 vs :54);
  `.surface-row { align-items: baseline }` → `center`; per-context shrink overrides
  (`.msg-meta .status-pill`, `.dv-thumb-label .status-pill`) become `chip--sm`.
- Canon rule: rows holding chips align by `center`, never `baseline`.

### D3 — Studio grows the real widget tree (this round)
- `ui/common/widgets/`: `chrome.html`, `primitives.html`, `_chip.html`, `_panel.html`
  (D4). Only genuinely cross-shell widgets + `base.html` + canon docs remain in common/.
- `ui/views/main_shell/shared/widgets/`: `main_panel.html`, `composer_panel.html`,
  `mini_panel.html`, `design_viewer.html`, `composer.html`, `panel.html` (merged into
  the D4 base) — every includer is a main_shell surface.
- **Delete** `ui/common/designer_panel.html` (zero includers; confirmed by user).
- CSS stays consolidated: new `assets/css/widgets.css` holds widget rules (chip
  tokens/variants migrate out of app/intake/composer.css). No per-widget CSS files.
- Chrome clarification (confirmed): `chrome.html` etc. ARE widgets. The only
  non-widgets in the tree are `base.html` (root layout) and each `<shell>_view.html`.

### D4 — Panels are instantiated, never re-implemented
- One base widget `ui/common/widgets/_panel.html` implements the panel contract once:
  3×3 section grid (top / side-start / body / side-end / bottom), card styling, size
  classes, `view-transition-name` wiring.
- The five roles — header, main, activity, composer, footer — are thin instantiations.
  `main_panel.html` / `composer_panel.html` / the old generic `panel.html` collapse
  into them.
- Each `<shell>_view.html` declares which role panels it mounts, each at most once.
  Undeclared panels don't exist in that shell (the panels-off requirement, structural).
- `design_viewer.html` is **demoted from panel to content**: loses its panel chrome,
  renders inside the main panel's body section. `mini_panel.html` likewise becomes
  viewer content.
- State ownership (canonized): a panel owns its internal UI state; a shell owns its
  own state plus panel-level state (which panels are mounted, their sizes). All
  server-side per ADR-0004. Session key namespaces: `<shell>.<panel>.*` panel state,
  `<shell>.*` shell state, `app.*` cross-shell.
- The scaffolder mirrors the five-role panel widget set so generated apps inherit the
  same shape.

### D5 — Enforcement: the opinion lives in appboxd
**Placement law (one sentence): a widget lives at the narrowest scope that covers all
its consumers; the include/import graph is the only authority, enforced in both
directions.** (Generalizes S10's sole-consumer overlay rule; the alternative
"downward-only" was rejected — it leaves placement co-managed by graph + discretion.)

W-gate wired into `design lint` (runs against ANY design, not just the studio).
All hard-fail:
- **W1** placement by include-count, both directions, fix named in the failure.
- **W2** dead widget sweep (zero includers = fail; extends orphan sweep).
- **W3** `.panel-*` structural markup only in `_panel.html`.
- **W4** shell composition declared in `<shell>_view.html`; five roles, each ≤ once.
- **W5** pill radius (999px/9999px) outside widgets CSS = fail (`50%` circles exempt).
- **W6** session-key namespacing per D4, checked in the pass that already checks
  viewmodel→facade imports.

Scaffolder updates (same law, build side):
- **S6 gains scope-truth**: sole-consumer widget in `shared/widgets/` fails → demote
  to `<view>/widgets/`.
- **New cross-shell home `lib/ui/widgets/`**: legal only for widgets imported by 2+
  shells; `scaffold.dart` emits it when the design's widget map warrants;
  `gate_scaffold.dart` + `scaffold_test.dart` updated.
- `skills/appbox-designer/references/app-architecture.md:141` ("Shared partials go in
  ui/common/") rewritten to the three-tier law.

### D6 — One vocabulary, no box-themed aliases
- Shells/panels/widgets are the user-facing terms too. No box-flavored words in code,
  file names, gates, or docs — ever.
- Sanctioned branding form: a **brand glossary table** in VOCABULARY.md
  (term → display name), presentation-layer only; nothing mechanical reads it.

## Execution order (each phase its own commit, probes gate every phase)

0. **Pre-step**: SSOT check before touching the skill —
   `~/.agents/skills/consultant/scripts/consult.sh gate skill appbox-designer`.
1. **Docs + vocabulary**: VOCABULARY.md entries (Widget, Panel, placement law, brand
   glossary), app-architecture.md rewrite, _integration_panels.md additions (state
   ownership, chip-row rule), new ADR "one vocabulary + placement law",
   starter-partials/components → widgets rename (+ all references).
2. **Chip widget**: kit `_chip.html` + kit CSS; studio `widgets.css` + `chip()` macro;
   migrate 11 classes; qr-chip/baseline fixes. Verify: probe suite + chip-alignment
   probe section (new), mutation-tested.
3. **Studio widget tree**: folder moves + include-path updates; delete
   designer_panel.html. Verify: full probe suite, design lint, orphan sweep.
4. **Panel base + roles**: `_panel.html`, five instantiations, shells declare panels.
   Verify: panel-contract probe (sections J/K keep passing).
5. **design_viewer demotion**: largest slice, own commit; islands (canvas/drag/
   inspect/flowwalk/explode) selector audit; viewer probes updated deliberately.
6. **W-gate**: W1–W6 in appboxd + `design lint` wiring; each rule mutation-tested
   (introduce violation → exact rule fails, others stay green).
7. **Scaffolder**: S6 scope-truth, `lib/ui/widgets/`, scaffold.dart emission,
   scaffold_test + gate tests.

## Risks
- Viewer demotion (phase 5) touches island selectors and viewer probes — mutation-test
  probe updates; keep the phase isolated.
- Studio hot-reload: run measurement probes against the live 4319 server read-only;
  mutation probes on a disposable project/port (seeded copy), as established.
- The skill rename (phase 1) is cross-repo-visible: gate skill check first (step 0).
- l10n: user-facing strings that say anything component-ish get swept in phase 1.

## Verification (definition of done)
- `design lint` clean including new W-rules; every W-rule proven non-vacuous by
  mutation.
- `dart test` green in appboxd (scaffold, gates, selftest).
- Full probe suite green: panel-contract (incl. J/K), panel-resize, no-reload,
  composer-draft, shell-chrome, inspect + new chip section.
- Zero `component` hits in skills/appbox-designer docs and appbox docs (excluding
  third-party/vendor).
- Chips visually aligned: one screenshot pass across intake/design/build at 1900/800px.
