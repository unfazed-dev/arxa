# The app architecture contract

The prototype you build is a **typed input to a build pipeline**, not a picture
of one. This file defines the layer you *author*; everything else downstream is
derived from it.

Read [`DESIGN-ARCHITECTURE.md`](../DESIGN-ARCHITECTURE.md) first — it is the
binding contract for the data spine and the motion vocabulary. This file adds
the layers the pipeline consumes.

## Three layers, one direction

```
AUTHORED      models/screens_model/registry.json   ← you write this, by hand
                       ↓
DERIVED       ui/views/**  +  app.routes.js        ← follows the registry
                       ↓
GENERATED     structure.json                        ← the freeze emits it
```

**The arrow never reverses.** `structure.json` is generated *from* the registry,
never inferred from filenames and never hand-edited. A structure inferred from
the tree is a structure that agrees with itself and with nothing else — it will
pass every check and still be wrong.

## 1. The registry — `models/screens_model/registry.json`

One entry per surface. This is the SSOT for what the app contains.

```json
{
  "id":      "train.library",
  "label":   "Training Library",
  "surface": "train_shell_training_library_view",
  "shell":   "train",
  "comp":    "TrainLibrary",
  "roles":   ["coach"],
  "route":   "/library"
}
```

| key | required | meaning |
|---|---|---|
| `id` | yes | stable dotted identifier, `<shell>.<short>`. Never renamed once shipped. |
| `label` | yes | human title, shown in UI |
| `surface` | yes | the surface file's identity — **or `null`** |
| `shell` | yes | which shell group this belongs to (the id's first segment) |
| `comp` | yes | component name for the scaffolder |
| `roles` | no | audience gate; absent = everyone |
| `route` | no | the surface's URL path (`/<shell>/<short>` by convention; detail views parameterize — `shop.product` → `/product/:id`). Absent = derive from id. |
| `requiresAuth` | no | truthy = the compiled route table guards this route |
| `tab` | no | `true` = bottom-tab membership in the built app; tab order = registry order |
| `kits` | no | kit dir names from `config/kit-registry.json` (`kits[].dir`) — the kit modules the surface's built app will use |

`kits`, `requiresAuth`, and `tab` are the sanctioned optional extensions to
this contract. `kits` is an array of kit dir names (e.g. `"kits": ["maps",
"payments"]`) declaring which kit modules the surface's built app will use;
the emitter validates the names against `config/kit-registry.json` and
threads them into `structure.json` for the scaffolder and builder. Declare it
**only when the surface genuinely needs the module in the built app** — a
login view → `auth`, a checkout → `payments`, a map → `maps`. Never
decorative: a declared kit is a promise the builder must wire and the client
must often supply credentials for. See
[`kit-catalog.md`](kit-catalog.md). `requiresAuth` and `tab` are route-table
inputs: the scaffolder compiles one go_router-shaped table from registry +
flows — `route` becomes the path, flow edges the typed ops, `requiresAuth`
plus `system` edges the guards, `tab` flags the tab shell.

No other keys. The reference producer also carries a `phase` key on every entry;
**nothing downstream consumes it**, so it is deliberately not part of this
contract. Do not add speculative keys — a key nothing reads is a key nothing
validates.

### `surface: null` **is** the exclusion

There is no separate exclusions file and there must never be one. A surface that
should not be built sets `surface: null` and stays in the registry with its
`label` and `id` intact.

**Why this matters:** in the reference project, entries with `surface: null`
were silently dropped from the frozen input — **46% of the registry vanished
with no warning**. Two lists of what exists means one of them is wrong and
nothing says which. One list, one nullable field, and every check can see the
whole population.

### Flows — data over the registry (optional)

The registry's output is a triad — views / flows / proto — three
switchable lenses over this one registry, never three artifacts (binding
contract: [`../DESIGN-ARCHITECTURE.md`](../DESIGN-ARCHITECTURE.md) "The output
triad"). The flows lens is a **thin data layer**, not an authoring surface:
journeys are arrays of `{from, to, trigger, action}` edges keyed by registry
ids — `action` typed `push` (default) | `replace` | `back` | `modal` |
`system`, a `system` edge becoming a route guard downstream. Flows are linear
chains (≤1 outgoing edge per view per flow); a view may belong to several
flows. Intake derives drafts (`provenance: inferred`) when answers carry
none; confirming flips provenance. Edges travel through the data spine (seed
→ fixture → repository → facade) like any other content and render by a
server component or named island — never bespoke per-flow markup, never
a separate file format. Flow-level metadata (`id`, `name`, `persona`,
`provenance`) is allowed; the edge endpoints are always registry ids. The
freeze threads the array into `structure.json` as an optional top-level
`flows` array — absent means no flows lens, which is valid for small
artifacts.

### `?embed=1` bare render mode

The stub view renderer (`screen_stub_view.tsx`) supports `?embed=1`: a
chromeless render (no nav, no tag, no max-width) for viewer tiles. The
inspect island is conditionally included when `inspect=1` is also present;
`still=1` freezes the tile (no auto-advance), and `live=1` renders the same
stub minus the still frame — the viewer's select (live-in-place) swaps a
tile's iframe from `still=1` to `live=1`.

### Undo/redo contract

Two server-side session stacks back the undo/redo buttons: `canvas` (flow
edits — move/add/remove — replayed as project `flows.json` file writes, plus
view pin/unpin) and `chat` (design-change messages +
checkpoints). Each entry is self-reversing — it carries enough data to undo
and redo in both directions. The `canvas` stack is driven by the floating
controller's undo/redo pair; the `chat` stack by the composer's. Element-
context changes write element-scoped checkpoints (before/after on the element,
element-level revert), independent of both stacks.

## 2. Surfaces — `ui/views/<shell>/<short>/`

```
ui/views/<shell>/<short>/
├── <short>_view.tsx         the view component (default export + Named Fragment exports)
└── <short>_viewmodel.js     co-located; the only place logic lives
```

A shell with many surfaces may add one subgrouping level —
`ui/views/<shell>/<subgroup>/<short>/` (e.g. `stage_shell/proj/home/`). The
subgroup is the shell's own organization, not a second registry concept.

Shell-level surfaces sit one level up:
`ui/views/<shell>/<shell>_view.tsx` + `<shell>_viewmodel.js`.

Widgets place at the narrowest scope that covers all their consumers; the
include graph (imports + fragment refs — `buildIncludeGraph`) is the only
authority, checked in both directions:

| scope | design medium | build medium |
|---|---|---|
| cross-shell (2+ shells) | `ui/widgets/common/<group>/` | `lib/ui/widgets/common/<group>/` |
| everything else (one feature) | `ui/widgets/<app>_<feature>_widgets/` | `lib/ui/widgets/<app>_<feature>_widgets/` |

**Two tiers, not three.** This law is read off the exemplar
(`kit/showcase_app/lib/ui/widgets/`), which is the structure contract, not an
example. `ui/common/widgets/`, `ui/views/<shell>/shared/widgets/` and
`<surface>/widgets/` are **illegal** — they do not exist in the exemplar. A
widget with a single surface consumer stays in its feature's widgets folder;
there is no per-surface tier to demote it to. Promotion to `common/<group>/` is
earned by a second *shell* consumer, proven by the include graph in both
directions.

Bare `<shell>/widgets/` is illegal. Empty tiers are never created
speculatively.

Every widgets folder carries a `widgets.dart` barrel exporting by full package
URI. Full anatomy: [`showcase-anatomy.md`](showcase-anatomy.md).

### Every surface stamps its inspect identity

```js
export const surfaceId = 'train.library';
export const inspectAttrs = {
  screenId: 'train.library',        // registry screen id
  surfaceId: 'train.library',       // this surface
  nodeId: 'anatomy:view.body',      // anatomy-node id
};
```

**Identity is stamped at emit time, never inferred at runtime** — the same
principle as Flutter's `--track-widget-creation`. The triple
**(screenId, surfaceId, anatomy-node id)** is derived from registry ids and is
mandatory on **every** emitted surface, shells included. In the DOM the
triple is spelled `data-inspect-view` / `data-inspect-surface` /
`data-inspect-widget` (the Q-v2-5 rename from `-screen`/`-node`, landed 2026-08-16 with the v2 emit — the probe reads the new spelling), and its presence is
mechanically enforced:
`arxa/lib/probes/studio/probe_inspect.dart` (section 18) dual-renders each
design view `?abxShell=legacy` vs `?abxShell=anatomy` against the running
server, strips the three attributes before the structural diff (the stamp is
the only licensed delta), and asserts every stamped node id on the anatomy
side against the registry vocabulary — an unstamped anatomy render is a
failure, and an off-vocabulary or incomplete triple is a failure. The legacy
side is deliberately unstamped and reads as a skip (N/A-unstamped), never a
pass and never a failure — stamping arrives with each view's anatomy cutover
(Q13 parallel-run).

The anatomy-node vocabulary is CLOSED, not open: the valid ids are exactly
those in `skills/arxa-scaffolder/kind-resolution.registry.json#/anatomyNodes/vocabulary`
(ratified at registry v1.2.0; Dart spells this slot `anatomyNodeId`, JS spells
it `nodeId` — one slot, two spellings). `anatomy:view.body` above is not an
illustrative sample of an open namespace; the vocabulary is closed, and as of
registry v1.3.0 it holds two members — `anatomy:view.body` (a view's own body
subtree) and `anatomy:shell.surface` (the shell-level surface a shell
contributes one level up, ratified to distinguish a shell's frame from the
leaf sharing its screenId). The registry, not this sentence, is the authority
on the member list.
New node ids are added there deliberately, with a version bump, exactly like
widget kinds — never invented at design time.

It is the join between the registry and the tree. Without it the pipeline
matches surfaces to registry entries by *filename convention*, which held for
21 of 37 surfaces in the reference project and silently lost the rest.

Studio inspect mode reads the triple **only** — hover tint, tags, and both icon
buttons key off it, with zero DOM heuristics. That is what lets inspect mode
survive regeneration by construction, so never emit a surface without the
triple "just for now", and never let a class name or DOM position stand in
for it.

Stamp it while designing. Back-filling it after the fact means guessing which
entry a file was meant to be — that is the same inference the export exists to
replace. Details: [`delta-runs.md`](delta-runs.md) §4.

### The app-shell roster is law

Every arxa design — no exceptions — declares these surfaces in its
app-level shell (the shell whose surfaces route at top level, registry ids
`app.*`):

| id | what it is |
|---|---|
| `app.splash` | the branded splash view |
| `app.startup` | the startup/loading view |
| `app.unknown` | the unknown-route (404) view |
| `app.access` | the sign-in gate — required **iff** any registry surface carries `requiresAuth` |

Each must be a real surface (`surface` set, viewmodel declaring the
`surfaceId`) — a `surface: null` roster entry routes to nothing and does not
satisfy the law. The freeze enforces this: `arxa emit structure` fails
naming each missing mandated surface, and the structure gate mirrors the
same check, so a design without the roster cannot freeze.

## 3. Routes — `app.routes.js`

Exports two things:

```js
export default [
  ['GET',  '/',              shell.page],
  ['GET',  '/library',       library.page],
  ['POST', '/library/pick',  library.pick],
];

export const shellRoots = {
  train:   '/',
  account: '/account',
};
```

- `GET` returns a rendered fragment or view; `POST` mutates then returns the
  updated fragment. No other verbs.
- **`shellRoots` is required and must be non-empty.** It names the landing route
  of each shell. The scaffolder cannot derive it — a shell whose root is unknown
  gets an invented one.

## 4. Services and models

```
services/
├── repositories/     read fixtures; the DB-swap seam
└── facades/          compose repositories for a viewmodel
models/
└── <x>_model/
    ├── <x>_seed.json        the SSOT you edit
    └── <x>_fixtures.json    generated from seed — never hand-edited
```

Viewmodels talk to **facades**, never to repositories or fixture files
directly. That indirection is what lets the scaffolded app swap a fixture for a
real backend without touching a single viewmodel.

Fixtures are **provenance, not shape**: generated from seed so that a change to
the seed propagates, and so nothing silently drifts into a fixture that the seed
does not justify.

## The checks this contract enables

Because the registry is authored and `surfaceId` is explicit, these are all
mechanical — and each one **can fail**, which is the point:

| check | fails when |
|---|---|
| registry parses | malformed JSON, missing required key |
| surface join | a viewmodel's `surfaceId` matches no registry entry |
| coverage | a registry entry with a non-null `surface` has no directory |
| orphan | a surface directory no entry declares |
| app-shell roster | `app.splash`/`app.startup`/`app.unknown` missing (or `surface: null`), or `app.access` missing while a surface carries `requiresAuth` |
| `shellRoots` | empty, or names a shell absent from the registry |
| ladder | a surface never rendered at an active rung |
| flows join | a `flows` edge's `from`/`to` matches no registry entry |

## Do not

- Do not hand-edit `structure.json`. It is generated.
- Do not add an exclusions list. `surface: null` is the exclusion.
- Do not omit `surfaceId` "because the filename is obvious". Obvious to you is
  inference to the pipeline.
- Do not let a viewmodel import a repository directly.
- Do not edit a `*_fixtures.json`. Edit the seed and regenerate.
