# No-reload interaction in arxa + generated designs

Status: **Lever 1 landed 2026-08-02.** Levers 2 and 3 specified, not started.

Reported symptom: *"every time I interact with anything on a screen the design
viewer reloads and shows me the first screen again."* That description is
literally accurate, and the mechanism is not the one the wording suggests.

## What was actually wrong

Two candidate causes were on the table. The second was falsified before any
code was written.

**(B) — server state resets to the first screen. FALSE.**
`design_facade.js` computes `active = ordered.some(s => s.id === v.screen) ?
v.screen : ordered[0]?.id`, and `ordered[0]` is literally the first screen —
a very good match for the words. But probing the live server disproved it:
`live=portalo.home` survives an unrelated pin on a different screen, and
proto's `screen=` round-trips too. Server state is fine.

**(A) — the swap destroys every iframe. TRUE, and measured.**
50 of 68 `hx-target`s point at `#panels`, 7 more at `#design-viewer`, all with
`hx-swap="outerHTML"`. Both containers hold the screen iframes — 10 canvas
tiles plus 10 composer-tray thumbs. A replace-style swap discards those DOM
nodes, so the browser re-fetches every `src` from scratch.

The "first screen" part follows from one detail: **an iframe's `src` attribute
never changes as the user navigates inside it.** Clicking through the
prototype moves the iframe's own session history; the attribute still says
where it started. Rebuild the element and it snaps back to that starting
screen. Baseline measurement (`probe-reload.mjs`):

| | baseline |
|---|---|
| iframes surviving one pin toggle | **0 of 20** |
| iframe re-navigations from one click | **20** |
| live tile after in-frame nav + unrelated click | reverted `category` → `home` |

## Why the obvious fixes were rejected

**`hx-preserve` — rejected.** It looked ideal: already vendored, and ADR-0003
already names Preserve Islands surviving navigation via `moveBefore`. Reading
the vendored htmx 2.0.10 source confirms it really does use the
state-preserving `moveBefore` (with a `replaceChild` fallback), and a live
Chrome 150 test confirmed a reparented iframe keeps its `contentWindow` state.
It still loses, for two reasons:

1. `Element.moveBefore` is **absent in Safari** as of 2026-08. On the fallback
   path htmx uses `replaceChild` and the iframe reloads anyway — the fix would
   silently not work for a whole browser.
2. It only saves nodes you explicitly tag, and it would need ids keyed on every
   `src`-determining parameter (`vp`, `live`, `inspect`) so that a tile which
   *should* reload still does. That list is hand-maintained and silently wrong
   the day someone adds a fourth parameter.

**Idiomorph — chosen.** It is an htmx-team extension, it is browser-independent
(plain JS, no `moveBefore` dependency), and it dissolves the stale-`src` trap
for free: morph diffs `src` as an ordinary attribute, so an unchanged `src`
leaves the node untouched and a changed one reloads normally. No parameter list
to maintain.

## Lever 1 — morph swaps (LANDED)

- **Vendored `idiomorph@0.7.4`** (`dist/idiomorph-ext.min.js`, core + htmx
  extension in one file) through the sanctioned `arxa design vendor-fetch`
  path, SRI-pinned in `manifest.json` + `SRI.md`.
- **Loaded in `base.html`** after htmx, with `hx-ext="…,morph"` on `<body>`.
  Passes all four ADR-0002 lint rules unchanged — it is a vendored `<script>`
  and declarative attributes only.
- **57 swap tags** across 15 files rewritten `outerHTML` → `morph:outerHTML`,
  scoped to those targeting `#panels`/`#design-viewer`. Applied to *all* such
  tags, not just the design shell: two swap styles into the same container
  would be a latent inconsistency.
- **Stable ids** on tiles/iframes, scoped by lens. Required because
  `portalo.home` renders in three flow rows plus the views grid plus the
  filmstrip simultaneously; screen id alone would collide and morph would pair
  a thumb with a tile. Ids carry identity only, never `src` params.

Result, same probe:

| | baseline | after |
|---|---|---|
| iframes surviving one pin toggle | 0 / 20 | **20 / 20** |
| iframe re-navigations | 20 | **0** |
| live tile after in-frame nav | reverts to `home` | **stays on `category`** |

Gates: lint clean · analyze clean · selftest 24/0 (60 routes) · `dart test` 907.

### Known-open after Lever 1 (not regressions)

Open `<details>` menus and typed composer text are still lost on a swap.
Verified by stashing the templates and re-measuring: at baseline those nodes
were **destroyed** and lost the same state. Morph now keeps the node, but
faithfully applies the server's content, and the server echoes neither `open`
nor the draft text. The fix is Lever 2 — a pin toggle should not re-render the
composer at all — not a bigger hammer in Lever 1.

## Lever 2 — the draft-text half is FIXED; the refactor is NOT

Lever 2 existed to fix one concrete symptom (a half-typed message dying on
every unrelated click) and one architectural problem (an 84 KB re-render for a
pin toggle). **The symptom is fixed; the architecture is not.** Saying "Lever 2
is done" would be false.

What shipped: the composer textarea carries `hx-preserve`, which — measured,
not assumed — **does** survive a morph swap. Morph keeps the node but still
applies the server's empty value, which is why the draft died even after
Lever 1.

The trap, and why the fix is two lines rather than one: preserved
unconditionally, the textarea also survives the **send**, leaving the text the
user just sent sitting in the box ready to be sent twice. Reproduced before
shipping (thread went 4 → 6 messages while the box kept its contents). So
`hx-preserve` is dropped on exactly the render that follows a send
(`c.draftSent`). Both halves are asserted together in
`tools/probe-composer-draft.mjs`, because either alone is misleading.

Freeze needed the flag threaded explicitly: it shares the composer textarea but
renders `freezeContext`, so `sendChat`'s own flag never reached the template.

### The refactor: CLOSED, because the premise was wrong

The refactor was justified by one number — "84 KB to toggle a class" — and that
number does not survive being broken down. Measured against the live studio
(10 screens, portalo), one pin response is **84,965 bytes**:

| region | bytes | share | does a pin change it? |
|---|---|---|---|
| `#design-viewer` | 49,115 | 58% | **yes** — tile tone + `is-dim` on every tile |
| `#av-list` | 15,608 | 18% | **yes** — every screen card's active state |
| composer tray | 11,589 | 14% | **yes** — every filmstrip thumb's tone |
| chat head chips | ~150 | <1% | yes |
| everything else (panel frames, panel bar, thread, composer bar) | ~8,500 | 10% | no |

**90% of the payload is regions a pin genuinely changes.** Panel-level
retargeting — the exact plan below — therefore saves ~10%, and the "several
panels shipped for a class change" story it rested on is simply not what is on
the wire. The studio renders each screen three times (canvas tile, activity
card, filmstrip thumb) and a pin re-tones all three; that is the cost, and
moving targets around does not touch it.

The only lever with real leverage is **per-element OOB**: send just the toggled
screen's tile, card and thumb (~10 KB, an 88% cut). It was rejected on cost, not
on taste. It needs stable per-tile ids across lenses (the flows lens renders one
screen in several rows), new per-card and per-thumb ids, and a server-side
wide/narrow branch — because the 0↔1 context transition re-dims *every* tile,
so the narrow path is wrong exactly when the context becomes non-empty or
empties. Its failure mode is a silently stale tile, on localhost, in a tool
where morph already removed the symptom the user reported.

`tools/probe-no-reload.mjs` now asserts a 200 KB ceiling on the pin response —
a blow-up detector, not a target, so a future change that starts shipping whole
extra panels goes red.

**`<details>` open state: won't-fix, with the reason.** Since the viewer is
still re-fed on a pin, `dv-tool-menu` still closes. A menu closing when you
interact with something else is conventional behaviour, and the two available
fixes both cost more than the wart: `hx-preserve` freezes the menu's contents
(a stale flow list), and an idiomorph `beforeAttributeUpdated` callback means a
new client-side island under ADR-0002. What the probe asserts instead is the
thing morph actually guarantees and that *can* regress: the `<details>` **node**
survives the swap rather than being destroyed. The old line was a
`console.log` labelled `KNOWN-OPEN` — a check that could not fail, which is the
defect this whole slice exists to remove.

### Original Lever 2 specification (not implemented — see above)

Morph stops the *damage* from an 84 KB re-render; it does not stop the
re-render. A pin toggle still ships every panel over the wire.

`#panels` is coarse for a real reason worth stating: one pin genuinely changes
three disjoint regions (tile tone, composer chips, chat thread), and
re-rendering the parent is the honest way to keep them consistent. That is what
out-of-band swaps are for.

- Give each region its own target; update siblings with `hx-swap-oob`.
- Keep OOB markers **out of shared partials** — nested-OOB stripping is a
  documented htmx pitfall; `allowNestedOobSwaps=false` is the guard.
- Server echoes state it wants preserved (`open`, draft text), or those regions
  stop being re-rendered at all. Either closes the known-open items above.
- Re-run `probe-reload.mjs` after: if the payload drops and the known-open
  checks flip to true, Lever 2 is done.

Note `globalViewTransitions:true` is already set; view transitions combined
with heavy fine-grained OOB is a known-fragile combination. Measure it.

## Inspect was dead, for a reason nobody could see (FIXED)

Reported as "cannot click a component to add it to context, highlight it, or
see its details." Two defects, and the primary one was not the obvious one.

**1. The armed flag never parsed.** `screen_stub_view.html` emitted it as an
interpolated attribute *string*:

```nunjucks
<body ... {{ 'data-inspect-armed="true"' if inspect }}>
```

Nunjucks autoescapes that, so the quotes became `&#34;` and the parser read an
**unquoted** attribute value that decoded to `"true"` — quote characters
included. `inspect.js` tests `dataset.inspectArmed === 'true'`, which was
therefore false on every screen ever rendered. The island loaded, armed
nothing, and every hover/click handler returned on its first line. Now a real
conditional attribute (`{% if inspect %} data-inspect-armed="true"{% endif %}`).

Same class as the `pri.name.undefined` chip bug: a template-level rendering
defect that no test could see, because every check asked whether the *element*
was present, never whether its *value* was sane.

**2. Nothing to bind to.** `DESIGN-ARCHITECTURE.md:207` makes inspect metadata
mandatory on anything carrying `data-el` — and all 12 of portalo's surfaces
carried zero. `e.target.closest('[data-el]')` was always null. The MUST was
documented and unenforced, which is the same family as findings 8, 11 and 14: a
rule that cannot fail.

Fixed at the root, not just for portalo: **a 5th ADR-0002 lint rule**
(`design_tools.dart`). Two halves, because the first half alone was itself a
check that passes over an empty set —

- any `[data-el]` must carry `role`/`style`/`fn` (`motion` may be absent);
- **and** a file under `surfaces/` that renders interactive elements while
  carrying *no* `data-el` at all is a finding. Without this the rule was green
  on a surface that annotated nothing, which is exactly how 12 of 12 shipped.

Proven falsifiable red-first: 8 surfaces failed, the studio (the reference
implementation) stayed green, then annotation brought both to clean.

Not a defect, though it looked like one: the overlay CSS. `.inspect-outline`
lives in `viewer.css`, which the stub never loads — but `inspect.js` sets the
full styling inline (`position:fixed`, `z-index`, tint). The island is
deliberately self-contained per ADR-0002; those CSS rules are vestigial.

**Programmatic swaps had to be fixed too.** `htmx.ajax()` takes its swap style
from its options, not from `hx-swap` attributes, so five island calls
(`inspect.js` ×1, `drag.js` ×4) still hardcoded `outerHTML` and rebuilt every
iframe — pinning an element reloaded the very screen being inspected. Now
`morph:outerHTML`. Verified: pinning keeps 20/20 iframes with 0 re-navigations.

## Lever 3 — no reload *inside* generated screens (DONE)

`screen_stub_view.html` now implements ADR-0003's Boosted MPA, but only for
frames the user can actually click:

- htmx + `hx-boost="true" hx-sync="this:replace"` + `globalViewTransitions`,
  loaded under `{% if not still %}`. Static canvas tiles are
  `pointer-events: none`, so they stay script-free rather than parsing htmx 20
  times over.
- `allowEval:false` / `allowScriptTags:false` keep ADR-0002's boundary intact.
- **`pqs` now carries `inspect`.** It did not, so navigating inside an
  inspected screen dropped `?inspect=1` on the next hop and inspect died
  silently after exactly one click.
- `inspect.js`'s `ensureOverlay` now checks `isConnected`. A boosted swap
  replaces the body's children, detaching the cached overlay nodes while the
  references stay live; the old `if (outlineEl) return;` would have handed back
  an orphan forever after the first in-frame navigation.

Verified (`tools/probe-boost.mjs`): still tiles load no htmx; live tiles carry
`hx-boost`; `home → category` changes the screen while a `window` token
survives, proving a same-document swap rather than a full load.

### Original Lever 3 specification (superseded by the above)

Independent of Levers 1–2, and the half that answers "reusable in the designs
arxa-designer generates."

`screen_stub_view.html` loads **no htmx at all**, and portalo's surfaces
(`~/.arxa/projects/portalo/design/surfaces/*.html`) navigate with plain
`<a href>`. So every click inside a prototype is a full document load of the
iframe — a white flash per interaction, independent of the studio bug.

ADR-0003 already specifies the target pattern for artifacts — Boosted MPA:
every surface a real URL, `<body hx-boost hx-sync="this:replace">`,
`globalViewTransitions:true`, server branching on `HX-Request` with
`Vary: HX-Request`. The stub is the runtime host for generated screens and
should implement it:

1. Load vendored htmx (+ `morph`) in `screen_stub_view.html`.
2. `hx-boost` the stub body so in-frame navigation is a body swap.
3. Preserve the `?vp=&embed=&still=` query across boosted navigation — `pqs`
   already exists in the template and must ride along.
4. Teach the designer skill to emit this by default, so generated designs get
   it without per-project work.

Caveat to settle first: `hx-boost` on `<body>` is documented as risky
(state loss, `<template>` stripping, forced innerHTML on body) and the htmx
core team's own discussion on it is unresolved. ADR-0003 chose it deliberately;
confirm it still holds for iframe-hosted screens before propagating it to every
generated design.

**This lever edits `skills/arxa-designer/` — the verified SSOT** (the server
serves `/assets/vendor/` from there; `.kimi-code/skills/arxa-designer/` is a
gitignored byte-identical copy). Do not edit the copy.

## Reusable rule this establishes

> Anything whose state lives in the DOM rather than on the server — an iframe,
> a media element, a scroll container, an open menu — must either sit outside
> the swap target, or be reached by a morph swap. A replace-style swap of a
> container that holds one is a state-destroying operation, and it will not
> announce itself.
