# Keeping iframes, media players, and JS islands alive across htmx swaps

Research date: 2026-08-02. Scope: htmx 2.x (current stable ~2.0.x). htmx 4 is a separate, still-experimental
project (`four.htmx.org`) with built-in morph swaps — **not** applicable to a 2.x codebase; noted only where it
changes the calculus for a future migration.

Target system: server-rendered htmx 2.x design tool, zero hand-written client JS, vendored "island" init modules
under `/assets/vendor/` (`drag.js`, `canvas.js`, `inspect.js`, third-party web components), `allowEval:false`,
`allowScriptTags:false`. Fragments swap `outerHTML` and currently blow away ~20 iframes + all island state.

---

## 1. `hx-preserve` — exact semantics

Source: [htmx.org/attributes/hx-preserve](https://htmx.org/attributes/hx-preserve/)

Quoted verbatim:

> The `hx-preserve` attribute allows you to keep an element unchanged during HTML replacement. Elements with
> `hx-preserve` set are preserved by `id` when htmx updates any ancestor element. **You must set an unchanging
> `id` on elements for `hx-preserve` to work. The response requires an element with the same `id`**, but its
> type and other attributes are ignored.

Answering the sub-questions directly:

- **Does it require an `id`?** Yes — mandatory, and it must be stable across requests. `hx-preserve` matches
  old-DOM to new-DOM purely by `id`.
- **Must the id appear in the response?** Yes — "The response requires an element with the same `id`." If the
  response fragment doesn't include a placeholder element with the matching `id`, preservation does not occur
  (the mechanism has nothing to splice back into). Practically: you keep a same-`id` stub/placeholder in every
  fragment you render, even if its own content is thrown away.
- **What happens if absent from the response?** The docs don't spell out a fallback explicitly, but the
  implementation is a swap-time DOM operation keyed on the old node's `id` being found in the *new* content;
  if there's no matching `id` node in the response, there is nothing to reattach to and the old element is
  simply removed along with the rest of the replaced subtree (implementation confirmed narratively via the
  `hx-swap-oob` note below — preservation is a relocation operation, not an "opt the node out of the diff"
  operation).

Additional documented notes (verbatim, from same page):

> Some elements cannot unfortunately be preserved properly, such as `<input type="text">` (focus and caret
> position are lost), **iframes or certain types of videos**. To tackle some of these cases we recommend the
> [morphdom extension](https://github.com/bigskysoftware/htmx-extensions/blob/main/src/morphdom-swap/README.md),
> which does a more elaborate DOM reconciliation.

> `hx-preserve` can cause elements to be removed from their current location and relocated to a new location
> when swapping in a partial/oob response.

> Can be used on the inside content of a `hx-swap-oob` element.

**This is the official htmx position, stated plainly: iframes are on the explicit list of things `hx-preserve`
does not handle correctly.** This is not a community inference — it's in the primary docs.

Corroborating GitHub history:
- [`bigskysoftware/htmx#695` — "hx-preserve does not work with iframes and input elements"](https://github.com/bigskysoftware/htmx/issues/695)
  (opened Nov 2021, closed as won't-fix/known-limitation): reporter shows a `hx-preserve` spinner working fine
  but an iframe in the identical position reloading on every swap.
- [`bigskysoftware/htmx#3370` — "Jam.dev Iframe Issue"](https://github.com/bigskysoftware/htmx/issues/3370)
  (opened Jul 2025, still open as of this research): a third-party iframe injected into the DOM causes htmx's
  `swapInnerHTML` cleanup loop to hang/crash because the library's node-removal walk chokes on an iframe it
  can't safely tear down — the reporter's workaround is to special-case-skip the iframe node by `id` in the
  cleanup loop. This is independent evidence (2025, not the 2021 report) that htmx's core swap machinery and
  iframes are an ongoing friction point, not a one-off legacy bug.

---

## 2. THE CRITICAL QUESTION: does `hx-preserve` reload an iframe on reparent/reorder?

**Yes — and this is not htmx-specific, it's a fundamental, spec-mandated browser behavior. `hx-preserve` (and
any plain DOM `removeChild`+`insertBefore`/`appendChild` reparenting) reloads an iframe. This is confirmed by
primary sources, not just anecdote, and it is *not* meaningfully browser-dependent — every engine implements
the same spec text.**

### The mechanism, from the WHATWG HTML spec

[html.spec.whatwg.org/multipage/iframe-embed-object.html#the-iframe-element](https://html.spec.whatwg.org/multipage/iframe-embed-object.html#the-iframe-element):

> The `iframe` HTML element **post-connection steps**, given insertedNode, are:
> 1. If insertedNode has a `sandbox` attribute, then parse the sandboxing directive...
> 2. **Create a new child navigable for insertedNode.**
> 3. Process the `iframe` attributes for insertedNode, with *initialInsertion* set to true.
>
> The `iframe` HTML element **removing steps**, given removedNode, are to **destroy a child navigable given
> removedNode**. This happens without any `unload` events firing (the element's content document is [discarded]).

Read literally: every time an `<iframe>` node is *inserted* into the document — including a re-insertion caused
by moving it — the browser runs "create a new child navigable" (i.e., spins up a fresh browsing context and
navigates it to `src`/`srcdoc`). Every time it is *removed* — including the removal that precedes a move — the
browser destroys the existing navigable outright, silently, with no unload event. There is no spec carve-out
for "this removal is just the first half of a move, so don't destroy state."

### Why an ordinary DOM move (`insertBefore`/`appendChild` on an already-attached node) triggers both

This is where the DOM spec closes the loop. The [DOM Standard](https://dom.spec.whatwg.org/#concept-node-insert)
defines an explicit new primitive, `Element.moveBefore()`, whose entire purpose is to be the *exception* to
normal move semantics:

> `node.moveBefore(movedNode, child)` — Moves, **without first removing**, movedNode into node after child...
> **This method preserves state associated with movedNode.**

The existence of `moveBefore()` and its framing ("without first removing... preserves state") is itself the
proof that the *ordinary* move path (`appendChild`/`insertBefore` on a node that already has a parent) works by
first removing the node (invoking removing steps — for an iframe, navigable destruction) and then re-inserting
it (invoking insertion/post-connection steps — for an iframe, navigable creation + navigation). `hx-preserve`'s
own documented mechanism ("can cause elements to be removed from their current location and relocated to a new
location") is exactly this remove-then-insert pattern, so it hits the same spec path.

### Is this browser-dependent?

**No — the reload-on-move behavior is universal and long-standing** across Chrome, Firefox, and Safari; it
follows directly from the spec text above, which all engines implement (this is why `moveBefore()` had to be
invented as new, opt-in platform surface rather than a bug fix). What *is* browser-dependent, as of Aug 2026, is
the **fix**:

- `Element.moveBefore()` — ships in **Chrome/Edge 133+** (Jan 2025) and **Firefox 144+**; **not supported in
  Safari** as of this writing (caniuse: [Element API: moveBefore](https://caniuse.com/mdn-api_element_movebefore),
  ~70% global usage, Safari column all "Not supported" through the latest tracked version). This is the single
  weakest point of coverage for a "ship it now" design — a Safari user gets zero benefit from any moveBefore-based
  workaround.
- The htmx-adjacent [Idiomorph](https://github.com/bigskysoftware/idiomorph) DOM-diffing library added a
  ["two pass" mode in v0.4.0 (Dec 2024)](https://github.com/bigskysoftware/idiomorph) that explicitly "uses the
  new `moveBefore()` API if it is available" to reattach elements with stable IDs without destroying them —
  i.e., the htmx ecosystem's own tooling had to build a feature-detected fallback specifically because plain
  DOM reparenting (what `hx-preserve` and naive morphing both do) breaks iframe/video/`<input>` state. Where
  `moveBefore()` isn't available, Idiomorph falls back to remove+reinsert, i.e., the iframe still reloads.

### Practical implication for a drag-to-reorder / move-left/move-right tile UI

`hx-preserve` **is not viable** as the mechanism for reordering tiles that contain iframes, on any browser,
without an explicit `moveBefore()`-based path — and even then, Safari has no such path today. Reordering tiles
via a full DOM-position change of the iframe node (which is what "drag to position 3" fundamentally means) will
reload the iframe in every current browser unless you either (a) never actually move the iframe element itself,
or (b) route the move through `moveBefore()` with a plain-DOM-move fallback path that accepts the reload as a
degraded-but-functional Safari experience.

---

## 3. Island re-initialisation lifecycle — canonical hook and idempotency

Source: [htmx.org/events](https://htmx.org/events/), [htmx.org/docs/#events](https://htmx.org/docs/#events)

### The events, in firing order for a swap

1. `htmx:beforeSwap` — fires before the swap; `detail.shouldSwap`/`detail.isError` can be mutated here to alter
   swap behavior. Not for init — content isn't in the DOM yet.
2. `htmx:beforeCleanupElement` — fires "before htmx disables an element or removes it from the DOM." **This is
   the teardown hook**, paired 1:1 conceptually with init: `detail.elt` is the element about to be discarded.
3. `htmx:afterSwap` — "triggered after new content has been swapped into the DOM." Content is in the DOM but
   not yet settled (CSS transition/settle delay window still open).
4. `htmx:load` — **"triggered when a new node is loaded into the DOM by htmx… also triggered when htmx is
   first initialized, with the document body as the target."** `detail.elt` is the newly added element.
5. `htmx:afterSettle` — after settle delay completes (transitions finished, `settle:`/`swap:` modifiers honored).

### Canonical hook: `htmx:load` via `htmx.onLoad()`

The docs are explicit and give this as *the* pattern:

> Using the `htmx:load` event to initialize content is so common that htmx provides a helper function:
> ```js
> htmx.onLoad(function(target) {
>     myJavascriptLib.init(target);
> });
> ```
> This does the same thing as [listening to `htmx:load` directly], but is a little cleaner.

And the worked example (Sortable.js) makes the scoping rule explicit — **scan `target`/`evt.detail.elt`, not
`document`**, so you only (re)initialize what's new:

```js
htmx.onLoad(function(content) {
    var sortables = content.querySelectorAll(".sortable");
    for (var i = 0; i < sortables.length; i++) {
        new Sortable(sortables[i], { animation: 150 });
    }
});
```

`htmx.onLoad` fires once at initial page load (body as target) and once per subsequent swap (swapped element as
target) — this is why it's the single correct hook for "initialize any new components in this content," rather
than `afterSwap`/`afterSettle` (correct DOM timing, but no built-in helper and less idiomatic) or `beforeSwap`
(too early — no DOM yet).

### Idempotency pattern (community-standard, not from official docs but consistently recommended in
2025-era practitioner writeups on morph-swap idempotency)

```js
htmx.onLoad(function (content) {
  content.querySelectorAll('[data-widget]').forEach(initWidget);
});
function initWidget(el) {
  if (el.dataset.initialized) return;   // idempotency guard
  el.dataset.initialized = '1';
  myLib.mount(el);
}
```

The guard matters more, not less, once any morph-style swap (Idiomorph/morphdom extensions) is introduced,
because morphing means *surviving* nodes can still pass back through `htmx:load`/`htmx.onLoad` on the ancestor
that got morphed, even though the leaf node itself was never removed and re-inserted — so "was this exact
node newly created" cannot be inferred from "did an ancestor swap happen." A `data-*` sentinel checked at the
leaf is the standard defense.

### Cleanup pairing

`htmx:beforeCleanupElement` is the documented counterpart for teardown — "triggered before htmx disables an
element or removes it from the DOM," with `detail.elt` the element about to go away. The idiomatic pattern is
to attach any external resources (event listeners not owned by the DOM node, timers, WebSocket handles, drag
libraries' internal registries) in the `htmx.onLoad` init and release them in a `htmx:beforeCleanupElement`
listener scoped the same way, so morph-driven partial removals and full outerHTML replacements both clean up
correctly.

---

## 4. Patterns for state that must outlive a swap

What practitioners and the docs converge on, roughly most-to-least robust:

1. **Never put the stateful node inside the swap target at all — fixed shell, narrow swap zones.** The most
   commonly recommended pattern (echoed across htmx docs' own "Preserving Content During A Swap" section, and
   consistently in community writeups): architect the page so iframes/players/canvas-with-state live as
   siblings outside the fragment that gets swapped, and only the chrome/controls around them are swap targets.
   htmx docs frame this directly under [AJAX → Out of Band Swaps → "Preserving Content During A Swap"](https://htmx.org/docs/#oob_swaps):
   > If there is content that you wish to be preserved across swaps (e.g. a video player that you wish to
   > remain playing even if a swap occurs) you can use the `hx-preserve` attribute...
   — but given Section 1/2's findings, for iframes specifically this recommendation should be read as "keep it
   *out of the swapped subtree in the first place*," with `hx-preserve` reserved for non-iframe/non-video DOM
   (badges, counters, decorative state) where it actually works.
2. **`hx-swap-oob` to route updates to a small number of long-lived, addressable elements** rather than
   re-rendering a whole region that happens to contain an iframe. If a tile's *chrome* (title, menu) needs to
   update but its iframe body doesn't, target the chrome's own `id` with an OOB swap and never touch the tile's
   outer wrapper.
3. **Persistent nodes rendered as siblings of the swap target, addressed independently.** For a tile grid with
   reorderable iframe tiles, this typically means: the *layout/ordering* is server state expressed as CSS order
   / grid-area / a data attribute driving `order`, not DOM position — so "reordering" a tile is a CSS-only
   change pushed via a narrow OOB swap to a `style`/`class` attribute, and the iframe's actual DOM node is
   never removed or reinserted. This sidesteps Section 2 entirely: the iframe never gets its removing/insertion
   steps re-run because it's never actually moved in the tree, only visually reflowed.
4. **`moveBefore()`-based reordering (Chrome/Edge/Firefox only, 2025+)** for cases where true DOM-order change
   is unavoidable (e.g., document/accessibility order must match visual order, not just CSS `order`). Requires
   a feature-detected fallback (regular move, accepting reload) for Safari.
5. **morphdom-swap / Idiomorph extensions** for finer-grained reconciliation than stock outerHTML replace — but
   per Section 1, htmx's own docs only recommend this to "tackle *some* of these cases," not as a full fix for
   iframes; Idiomorph's two-pass `moveBefore()` mode helps only where the browser supports the API.

---

## 5. Web components / custom elements with htmx

Source: [htmx.org/docs/#web-components](https://htmx.org/docs/#web-components), [htmx.org/examples/web-components](https://htmx.org/examples/web-components/)

- **`connectedCallback` re-runs whenever the custom element is (re)connected to the document** — this is
  standard Custom Elements v1 behavior, not htmx-specific, and follows the same insertion-steps mechanism
  discussed in Section 2: a plain DOM move disconnects then reconnects the element, so `connectedCallback`
  fires again on move just as an iframe's navigable gets recreated on move. Custom elements are *not*
  automatically exempt from this — if the component's `connectedCallback` does expensive setup (attaches
  shadow DOM, opens a socket, etc.) and you don't guard it, a reorder will silently redo that setup.
- **htmx does not know about your web component's internals by default**, per the docs:
  > By default, HTMX doesn't know anything about your web components, and won't see anything inside their
  > shadow DOM. Because of this, you'll need to manually tell HTMX about your component's shadow DOM by using
  > `htmx.process`.
  The documented pattern is to call `htmx.process(root)` inside `connectedCallback` after attaching shadow DOM,
  so any `hx-*` attributes rendered into the shadow root get picked up. This means: every time a shadow-DOM
  custom element reconnects (including on a reorder-triggered disconnect/reconnect), you must re-run
  `htmx.process` — htmx will not automatically discover new shadow roots on its own without this explicit call.
- **`hx-target`/selector scoping inside shadow DOM is shadow-root-local** — `host` and `global` prefixes exist
  specifically to reach outside a component's own shadow DOM, which matters for islands whose triggers need to
  affect page-level swap targets outside their own shadow boundary.
- **Interaction with morphing**: community discussion (practitioner-level, not official docs) around morph
  extensions consistently flags that morph-style reconciliation (Idiomorph/morphdom-swap) is riskier for custom
  elements that do heavy first-connect work in `connectedCallback`, because morphing tries to *reuse* nodes
  rather than replace them — meaning `connectedCallback` may run zero times on a "content update" that a naive
  developer expected to re-render the component (the opposite failure mode from outerHTML replace, where it
  reruns too often). The consistent recommendation is to move idempotent, re-runnable init logic into
  `attributeChangedCallback`/`observedAttributes` reacting to server-rendered attribute changes, keeping
  `connectedCallback` limited to one-time DOM scaffolding (shadow root creation, `htmx.process` call) — this
  mirrors the `data-initialized` guard pattern from Section 3.

---

## Confidence grading

**Overall: 🔥 (high confidence)** on the core architectural conclusion — `hx-preserve` is documented and
independently corroborated (spec text + GitHub issues, 2021 and 2025) as unsuitable for iframes, and the
DOM/HTML spec text on insertion/removal steps + the existence of `moveBefore()` gives a rigorous, non-anecdotal
explanation of *why*, that also answers the reorder question definitively: reordering an iframe via ordinary
DOM manipulation reloads it, in every current browser, unless routed through `moveBefore()`.

**🌡️ (moderate confidence)** on some of Section 3/5's synthesis — the idempotency (`data-initialized`) pattern
and the custom-element/morph interaction notes are consistent, recurring community practice rather than
something stated authoritatively in one canonical source; I did not find a single official htmx doc page that
lays out the idempotency guard as prescribed practice, only the `htmx.onLoad`/scoping mechanics it depends on.

**Weakest claim, named explicitly:** the description of "morphing causes `connectedCallback` to sometimes not
re-run, causing under-initialization" in Section 5 is drawn from aggregated/compressed web-search summaries of
practitioner discussion rather than a single citable primary source I fetched and read directly (unlike the
spec text and GitHub issues, which I read in full). Treat that specific sub-claim as directionally right but
verify against Idiomorph's actual morph algorithm before depending on it architecturally — Idiomorph's own docs
(not deeply reviewed here beyond the changelog) would be the next primary source to check.

**Not browser-dependent claim, stated precisely:** the *reload-on-move* behavior itself is not browser-dependent
(spec-mandated, universal). What *is* browser-dependent is the *availability of a fix* (`moveBefore()`): solid
in Chrome/Edge and Firefox as of 2025-2026, absent in Safari as of this research date (Aug 2026).

## Sources

- https://htmx.org/attributes/hx-preserve/
- https://htmx.org/events/
- https://htmx.org/docs/
- https://htmx.org/attributes/hx-swap/
- https://htmx.org/examples/web-components/
- https://html.spec.whatwg.org/multipage/iframe-embed-object.html#the-iframe-element
- https://dom.spec.whatwg.org/#concept-node-insert (and `moveBefore` / `ParentNode` mixin sections)
- https://github.com/bigskysoftware/htmx/issues/695
- https://github.com/bigskysoftware/htmx/issues/3370
- https://github.com/bigskysoftware/htmx-extensions/blob/main/src/morphdom-swap/README.md
- https://github.com/bigskysoftware/idiomorph (README + CHANGELOG, v0.4.0 entry)
- https://caniuse.com/mdn-api_element_movebefore
- https://four.htmx.org/ (htmx 4 preview — context only, not applicable to htmx 2.x target)
