# Screen Reveal-Drawer: Composer / Tools / Logic

Date: 2026-08-04. Status: shipped 2026-08-05 (increments 1–5 merged; see `handoff-reveal-drawer-remaining.md`).
Supersedes: `widget-editing-autolayout-and-manager.md` § "Components-container 2-col split" (that section is dead; a supersession note points here). Task #4 is replaced by the increments below.

## Requirement (operator's intent)

Every screen designed by appbox ships with a slider panel hidden at the **back** of the screen. The screen is the main, always-visible item. A hover-revealed top bar on the screen (pill icon buttons, per Image #7) carries an icon toggle that smoothly animates the panel out from behind the screen — card-scoped reveal-drawer/off-canvas pattern — until it sits beside the screen (Image #4 end state; Image #5 is a look reference for the composer section only). The panel has 3 tabs:

- **Composer** — the existing composer made reusable (thread-style UI incl. chat input), scoped to this screen and its widgets.
- **Tools** — specifics of only the selected widget, with all details, editable on the spot.
- **Logic** — what the screen and each widget connect to (function, facade, repository, …) in technical and simple human terms.

The components container and **all** its features (element list, "Add to plan" composer, PLANNED EDITS tray) are removed. The global composer panel is untouched.

## Decisions (locked, from grilling interview)

- D1 **Placement**: serve-time wrapper around every designed screen; hover-revealed top bar with icon trigger buttons; smooth open/close animation.
- D2 **Removal scope**: pure removal of the components container; no plan-editor migration; global composer panel stays. Removal is the *last* increment (see ordering note) — rollback story until then is the container still existing on HEAD^ plus git revert; no runtime feature flag (local single-user tool).
- D3 **Mechanic**: screen fixed, `z-index: 2`; panel behind at `z-index: 1`, `transform: translateX(0)` → `translateX(100% + gap)`; transition on `transform` only; `visibility` toggled at transition end; `prefers-reduced-motion` → instant swap; no scrim, no screen movement/scaling; viewport too narrow → horizontal pan, never cover the screen.
- D4 **Composer tab**: existing composer extracted into a reusable component (thread UI + chat input), scoped to screen+widgets. Image #5 is style reference only — no new checkpoint machinery decided.
- D5 **Selection**: click widget in the rendered screen (primary) + compact hierarchy strip (breadcrumb + siblings) in the Tools tab header; one shared selection state consumed by Tools and Logic.
- D6 **Logic tab**: deterministic connection graph derived from widget contracts / registry / provenance / inspect metadata; plain language via deterministic templates over the same facts; underivable = honest "not wired / unknown"; no LLM dependency to view.
- D7 **Tools tab editing**: provenance-routed writes through design_server (pattern proven by the text-editing pipeline); contract-declared, source-addressed; unresolvable properties render read-only; re-render via normal serve reload.
- D8 **View state**: session-scoped only; drawer closed by default; Composer is first-open tab; per-screen memory of open/tab within a session; selection state same rule; nothing persisted to project files.
- D9 **Cleanup**: container-specific probes deleted; new drawer probes; supersession note in old plan; l10n updates all locales incl. `qps-ploc` (mind the scaffold-validator quirk).

## A11y / interaction defaults

Trigger is a real `<button>` with `aria-expanded`; ESC closes the drawer; focus moves into the panel on open and returns to the trigger on close; hover bar is also reachable by keyboard focus. Panel column width: matches screen card height, width = screen width capped ≈420px (tune against Image #4).

## Increments (ordering per advisor review: extraction proven before its old host dies; removal never shares a step with the composer's first reusable render)

1. **Composer extraction** — extract the composer into a reusable, scope-parameterized component while the components container still exists and works. Gate: global composer panel and container both render identical to pre-refactor; existing composer probes pass unchanged.
2. **Wrapper + drawer shell + Composer tab** — serve-time wrapper, hover top bar, reveal-drawer animation, 3-tab skeleton, reusable composer mounted screen-scoped. Container untouched. New probes: tucked/out end states, hover-bar presence, tab switch, reduced-motion instant path.
3. **Selection + Tools tab** — shared selection state (click-in-render + hierarchy strip; reconcile with any existing canvas/inspect selection state — verify none conflicts), widget details read-only first, then provenance-routed editing for resolvable props. Probes: click→Tools sync, read-only honesty for unresolvable props.
4. **Logic tab** — deterministic graph + template phrasing. Probes: known wiring renders both technical and plain sentence; unknown renders honest state, never fabricated.
5. **Removal + cleanup** — delete components container + its probes; l10n: remove container strings, add drawer/tab strings across all locales incl. `qps-ploc`, with a probe asserting pseudo-expanded strings don't overflow the drawer chrome; refresh task list; confirm supersession note.

## Verification

Each increment lands committed with its probes green (`probe all` — wait for process exit, per memory) before the next starts. Advisor risk notes tracked: drawer width/pan behavior on narrow rungs, focus management, selection-state reconciliation, qps-ploc overflow.
