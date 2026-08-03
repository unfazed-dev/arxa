# Boosted MPA navigation

Navigation uses the Boosted MPA pattern: every Surface is a real URL serving a full page; `<body hx-boost hx-sync="this:replace">` converts links to body swaps with a race guard; `globalViewTransitions:true` via meta config animates swaps with zero JS — cross-document view transitions do not fire under boost, so same-document VT via config is the no-JS path. The server branches full-page vs Named Fragment on the `HX-Request` header (with `Vary: HX-Request`); head merging via the head-support extension; `hx-preserve` Preserve Islands (mini-player) survive boosted navigation (`moveBefore`; idiomorph as fallback). Considered and rejected: plain MPA + cross-document VT (full reloads kill Preserve Islands; cross-doc VT unshipped in Firefox), fragment-shell SPA (deep-link/back-button fragility, most moving parts per artifact).

**Amendment (2026-08-03) — what `globalViewTransitions:true` costs, and the
state-write rule.** The config above is written as a pure win. It has one sharp
edge, and it cost a real bug, so it is recorded rather than left to be
rediscovered.

`globalViewTransitions:true` wraps EVERY htmx swap in
`document.startViewTransition` — not just boosted navigations. A view
transition snapshots the page as a tree of named elements plus one ROOT
snapshot holding everything unnamed. So an element swapped **without its own
`view-transition-name` is captured in the root snapshot, and the browser
cross-fades the whole document.** A 340px→410px panel resize therefore
animated the entire app; users read it as the page reloading itself.

`hx-swap="none"` does NOT suppress this. The transition rides the swap
*cycle*, not the swap *style* — measured: with `swap: 'none'` htmx still
started one transition and still fired `htmx:beforeSwap`. The modifier that
actually suppresses it is `transition:false`, which composes with any swap
style: `swap: 'none transition:false'`.

The rule that follows, in both directions:

- A request that only **writes state**, where the client has already applied
  the result (an island that set the final width/position/scroll before
  committing), must not swap. Use `hx-swap="none transition:false"` — there is
  nothing to render and nothing to animate.
- A request that genuinely **re-renders a region** either gives that region its
  own `view-transition-name` (so only it animates — `.panel-composer` does
  this) or accepts that the whole page cross-fades. There is no third option;
  an unnamed swapped region is a full-page fade by construction.

Corollary for islands (ADR-0002): an island that has already mutated the DOM
must commit with a non-swapping request. Asking the server to re-render what
the island just rendered is both a wasted round trip and, under this config, a
visible full-page flash.

Regression cover: `appbox design probe panel-resize` counts
`document.startViewTransition` calls across a drag-release and fails if any
fire. Note that a node-identity check does NOT catch this — morph preserves
nodes either way, so the transition counter is the load-bearing assertion.
(The check began life in `tools/probe-panel-resize.mjs`, retired to
`archives/tooling-pre-dart/tools/studio-probes/`; see
`docs/probes-capability-map.md`.)
