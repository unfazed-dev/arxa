# app-box-designer

The design-prototyping context: generates polished design artifacts (mockups, interactive prototypes, decks, mobile screens) as server-rendered hypermedia applications — htmx + CSS, zero custom client-side JavaScript — in a genuine MVVM structure. Ported from app-box-designer (the upstream MIT project / Claude Design lineage).

## Language

**Artifact**:
A generated design deliverable: a Hono/Node hypermedia app (templates + viewmodels + fixtures + assets) run by the Runtime. Lives in its own directory.
_Avoid_: project, website, page

**Runtime**:
The skill-vendored Hono mini-framework (routing, named-fragment templates, sessions, cookies, timers, static) that boots an Artifact. One implementation, shared by all Artifacts.
_Avoid_: server, backend

**Serve CLI**:
The command that runs an Artifact against the Runtime (`runtime/serve.mjs <artifact-dir>`).

**Productionize**:
The command that ejects an Artifact into a self-contained, hardened Hono app (own package.json, Runtime inlined, tests, deploy notes). The Repository seam is the documented DB swap point.
_Avoid_: export, compile, build

**Surface**:
One screen of an Artifact: a view template plus its co-located ViewModel. The unit of design proof.
_Avoid_: page, route, screen (except in URL/registry contexts)

**Shell**:
The layout tier between `base.html` and Surfaces — section chrome (nav, tab bar, device frame) shared by a group of Surfaces.
_Avoid_: layout (reserved for `base.html`)

**ViewModel**:
A per-Surface server module: context builders (pure functions → template data) plus handlers (request → facade calls → full-page-vs-fragment response). Stateless by construction — rebuilt per request; re-render-and-swap replaces binding.
_Avoid_: controller, presenter, handler (the file holds handlers, but the concept is ViewModel)

**Model**:
A data shape + codec under `models/`, with its Fixture beside it.

**Repository**:
Single-source gateway over one Fixture; the only data access ViewModels may touch indirectly. The Productionize swap seam.
_Avoid_: DAO, store

**Facade Service**:
Composes Repositories into view-ready state. ViewModels depend only on Facade Services, never on Repositories directly.
_Avoid_: service (bare)

**Named Fragment**:
A block inside a Surface's view template that the Runtime can render alone for `HX-Request` swaps (`view.html#fragment`). Surface-private swap targets live here, not in files.
_Avoid_: partial (that word means the shared kind)

**Partial**:
A shared `_name.html` fragment file under `ui/widgets|dialogs|bottomsheets/`, used across Surfaces.

**Boosted MPA**:
The navigation architecture: every Surface is a real URL serving a full page; `hx-boost` swaps body content; the server branches full-page vs Named Fragment on `HX-Request`.

**Preserve Island**:
An `hx-preserve` element with a stable id on every page (e.g. the mini-player) that survives Boosted navigation with its live state (playing video) intact.

**State Playbook**:
The decided mechanism table: server = single truth, URL = shareable state, cookies = small prefs, session store = flows, OOB swaps = fan-out, load-polling = timers (server holds the deadline).

**Allowlisted Extension**:
An official `htmx-ext-*` library permitted in Artifacts (preload, head-support, sse; client-side-templates allowed but not recommended). Vendored, never CDN.

**Client-JS-Free**:
The skill's boundary: zero hand-written client-side JavaScript — no `<script>` blocks, no `hx-on:*`, no `js:`-prefixed attributes, no `[expr]` trigger filters. Libraries (htmx + Allowlisted Extensions) are exempt. Enforced by `allowEval:false` + lint.

**Read States**:
The closed set idle / loading / error / empty / data, rendered as server-side template branches; "loading" appears client-side only as indicator CSS during requests.
