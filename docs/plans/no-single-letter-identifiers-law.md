# Law: no invented single-letter identifiers in designer-generated code

Date: 2026-08-09. Session: rung→viewport sweep follow-up.

## Ruling (user, via grill)

1. **Full ban** — including `t` (i18n convention loses; zero exceptions for invented names).
2. **API members too** — `Helpers.t` renames; runtime contract change, not just bindings.
3. **Sweep scope** — designs/arxa-studio-v2 (15 files, list below) **and** the skill SSOT
   (eject runtime, hello-hda example, starter-partials, ui-recipes).
4. **Law + mechanical gate** — prose in DESIGN-ARCHITECTURE.md plus a grep-based check.
5. **Carve-out** — medium-native tokens are exempt: the HTML `<a>` element, CSS single-letter
   type selectors, established file formats. The law governs identifiers we *invent*
   (params, consts, lets, function/method names, API members), not the platform's vocabulary.

## SSOT reconciliation (rule-10 trail)

- Mechanical gate script `~/.agents/skills/consultant/scripts/consult.sh` **does not exist**
  on this machine; manual check performed instead.
- SSOT = `skills/arxa-designer` (git-tracked). `.claude/skills/arxa-designer` is an
  untracked content-identical copy the harness loads (delta: `.claude-flow` only).
  `~/.agents/skills/arxa-designer` is a **dangling symlink** → nonexistent
  `skills/arxa-designer`.
- Procedure: edit SSOT, then rsync SSOT → `.claude` copy. Debt: repoint or remove the
  dangling `~/.agents` symlink (surface to user; do not silently fix).
- Advisor unavailable: consult-z API balance exhausted (HTTP 429), noted per conventions.

## Renames (contract)

- `Helpers.t(c)` → `Helpers.translate(context)` — types.d.ts, helpers.js, 7 call sites.
- `L10n.createT` → `L10n.createTranslator`.
- Viewmodel signature `(c, h)` → `(context, helpers)` everywhere (templates + designs).
- Local `const t = h.t(c)` → `const translate = helpers.translate(context)`.
- TSX/facade one-letters (`s`, `d`, `n`, `p`, `k`, `f`, map/filter params) → per-site
  meaningful names.

## Sweep list (v2)

ui/common: v1_strings.tsx, prefs_viewmodel.js
ui/views: studio_dashboard_shell/{studio_dashboard/{studio_dashboard_viewmodel.js,
  studio_dashboard_view.sections.tsx}, studio_dashboard_shell_viewmodel.js},
  studio_startup_shell/{studio_startup_shell_viewmodel.js,
  studio_startup/studio_startup_viewmodel.js},
  studio_application_hub/studio_application_hub_viewmodel.js
ui/widgets: studio_application_widgets/{header,rail,tabbar}.tsx,
  studio_startup_widgets/boot_checklist.tsx
services: {studio_dashboard,studio_startup,studio_application}_services/facades/*.js

## Order

1. Commit untracked `studio_dashboard_shell/` (dash-variants work, verified clean + idle)
   so the sweep mutates a committed tree (memory: commit-before-mutation).
2. Rename runtime contract in SSOT eject runtime; sweep skill templates.
3. Sweep v2 files.
4. Law paragraph in DESIGN-ARCHITECTURE.md (SSOT).
5. Gate: `skills/arxa-designer/runtime/eject/check_naming.sh` (or wire into existing
   lint if found) — regex over generated js/tsx, vendor + node_modules excluded.
6. rsync SSOT → `.claude/skills/arxa-designer`.
7. Verify: gate passes on v2 + hello-hda; design server smoke (`h.t` gone, pages render).
