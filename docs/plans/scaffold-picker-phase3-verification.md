# scaffold.picker — Phase 3 verification (lint + lens + live routes)

All evidence below was taken against a **correctly launched design server**:

```
dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319
```

run from the worktree root
(`.kimi-code/worktrees/scaffold-shell-worktree`).

## 0. Measurement hazard that invalidated an earlier round

Two distinct traps produced false evidence earlier in this phase. Both are worth
knowing because both *look like passes*:

1. **Wrong server.** `appbox serve` is the app/API server; `appbox design serve`
   is the design server. `appbox serve` 404s every design surface, and because
   404 bodies are uniform, a six-state sweep against it returns *byte-identical
   results for every state* — which reads exactly like a state-binding bug. An
   earlier reported table ("23333 B identical across six states, 5 `undefined`
   each") was this artifact and is formally superseded by §2.
2. **Wrong tree.** Bash runs in the worktree; the context-mode sandbox runs in
   the main repo checkout. The main repo has no `picker_view.html` at all, so
   any sandbox command using a *relative* path silently measured a different
   tree. All commands here use absolute paths or an explicit `cd` to the
   worktree.

The design server also loads its route table **at boot**, so newly added routes
404 until it is restarted.

## 1. Lint — exit 0

```
dart run appboxd/bin/appbox.dart design lint designs/appbox-studio   # exit 0
lint clean: no custom client-side JS in .../designs/appbox-studio
widget/panel gate clean: W1–W6 in .../designs/appbox-studio
```

The prior W4 failure (`picker_view.html: mounts _panel.html`, not one of the
five panel roles) was fixed by switching to the shared `sh.panels(c)`
composition rather than mounting the partial directly.

## 2. Six read states — 0 `undefined`, all differentiate

| state | bytes | `undefined` |
|---|---|---|
| success | 82702 | 0 |
| empty | 80944 | 0 |
| loading | 27416 | 0 |
| error | 28004 | 0 |
| notentitled | 81233 | 0 |
| signedout | 81207 | 0 |

Root cause of the earlier `undefined` tokens was the shim's
`const bag = Object.assign(...); bag.c = bag` self-reference: screen data must
be **spread at top level**, not nested under `c:`. Fixed in `3b5aeae`.

State tokens are lowercase canonical (`notentitled`, `signedout`) — `1647f67`.

## 3. Lens viewport ladder — 3 rungs, 0 problems, exit 0

```
lens shoot compact (390px):   ok
lens shoot medium (744px):    ok
lens shoot expanded (1280px): ok
lens shoot: 3 rung(s), 0 problem(s)
```

`lens shoot` fails on console errors or horizontal overflow; none occurred.

## 4. Mutation routes — live, 200, 0 `undefined`

> **Conditional — read before trusting this section.** These four routes exist
> **only in an uncommitted working-tree edit** to `routes.scaffold.js` (a
> chrome-integration file, see Lane note). In the committed tree all four POSTs
> **404**. Neither `design lint` nor the lens ladder catches that, because
> neither exercises a POST — this is precisely the §0 "looks like a pass" class.
> Everything below is verified *with the unlanded spine edit applied*.
>
> The method is also **not ratified**: chrome-integration proposed
> `GET /scaffold/add?kit=`; I implemented **POST with a form body** and told
> them. If they land the GET form instead, the view's `<form method="post">`
> elements break and this section must be re-measured.

All mutations are **POST with a form body** (`kit=<id>`); the kit id never
travels in the query string from the view.

| route | export | status | fragment root |
|---|---|---|---|
| `POST /scaffold/add` | `picker.add` | 200 | `#picker-grid` |
| `POST /scaffold/remove` | `picker.remove` | 200 | `#picker-grid` |
| `POST /scaffold/remove/confirm` | `picker.removeConfirm` | 200 | `#panels` (grid nested) |
| `POST /scaffold/remove/cancel` | `picker.cancelRemove` | 200 | `#picker-grid` |

`cancelRemove` must be a **server route**, not a link back to `/scaffold`:
clearing `session.pendingRemove` is what ends the confirm. Re-rendering the page
would leave it set and re-show the dialog forever (`4d0ece8`).

### `removeConfirm` precedence — measured, not assumed

`session.pendingRemove` **wins when set**; `?kit=` is consulted only when it is
absent.

- fresh session `?kit=auth` → 65342 B; `?kit=payments` → 64393 B (so `kit` *is*
  read)
- with `pendingRemove=auth` set, `?kit=payments` → 65342 B (the pending kit
  wins)

The two agree in every real flow. An earlier comment in `routes.scaffold.js`
stated this precedence backwards and has been corrected.

## 5. Known gap — confirm dialog is not laddered

The confirm dialog is reachable only via POST, and `lens shoot` navigates by
GET, so the dialog layout is **not** covered by the 3-rung pass in §3. "3 rungs,
0 problems" refers to the picker grid only. Laddering the dialog needs either a
GET-addressable state param or a CDP click step; neither exists today.

## 6. Unowned route — CORRECTED

An earlier revision of this section claimed the scaffold surfaces "run the
shared composer disabled" and that nothing references `/scaffold/messages`.
**Both claims were wrong.** chrome-integration supplied the rendered markup and
I re-measured; the corrected facts:

- The composer renders **live** on `/scaffold`, with a live `textarea`:
  ```html
  <form class="composer" id="composer" method="post" action="/scaffold/messages"
        hx-post="/scaffold/messages" hx-target="#panels" hx-swap="morph:outerHTML">
  ```
- `POST /scaffold/messages` returns **404**. Measured, not inferred.
- The path string is supplied by **my** file: `scaffold_facade.js:205` sets
  `composerAction: '/scaffold/messages'`, with a `needs-route:` comment I wrote
  myself and then failed to recall.
- `ui/views/main_shell/scaffold/_shared.html:95` mounts `composerPanel(c)`
  unconditionally, so the surface is chrome-integration's; the value is mine.

**Why the original claim was unsound:** I grepped `ui/` for the literal
`/scaffold/messages`. The template reads `{{ c.composerAction }}`, so a
facade-computed action can never match a literal-path grep. The method could
not have detected the defect it was used to rule out. The same blind spot
applies to the selftest, which scans template *source*: no rendered form action
is checked anywhere today.

The disposition (gate the render vs. wire a handler) is a product call with the
lead — see §6a. Nothing here is actionable by me unilaterally.

## 6a. Input to the disposition — the compose column is a fixed grid track

First stated here as an unverified inference. I had *not* read the desktop
areas block — I inferred the track position from the mobile row order and a
prose comment, which is the same "source that cannot settle the claim" error
corrected in §6. Now read verbatim and settled:

```css
grid-template-areas:
  "header  header  header"
  "compose main    activity"
  "footer  footer  footer";
grid-template-columns: minmax(240px, 280px) 1fr minmax(280px, 340px);
```

- `compose` is the **first** track: `minmax(240px, 280px)`. Confirmed, not inferred.
- The area is carried by `.panels-scaffold > .panel-composer` (line 52–53).
- `.panel-composer` is emitted by `cp.open` (`PID = 'panel-composer'`,
  `composer_panel.html:32/68`) — i.e. from **inside** the `composerPanel` macro.
- Live check: `.panel-composer` is PRESENT on both `/scaffold` and
  `/scaffold/run`, ordered `panel-composer > panel-main > panel-activity`.

Consequence, now determined rather than predicted: explicit grid tracks are
always created regardless of occupancy, and this track's `minmax()` **minimum
is a fixed 240 px**. Gating the whole `composerPanel` removes the only element
carrying `grid-area: compose`, so both scaffold screens keep a ≥240 px empty
first column at desktop, collapsing only at the mobile stack (line 69).

Gating only the field (`cm.field(c)`) keeps `cp.open`'s `.panel-composer` with
its thread and chips, so the column stays populated. That is the surgical shape.

Scope of the remaining uncertainty, stated precisely: the track geometry is
settled by the CSS and the emitter is settled by the live render; what has
**not** been done is a screenshot of the gated variant, so visual judgment about
whether a thread-without-field column reads as broken is still open.

## Lane note — the unlanded edit, preserved verbatim

The **four** route tuples in §4 are an edit to `routes.scaffold.js`, which
belongs to chrome-integration. It was made to get the mutations testable and has
been reported to them for accept-or-revert; it should not land in the Phase 3
commit unacknowledged.

It deliberately does **not** register `POST /scaffold/messages`. Note that the
*reason* recorded here originally ("no owner") was wrong — see the correction in
§6. The route is still unregistered and still 404s; what changed is that this is
now a known live defect awaiting a product call, not a route that was correctly
left out.

Because this worktree is shared with concurrent sessions and the edit is
uncommitted, the exact tuples are recorded here so they survive a clean:

```js
// in designs/appbox-studio/ui/views/main_shell/scaffold/routes.scaffold.js,
// immediately after: ['GET', '/scaffold/panel/size/:panel/:size', picker.panelSize],
['POST', '/scaffold/add',            picker.add],
['POST', '/scaffold/remove',         picker.remove],
['POST', '/scaffold/remove/confirm', picker.removeConfirm],
['POST', '/scaffold/remove/cancel',  picker.cancelRemove],
```

`removeConfirm` is the one route that also reads `?kit=` (the facade emits
`confirmHref` with it), so a single route serves both entry paths; see the
precedence measurement in §4. `cancelRemove` must stay a server route for the
reason given in §4.
