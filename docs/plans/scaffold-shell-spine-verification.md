# Scaffold shell — spine verification (behavioural, not just static)

Server used: private probe instance on `:4347` (`dart bin/appbox.dart design serve ../designs/appbox-studio --port 4347`).
Shared `:4319` loads its route table at boot, so it still 404s the new scaffold routes until someone restarts it.

## 1. Gate state: selftest 25/25, emit structure clean

`scaffold.run` and `scaffold.picker` are structurally identical in shape to the
established intake/design entries in `structure.json` (`comp` / `shellDir` /
`surface` / `viewmodel` / `deps`). `states` is not a `structure.json` field —
lens states live in `registry.json`, and both entries carry the full list
(`success | empty | loading | error | notEntitled | signedOut`).

## 2. Mutation round-trip is real (this is what static checks cannot see)

Earlier probes showed every mutation returning a byte-identical 55950 B, which
looked like "handlers bound to the wrong paths". That reading was wrong, and the
mechanism is worth recording because it produced a false alarm twice this session:

1. **No cookie jar.** The design server issues `kdh_sid` per session. Raw `fetch`
   without echoing the cookie mints a *new* session on every request, so no
   mutation can ever accumulate. With the cookie echoed the sid is stable and
   state persists.
2. **The probe kit was already chosen.** `add(auth)` is a legitimate no-op
   because `auth` is in the default seed. Identical byte counts were the correct
   answer to the question actually asked.

Re-probed with a sticky session and an *unchosen* kit — full state machine:

| step | result |
|---|---|
| `POST /scaffold/add` (`analytics`) | page 82702 → 82872 (+170 B); removable kits 4 → 5 |
| `POST /scaffold/remove` | confirm dialog appears (+729 B) |
| `POST /scaffold/remove/cancel` | back to 82872, dialog cleared |
| `POST /scaffold/remove/confirm` | page returns to 82702 baseline, kit gone |

Add / remove / cancel / confirm each mutate distinct state and the round-trip
closes exactly on the original byte count. The picker spine is genuinely wired.

## 3. Open defect: the composer is broken on *both* scaffold screens

Checked the composer action on every screen. Two different failures, two owners:

| screen | `composerAction` | source | result on submit |
|---|---|---|---|
| `/scaffold` (picker) | `/scaffold/messages` | `scaffold_facade.js:205` (hardcoded) | 404 — no such route |
| `/scaffold/run` | `""` (absent) | `scaffold_run_facade.js` never sets it | posts to itself; `/scaffold/run` is GET-only |
| `/intake/brief` | `/intake/brief/messages` | `intake_facade.js:709` — `` `${base}/messages` `` | 204 ✓ |
| `/design/freeze` | `/design/freeze/messages` | `design_facade.js:1245` | ✓ |

Established facades always scope the action to the screen. Scaffold has one
facade pointing at a path nobody routed, and one that emits no path at all.

**Re-confirmed after a clean server restart** (`pkill` + fresh `design serve`),
so neither is a stale-ESM-module artifact. Selftest re-ran 25/25 on the same
restart. Live POST results:

```
POST /scaffold/messages        404
POST /scaffold/run/messages    404
POST /scaffold/run             404   <- what action="" actually hits
POST /intake/brief/messages    204   <- established, for contrast
```

Why the selftest's "every static URL in markup resolves to a route" check passes
anyway: in the template the attribute is `{{ c.composerAction }}`, not a literal.
The rule inspects template source, so a facade-computed action is invisible to it
— the string only becomes a URL at render time.

### 3a. `/scaffold/messages` has no route

The rendered picker emits a live composer form:

```html
<form class="composer" id="composer" method="post"
      action="/scaffold/messages" hx-post="/scaffold/messages" ...>
```

There is no `/scaffold/messages` entry in `routes.scaffold.js`, so submitting the
composer 404s. Neither existing check catches it: the selftest's static-URL rule
does not follow `c.composerAction` (a facade-computed string), and the
mutation-reachability rule only walks routes that exist.

**Canon in every established shell** — the handler is the *screen viewmodel's*
`sendMessage`, and the route carries a `posted-by` comment:

```js
['POST', '/intake/brief/messages', brief.sendMessage],   // posted-by: c.composerAction (intake_facade)
['POST', '/design/chat/messages',  chat.send],           // posted-by: c.composerAction (design_facade)
```

6 established bindings follow this shape; `picker_viewmodel.js` exports no
`sendMessage`. Resolution: picker exports `sendMessage`, then this side adds the
one-line route. Until then the composer is decorative.

### 3b. `/scaffold/run` emits an empty composer action

`scaffold_run_facade.js` sets no `composerAction`, so the shared composer renders
`action=""` and posts back to `/scaffold/run`, which is GET-only. Fix mirrors
3a: run's facade sets `composerAction: '/scaffold/run/messages'`,
`run_viewmodel.js` exports `sendMessage`, this side routes it.

Note this is why a static check would not have found either one: 3a has a path
with no route, 3b has no path at all.

## 4. Who owns the composer (settled)

The composer is rendered on both scaffold screens by **`ui/views/main_shell/scaffold/_shared.html:113`** — `{{ composerPanel(c) }}`, unconditional. That
file is the scaffold shell's own composition, i.e. this lane's. Picker is right
that they don't own the composer's *presence*; they do own the action *string*
(`scaffold_facade.js:205`).

Picker's claim that "the scaffold surfaces run the shared composer disabled" is
falsified by the rendered markup. The only `disabled` in the whole composer block
is on the undo button:

```html
<form class="composer" id="composer" method="post"
      action="/scaffold/messages" hx-post="/scaffold/messages"
      hx-target="#panels" hx-swap="morph:outerHTML">
  <textarea id="composer-text" name="text" ...></textarea>
  ...<button type="button" class="ico-btn undo-btn" disabled title="Undo">
```

The form, the textarea and the submit are all live. `composer.html:44` hardcodes
`action="{{ c.composerAction }}"` with no guard, which is why "no composerAction"
yields `action=""` (run) rather than "no composer".

Their grep missed it because nothing references the literal `/scaffold/messages`
in `ui/` — the reference is the template variable `{{ c.composerAction }}`, and
the string is supplied from `services/facades/`.

**Proposed fix (pending lead's call):** gate `{{ composerPanel(c) }}` on
`c.composerAction` in `scaffold/_shared.html`, and picker drops facade line 205.
That fixes both screens at once and touches only this lane's file. Explicitly
*not* guarding shared `composer.html` — intake, design and scaffold all import
it, and the other two shells' owners aren't in this loop.

## 5. Corrections to my earlier reports

- **Retracted: the "gated states are ~81 KB vs ~55 KB" anomaly I flagged to the
  lead.** That compared full state renders against mutation *fragments*. Picker's
  corrected table (success 82702, empty 80944, loading 27416, error 28004,
  notEntitled 81233, signedOut 81207, zero `undefined`) shows no anomaly, and its
  success figure independently corroborates the 82702 measured here.
- **The mutation round-trip in §2 validated code this lane did not author.** The
  five route tuples were an uncommitted 17-line edit to `routes.scaffold.js` made
  by picker to get the mutations testable. The edit matches canon, including the
  `posted-by` comments, so it is taken as-is rather than reverted — but it is
  picker's work sitting in a spine file, and is recorded here so it does not
  enter the Phase 3 commit unattributed.

## Status

Spine green **with the composer open on both screens**. Add / remove / cancel /
confirm are genuinely wired; the composer is not. The shell is not "fully wired"
until `/scaffold/messages` and `/scaffold/run/messages` both exist.

## Composer guard — resolution (Phase 3, pre-commit)

**Decision:** guard the field on the action, not the screen. `_shared.html:74`

```
{% if c.composerAction %}{{ cm.field(c) }}{% endif %}
```

Chosen over per-screen suppression because `action=""` was a shared-widget
defect, not a `scaffold.run` defect: the field emitted an unrouted
`action=""` form for *any* facade that does not set `composerAction`.
Suppressing one screen would have left the trap armed for the next surface.

**Field is state-invariant.** Measured on the served design, pre-guard:

| state | total B | composer field B |
|---|---|---|
| pre | 26510 | 1862 |
| completed | 28656 | 1862 |
| warning | 30214 | 1862 |
| failed | 27148 | 1862 |
| blocked | 23986 | 1862 |

Identical 1862 B on all five ⇒ the guard removes a constant 1864 B
(field + newline) from `/scaffold/run`, and nothing else.

**On the 68 B discrepancy:** run-screen's reported `failed` baseline of
27216 B was stale; the true pre-guard value is 27148 B. Four of five
states reproduced to the byte, so the drift was in the recorded table,
not an effect of the guard. No state-dependence exists to explain.

**Blast radius — measured on rendered output, not inferred.** The guard
is scoped to `ui/views/main_shell/scaffold/_shared.html`, so only the
scaffold shell's composition can change; the design, intake and build
shells never load that file. Verified by fetching each surface:

| surface | route | status | `<form class="composer">` | action |
|---|---|---|---|---|
| scaffold.picker | `/scaffold` | 200 | PRESENT | `/scaffold/messages` |
| design.freeze | `/design/freeze` | 200 | PRESENT | `/design/freeze/messages` |
| intake.brief | `/intake/brief` | 200 | PRESENT | `/intake/brief/messages` |
| scaffold.run | `/scaffold/run` | 200 | **absent** | — |

No `action=""` renders anywhere. Post-guard `/scaffold/run` loses exactly
1864 B on **every** state with 0 `undefined`:

| state | pre-guard | post-guard | delta |
|---|---|---|---|
| pre | 26510 | 24646 | 1864 |
| completed | 28656 | 26792 | 1864 |
| warning | 30214 | 28350 | 1864 |
| failed | 27148 | 25284 | 1864 |
| blocked | 23986 | 22122 | 1864 |

`thread(c)` still renders on `/scaffold/run` — the screen keeps its
narrative content, it just has no input path, which is the honest
encoding of a READ surface.

**One correction to my own earlier claim:** I had written "4 of 5 facades
set `composerAction`" from a grep of `services/facades/`. At the rendered
level that is unverified for build — `build_facade.js:457,527` does set
`composerAction: '/build/messages'` and `build/loop/loop_view.html:86`
does call `cm.field(c)`, but `/build` serves the Build Monitor screen and
`build.loop` has no GET route in the swept table, so it renders nowhere I
could measure. Pre-existing and outside this change: build's render path
does not include `scaffold/_shared.html`. Flagged, not touched.

**Gate result after the guard:**
- `design lint` — clean, widget/panel gate W1–W6 clean
- `emit structure` — unchanged (write-on-diff), 38 screens, both scaffold
  screens resolve surface + viewmodel + deps
- `design selftest` — **passed 25, failed 0, skipped 0 of 25**; 65 GET
  routes swept

No new failure. run-screen's predicted 23/25 did not occur.

**Deferred (not mine to land):** promoting "every rendered
`<form class="composer">` action must resolve to a route" into the
selftest, so `action=""` is caught by machine rather than by hand.
`POST /scaffold/messages` remains unowned and unrouted — do not add it.

## Accepted from picker-screen: 4 POST tuples in routes.scaffold.js

picker-screen edited `routes.scaffold.js` (my file) to make their
mutations testable and asked that it not enter the Phase 3 commit
unacknowledged. **Reviewed and accepted as-is** — the routes are
load-bearing for `scaffold.picker`; without them all four mutations 404.

```
['POST', '/scaffold/add',            picker.add]
['POST', '/scaffold/remove',         picker.remove]
['POST', '/scaffold/remove/confirm', picker.removeConfirm]
['POST', '/scaffold/remove/cancel',  picker.cancelRemove]
```

`remove/cancel` is correctly a POST route rather than a link back to
`/scaffold`: cancelling must clear `session.pendingRemove` server-side,
and re-rendering the page would leave it set and re-show the dialog.
Notably **no** `/scaffold/messages` route was added, which is consistent
with the guard above — the composer emits no form on this shell's read
surface and picker's composer posts to the shared handler.

## For the lead, at commit time

1. `docs/plans/scaffold-shell-spine-verification.md` is **untracked** —
   `git add` it or it will not land in the Phase 3 commit.
2. Two modified files are mine to hand over:
   `ui/views/main_shell/scaffold/_shared.html` (the guard) and
   `ui/views/main_shell/scaffold/routes.scaffold.js` (picker's 4 tuples).
3. I have not committed anything, per instruction.
