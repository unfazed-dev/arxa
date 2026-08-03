# Handoff — the viewmodel `design_facade.js` must produce for the inspector pane (D14–D17)

I own the template, the fragment, the routes, the island and the strings. I do **not**
own `services/facades/design_facade.js`. This file is the exact shape I render against.
Everything below is read defensively in the template (`{% if %}` on every scalar,
`{% for %}…{% else %}` on every list), so a field you have not built yet renders an
empty-but-valid pane rather than throwing. Build them in any order.

---

## 0. Two changes outside the new object

### 0a. The allowed-list — `stageContext`, currently `design_facade.js:~603`

```js
const activityView = ['screens', 'artifacts', 'files'].includes(d.activityView) ? d.activityView : 'screens';
```
must become
```js
const activityView = ['screens', 'artifacts', 'files', 'inspector'].includes(d.activityView) ? d.activityView : 'screens';
```
Without this, `setActivityView(…, 'inspector')` silently falls back to `screens` and the
carousel icon never lights.

### 0b. The carousel entry — `activityViews` in the same return

The existing three entries are built as `{ id, icon }` then mapped to
`{ label: t('activityView.' + id), href: '/design/panel/' + id, active }`.
The inspector entry needs a **different href** and therefore cannot ride that map:

```js
activityViews: [
  { id: 'screens',   icon: 'layout-grid', href: '/design/panel/screens'   },
  { id: 'artifacts', icon: 'package',     href: '/design/panel/artifacts' },
  { id: 'files',     icon: 'folder',      href: '/design/panel/files'     },
  // The inspector renders from prototype_view.html#inspectorSwap, not from
  // _shared.html#activityBody, so it has its own route.
  { id: 'inspector', icon: 'scan-search', href: '/design/inspector'       },
].map((v) => ({ ...v, label: t('activityView.' + v.id), active: v.id === activityView })),
```

`activityView.inspector` is already in `app_en.arb` / `app_pl.arb` (I added it).
`scan-search` is a Lucide name; swap it if the vendored subset lacks it.

> **§0a is a hard prerequisite for §4.** `POST /design/inspector/select` 204s (renders
> nothing) whenever `activityView !== 'inspector'` — that guard is what stops a hover
> from overwriting the screens list. Until `'inspector'` is in the allowed list,
> `setActivityView(…, 'inspector')` falls back to `'screens'`, so **every hover 204s
> forever and the pane looks dead with no error anywhere**. Land §0a first.

### 0c. ~~BLOCKER — a file neither of us owns~~ — RESOLVED (verified 2026-08-03)

**This blocker no longer exists.** Both edits below landed in `be9ea3c`. Verified in-tree:
the branch is at `ui/views/main_shell/design/_shared.html:180` (with an explanatory
comment at 181-183 and `{{ ins.pane(c) }}` at 184), and the import is at line 24.
Nothing to do here. The original text is kept below for the record.

> Note on the original citation: this section cited `_shared.html:144`, which was wrong
> even when written — line 144 sits *before* the `activityBody` macro, which opens at 152.
> Cite by symbol + verified line, and re-verify line numbers before a handoff is read.

`ui/views/main_shell/design/_shared.html` `activityBody(c)` (macro opens at **152**) is
the **full-page**
dispatch. After any full render (`GET /design`) with `activityView === 'inspector'` it
falls through to the screens list. It needs exactly one branch added before the final
`{% else %}`:

```nunjucks
{% elif c.activityView == 'inspector' %}
{{ ins.pane(c) }}
```

plus the import at the top of `_shared.html`, next to the other imports:

```nunjucks
{% import "ui/views/main_shell/design/inspector_pane.html" as ins %}
```

`inspector_pane.html` is macro-only, so importing it emits nothing. Fragment swaps work
without this change; only a full page load is affected.

---

## 1. The new object — `c.inspector`

Hung off the `stageContext` return, same level as `c.viewer`. Present on **every**
render (the pane is re-rendered by fragment swaps that carry the whole stage context).

```js
inspector: {
  mode,          // 'element' | 'screen' | 'empty'
  locked,        // bool
  element,       // object | null  (see §2)
  screen,        // object | null  (see §3)
  unlockHref,    // string — POST target that clears the lock. Use '/design/inspector/unlock'.
  hint,          // string | null — one line of copy for mode 'empty'; null uses my default string.
}
```

`mode` is the only field the template branches on:

| `mode` | when | renders |
|---|---|---|
| `element` | an element is hovered or locked | the element card (§2) |
| `screen` | nothing hovered/locked, but a screen is in view/pinned | the screen card (§3) |
| `empty` | neither | the empty state (my string, or `hint`) |

Derive `mode`: `element ? 'element' : (screen ? 'screen' : 'empty')`. If you set `mode`
to something else the template renders the empty state — that is deliberate.

---

## 2. `inspector.element` — the element card (D17, element half)

Every field here except `screenId`/`tone`/`pinned`/`pinHref`/`unpinHref` originates in
the **client POST** (see §4). The server cannot derive them: `data-el="hero:{{ t(…) }}"`
is unresolved and per-locale server-side.

| field | type | source |
|---|---|---|
| `name` | string | client POST `name` (= `el.dataset.el`) — the SAME string the composer chip renders |
| `kind` | string | client POST `kind` (= lowercased tagName) |
| `screenId` | string | client POST `screen` (= `document.body.dataset.surface`) |
| `tone` | string | server — `toneFor(screenId, locale)`, so the card can wear `ctx-<tone>` like the chips do |
| `role` | `{ value: string, inferred: bool }` | `value` from client POST `role`; **`inferred` is yours**: true when the client sent nothing and you fell back to the `data-el` prefix |
| `style` | string \| null | client POST `style` (`data-inspect-style`) |
| `motion` | string \| null | client POST `motion` (`data-inspect-motion`) |
| `fn` | `{ value: string, inferred: bool }` \| null | `value` from client POST `fn` (`data-inspect-fn`) when present; when absent and you can infer one (D9), return the inference with `inferred: true`. **The client never sets `inferred`** — it POSTs only what it reads off data-attributes; the server owns the flag |
| `pinned` | bool | server — is this `screenId`+`name` already in `d.elementContext` |
| `pinHref` | string | server — `'/design/chat/context/element'`. POSTed as a form with `screen`/`name`/`kind` hidden inputs; the existing `chat.elementContext` route handles it unchanged |
| `unpinHref` | string | server — the existing `${contextBase}element/remove?screen=…&name=…` you already build for `c.elements[]`. GET |

`inferred: true` renders a visible "inferred" badge next to the value — the house
derive+confirm pattern. `inferred: false` or absent renders the value plain.

---

## 3. `inspector.screen` — the screen card (D17, screen half)

All server-side (registry / flows / annotations). Every list may be empty.

| field | type | source |
|---|---|---|
| `id` | string | registry |
| `epic` | string | registry — feeds `prim.typeBadge('screen', epic)` |
| `state` | string | registry — feeds `prim.statusPill(state)` |
| `tone` | string | `toneFor(id, locale)` |
| `states` | `[{ name, source }]` | `source` is `'declared'` (authored in the registry) or `'derived'` (computed). Renders a badge per state; `derived` is marked |
| `missingStates` | `[{ name, why }]` | states this screen's kit implies but does not declare. `why` is one short line — a kit name is fine. Empty array = nothing missing = no section rendered |
| `kits` | `[{ id, label }]` | registry. `label` may equal `id` |
| `edges` | `[{ flow, flowLabel, trigger, to, element }]` | flows. `flow` is the flow id, `flowLabel` its display name, `to` the destination screen id, `element` the `data-el` that fires it or `null`. Outgoing only |
| `annotations` | `{ covered, total, pct, missing }` | `covered`/`total` ints, `pct` an int 0–100 (I do NOT compute it — send it), `missing` an array of `data-el` name strings. Whole object may be null |

---

## 4. What the island POSTs — `POST /design/inspector/select`

I own the island and the route. Listed so the facade function you write has the right
signature. Form-urlencoded, sent by `htmx.ajax('POST', …, { values })` from the parent:

| key | always sent | meaning |
|---|---|---|
| `screen` | yes | `document.body.dataset.surface` |
| `name` | yes | `el.dataset.el` |
| `kind` | yes | lowercased tagName |
| `role` | when present | `data-inspect-role` |
| `style` | when present | `data-inspect-style` |
| `motion` | when present | `data-inspect-motion` |
| `fn` | when present | `data-inspect-fn` |
| `lock` | on click only | `'1'` — click locks, hover does not |

So the facade entry point I call is:

```js
export const selectElement = (sessionData, payload, prefs, t, locale) => …
```

with `payload = { screen, name, kind, role, style, motion, fn, lock }` (strings; `lock`
is `'1'` or absent). Rules it must implement:

1. **Locked wins.** If `d.inspectorLock` is set and `payload.lock` is absent, this is a
   hover — return the stage context **unchanged**. Do not recompute the card; the pane
   re-renders identically and the swap is a no-op. (The island still fires one request
   per element change while locked; making that cheap is the point of this rule.)
2. `payload.lock === '1'` sets `d.inspectorLock = { …payload }` and makes it the shown
   element.
3. Otherwise store the hover in `d.inspectorHover = { …payload }` and show that.
4. `d.inspectorLock` survives htmx morphs because it is session state, never DOM state —
   that is the whole D16 requirement.

And the unlock entry point:

```js
export const unlockInspector = (sessionData, prefs, t, locale) => …   // clears d.inspectorLock, keeps d.inspectorHover
```

`setActivityView` needs no change beyond §0a — I call it from my own route.

---

## 5. Things I explicitly do NOT need

- No new client-JS island and **no second ADR-0002 amendment**: the pane is
  server-rendered, the existing `inspect.js` island only POSTs measurements, exactly the
  pattern it already uses at `inspect.js:139-161`.
- No CSS. The pane reuses `.av-list` / `.msg .msg-agent` / `.msg-meta` / `.msg-text` /
  `.msg-detail` / `.msg-foot` / `.msg-cta` / `.ctx-<tone>` and `prim.typeBadge` /
  `prim.statusPill`.
- No change to `chat.elementContext` or `chat.elementContextRemove` — pin/unpin from the
  pane reuse them as-is.
