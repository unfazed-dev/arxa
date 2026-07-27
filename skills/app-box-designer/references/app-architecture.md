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
  "tab":     "train",
  "comp":    "TrainLibrary",
  "roles":   ["coach"]
}
```

| key | required | meaning |
|---|---|---|
| `id` | yes | stable dotted identifier, `<tab>.<short>`. Never renamed once shipped. |
| `label` | yes | human title, shown in UI |
| `surface` | yes | the surface file's identity — **or `null`** |
| `tab` | yes | which shell/tab this belongs to |
| `comp` | yes | component name for the scaffolder |
| `roles` | no | audience gate; absent = everyone |

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

## 2. Surfaces — `ui/views/<shell>/<tab>/<short>/`

```
ui/views/<shell>/<tab>/<short>/
├── <short>_view.html        the template
└── <short>_viewmodel.js     co-located; the only place logic lives
```

Shell-level surfaces sit one level up:
`ui/views/<shell>/<shell>_view.html` + `<shell>_viewmodel.js`.

Shared partials go in `ui/common/`.

### Every viewmodel declares its surface

```js
export const surfaceId = 'train.library';
```

**This line is mandatory in every viewmodel and is not optional for shells.**
It is the join between the registry and the tree. Without it the pipeline
matches surfaces to registry entries by *filename convention*, which held for
21 of 37 surfaces in the reference project and silently lost the rest.

Declare it while designing. Back-filling `surfaceId` after the fact means
guessing which entry a file was meant to be — that is the same inference the
export exists to replace.

## 3. Routes — `app.routes.js`

Exports two things:

```js
export default [
  ['GET',  '/',              shell.page],
  ['GET',  '/library',       library.page],
  ['POST', '/library/pick',  library.pick],
];

export const tabRoots = {
  train:   '/',
  account: '/account',
};
```

- `GET` returns a rendered fragment or page; `POST` mutates then returns the
  updated fragment. No other verbs.
- **`tabRoots` is required and must be non-empty.** It names the landing route
  of each tab. The scaffolder cannot derive it — a tab whose root is unknown
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
| `tabRoots` | empty, or names a tab absent from the registry |
| ladder | a surface never rendered at an active rung |

## Do not

- Do not hand-edit `structure.json`. It is generated.
- Do not add an exclusions list. `surface: null` is the exclusion.
- Do not omit `surfaceId` "because the filename is obvious". Obvious to you is
  inference to the pipeline.
- Do not let a viewmodel import a repository directly.
- Do not edit a `*_fixtures.json`. Edit the seed and regenerate.
