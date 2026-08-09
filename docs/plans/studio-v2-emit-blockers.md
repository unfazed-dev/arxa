# studio-v2 emit — pre-emit findings

Status: **B1 RESOLVED by the operator — recipe grammar sits at the artifact
root; the brief's "Structure (locked)" section and Q-v2-4 were amended
2026-08-08. Emit proceeding.** B2/B3 stand as non-blocking notes.

Flagged rather than resolved, per the brief: "On any conflict between this
brief and the decision log, the decision log wins — flag the conflict, do not
silently resolve it."

---

## B1 — where the recipe tree roots: `lib/` or the artifact root? (RESOLVED: artifact root)

**Resolution.** The brief now reads: "Recipe grammar sits at the **artifact
root** `designs/appbox-studio-v2/` (Q-v2-4 as amended 2026-08-08): the
manifest's `lib/` is a Dart-medium prefix; anatomy §1 translates it to the
artifact root for the design medium." That matches the evidence below.

**One structure-diff note carried forward.** The brief's gate "structure diff
against the feature-recipe manifest: zero unexplained deltas" compares against
`pathTemplate` values that literally begin with `lib/`
(`lib/ui/views/<app>_<feature>_shell/`, …). The only in-repo reader of those
templates, `appboxd/lib/probes/contract/probe_q11_shells.dart:39,76,485`, runs
them against the **Dart golden** `kit/showcase_app/lib` — it never walks a
`designs/*` artifact. So no shipped gate compares a design artifact to a
`lib/`-prefixed template, and the structure diff for v2 is performed with the
anatomy §1 mapping applied (`lib/X` → `X`). Recorded so the next reader does
not mistake a passing diff for a literal one.

**The original conflict, for the record:**

**Q-v2-4 verbatim:**

> Studio v2 uses the Q8 manifest's folder/naming grammar verbatim under
> `designs/appbox-studio-v2/lib/`

The brief echoes it: "`lib/` + `assets/` as siblings under the artifact root."

**Every other authority roots the design-medium tree at the artifact root,
with no `lib/` segment:**

| authority | evidence |
|---|---|
| recipe SSOT | `references/showcase-anatomy.md` §1 — the table's columns are literally `build medium (showcase_app/lib/…)` → `design medium (artifact root)`; rows read `app/app.routes.js`, `ui/views/<app>_<shell>_shell/`, `services/…` |
| serve | `appboxd/lib/design_server.dart:129-146` — `resolveArtifact` accepts a candidate only if `<candidate>/app.routes.js` exists; the walk climbs `designs/` ancestors and never descends into `lib/` |
| widget lint | `appboxd/lib/gate_design_widgets.dart:422,503,770` — scans `<artifactDir>/ui` and `<artifactDir>/ui/views` |
| structure emit | `emit_structure.dart:384`, `crud.dart:20`, `gate_freeze.dart:319`, `gate_intake.dart:301`, `intake.dart:1327` — all literal `models/screens_model/registry.json` |
| tools | `design_tools.dart:1592` `<out>/ui/common/base.tsx`; `:1833` `<artifactDir>/l10n`; `:1844` `<artifactDir>/models`; `:2001` `<artifactDir>/app.routes.js` |
| css | `emit_htmx.dart:360,403` — `<designRoot>/assets/css/<name>` |
| v1 precedent | `designs/appbox-studio/ui/…` — no `lib/` |

A grep for a `lib/` join in `appboxd/lib/*.dart` returns only Flutter-app
tooling (`arch_guard`, `blueprint`, `trace`, `gen_freshness`, `api_map_scan`,
`capability_scan`) operating on a generated app's `targetDir` — **zero**
design-artifact paths.

**Consequence if emitted under `lib/`:** `resolveArtifact` cannot find the
artifact, so `appbox design serve` never starts, and none of the brief's own
"Gates before surfacing" can run — lint, the lens width sweep, the console
check. The tree would also miss `models/screens_model/registry.json`, read
from the root by five call sites.

**Most likely reading (needs one confirmation, not a skill fix).** Q-v2-4's
own last bullet says "The Q8 manifest itself stays Dart-only and untouched."
So `lib/` is plausibly the *manifest's* prefix being quoted, not a web
placement ruling — and showcase-anatomy §1 is exactly the design-medium
translation of that grammar onto the artifact root. That also satisfies the
brief's "`lib/` + `assets/` as siblings": at the root they are siblings.

**Question to the operator:** confirm the recipe tree roots at the artifact
root (`designs/appbox-studio-v2/ui/…`, `app.routes.js`, `assets/`,
`models/`, `l10n/`, `runtime/`) per anatomy §1 — and Q-v2-4 gets a one-line
amendment saying so. On confirmation the emit proceeds immediately.

---

## Withdrawn: "the 15-kind vocabulary can't express studio's widgets"

Recorded because it was wrong and the trail is worth keeping — it is the exact
misreading `showcase-anatomy.md` §2 warns has "already missed twice."

I read Q-v2-3's `design_canvas` / `inspector_panel` / `composer_slider_panel` /
`needs_you_strip` against the 15-name kind list, found no 1:1 match, and was
about to file a gate failure demanding four new `panel-*` kinds. That is the
"read `widget: null` as absence" error one level up — applied to widget *names*
instead of registry entries.

What actually governs these:

- `DESIGN-ARCHITECTURE.md` §182 "Compositions are recipes, and recipes are the
  designer's (Q7)" — "**The designer always composes.** … Panels included: a
  `panel-activity` is composed, never wished into one class." A composed widget
  needs a *recipe* (parts, slots, arrangement), not a new kind.
- `gate_design_widgets.dart:41` — `const panelRoles = ['header', 'main',
  'activity', 'composer', 'footer']` is already first-class in the lint. W3
  expects one `_panel.tsx` base holding the skeleton; W4 checks each shell
  composes `<role>_panel.tsx` widgets from it.
- `references/ui-recipes.md` §19 "Multi-view panel (the stateful widget)" is
  the catalog entry for exactly this — `_panel-views.tsx`, `Frame`/`Head`/
  `Body`/`Bar`, server-session panel state, OOB refresh.
- v1 already does it: `designs/appbox-studio/ui/common/widgets/_panel.tsx`
  plus `main_panel.tsx`, `header_panel.tsx`, `activity_panel.tsx`,
  `composer_panel.tsx`, `footer_panel.tsx`.

So the mapping is roles-and-recipes, not new kinds: `design_canvas` → the
**main** panel's content; `inspector_panel` and `composer_slider_panel` →
**composer**/side role panels per recipe 19; `needs_you_strip` → **header**
or **footer** role; `activity` → **activity**. `interview_thread` composes
from recipe 7 (list rows & sections), `asset_upload_dropzone` from recipe 10
(form fields). No two-registry change is needed and none should be filed.

---

## B2 — the widget-placement law and the lint's doctrine comments disagree (non-blocking, real)

`showcase-anatomy.md` §2 retires the three-tier law: "`ui/common/widgets/`,
`ui/views/<shell>/shared/widgets/` and `<surface>/widgets/` **do not exist in
the exemplar** and are illegal." Two tiers only — `ui/widgets/common/<group>/`
and `ui/widgets/<app>_<feature>_widgets/`.

`gate_design_widgets.dart:72-77` still reasons in the retired vocabulary:

> A fixed `ui/common/widgets/_panel.tsx` would put W3 in direct conflict with
> W1. … a base whose only consumers are one shell's role panels belongs in
> that shell's `shared/widgets/`

and v1 places its panels in both illegal tiers
(`ui/common/widgets/`, `ui/views/main_shell/shared/widgets/`).

This does not block the emit — v2 is a fresh tree and will use the two-tier
law. The panel base and role panels start **feature-scoped** in
`ui/widgets/studio_design_widgets/`, not in `ui/widgets/common/<group>/`:
anatomy §2 says promotion to `common/` is "earned by a second *shell*
consumer, proven by the include graph in both directions, never by intent," and
until the intake shell's surfaces actually import them there is one shell
consumer. W3 is satisfied either way — it keys `_panel.tsx` by name in "any
legal widget home", not by path. If the intake shell ends up mounting role
panels, promotion happens then, on the proven graph. It is filed because the lint's
explanatory comments will mislead the next reader, and because W1's placement
judgement should be re-read against the two-tier law before the next skill
change.

---

## B3 — kind validator cannot run in this checkout (non-blocking, blocks verification)

```
$ python3 .claude/skills/appbox-scaffolder/scripts/validate-registry.py
REGISTRY INVALID — 2 violation(s):
  x no Dart classes found under …/.claude/kit/ui_library/lib — cannot verify targets
  x inspectAttrs shape package:appbox_kit_core/common/appbox_kit_inspect_attrs.dart
    does not exist on disk (…/.claude/kit/core/lib/common/appbox_kit_inspect_attrs.dart)
```

The kit is not materialised at `.claude/kit/`, so the mechanical check
showcase-anatomy insists on ("Never settle a coverage question in prose — this
note was wrong twice") cannot run here. The vocabulary was therefore read
directly from the SSOT the validator itself derives from —
`starter-partials/widgets/*.tsx`, exactly 15 files — and cross-checked against
`kind-resolution.registry.json`'s keys, which match byte-for-byte.

---

## Verified, not blockers

- **Intake exists and is the only authoring surface:**
  `designs/appbox-studio-v2/intake/design-brief.md` (3527 bytes). No second
  source of truth was authored.
- **`library;`** is scoped to `.dart` by anatomy §3's own wording ("Every
  emitted `.dart` file opens with a `///` block, then `library;`"). Omitting it
  from `.tsx`/`.js` is scope-correct, not a deviation.
- **Factor enum** (`desktop`/`mobile`/`tablet`) matches Q-v2-3's "NO
  desktop-only exception."
- **Barrels**: `widgets.js` / `models.js` / `enums.js` / `services.js`, never
  `index.js` (Q-v2-4, user-ruled).
