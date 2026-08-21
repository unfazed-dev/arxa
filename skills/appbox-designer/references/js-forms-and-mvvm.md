# JS Forms and MVVM Backbone

The design stage of the appbox pipeline. Every artifact is a Hono + htmx
MVVM app whose **backbone stays server-rendered** — URL in, HTML out, always
crawlable and lens-capturable. Client JavaScript is legal in exactly **three
forms** (ADR-0009): **categorized vendored libraries** (runtime/vendor/:
htmx, Alpine, GSAP, <model-viewer>, rive, three, leaflet… — SRI-pinned in
manifest.json, every row carrying a category: hypermedia, state-framework,
motion-framework, rich-media, data-viz, reactive-primitive); **first-party
islands** (named, scoped, no-globals data-attribute modules with a
why-this-exists header: canvas.js, drag.js, inspect.js…); and **artifact app
modules** (assets/app/*.js — per-artifact authored wiring that connects
vendored libraries to markup; same island discipline: named, headered,
lint-resolved). Still banned and linted: inline event handlers, scripts that
resolve to nothing, flow state living only in client JS — if losing it breaks
a flow, it belongs in the viewmodel, the URL, or the server. A commission may
declare a per-artifact JS weight ceiling (client-js.json); the lint enforces
it over what the HTML actually loads. The MVVM structure is what the
scaffolder later emits as Flutter — client JS is design simulation, never
flow state — which is why the prototype can carry structure rather than
pixels.
