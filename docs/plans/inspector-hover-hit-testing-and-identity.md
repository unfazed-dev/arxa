# Inspector Hover: Hit-Testing + Identity Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every authored widget on a served design surface — including Label/Heading/Txt leaves and icons — resolves to its own `data-el` identity on hover/click, with per-instance disambiguation, correct pane rendering, and gate + probe enforcement so regressions are mechanical failures, not silent mis-resolves.

**Architecture:** The inspector island (`skills/appbox-designer/runtime/vendor/inspect.js`) resolves hovers via an `elementsFromPoint` stack-walk to the nearest `[data-el]` and posts `name + instance path` to the design server's inspector endpoint. Identity is authored only (JSX primitives spread `inspectAttrs`); the Dart widget gate makes raw text unrepresentable; probes assert the full resolution surface.

**Tech stack:** Vanilla JS island (no ad-hoc client JS beyond named islands), Hono+htmx TSX views, Dart gate/probes (`appboxd`).

## Decisions (locked in grill 2026-08-08)

| # | Decision |
|---|----------|
| Q1 | Gate-enforce text identity: text-bearing tags with rendered text must resolve to a text-role `[data-el]`; failure message: "author via Label/Heading/Txt" |
| Q2 | `Icon` is a first-class widget: `inspectAttrs` on the `<svg>` root, `role: 'icon'`; internal paths stay unselectable (collapse-then-closest preserved) |
| Q3 | `data-el` stays the *type* name; selection posts a stable *instance path*; badge shows `name · k/n` when n>1. Same name across if/else branches of the same logical widget is legal |
| Q4 | Hover = capture-phase `pointermove` → `elementsFromPoint` stack-walk with `e.target` fallback; highlight = one rect per `getClientRects()` fragment |
| Q5 | In scope: chrome annotation holes, pane leaf-badge fix, full probe coverage. OUT of scope: Figma-style modifier deep-select / click-cycling (breadcrumb already disambiguates) |

## Global Constraints

- No ad-hoc client-side JS: all changes live inside the existing named island `inspect.js`.
- Overlay never carries `data-el`; overlay nodes stay `pointer-events:none`.
- One-vocabulary discipline: never interpolate loop indices into `data-el` names.
- Commits: single line, no author mentions, e.g. `feat: resolve inspector hovers via elementsFromPoint stack walk with instance paths`.
- Verify each task with the commands listed; probe suite completion = process exit, never grep "ALL PASSED".

## Diagnosis references (why each task exists)

- `inspect.js:103-106` — resolution is `ownerSVGElement`-collapse then `closest('[data-el]') || document.body`; no point APIs.
- `inspect.js:241` — bubble-phase `pointermove`, `e.target` only (topmost element; occluded widgets unreachable).
- `primitives.tsx:10-19,24-47` — Label(span)/Heading(h*)/Txt(p) all emit `data-el` correctly; primitives are NOT the bug.
- `gate_design_widgets.dart:782,830-833` — identity required only for `{button,a,input,select,textarea}`; raw text tags exempt.
- `designs/appbox-studio/ui/runtime/icon.tsx` — no `inspectAttrs`; every icon resolves to its parent.
- `screen_stub_view.tsx:112` — raw `<span class="stub-thumb sm">`; `:113` — `screen-stub:row-name` duplicated per loop row.
- `inspector_pane.tsx:120,182` — `TypeBadge type={el.kind}` unstyled for `.tb-span/.tb-p/.tb-h1`; pin posts name only.
- `ui/common/widgets/chrome.tsx`, `header_panel.tsx` — zero `inspectAttrs`.
- `appboxd/lib/probes/studio/probe_inspect.dart` — no assertions on text leaves, icons, duplicates, occlusion.

---

### Task 1: Gate — make raw text unrepresentable

**Files:**
- Modify: `appboxd/lib/gate_design_widgets.dart` (around `:782` `_interactiveTags` and `:830-833` identity check)
- Test: extend the gate's existing fixture/self-test harness alongside the current interactive-tag cases

**Rule:** For every element with non-whitespace *direct* text content, its nearest ancestor-or-self carrying `data-el` must have `data-inspect-role` in `_textBearingRoles = {label, heading, text, button, link, chip, badge, input, option}`. A container-role carrier (card/panel/list/section/nav…) or no carrier at all = FAIL with message: `raw text "<snippet>" in <tag> — author via Label/Heading/Txt (or a text-bearing widget)`.

- [ ] **Step 1: failing test** — add gate fixture: a card (`data-el`, role `card`) containing `<span>hello</span>`. Expect gate failure with the message above. Run the gate self-test; confirm it fails (rule not implemented).
- [ ] **Step 2: implement** — add `_textBearingRoles` const; in the element walk, for each node with non-whitespace direct text, resolve nearest `data-el` ancestor-or-self, check role membership. Whitespace-only and script/style contents exempt.
- [ ] **Step 3: pass** — gate self-test green; also add a passing fixture (text inside Label span, text directly inside a `data-el` button).
- [ ] **Step 4: sweep** — run the gate across `designs/appbox-studio`; convert every newly failing raw text node to Label/Heading/Txt (known: `screen_stub_view.tsx:112` thumb span is empty → unaffected; check chrome/header_panel after Task 3). Re-run until green.
- [ ] **Step 5: commit** `feat: gate requires text-bearing widget identity for rendered text`

### Task 2: Icon becomes a first-class widget

**Files:**
- Modify: `designs/appbox-studio/ui/runtime/icon.tsx`
- Consumes: `inspectAttrs` from `designs/appbox-studio/ui/common/widgets/primitives.tsx:10`

- [ ] **Step 1:** Spread `inspectAttrs(props.name ?? `icon:${glyph}`, { role: 'icon', style: 'icon' })` on the `<svg>` root (glyph = the icon's registered name prop). Accept optional `name`/`fn` passthrough props mirroring `TextProps`.
- [ ] **Step 2:** Verify in a served surface: hover any icon → badge shows `icon:<glyph>`, hovering an internal `path` shows the same (collapse lands on the svg's own `data-el`). No path/group ever selectable.
- [ ] **Step 3: commit** `feat: icons carry authored inspect identity on svg root`

### Task 3: Annotate chrome holes

**Files:**
- Modify: `designs/appbox-studio/ui/common/widgets/chrome.tsx`, `designs/appbox-studio/ui/common/widgets/header_panel.tsx`

- [ ] **Step 1:** Spread `inspectAttrs` on each widget's root element (names namespaced like existing widgets, e.g. `chrome:top-bar`, `header-panel`; roles from DESIGN-ARCHITECTURE vocabulary). Any rendered text inside them must flow through Label/Heading/Txt (Task 1 gate will enforce).
- [ ] **Step 2:** `appbox design lint <artifact-dir>` clean; gate green.
- [ ] **Step 3: commit** `feat: chrome and header panel widgets carry inspect identity`

### Task 4: inspect.js — stack-walk hit-testing + instance paths

**Files:**
- Modify: `skills/appbox-designer/runtime/vendor/inspect.js` (`inspectTarget` `:98-106`, `pointermove` `:241`, `measure()` `:173-188`, `buildChain` `:108-120`)

**Resolution spec (replaces `inspectTarget`):**
```js
const resolveAt = (x, y, fallbackTarget) => {
  const stack = document.elementsFromPoint(x, y);
  for (const raw of stack) {
    if (raw.closest('[data-inspect-overlay]')) continue;   // our own nodes
    const el = raw.ownerSVGElement ? raw.ownerSVGElement : raw;
    const hit = el.closest('[data-el]');
    if (hit) return hit;
  }
  const el = fallbackTarget && (fallbackTarget.ownerSVGElement || fallbackTarget);
  return (el && el.closest('[data-el]')) || document.body;
};
```
**Instance path spec:** for the resolved widget and each `buildChain` entry: scope = nearest `[data-el]` ancestor (or document); `siblingsSameName = scope.querySelectorAll(`[data-el="${name}"]`)` filtered to those whose own nearest widget ancestor is `scope`; `k = index of this element`, `n = count`. Instance path = `/`-joined `k` per chain level. POST gains `instance: "0/2/3"` and `instanceCount: n` for the leaf.

- [ ] **Step 1:** Tag overlay container with `data-inspect-overlay` (no `data-el`, keep `pointer-events:none`).
- [ ] **Step 2:** Switch `pointermove`/`click` handlers to capture phase; both call `resolveAt(e.clientX, e.clientY, e.target)`. Identity throttle (`lastHovered`) must compare element ref, unchanged.
- [ ] **Step 3:** Implement instance computation in `measure()`; include `instance`/`instanceCount` in the POST body; badge text becomes `${name} · ${k+1}/${n}` when `n > 1`.
- [ ] **Step 4:** Manual check on stub screen: rows resolve to distinct `screen-stub:row-name · k/n`; a label positioned under an overlapping sibling (add temp fixture if none exists) is hoverable.
- [ ] **Step 5: commit** `feat: inspector resolves hovers via elementsFromPoint stack walk with instance paths`

### Task 5: inspect.js — per-fragment highlight

**Files:**
- Modify: `skills/appbox-designer/runtime/vendor/inspect.js` (`ensureOverlay`/`showOverlay`), `skills/appbox-designer/runtime/vendor/viewer.css` (`:320-321` region)

- [ ] **Step 1:** Overlay holds a reusable pool of absolutely-positioned rect divs inside the `position:fixed` `data-inspect-overlay` container. `showOverlay(el)`: `rects = el.getClientRects()`; draw one div per rect (batch read then write in one rAF; position via `transform`). Blocks yield exactly one rect — visual parity.
- [ ] **Step 2:** `rects.length === 0` (empty inline/`display:contents`) → draw the nearest block container's rect but keep the leaf's name/identity in the badge and POST.
- [ ] **Step 3:** Wrapped multi-line Label shows one rect per line fragment, not a full-column box. Survives htmx morph (keep the existing `isConnected` re-attach guard).
- [ ] **Step 4: commit** `feat: inspector highlight draws one rect per line fragment`

### Task 6: Pane — leaf badges + instance-aware pin

**Files:**
- Modify: `designs/appbox-studio/ui/views/main_shell/…/inspector_pane.tsx` (`:120` TypeBadge, `:182` pin POST), server route handling the inspector session lock

- [ ] **Step 1:** Map `kind` → styled badge set: `span→text·label`, `p→text·body`, `h1|h2|h3→text·heading`, `svg→icon`; unknown kinds get a neutral styled badge (no more bare `.tb-span/.tb-p/.tb-h1`).
- [ ] **Step 2:** Pin/lock POST includes `instance`; session lock stores `{name, instance}`; pane header renders `name · k/n` when `n > 1`.
- [ ] **Step 3:** Composer context payload for a pinned widget includes name, role, instance, and ancestor chain — verify the chat context block shows the instance.
- [ ] **Step 4: commit** `feat: inspector pane renders text leaf badges and instance-aware pins`

### Task 7: Probes — cover the regression surface

**Files:**
- Modify: `appboxd/lib/probes/studio/probe_inspect.dart` (+ its fixture surface)

New assertions (each = hover/click via CDP, then assert POST payload/badge):
- [ ] Label, Heading, Txt each resolve to their OWN `data-el` (`role` label/heading/text), never the parent container.
- [ ] Icon glyph hover resolves to `icon:<glyph>`; hover on an inner `path` resolves identically; no path identity ever posted.
- [ ] Loop fixture with 3 same-name rows: three distinct `instance` values, `instanceCount == 3`; pinning row 2 locks row 2.
- [ ] Occlusion fixture (label under absolutely-positioned transparent sibling): label still resolvable (stack-walk).
- [ ] Wrapped label (narrow container): overlay renders `> 1` highlight rect.
- [ ] Gate case: fixture with raw `<span>text</span>` inside a card fails `gate_design_widgets` with the Task 1 message.
- [ ] Run full probe suite; wait for process exit for the verdict. Commit: `test: probe inspector text leaves icons instances occlusion and fragments`

### Task 8: End-to-end verification

- [ ] `appbox design lint` + widget gate green across `designs/appbox-studio`.
- [ ] Serve studio, arm inspector: walk one real screen — every visible element resolves to an authored widget or the screen sentinel; no raw span/path/div identity anywhere.
- [ ] Full probe suite exit-verdict green. Final commit if any stragglers.

## Self-review notes

- Task 4's `resolveAt` replaces `inspectTarget` — `buildChain`, `measure`, click-lock all call through it; no second resolution path remains.
- `elementsFromPoint` omits `pointer-events:none` app elements — identical blindness to today's `e.target`, no regression; the `fallbackTarget` arm covers empty-stack edges.
- Q3 legality: same `data-el` in mutually exclusive branches is one logical widget — the gate must NOT flag it; only the probe's *instance* assertions cover runtime duplicates.
