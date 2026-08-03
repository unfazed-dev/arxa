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
> **only in an uncommitted working-tree edit** to `routes.scaffold.js`. In the
> committed tree all four POSTs **404**. Neither `design lint` nor the lens
> ladder catches that, because neither exercises a POST — this is precisely the
> §0 "looks like a pass" class. Everything below is verified *with the unlanded
> spine edit applied*.
>
> **Authorship — corrected.** I previously called `routes.scaffold.js` "a
> chrome-integration file" and left it unstaged on that basis. The *file* is
> theirs; the **17-line hunk is mine**, which they stated plainly: "Your
> `routes.scaffold.js` edit: keep it, don't revert. I read all 17 lines… you
> even carried the `posted-by` convention. I've told the lead that 17 lines of
> the file are yours." My disclosure had it backwards and under-claimed my own
> work — the opposite error to the over-claiming `git add` of `528ac71`, from
> the same root: attribution asserted without checking.
>
> **Substrate is backed up (both halves).** As of `docs/plans/`:
>
> | at-risk change | owner | backup | bytes |
> |---|---|---|---|
> | `_shared.html` composer guard | chrome-integration | `scaffold-composer-guard.patch` | 1791 |
> | `routes.scaffold.js` +17 routes | **mine** | `scaffold-routes.patch` | 1941 |
> | | | **live `git diff`** | **3732** |
>
> 1791 + 1941 = 3732 exactly, so coverage is total, and
> `git apply --check --reverse` passes on mine. Before this, the guard was
> patch-backed and my routes were not — a `git restore designs/` would have
> erased the substrate of every number in this section while leaving the
> composer half recoverable.
>
> Not committed: three agents share one branch (`scaffold-shell-worktree`) and
> Phase 3's commit is the lead's. A patch protects the work without pre-empting
> that call; whether the code lands stays a deliberate decision, not an
> oversight.
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
- `ui/views/main_shell/scaffold/_shared.html:113` mounts `composerPanel(c)`
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

### 6a.1 Gated variant measured — the column is populated, and "empty" was too weak

The field-only gate now exists in the working tree (`_shared.html:74`,
uncommitted). Measured against :4319, contents of
`<section class="panel panel-composer">` on each screen:

| screen | panel bytes | thread rows | `<form>` | `<textarea>` |
|---|---|---|---|---|
| `/scaffold?state=success` | 2754 | 2 | 1 | 1 |
| `/scaffold/run?state=completed` | 916 | 2 | 0 | 0 |

Run's gated column is **not** empty — it retains eyebrow `Scaffold`, ctx chips
`structure r7` / `6 kits`, and two `bt-event` rows:

- "Your design was frozen at 11 screens. Nothing below changed it."
- "Files are on disk. Nothing needs you."

Picker retains its two rows (`7 kits detected in your project`,
`Add or remove anything — nothing here is locked in.`) and still emits the form.

This corrects the framing above, in the direction that strengthens the
conclusion: gating the whole `composerPanel` would not merely leave a ≥240 px
**empty** track — it would **delete real orientation content on both screens**,
including the entirety of run's 916 B receipt. The layout argument was the weaker
of the two available arguments and I led with it.

Also settled: gating the field does not strand run's forward path — but my
first mechanism for it was inverted, and the corrected version is below
(run-screen caught this; the file citations in the original were wrong).

Measured on `/scaffold/run?state=completed`, gate active:

| `/build` occurrences | count | source |
|---|---|---|
| inside `<section class="panel panel-composer">` | 1 | `scaffold_run_facade.js:82` |
| outside it | 6 | `run_view.html:231` |
| **total on page** | **7** | |

What I originally wrote — "6×, rendering from `scaffold_run_facade.js:82`
inside `mainContent` (`_shared.html:214`)" — was wrong three ways. The count
6 belongs to the *other* source; `_shared.html` is 121 lines long so `:214`
cites nothing; and facade:82 is not in `mainContent` at all. It is an entry in
the `thread:` array (`scaffold_run_facade.js:77–84`), rendered by
`{{ thread(c) }}` at `_shared.html:73` — **inside** `composerPanel`
(macro `71–77`), one line above the field guard at `:74`. It sits in the very
916 B column measured in §6a.1 and survives only because the gate is
field-level; panel-gating would take it.

The affordance that is genuinely independent is the literal CTA at
`run_view.html:231`, inside `mainContent` (macro `214–236`) and the only
`/build` literal in that file. It is untouchable by any composer gating, and
the no-stranding conclusion rests on it alone.

(The 6× multiplicity of a single literal is unexplained — plausibly repeat
renders via the `panels` / `panelsSwap` fragment paths, but I have not
verified that and nothing here depends on it.)

Still open, and only this: pixel judgment on the gated variant. Content
occupancy is now measured, not predicted.

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

## Composer gate — live measurement (uncommitted working tree)

Gate applied at `ui/views/main_shell/scaffold/_shared.html:74` wraps the composer
**field** only, not `composerPanel(c)` (which is mounted at `:113`). Measured
against design server :4319:

| URL | `<form class="composer">` | `panel-composer` |
|---|---|---|
| `/scaffold?state=success` | `action="/scaffold/messages"` | PRESENT |
| `/scaffold/run?state=completed` | ABSENT (gated) | PRESENT |

Stranding check (run-screen's concern): the conclusion holds — the forward path
is not stranded — but see §6a.1 for the corrected mechanism. Measured split on
`/scaffold/run?state=completed`, gate active: **7** `/build` occurrences, **1**
inside `panel-composer` (from `scaffold_run_facade.js:82`, which renders via
`{{ thread(c) }}` at `_shared.html:73`, *inside* `composerPanel`) and **6**
outside it (from the literal CTA at `run_view.html:231`, inside `mainContent`,
macro `214–236`). The earlier claim here — 6× from facade:82 inside
`mainContent` at `_shared.html:214` — was wrong on count attribution, on
location, and cited a line past the end of a 121-line file. No-stranding rests
on `run_view.html:231`, which no composer gating can reach.

Picker thread rows survive the gate: `scaffold.picker.thread.detected` and
`scaffold.picker.thread.help` both render.

Unfixed by the gate: picker's own field still renders and `POST /scaffold/messages`
still returns **404**, because `scaffold_facade.js:205` sets `composerAction`
unconditionally. That line is the lead's call (task #16).

Note: `docs/plans/scaffold-composer-contract.md`, cited in coordination, does not
exist in the repo. This file holds the measurements.

## 7. Method — an absence claim needs a positive control

Adopted from run-screen; their four-failure table is in
`docs/plans/composer-action-integrity.md`. The rule:

> Before trusting a zero, show the same check finds a known-present instance.
> A check that has never once produced a hit hasn't been demonstrated capable
> of one.

This supersedes my weaker "confirm the search path exists", which catches only
the two failures where the path was fictional. It would have passed my
`/scaffold/messages` literal grep — a real search of real files that could never
match, because the template emits `{{ c.composerAction }}` and a computed value
has no literal to find. That one cost this thread the most time.

### Applied to my own live absence claim

Claim: *no lens/preview state-picker UI exists under `appboxd/lib/` (the dart
tool) or `designs/` (the design tree)* — the sweep chrome-integration relied on
to withdraw their "edit the dropdown in your UI" redirect. Scope is those two
directories; my earlier phrasing said "the repo" and overclaimed. It had never
been positive-controlled.

It took **three attempts** to build a control that discriminates. Both failures
were the rule's own subject matter:

| # | attempt | outcome |
|---|---|---|
| 1 | grep `surfaceStates` under `appbox/lib/` | 0 hits — but known-present. **No dir named `appbox`; it is `appboxd/`.** Fictional path — run-screen's failure #1/#2 |
| 2 | re-run under `appboxd/lib/` → `intake.dart:62` hits | Instrument proven for *dart identifiers*. But the claim is about `<select>` **markup** — a different instrument. Wrong-control, i.e. failure #3, committed inside the demonstration of the rule |
| 3 | control on markup literals in `.dart` | `<div`×31, `<button`×3, `<a href`×2 → proven capable of finding HTML controls in dart |

Only after attempt 3 does the zero carry information:

| check | result |
|---|---|
| `<select>` / `<option>` in `appboxd/lib/**.dart` | 0 — **meaningful**, instrument proven |
| `design_server.dart` reads a `state` param | no occurrences — it never branches on state |
| `<select>` / `<option>` in `designs/` | 0, with `type="radio"`×1 as that sweep's own control |

Verdict: the zero was **correct but undemonstrated**, and two of my three attempts
to demonstrate it were themselves unsound. Consistent with chrome-integration's
account — `?state=` is facade-driven at request time, so there is no options list
to author anywhere. That is the case for the rule, not against it: a claim I was
confident in, that happened to be true, survived on luck through two bad
instruments.

Second instance, same session: this finding nearly became a false broadcast. From
`appbox/` ≠ `appboxd/` I inferred that every lane's `appbox/lib/intake.dart:62`
citation was one character wrong, and started drafting the correction. Checked
first: this thread's docs already use `appboxd/lib/` and all three cited lines
resolve (`intake.dart:62`, `design_tools.dart:260`, `emit_structure.dart:263`).
The only two `appbox/lib` strings in `docs/plans/` are in unrelated pre-existing
files. A confident correction, aimed at teammates, built on one unverified
inference — caught by the same rule one step before sending.
