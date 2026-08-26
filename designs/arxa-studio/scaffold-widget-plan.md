# Scaffold-stage widget plan

Source moodboard: `docs/moodboards/scaffold-stage.md` ("Patterns this slice
must have", 7 items — VS Code Marketplace card anatomy, PostHog toggle+%
fusion, JetBrains Installed/Available grouping, Railway gate-to-run tile,
GitHub Actions per-item status list). Existing registry hook: `registry.json:183-189`
already declares `build.gates` (comp `BuildGates`, route `/build/gates`) with
no view file yet (`ui/views/main_shell/build/` currently holds only `loop/`).
All three target screens live inside the **build shell**, hosted by the
existing `main_shell` chrome — the moodboard is explicit that the per-kit
status list belongs in the *existing* activity panel or footer panel, never a
new panel.

Placement-law tier for the net-new macros (per
`skills/arxa-designer/references/app-architecture.md`): intra-shell, new
directory `ui/views/main_shell/build/shared/widgets/`, mirroring the existing
`ui/views/main_shell/shared/widgets/` sibling convention one level down (that
dir is scoped to all of `main_shell`'s shells; this one is scoped to `build`
only, since none of these four widgets are needed by design/intake/loop).

---

## Screen 1 — Kit picker (tiered cards + badges)

| UI element | Existing macro / partial | Note |
|---|---|---|
| Tier grouping (Core / Integrations / Platform / Advanced, VS Code Featured/Most Popular + JetBrains Installed/Available) | **NEW** — `kit_tier_section` | Extends the list-section header pattern (`_list-row.html` doc comment, `skills/arxa-designer/starter-partials/widgets/_list-row.html:1-10`, recipe 7 in `ui-recipes.md`) but wraps a `.card-grid` body instead of rows. `data-layout data-flow="v" data-gap="24"` on the section stack; each tier's card-grid keeps the existing 1→2→3 column ladder (`.card-grid` in `widgets.css`). |
| Kit card (icon top-left, title, publisher/category line, right-aligned metric, corner badge) | **NEW** — `kit_card`, extends `_card.html` | `skills/arxa-designer/starter-partials/widgets/_card.html:12-22` context shape (`id, media?, title, subtitle?, body?, actions?, vt?`) covers icon/title/subtitle/actions but has no metric slot or corner-pinned badge; `kit_card` adds `metric?` and `badge?` fields. Card container: `data-layout data-flow="v" data-gap="12" data-pad="16" data-resize-x="fill"`; header row `data-gap="auto" data-align-y="center"` to push the metric to the far end (identical pattern to ui-recipes.md's card-in-list example, "20. Auto Layout"). |
| Corner/category badge (FREE / beta / requires-payments) | REUSE — `primitives.chip()` / `primitives.typeBadge()` | `designs/arxa-studio/ui/common/widgets/primitives.html:11-25`, tone hooks `.tb-*` in `designs/arxa-studio/assets/css/widgets.css:28-38`. Pin to the card's bottom-right corner with `data-layout-ignore` (the one-child escape hatch is acceptable here; a second ignored child would mean dropping Auto Layout from the card). |
| Combined toggle + rollout-percentage control (Unleash/PostHog fusion — ring around/beside the toggle while scaffolding runs, plain on/off when idle) | **NEW** — `kit_toggle_progress` | No existing analog; the moodboard's own "Patterns this slice must have" #2 states the ring is "arxa's own invention." Build it Auto-Layout-on (`data-layout data-gap="8" data-align-y="center"`) so it drops into the card header exactly like the canonical button recipe. |
| "Select all essentials" / select-all / clear-all action row | REUSE — action-row/`.btn` pattern | Recipe 1 ("Buttons & action rows") — `.action-row` is already used this way in `_form-field.html`'s example (`skills/arxa-designer/starter-partials/widgets/_form-field.html`); `data-layout data-gap="8" data-align-x="end"`. |
| Pinned "enabled kits" chips once the gate closes | REUSE — `composer_panel.headContent()` chip loop | `designs/arxa-studio/ui/views/main_shell/shared/widgets/composer_panel.html:39-49` — the `chips: [{ id, label, tone?, removeHref? }]` context already exists for exactly this ("design's pinned screens, build's gate refs" per its own doc comment, line 22-23). |

## Screen 2 — Scaffold progress / checklist with gate

| UI element | Existing macro / partial | Note |
|---|---|---|
| Per-kit status row list, one row per kit, status icon flips spinner→check/fail (GitHub Actions job list) | REUSE — `timeline.items()` | `designs/arxa-studio/ui/views/main_shell/shared/widgets/timeline.html:29-52` already renders `{{ i.state }}` as a `tl-state-{state}` class per `<li>` — the exact per-item status-icon shape the moodboard calls for. Host it via `footer_panel.open({ tag: 'ol', bodyClass: 'timeline', bodyId: 'timeline' })` (`designs/arxa-studio/ui/views/main_shell/shared/widgets/footer_panel.html:22-23`), matching the moodboard's own steal-note that this belongs in "the footer panel's timeline… not a new panel." |
| In-flight spinner on the active row | REUSE — recipe 17 pending indicator | `.htmx-indicator` / `.indicator-spin` (motion.css §1) layered on the row's status glyph; no markup change needed beyond swapping `i.state`. |
| Gate confirm tile (kit selection collapses into one confirmation tile before the pipeline view takes over — Railway's New Project tile) | **NEW** — `scaffold_gate_tile`, extends `_empty-state.html` | `skills/arxa-designer/starter-partials/widgets/_empty-state.html:15-19` context shape (`icon?, title, body?, action?`) is structurally close (centered column, one CTA) but semantically wrong to reuse bare — empty-state means "nothing here," this tile means "confirm and proceed." Same layout primitive, new macro name so `arxa design lint` doesn't conflate the two intents. |
| Fatal scaffold failure (whole run can't continue) | REUSE — dialog / screen-level error state | `_dialog.html` (`skills/arxa-designer/starter-partials/widgets/_dialog.html`) per the D17/D19 error-manager taxonomy (`DESIGN-ARCHITECTURE.md`, "Feedback & state placement") — fatal errors never go to a toast. |
| Recoverable per-kit scaffold failure (retry one kit) | REUSE — `_toast.html` with Retry action | `skills/arxa-designer/starter-partials/widgets/_toast.html` — D11's rule that a toast's defining feature is its action; pairs with the row's `fail` state. |

## Screen 3 — Shell chrome integration

| UI element | Existing macro / partial | Note |
|---|---|---|
| Top nav strip | REUSE — `chrome.headerBody()` | `designs/arxa-studio/ui/views/main_shell/shared/widgets/chrome.html` — no new destination entry expected; `build.gates` already nests under the existing Build tab (`registry.json:183-189`). |
| Activity panel (left/right multi-view carousel) | REUSE — `activity_panel.open()/close()` | `designs/arxa-studio/ui/views/main_shell/shared/widgets/activity_panel.html:19-23`. Build's views doc comment (line 15) lists `runs / commits / files` — if the kit gate needs a persistent side inventory, add a `kits` view to that same registered list; otherwise the kit picker is the main-panel body and this panel is untouched. |
| Composer panel (pinned context) | REUSE — `composer_panel` (see Screen 1) | Same chip mechanism carries the enabled-kit set through from gate to progress screen. |
| Footer panel (timeline host) | REUSE — `footer_panel.open()/close()` | Same file as Screen 2; this is the wiring point, not a new panel. |
| Mini panel (device rung / bg swatch) | N/A — out of scope | No design canvas on these two screens; `mini_panel.html` is not consumed here. |
| Panel skeleton primitive (if the kit gate needs its own top/bottom sections distinct from activity/composer/footer) | REUSE — `_panel.html` `open/close/top/bottom` | `designs/arxa-studio/ui/views/main_shell/shared/widgets/_panel.html:92-163`. |

---

## Evidence

- File: `designs/arxa-studio/scaffold-widget-plan.md`
- Reused macros/partials: 13 (`_card.html`, `_list-row.html` pattern, action-row/`.btn`, `composer_panel.headContent`, `timeline.items`, recipe-17 pending indicator, `_empty-state.html` layout primitive, `_dialog.html`, `_toast.html`, `chrome.headerBody`, `activity_panel.open/close`, `footer_panel.open/close`, `_panel.html` base, `primitives.chip/typeBadge`)
- Net-new: 4

## Net-new macros, build order

1. `kit_toggle_progress` — the toggle+ring/bar fusion; foundational, feeds both the kit card and (as a summary %) the gate tile.
2. `kit_card` — depends on (1) slotting into its header.
3. `kit_tier_section` — depends on (2) for its grid body.
4. `scaffold_gate_tile` — depends on (1) for its aggregate-progress summary once the gate closes.

All four go in a new `ui/views/main_shell/build/shared/widgets/` directory
(does not yet exist — `ui/views/main_shell/build/` currently holds only
`loop/`).
