# app-box-app — the dogfood prototype

app_box's own desktop application, designed with `app-box-designer` from
[`docs/design/brief.md`](../../docs/design/brief.md). This is **D1** in plan 14.

```sh
node ../../skills/app-box-designer/runtime/serve.mjs . --port 4319
```

## What is authored here

| layer | file | who writes it |
|---|---|---|
| AUTHORED | `models/screens_model/registry.json` | a person, by hand |
| DERIVED | `ui/views/**`, `app.routes.js` | follows the registry |
| GENERATED | `structure.json` | the freeze emits it — not present yet |

20 registry entries: **15 buildable** (the shell plus the brief's 14 surfaces)
and **5 excluded**. Every viewmodel carries an explicit
`export const surfaceId`; nothing downstream has to infer one from a filename.

### The five excluded entries

`surface: null` **is** the exclusion — there is no exclusions file and there
must never be one. Each of these is named in the brief's journeys but is not an
independent surface, and each says why in a `_why` key:

| id | why it is not a surface |
|---|---|
| `projects.splash` | J1 launch moment — the desktop shell paints it before the app mounts |
| `projects.showcase` | J1 auto-launch — a separate generated app in its own window |
| `build.recovery` | J5 P3 recovery is a *mode* of `build.finding` |
| `settings.pair` | J7 QR pairing is a dialog over `settings.devices` |
| `ship.released` | the loop's terminal node — an outcome, not a screen |

They stay in the registry with their `id` and `label` intact so the whole
population is visible. Zero excluded on an app this size would mean someone
deleted entries instead of nulling them.

## The ladder

`targets: ["macos"]` derives **one** rung: `expanded`, 1280 × 832 — three
layout files, not five. This is pinned in `_d_meta.json`, which is
load-bearing: `shoot.mjs` falls back to *all three* rungs when nothing
resolves, and would then report failures at 390 for a width this app never
ships.

All 14 surfaces and all 29 surface-states have been rendered at that rung and
read back. A surface that has never been rendered at an active rung is not
done, whatever the markup suggests.

## Three colour languages

A colour that can mean two things states nothing (brief §5.2).

| language | value | means | may never mean |
|---|---|---|---|
| brand | `#21BFE9` → `#4E28D5` | the mark, interactive affordances | status, approval |
| gate | `#D2522B` / `#B8431F` | one of the three human gates | anything an agent can do |
| status | green / red | passed / broken | money, a missing licence |

The gate hue is taken from the brief's own loop diagram, so a reader who has
seen the flowchart already knows what orange means here. Incompleteness —
`partial`, `stubbed`, an unavailable target — is deliberately **not** a fourth
colour: it is a dashed outline, with a filled dot for *partial* and a hollow
one for *stubbed*. Borrowing the gate hue for a stub would make orange mean two
things.

The brand mark is nested frames with one filled solid, and that grammar carries
through: an outlined stage ordinal is uncommitted, a filled one is committed; a
pending gate is a frame, an approved one is not.

## Appearance

Follows macOS via `prefers-color-scheme` until the person overrides it. The
override is a server-rendered `data-theme` on `#app` — never on `<body>`, never
from script. `system` is stored explicitly, so choosing it after an override is
a real choice rather than a reset. Both grounds were designed and both were
rendered; neither is an inversion of the other.

## States

Every state the brief lists is reachable as a server-driven in-page variant —
`?state=empty`, `?state=red`, `?state=approved` — never a forked file. The
dashed **STATE** strip under each heading is a designer affordance and does not
ship.

## Verifying

```sh
../../skills/app-box-designer/selftest.sh .          # 14/14
node ../../skills/app-box-designer/runtime/lint.mjs .
node ../../skills/app-box-designer/runtime/shoot.mjs http://localhost:4319/ --artifact .
```

`--artifact .` is what makes `shoot.mjs` read the pinned ladder. Without it you
get all three rungs.

`agents/record-asset.mjs` also writes `_d_meta.json`; it was run against a copy
of this artifact to confirm it **merges** rather than rebuilds, so `ladder` and
`targets` survive. Re-check that if the tool changes — a silently dropped pin
puts the rung count back to three without anything failing.

Every `hx-post` in the markup is routed in `app.routes.js`. This is worth
checking after any edit: the htmx config sets `{"[45]..": {swap: false}}`, so an
unrouted POST returns 404 and the button simply does nothing rather than
erroring. `grep -rho 'hx-post="[^"]*"' ui` against the `POST` rows catches it.

Every mutation answers with a **Named Fragment** — `{% macro %}` in the view,
rendered as `view.html#macro`, swapped into an `hx-target` — and writes to the
session *before* it renders, so the swap and a later reload cannot disagree.
Two answer `422` instead (an unacknowledged release, a project with no client);
the head config maps 422 to `swap: true` for exactly that. The one deliberate
full reload is the theme flip, marked `refresh-exempt:` and enforced by
selftest check 11. See
[`docs/research/htmx-conformance-audit.md`](../../docs/research/htmx-conformance-audit.md)
for why that check exists.

## Known gaps

- **`structure.json` is not emitted.** `emit_structure` regex-scrapes
  `const P2_REGISTRY` out of `jsx/app.jsx` and never opens a JSON file, so it
  cannot read this registry yet. That rewire is plan 05's job; this registry
  already carries every field the emitter extracts.
- **Fixtures are illustrative, with one exception.** The seeds describe a
  plausible project (Ledgerly) so the surfaces have something to render. The
  **kit and target seeds are not illustrative** — they were read from
  [`docs/research/stub-inventory.md`](../../docs/research/stub-inventory.md):
  23 kits, 14 `stable`, and the real holes are payments (Stripe and PayPal both
  throw), auth (Apple and Google sign-in throw), maps, and `VercelTarget`.
  `settings.kits` is the surface whose whole job is honesty, so inventing its
  contents would have been the one unacceptable place to do it.
- **Session-scoped state, deliberately.** Gates, the build state and sent chat
  messages persist in the session so a swap and a later reload agree. They do
  not persist further: approval *state* belongs to pipeline state, not to a
  design artifact pretending to hold it. Restarting the server forgets it all.
- **`projects.new` does not create a project.** A valid submit hands the
  browser to the list, which is the seeded one. Inventing a row for whatever
  you typed would be a lie on the way into an app about not lying.
- **No `hx-get` or `hx-trigger` anywhere.** Nothing here polls or lazy-loads,
  and boosted links cover navigation, so neither has a job. That is an absence
  with a reason, not a gap to fill.
