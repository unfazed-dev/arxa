# Design viewer: per-lens hover toolbars + flow mode

Status: planned, not implemented. Written 2026-08-02.

Supersedes the "live mode" tile tool.

**Read alongside this:** `skills/arxa-designer/DESIGN-ARCHITECTURE.md`
§"The output triad: views / flows / proto" (lines 81-110) and
`designs/arxa-studio/ui/common/_integration_viewer.md` (the `v` contract).

**Do NOT read `docs/plans/canvas-redesign-contract.md`** — its own line 3 marks it
*Superseded (2026-07-30)*: it describes the retired rail/mini-rail chrome and a
dropped `prototype` viewer mode, and says "do not implement against it". Two
in-repo comments still point at it as canon —
`designs/arxa-studio/ui/common/design_viewer.html:25` ("Canon markup:
canvas-redesign-contract.md §3") and `mini_panel.html:16` ("v.miniPanel shape
(canvas-redesign-contract.md §1/§3)"). Those pointers are stale and are part of
the docs slice below.

## The request, and what the evidence changed about it

The ask was: *make live mode in the flows panel work like tapping Continue on the
auth screen and advancing to the linked screen; stop duplicating what the
prototype lens already does; give each lens its own hover behaviour.*

Three findings reshaped it.

### 1. Flow-linked navigation already exists

`~/.arxa/projects/portalo/design/surfaces/auth.html:2` states it in its own
header comment: *"the primary CTA is the flow edge (next.to = home)"*. Line 22:

```html
<a class="auth-provider" href="/build/screens/{{ next.to if next else 'portalo.home' }}{{ pqs }}"
```

Every interactive surface is already wired this way — `product.html:41`,
`cart.html:42`, `checkout.html:36`, `account.html:18` — and `splash.html:4` /
`startup.html:5` auto-advance to `next.to` via `<meta http-equiv="refresh">` when
not `still`. Tapping Continue *already* navigates to the flow-linked screen,
inside a live tile and inside the proto lens, as a plain `<a href>` with zero JS.

So "make flow mode follow the flow" is not new machinery. The navigation works.

### 2. Flow triggers are prose, and only *sometimes* name an element

`~/.arxa/projects/portalo/intake/flows.json` edges carry `{from, to, trigger,
action}`. All nine edges are `action: "push"`. The triggers:

```
flow-onboarding   splash   -> startup    "App launch"
                  startup  -> auth       "Kits loaded"
                  auth     -> home       "continue"
flow-browse-buy   home     -> checkout   "Category tile"
                  checkout -> category   "continue"
                  category -> product    "Product card"
                  product  -> cart       "Add to bag, then review bag"
                  cart     -> orders     "Checkout"
flow-account      home     -> account    "Account tab"
                  account  -> orders     "Order history"
```

Most triggers *do* name something element-like (`"continue"`, `"Category tile"`,
`"Checkout"`, `"Account tab"`), and `auth.html:24` carries
`data-el="button:Continue"` — so `"continue"` fuzzy-matches its element well.
But `"App launch"`, `"Kits loaded"` and `"Add to bag, then review bag"` name an
event or a two-step narration, not an element.

So: **there is no *declared* element→edge join, and the trigger is an unreliable
proxy for one.** Hence the decision below — an explicit `element` field as the
join, with fuzzy trigger matching as the fallback that happens to cover most of
this file.

> **Correction (recorded deliberately).** An earlier revision of this plan
> claimed the `auth → home` trigger was `"Sign-in success"` with
> `action: "system"`, and that the requested example did not exist in the data.
> That was wrong on both counts — it came from reading a *compressed* dump of
> flows.json that dropped most of its content, instead of opening the file. The
> requested example is authored exactly as described. Two things that followed
> from the bad read are also void: there are no `action: "system"` edges, and
> splash/startup auto-advance comes from `<meta http-equiv="refresh">` in the
> surface templates, not from an edge action.

### 3. The real defect: `nextEdge` is not scoped by flow

`designs/arxa-studio/services/repositories/project_repository.js:46-57`:

```js
export const nextEdge = (screenId) => {
  try {
    for (const f of flows()) {
      for (const e of f.edges ?? []) {
        if (e.from === screenId) return { ...e, flow: f.id, flowName: f.name };
      }
    }
  } catch { /* no project overlaid — no flow chrome */ }
  return null;
};
```

**First match wins across all flows.** `portalo.home` is in both
`flow-browse-buy` (`→ checkout`) and `flow-account` (`→ account`); whichever
flow appears first in flows.json silently wins. `build_facade.js:301` calls it
as `proj.nextEdge(surface)` with no flow context.

This is the load-bearing finding. **Live mode in the views lens is not merely
redundant with the proto lens — it is unsound**, because the views lens has no
row and therefore no way to disambiguate which edge a screen advances along. It
navigates a guessed edge. The flows lens is the only surface where `next` is
well-defined, because the row *is* the disambiguator.

That reframes the task from "remove a duplicate feature" to "remove a wrong one,
and make the remaining one correct."

Note `nextEdge` already returns `flow: f.id` — the edge knows its flow. It simply
cannot be *asked* for a specific one. The fix is a second parameter.

## Decisions (from the grill)

| # | Question | Decision |
|---|---|---|
| 1 | What moves on tap? | **The row's active tile moves.** Tile content unchanged; viewer state gains `?flow=<flowId>&step=<screenId>`; server round-trip + morph swap so the iframe grid survives. |
| 2 | `action: "system"` edges | **Leave auto-advance as-is.** `splash`/`startup` already self-advance via `<meta refresh>`; `auth → home` is `system` but has a Continue button hrefing to `next.to`, so it already works. Zero diff. |
| 3 | Element→edge join | **Add an optional `element` field to flow edges as the primary join, with fuzzy `trigger`→`data-el` matching as the fallback** when `element` is absent. |

On decision 3: fuzzy matching alone was flagged as failing on the requester's own
example (`"Sign-in success"` does not match `"button:Continue"`). The explicit
`element` field covers exactly that case; fuzzy covers the edges whose trigger
already names its element (`"continue"`, `"Checkout"`, `"Account tab"`,
`"Order history"`, `"Category tile"`, `"Product card"`). Both, not either.

## Lens contract after this change

| Lens | Tiles? | Hover toolbar |
|---|---|---|
| **views** | yes, flat grid | pin · inspect · add-to-flow. **No interactive mode** — `nextEdge` cannot be resolved without a row. |
| **flows** | yes, per-row chain | pin · inspect · **flow mode** · move ← → · remove-from-flow |
| **proto** | **no** — one `deviceChrome` iframe | none; its controls live in the mini panel bar + composer filmstrip |

`design_viewer.html:87-95` renders `protoStage(v)` as a single stage, not tiles.
"Each panel manages its own hover" therefore yields **two** toolbars, not three.
This is called out explicitly so a later reader does not invent a third.

Today a single `tileTools(v, s, row, first, last)` macro serves both views and
flows, branching internally. It splits.

## The iframe boundary, and why row-advance is still buildable

This nearly sank decision 1 and is the least obvious constraint in the whole
change, so it is written down rather than rediscovered.

The tap happens **inside an iframe**. `screen_stub_view.html:1-9` renders a
standalone `<!doctype html>` document; the viewer tile is a separate browsing
context. A child document cannot move the parent's flow-row marker by ordinary
means, and ADR-0002 forbids custom client-side JS — a boundary the `design lint`
gate actively enforces ("lint clean: no custom client-side JS"). `hx-boost` on
the stub body (`screen_stub_view.html:39`) makes in-frame clicks a boosted swap
*within the iframe*, which is precisely not what decision 1 asks for.

The escape is the **named island**, which ADR-0002 permits and which
`assets/vendor/inspect.js` already uses for exactly this crossing:

1. it intercepts the click and suppresses navigation;
2. `fetch('/design/chat/context/element', …)` posts the change to the server;
3. `window.parent.htmx.ajax('GET', p.location.pathname + p.location.search, …)`
   re-renders the parent from its own URL, since the change is session state.

`tools/probe-inspect.mjs` measures the result: the chip appears in the parent
composer with **20/20 iframes surviving and 0 re-navigations**. That is the
proof the pattern moves parent state without destroying the grid.

Flow-walk therefore follows the same shape: an armed island in the stub
intercepts a click on an element that matches a flow edge, suppresses the
in-frame navigation, posts the new step, and triggers the parent re-swap.

**This is not free, and an earlier draft of this plan understated it.** ADR-0002
(`skills/arxa-designer/docs/adr/0002-zero-custom-client-js-boundary.md`) ends
its amendment section with: *"A new runtime enters only as a new named, vendored,
documented island amending this ADR."* A flow-walk island is a **new** island, so
it requires an ADR-0002 amendment — the same ceremony the media (2026-07-31) and
map (2026-08-01) islands went through. It is a sanctioned *kind* of change, not a
free one.

Two further costs, both confirmed against source:

- **`?flow=` / `?step=` do not ride for free.** The viewer route reads a FIXED
  param list — `prototype_viewmodel.js`: `{bg, inspect, live, mode, screen, vp}`.
  Anything new must be added there explicitly.
- **Canon currently says the flows lens is NOT navigable.**
  `DESIGN-ARCHITECTURE.md:83,94,105` frames flows as "a projection of the registry
  plus the edges", tiles joined by "pure-CSS connectors… zero JS measurement",
  with navigability living only in proto ("navigating each entry's `route`").
  Making flows walkable contradicts that framing, so DESIGN-ARCHITECTURE.md's
  output-triad section is a required edit, not an optional one.

Cheaper fallback if that proves too costly: put the advance affordance in the
tile chrome (parent document) instead of inside the screen. It needs no island
at all, but it is not "tapping Continue" — so it is the fallback, not the plan.

## Slices

1. **Per-lens hover toolbars** — split `tileTools` in
   `designs/arxa-studio/ui/common/design_viewer.html`. Drop the live/flow tool
   from the views branch entirely.
2. **Rename live → flow mode** — `v.live` → flow/step state, `liveHref` /
   `liveCloseHref`, `.is-live`, `dv-live-close`, i18n keys
   `viewer.live|liveAria|liveClose|liveCloseAria`, and the `play` icon → a
   different name from the existing lucide-style set.
3. **Scope `nextEdge` by flow** — `nextEdge(screenId, flowId = null)`; thread
   `flowId` from viewer state through `build_facade.js:301`. Add `step` to the
   viewer state the control hrefs echo (`setViewer`, `build_facade.js:308`).
4. **Flow edge `element` field** — optional, joins to existing `data-el` values.
   Touches the intake schema/generator, `arxa/lib/emit_structure.dart`
   validation (flows.json edges over registry ids), the `arxa-story-mapper`
   skill that authors flows, and the portalo fixtures.
   **Fixtures are generated — edit the seed and re-run the generator, never the
   fixture.**
5. **Update the arxa mechanisms** — the real list, from the canon audit:
   - `skills/arxa-designer/DESIGN-ARCHITECTURE.md` §output-triad — the
     "projection, never navigable" framing (lines 83, 94, 105).
   - `skills/arxa-designer/docs/adr/0002-zero-custom-client-js-boundary.md` —
     an amendment for the flow-walk island.
   - `designs/arxa-studio/ui/common/_integration_viewer.md` — the `v` contract.
   - `docs/arxa-system-map.md` §5 "viewer: one SSOT" — the mermaid currently
     annotates proto's edges as clickable nav and flows' as not.
   - `skills/arxa-story-mapper` — it authors flows; the `element` field is new.
   - **Stale pointers to retire:** `design_viewer.html:25` and
     `mini_panel.html:16` both cite the superseded canvas-redesign-contract.
   - `docs/INDEX.md` needs nothing — it is a pure directory index.
6. **Red-first proof** — see below.

## Verification

Each behaviour change needs a check that goes red when reverted:

- **views lens ships no interactive tool** — assert the rendered views-lens tile
  toolbar has no flow-mode control.
- **`nextEdge` is flow-scoped** — a unit test that `portalo.home` resolves to
  `portalo.checkout` under `flow-browse-buy` and `portalo.account` under
  `flow-account`. Drop the `flowId` argument and it must go red. Same shape as
  the `gate_runner` `ctx.project` pass-through test.
- **the row advances without destroying the grid** — extend the iframe-survival
  assertion already proven in `tools/probe-inspect.mjs` (20/20 iframes survive a
  pin, 0 re-navigations).

Full suite before commit: `dart analyze` · `design lint` on studio **and**
portalo · design selftest · `dart test` · all four probes.

## Flagged, not fixed

`flow-browse-buy` runs `home → checkout → category → product → cart → orders`.
Checkout before category is almost certainly a seed authoring bug. Out of scope
here; fixing it means editing the seed and regenerating, and it changes what the
flows lens renders, which would confound the verification above.
