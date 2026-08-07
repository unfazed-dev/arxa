# appbox-designer

The design-prototyping context: generates polished design artifacts (mockups, interactive prototypes, decks, mobile screens) as server-rendered hypermedia applications — htmx + CSS, no ad-hoc client-side JavaScript (named islands only) — in a genuine MVVM structure. Ported from appbox-designer (the upstream MIT project / Claude Design lineage).

## Language

_Docs deferral: `docs/VOCABULARY.md` is the project-wide sacred glossary SSOT.
This file holds only designer-skill-local terms; on any disagreement,
`docs/VOCABULARY.md` wins._

**Artifact**:
A generated design deliverable: a hypermedia app (TSX views + viewmodels + fixtures + assets) run by the Runtime. Lives in its own directory.
_Avoid_: project, website, page

**Runtime**:
The serving layer (routing, named-fragment TSX rendering via hono/jsx, sessions, cookies, timers, static) that boots an Artifact — the Dart design server at design time, an inlined Hono/Node runtime when ejected. One implementation, shared by all Artifacts.
_Avoid_: server, backend

**Serve CLI**:
The command that runs an Artifact against the Runtime (`appbox design serve <artifact-dir>`).

**Productionize**:
The command that ejects an Artifact into a self-contained, hardened Hono app (own package.json, Runtime inlined, tests, deploy notes). The Repository seam is the documented DB swap point.
_Avoid_: export, compile, build

**Surface**:
One screen of an Artifact: a view component plus its co-located ViewModel. The unit of design proof.
_Avoid_: page, route, screen (except in URL/registry contexts)

**Shell**:
The layout tier between `base.tsx` and Surfaces — section chrome (nav, tab bar, device frame) shared by a group of Surfaces. Shell also absorbs the retired Tab grouping role: the registry's `shell` field and each registry id's `<shell>.<short>` prefix name the shell group a Surface belongs to.
_Avoid_: layout (reserved for `base.tsx`), tab (legacy — say shell)

**ViewModel**:
A per-Surface server module: context builders (pure functions → view props) plus handlers (request → facade calls → full-page-vs-fragment response). Stateless by construction — rebuilt per request; re-render-and-swap replaces binding.
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
A named PascalCase export inside a Surface's view component that the Runtime can render alone for `HX-Request` swaps (`view.html#fragment` — the viewRef keeps its `.html` name for render-registry parity; `#fragment` maps to export `Fragment`). Surface-private swap targets live here, not in files.
_Avoid_: partial (that word means the shared kind)

**Partial**:
A shared `_name.tsx` component file living at its placement-law tier (`references/app-architecture.md`), imported and used across Surfaces.

**Widget Library**:
The artifact's own set of parameterized components, placed per the three-tier placement law (`references/app-architecture.md`: `ui/common/widgets/` cross-shell, `ui/views/<shell>/shared/widgets/` intra-shell, `<surface>/widgets/` per-surface), authored in the widget-library pass BEFORE any Surface is composed; Surfaces compose only from it. Seeded from `references/ui-recipes.md` (the Recipe catalog) and `starter-partials/widgets/`.
_Avoid_: widget set, UI kit (that word means a design system)

**Boosted MPA**:
The navigation architecture: every Surface is a real URL serving a full page; `hx-boost` swaps body content; the server branches full-page vs Named Fragment on `HX-Request`.

**Preserve Island**:
An `hx-preserve` element with a stable id on every page (e.g. the mini-player) that survives Boosted navigation with its live state (playing video) intact.

**State Playbook**:
The decided mechanism table: server = single truth, URL = shareable state, cookies = small prefs, session store = flows, OOB swaps = fan-out, load-polling = timers (server holds the deadline).

**Allowlisted Extension**:
An official htmx extension permitted in Artifacts — under htmx 4 `hx-ext` is gone and only `hx-sse` (v4) survives from the old set (preload/head-support were dropped). Vendored, never CDN.

**Client-JS-Free**:
The skill's boundary: zero hand-written client-side JavaScript — no `<script>` blocks, no `hx-on:*`, no `js:`-prefixed attributes, no `[expr]` trigger filters. Libraries (htmx + Allowlisted Extensions) are exempt. Enforced by `appbox design lint`; htmx 4 evaluates no attribute expressions (the v2 `allowEval:false` switch has no v4 equivalent). Named islands (vendored, enumerated in ADR-0002's islands amendment) are the only permitted extension: third-party declarative web components and first-party data-attribute init modules, all loaded from /assets/vendor/.

**Read States**:
The closed set idle / loading / error / empty / data, rendered as server-side template branches; "loading" appears client-side only as indicator CSS during requests.
