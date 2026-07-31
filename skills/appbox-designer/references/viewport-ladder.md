# The viewport ladder

**Read this before authoring a single surface.** Which widths you design at is
not a style preference — it decides how much of the app gets invented by
somebody downstream who never saw your design.

## The problem this solves

A prototype authored at phone width only forces the scaffolder to guess every
wider layout. That guessing is not cheap and it is not visible: in the reference
project roughly **1,600 lines of tablet and desktop layout in a single shell**
were invented after the freeze, with no design to check them against. The
prototype's job is to carry **structure at every width the app ships**, not
pixels at one.

## The ladder

Three freeze widths, each sitting **inside** a Material 3 window size class,
never on a boundary:

| rung | width | window size class | class boundary it sits inside |
|---|---|---|---|
| `compact` | **390** | Compact | `< 600` |
| `medium` | **744** | Medium | `600 – 839` |
| `expanded` | **1280** | Expanded | `≥ 840` |

**Why not on the boundary.** A layout authored at exactly 600 or 840 renders
whichever side of the branch the rounding happens to pick, and the two sides
disagree. Freezing at 390 / 744 / 1280 puts every render unambiguously in one
class, so the frozen image is reproducible.

Heights pair with the widths (`390×844`, `744×1133`, `1280×832`) but are far
less load-bearing — surfaces scroll; classes branch on width alone.

## Which rungs are active is DERIVED, never chosen

The active ladder comes from the project's **targets**, resolved from config.
**Never hardcode a width in a template, a script, or a check.**

| targets | active rungs | layout files the scaffolder emits |
|---|---|---|
| `ios`, `android` | compact + medium | 4 |
| `macos`, `windows`, `linux` | expanded | 3 |
| `web`, `pwa` | compact + medium + expanded | 5 |
| `ios` + `macos` | compact + medium + expanded | 5 |

Read the resolved list from the project's config at the start of every session
and state it back to the user before designing. If the config does not resolve,
**stop and say so** — do not fall back to phone-only, which is the failure this
document exists to prevent.

## What changes between rungs

Not scale. **Composition.** A wide layout is a different arrangement of the same
information, never a stretched phone column. The archetype catalog below is
closed — if a surface does not fit one, that is a signal the surface is doing
two jobs.

| archetype | compact | medium | expanded |
|---|---|---|---|
| **tab-shell** | tabbar | nav-rail | nav-rail or permanent drawer |
| **nested-shell** | tabbar + inner segmented control | nav-rail + inner tabs | nav-rail + two-pane content |
| **dashboard-stack** | one scrolling column of cards | two-column grid | true multi-column grid |
| **inset-grouped-list** | full-width grouped rows | wider inset, same rows | master–detail two-pane |
| **pinned-search-list** | pinned search + results column | same, wider gutters | search + results list + detail pane |
| **form-flow** | full-width fields | centered column | **centered fixed-width column, never full-width fields** |
| **full-bleed-detail** | edge-to-edge media + overlay | same with margins | the detail pane of a master–detail pair |
| **centered-state** | centered icon + copy + action | same, capped width | same, capped width |

The recurring wide-layout mistake is a form whose inputs stretch to 1280px.
Cap it.

## Default chrome per rung

The archetype table says how *content* composes; this table says which **chrome**
a surface wears at each rung. These are the shipped defaults — a project's
design brief may override any cell explicitly ("no FAB", "top tabs everywhere"),
but silent deviation is a bug, not a choice. State the resolved chrome alongside
the resolved ladder at session start.

| chrome | compact | medium | expanded |
|---|---|---|---|
| header panel | always — title + **drawer action** + **dropdown menu** | same as compact | always — full action row |
| primary nav | **tabbar** | **railbar**, collapsible/expandable | **activity panel + composer panel**, the composer permanent |
| footer panel | — | — | the read-only stage timeline |
| FAB | **staggered action menu**, animated fan-out | same as compact | — |

- The compact/medium drawer carries whatever the expanded activity panel
  carries; the railbar is the drawer's docked form, not a second component.
- Chrome *contents* (which destinations, which activity views, which FAB
  actions) come from the surface's viewmodel — this contract fixes placement
  and behaviour, not items.
- The staggered FAB is the home of contextual actions on touch rungs; on
  expanded those same actions live in the panels/footer panel instead.

## Authoring and verifying at every rung

1. Author the surface at **every active rung** — same `registry.json` entry,
   same `surfaceId`, same viewmodel; the *view* branches on width via CSS
   container queries or media queries.
2. Shoot every surface at every active rung and read the images back:
   `appbox lens shoot <url> [--rungs a,b]`. Widths live in
   `runtime/ladder.json` — pass rung *names*, never pixels. See
   [`harness-tools.md`](harness-tools.md).
3. A surface that renders identically at two rungs is fine — say so explicitly
   rather than leaving it ambiguous, so the scaffolder knows it was a decision.
4. A surface that has **never been rendered** at an active rung is not done,
   regardless of what the markup suggests.

## Do not

- Do not hardcode `390`, `744` or `1280` anywhere in code. They live in
  `runtime/ladder.json`; everything else refers to the rung *names*
  `compact` / `medium` / `expanded`.
- Do not author at a boundary width (600, 840).
- Do not treat "it looks fine when I resize the browser" as verification. Resize
  behaviour and a frozen render at a fixed width are different observations.
- Do not add a fourth rung without changing the config and the derivation table
  together — a width nothing derives is a width nothing checks.
