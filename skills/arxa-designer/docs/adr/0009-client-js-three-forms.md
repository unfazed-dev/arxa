# Client JS in three legal forms, categorized and gated

Date: 2026-08-18 · supersedes the zero-custom-client-JS law of ADR-0002 (that
law's lint survives as the inline-handler + resolution ban).

## Context

ADR-0002 banned every custom client-side JavaScript outside named vendored
islands. That law bought lintability and honesty — but at the cost of the
entire interaction/motion surface: no local UI state framework, no scroll
choreography library, no per-artifact wiring. Real commissions (the energize
landing replica of coffee-tech.com) demanded GSAP-class motion and
Alpine-class state, and the workaround du jour was either CSS-only contortions
or another amendment. The owner amended the contract rather than keep paying
that tax — portfolio-general, not project-shaped.

## Decision

The backbone stays **server-rendered htmx**: URL in, HTML out; every artifact
crawlable, lens-capturable, degradable without JS. On top of that, client
JavaScript is legal in exactly **three forms**:

1. **Categorized vendored libraries** — `runtime/vendor/`, SRI-pinned in
   `manifest.json`. Every manifest row carries a **category** naming its
   role: `hypermedia` (htmx), `state-framework` (Alpine + hx-alpine-compat),
   `motion-framework` (GSAP + ScrollTrigger + SplitText), `rich-media`
   (model-viewer, rive, dotlottie, three, leaflet), `reactive-primitive`
   (alien-signals), `data-viz` (none yet). Adding a package inside an
   existing category is a vendor-fetch row; adding a CATEGORY is an
   ADR-level decision. The manifest is the whole truth — a library with no
   row does not exist.
2. **First-party islands** — the ADR-0002 shape, unchanged: named, scoped,
   no globals, documented HTML contract, why-this-exists header
   (canvas.js, drag.js, flowwalk.js, reveal.js, tabs_island.js, …).
3. **Artifact app modules** — `assets/app/*.js`, authored per artifact,
   wiring vendored libraries into markup (choreography, bootstrapping).
   Same island discipline: the file must exist, carry the why-header, and
   load as `<script src="/assets/app/<name>.js">` which the lint resolves.

**Still banned**: inline event handlers (`onclick=`, `hx-on:`); `js:`-
prefixed hx-vals/headers; `[expr]` trigger filters; any `<script>` that
resolves to neither vendor manifest nor app module nor
`type="application/json"` island config; **flow state in client JS** —
state honesty: if losing it breaks a flow, it must live in the viewmodel,
the URL, or the server session. Ephemeral UI state (menu open, tab index,
hover) is the client's job.

**Weight ceiling (opt-in)**: a commission may declare a per-artifact client-JS
ceiling. Machine copy: `client-js.json` at the artifact root with
`{"ceilingKb": N}`. The lint sums the vendor .js + app modules the HTML
actually references (the same narrowing eject performs) and fails over the
ceiling. Absent file = no ceiling (zero-JS remains valid, never mandated).

## Consequences

- The lint gate: rule 1 widened (app-module src is legal), plus app-module
  existence + header checks, plus the ceiling check. The selftest gains the
  `app-module` mutation (a ghost module reference must fail).
- MVVM/scaffolder contract untouched: client JS is design simulation; flow
  state stays server-side, so transliteration to Flutter is unchanged.
- Site-kind artifacts (eject = production) get SRI + narrowed vendor + the
  ceiling — the perf discipline the zero-JS law gave by accident, restored
  deliberately and per commission.
- `vendor-fetch` stamps the category column; `SRI.md` carries it.

## Considered and rejected

- **Client-rendered SPA mode** (React/Svelte islands as a fourth form):
  rejected — no current surface needs it; a component-graph artifact breaks
  the scaffolder join and the crawlability backbone. Recorded as the door
  that reopens via a new category + ADR when a real surface demands it.
- **Motion via CSS scroll-driven timelines only**: kept for simple cases,
  insufficient for SplitText-class choreography; GSAP is now MIT-free (all
  plugins public since the Webflow acquisition), so the real engine is also
  the cheapest one.
- **_hyperscript / Stimulus / petite-vue** as the state layer: Alpine won on
  the official htmx-4 compat extension (settle-phase init, morph state
  carry, history serialization), community size, and SRI-pinnable CDN build.
