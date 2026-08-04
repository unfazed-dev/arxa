# Composer action integrity

Status: proposed (owner: chrome-integration; raised by run-screen during Phase 3)

## The defect class

`ui/views/main_shell/shared/widgets/composer.html:43-45` emits the composer's
post target unconditionally, in two attributes:

```jinja
<form class="composer" id="composer" method="post" action="{{ c.composerAction }}"
      hx-post="{{ c.composerAction }}" hx-target="#panels" hx-swap="morph:outerHTML">
```

A facade that does not set `composerAction` therefore renders `action=""`, which
posts back to the current URL. On a GET-only surface that is a 404.

Two distinct failures live here, and they need different fixes:

| Failure | Cause | Example |
|---|---|---|
| `action=""` | facade sets no `composerAction` | `/scaffold/run` (scaffold_run_facade.js) |
| `action="/nowhere"` | facade sets one, no route answers it | `/scaffold` (scaffold_facade.js:205 → `POST /scaffold/messages` 404) |

Live POST sweep (chrome-integration, post-clean-restart, 65 GET routes):

```
POST /scaffold/messages       404   <- set but unrouted
POST /scaffold/run/messages   404
POST /scaffold/run            404   <- what action="" actually hits
POST /intake/brief/messages   204   <- established, for contrast
```

## Why the selftest reads green anyway

The "every static URL in markup resolves to a route" rule scans **template
source**, where the attribute is the literal string `{{ c.composerAction }}` and
never a URL. Facade-computed actions are structurally invisible to it.

This is not specific to one screen: **no** facade-computed URL on any surface is
covered today. `selftest 25/25` currently carries no information about whether
any composer works.

## Proposal

Two changes, deliberately paired. Neither is sufficient alone.

### 1. Guard the field on the action (kills `action=""`)

In `composerPanel`, or equivalently inside `field` itself:

```jinja
{% if c.composerAction %}{{ cm.field(c) }}{% endif %}
```

Makes `action=""` structurally unreachable. A facade that sets no action encodes
"this surface has no mutation" and gets no input — which is the correct rendering
for a read-only surface. `thread(c)` continues to render regardless, so panels
keep their narrative content.

**Known cost:** a *forgotten* `composerAction` now fails silently — the composer
vanishes rather than visibly breaking. This trades a loud wrong behavior for a
quiet absent one, which is why change 2 is not optional.

### 2. Assert on rendered actions, not source (kills `action="/nowhere"`)

Extend the selftest to sweep the **rendered** `<form class="composer">` action on
every screen and require it resolve to a route. This is exactly the table
chrome-integration produced by hand above; promoting it into selftest makes it
regression-proof.

Catches the picker-class defect (action set, unrouted) that the guard does not.

## Gate the field, not the panel

`composerPanel` renders two things:

```jinja
{% macro composerPanel(c) %}
  {{ thread(c) }}
  {{ cm.field(c) }}
{% endmacro %}
```

Gating the `composerPanel(c)` call therefore drops the **thread** as well as the
input, which costs each screen its narrative rows (`scaffold.run.thread.*`,
`scaffold.picker.thread.detected` / `.help`). Gate `cm.field(c)` instead.

### Retracted: the "stranding" argument for this

An earlier revision of this doc claimed gating the panel would strand
`/scaffold/run` because `scaffold_run_facade.js:82` held the screen's only
`/build` link. **That was false.** `run_view.html:231` carries a literal CTA
inside `mainContent` (macro at 214), wholly outside the composer:

```jinja
<div class="run-actions run-next">
  <a class="cta-link cta-link--main" href="/build">{{ t('scaffold.run.next.build') }}</a>
</div>
```

The completed state therefore keeps its forward path under any gating choice.

**Which `/build` lives where** (the two are often conflated):

| source | renders inside | survives field-gate | survives panel-gate |
|---|---|---|---|
| `scaffold_run_facade.js:82` (thread agent row) | `thread(c)` → `composerPanel` | yes | **no** |
| `run_view.html:231` (literal CTA) | `mainContent` (macro 214) | yes | yes |

So the facade link *is* in the gated column — it is not in `mainContent`, and it
would have been removed by panel-gating. The forward path survives regardless
only because of the independent CTA at view:231. Conclusion and mechanism have
to be kept apart here: "`/build` survives" is true, "`/build` survives because
the facade link is in `mainContent`" is false.

**The duplication is load-bearing — do not collapse it.** Calling these two
affordances redundant (as an earlier note of mine did) invites a tidy-up that
would delete one. They sit on *opposite sides of the gate boundary*: one inside
the gated column, one outside it. That separation is the only reason the forward
path survived a gating decision taken for entirely unrelated reasons. Collapsing
them to a single link would introduce the single point of failure that the
retracted stranding claim wrongly asserted already existed. If either is ever
removed, it must be the gated one, and only with the outside CTA confirmed
present by render. (Position held by run-screen; I withdraw the "redundancy"
framing.)

## Scope of the shipped guard

The `{% if c.composerAction %}` guard landed in `main_shell/scaffold/_shared.html`,
not `shared/widgets/composer.html`. That is a deliberate cross-owner sequencing
call, but it means the guard disarms the `action=""` trap **for the scaffold
shell only**. A new surface mounted in intake, design or build that forgets
`composerAction` still renders an empty action. My "guard over suppression"
argument was that suppression leaves the trap armed for the next surface; a
shell-scoped guard leaves it armed for three shells. The general property needs
the shared widget, which is the lead's to sequence.

## Two defect classes, one symptom

| class | rendered | caught by guard | caught by rendered sweep |
|---|---|---|---|
| unset action | `action=""` | yes (scaffold only) | yes |
| set but unrouted | `action="/scaffold/messages"` → POST 404 | **no** — attribute is non-empty | yes |

The guard cannot catch the second class by construction. Only the second class
is live in the tree right now (`scaffold_facade.js:205`). The rendered sweep is
therefore the load-bearing half of the fix, not cleanup.

**Design constraint on the sweep.** It must distinguish *measured zero* from
*not measured*. In the current probe table `/scaffold/run` shows "no form" (a
real measurement) and `/build/loop` shows "route 404s" (the surface never
rendered, so nothing was tested) — and both read as a dash. (The `/build/loop`
example is itself retracted as a datum — that route never existed; see "The
fourth mount" below. The design constraint it motivates survives, and the real
build surface turns out to need exactly this result class.) An unreachable
surface must fail the sweep loudly, not pass it silently. This is the same
failure that produced the stranding claim: absence of output taken as absence
of defect.

Concretely, the sweep must emit four distinct results per surface, not two:

| result | meaning | verdict |
|---|---|---|
| `routed` | form rendered, action resolves to a live route | pass |
| `no-form` | surface rendered, no composer form present | pass (measured zero) |
| `unrouted` | form rendered, action returns 404 | **fail** |
| `unreachable` | surface never rendered (route 404s) | **fail** |

`unreachable` failing is the point: a sweep that iterates rendered surfaces and
skips the ones it cannot reach will report clean over an unmeasured tree, which
is the precise bug the sweep exists to catch. Coverage must be asserted, not
assumed — the count of surfaces swept must equal the count of surfaces in the
registry, and that equality is itself an assertion.

**Where the denominator comes from (layer discipline applied to the sweep).**
The sweep is a *rendered-layer* instrument, so it is authoritative for "does
this action resolve" but **not** for "which screens exist". Its coverage
denominator must be read from the authored registry — currently 38 screens, 21
with a non-null surface — and never from enumerating what successfully
rendered. A sweep that derives its own denominator from its own output cannot
report a gap by construction: every surface it failed to reach simply leaves
the list, and 21/21 is printed over 19 measurements. That is the layer error
committed by the instrument built to catch the capability error, which is
precisely how these two axes combine when nobody is watching for both.

(Constraint raised independently by run-screen during Phase 3 review; the
`unreachable`-vs-`no-form` split above is their framing.)

## Positive control: the general rule behind four failures

Four checks failed the same way in one thread, each producing a confident zero:

| # | check | why it could not find what it ruled out |
|---|---|---|
| 1 | grep `scaffold/run_view.html` | path doesn't exist (real file is `scaffold/run/run_view.html`) |
| 2 | grep `{runtime,tools,ui}` | two of three dirs don't exist; only `ui` was searched |
| 3 | grep literal `/scaffold/messages` in `ui/` | template emits `{{ c.composerAction }}`; a computed value can't match a literal |
| 4 | probe sweep incl. `/build/loop` | **not a route** — never existed; the mount is `/build` (see "The fourth mount") |

| 5 | "no `action=""` anywhere on build" | asserted from 2 of 10 GET routes |
| 6 | "doc is 605 lines" | never measured; was 682 at the time |

Row 4 was originally filed as "real route, surface never rendered." That was
wrong: `/build/loop` is a fabricated address, inferred from the *directory*
`ui/views/main_shell/build/loop/`. It therefore belongs with rows 1 and 2, not in
a class of its own — three of the first four instances are the same error.

Rows 5 and 6 are mine, added after the fact, and they matter because they were
committed *into this document* — the one arguing that computed values must be
measured. Row 5 is a denominator error of the kind run-screen identified at
38/21: a true claim stated at a scope the evidence didn't cover. Row 6 is barer
still, a number typed because it felt about right. Neither was caught by care;
both were caught by re-running the command. That is the argument for the sweep in
one line — **the discipline that fails is the one held in a person's head, and
the fix is an instrument that runs whether or not anyone remembers to be
careful.** Six instances, four authors, one document.

"Confirm your search paths exist" catches 1, 2 and 4. Only #3 aimed at a real
file and still reported zero from an instrument structurally
incapable of a hit.

The rule that covers all four: **an absence claim requires a positive control.**
Before trusting a zero, demonstrate the same check finds a known-present
instance — grep a file where the string is known to occur, or render a surface
known to carry the form. A check that has never once produced a hit has not been
shown to be able to. Applies to greps, probe sweeps, and the rendered-action
sweep itself, where the control is: assert coverage, don't infer it from a clean
report.

## Second axis: right layer, not just a working instrument

A fifth failure in the same thread does not fit the rule above. Reading the
*emitted* `structure.json` and reporting its field names as the *authored*
`registry.json` schema used a check that worked perfectly — it searched a real
file and returned real hits. A positive control would have **passed**. The claim
was still wrong, because the artifact inspected was downstream of the artifact
the claim was about.

So there are two independent axes:

| axis | question | failure | remedy |
|---|---|---|---|
| capability | can this check produce a hit at all? | 1–4 above: false zero | positive control |
| layer | is this artifact the one the claim is about? | emitted vs authored: false hit | check at the claim's layer |

Positive control does not catch a layer error, and layer discipline does not
catch a blind instrument. Both are needed.

**"Measure, don't grep" is the wrong generalisation.** The correct layer is
determined by what the claim is about, not by a standing preference:

- Claim about *rendered output* (`action=""`, thread survival) → rendering is
  authoritative; source grep is downstream-blind. Grep failed here.
- Claim about *authored schema* (registry keys) → the authored file is
  authoritative; emitted output is downstream. Rendering would fail here.

The pipeline has a direction. Check on the same side of it as the claim.

### Not to be confused: how the *stranding* claim was produced (capability axis)

This paragraph documents failure #1, not the layer error above. The two have
different mechanisms and it matters that they aren't merged.

The stranding claim came from a grep against
`ui/views/main_shell/scaffold/run_view.html` — a path missing the `run/`
segment. The file does not exist, grep matched nothing, and the empty result was
read as "no other reference exists". That is a pure capability failure: a check
incapable of finding what it was used to rule out, reproduced by the person who
named the rule. A non-existent path and a genuinely absent string are
indistinguishable in grep output.

The layer error was the opposite: a real file, real hits, a check that could not
have been more capable — and a false conclusion anyway. Fixing the path would
have done nothing for it. Keep the remedies attached to the right failures.

The recommendation to gate the field rather than the panel stands, on the
narrative-content argument alone.

## Consequence for `/scaffold/run`

None in code, under the field-level guard. `scaffold_run_facade.js` sets no `composerAction` because the run
receipt is a frozen READ surface — the run is complete before the screen renders,
and no message sent from it has a semantic action behind it. Under change 1 the
field disappears on its own.

Rejected alternatives for this screen:

- **Mirror intake's `sendMessage` fully** (user row + agent reply from
  `repo.replies()` / `replyFallback`): requires new `scaffold.run.thread.*` keys
  across en/pl/qps-ploc, risking the green 996-key exact-parity gate mid-phase,
  to ship a canned reply fired at arbitrary input on a frozen receipt.
- **Accept and 204-discard:** a field that swallows input is worse than no field.

If the shared widget should not be touched mid-Phase-3, the interim is a
per-screen suppression of `cm.field` on `/scaffold/run`, with both changes above
applied after the Phase 3 commit.

## Denominator: verified, and one refinement

`38 screens / 21 non-null surface` checked against the **authored**
`designs/appbox-studio/models/screens_model/registry.json` (not `structure.json`,
which sits next to it and would have been the layer error). Confirmed: 38 total,
21 non-null, 17 null. Both scaffold entries carry surfaces
(`main_shell_scaffold_picker_view`, `main_shell_scaffold_run_view`).

**Refinement.** The denominator counts *screens*, but the property asserted —
"this action resolves to a route" — is a property of a rendered response, and one
screen can render from more than one return path. Source-layer check of every
`composerAction` assignment (positive control: instrument found all 6 known
sites before its zeros were trusted):

| facade | lines | note |
|---|---|---|
| `scaffold_facade.js` | 205 | one path |
| `intake_facade.js` | 709 | one path, templated `${base}` |
| `design_facade.js` | 916, 1245 | two *screens* (chat, freeze) |
| `build_facade.js` | **457, 527** | two *return paths, one screen* |

`build_facade` sets the action on two separate returns — the `noEvidence: true`
early return and the main one. Both currently emit `/build/messages`, so there is
no live state-dependence and a per-screen denominator of 21 is adequate **today**.

But (screen × return path) is the true unit of the property. A sweep that hits
one branch per screen would pass while the other branch drifts. `build_facade`
already has the shape; only the equal values make it harmless. Worth stating in
the constraint so the denominator isn't later assumed safe for a reason that has
expired.

*(Method note: the conditional-detection heuristic used here produced 2 false
positives — it matched `name ? { name } : null` and `d.panel ?? 'main'` as
branches. Inspected individually rather than trusted. A false positive is the
cheap failure; the expensive one is the false zero this control was built to
prevent.)*

## Durability: the verified state is not durable

Verified after the accidental-commit incident (`528ac71`, reverted cleanly —
this doc is absent from every reachable commit and its 313 lines are intact).
The revert was correct. What it exposed is not.

**All three agents share one worktree and one branch** (`scaffold-shell-worktree`);
`git worktree list` shows only this and `master`. So "nothing committed" — which
I reported repeatedly — was true of *my files* and false of *the branch*, which
has taken four commits from teammates during this task. In a shared branch that
distinction is the whole meaning of the phrase.

**The guard is uncommitted.** `git status` shows:

```
 M designs/appbox-studio/ui/views/main_shell/scaffold/_shared.html   <- the guard
 M designs/appbox-studio/ui/views/main_shell/scaffold/routes.scaffold.js
?? docs/plans/composer-action-integrity.md
?? docs/plans/scaffold-shell-spine-verification.md
```

Every green result in this task — selftest 25/25, uniform 1864 B delta, five
verified baselines, zero `undefined` — describes a working tree, not a commit.
The guard at `_shared.html:75` exists solely as an unstaged modification in a
directory where a teammate has already run a directory-wide `git add` once. One
`git restore designs/` or `git reset --hard` and every measurement above becomes
a description of a state no longer in the repository.

That is the same failure this document is about, moved one layer out: evidence
carefully gathered against an artifact whose existence was never checked. Here
the artifact is the fix itself.

**Line-number correction.** The guard is at `_shared.html:75`, not `:74`
(`composerPanel` opens 71, `thread(c)` is 74, guard is 75). I repeated `:74`
from a report without checking; a comment block at 52–55 shifted it. picker's
citation was the correct one.

## Unit correction: (screen × return path), and why the fan-out is safe

run-screen's correction to my `38/21` denominator is accepted and verified. The
property is of a **rendered response**, not a screen; a screen can render from
more than one return path, so the true unit is (screen × return path). An
instrument that derives its denominator from its own output cannot report a gap
by construction.

Traced the fan-out at the source layer rather than assuming it. Six assignment
sites across four facades:

| facade | line | value |
|---|---|---|
| `build_facade.js` | 457 | `/build/messages` |
| `build_facade.js` | 527 | `/build/messages` |
| `design_facade.js` | 916 | `/design/chat/messages` |
| `design_facade.js` | 1245 | `/design/freeze/messages` |
| `intake_facade.js` | 709 | `` `${base}/messages` `` |
| `scaffold_facade.js` | 205 | `/scaffold/messages` |

`build_facade` is sharper than "two return paths, one screen": `:457` sits in
the helper `emptyContext` (451) behind exported `emptyLoopContext` (492), and
`:527` in exported `loopContext` (495). Both emit the identical literal, so
there is no live state-dependence — the equal values make the duplication
harmless today, not correct by design.

**Falsified hypothesis, recorded because it was checked.** I predicted a second
live `action=""` instance outside scaffold: `showArtifact` (`build_facade:558`)
is a third exported entry point that sets no `composerAction`, and
`loop_viewmodel.js:41` renders `#panelsSwap`, which mounts `composerPanel` →
`cm.field(c)` → `action="{{ c.composerAction }}"` ungated (the guard is
scaffold-only). Checked instead of reported: `showArtifact` returns
`loopContext(...)`, so it inherits `/build/messages`. Intake is the same shape —
its `showArtifact` (`intake_facade:747`) returns `context(...)`, which sets the
action at `:709`. Delegation collapses the fan-out; no render path reaches a
composer without an action. **The prediction was wrong.**

## Route probe with an embedded positive control

The remaining half of the claim — that the scaffold target is the only unrouted
one — had never been measured for the four non-scaffold actions. POST to every
`composerAction` target on `:4319`:

```
200   /build/messages
204   /design/chat/messages
204   /design/freeze/messages
204   /intake/brief/messages
404   /scaffold/messages
404   /scaffold/run/messages
```

The control is embedded rather than run separately: four known-good routes
returning 2xx prove the instrument can detect a live route, so the two 404s are
a measurement and not a blind zero. This is the check on the same side of the
pipeline as the claim — the claim is about a *route*, and the probe exercises
routing.

## Retraction: the enumeration above committed this document's own error

I first concluded from the six-site table that class 1 (`action=""`) had no live
instance and the guard was mere hygiene. **That was false, and it argued for
dropping a verified fix at Phase 3.** Retracted in full.

The table enumerates **assignments** (`grep composerAction services/facades/*.js`).
A facade that *never assigns* cannot appear in it. The defect is an absence, so
a positive-only instrument reports a blind zero — the precise failure this
document spends 350 lines on. I ran it on myself.

The absence that mattered:

```
$ grep -c composerAction services/facades/scaffold_run_facade.js
0
```

`scaffold_run_facade.js` never appears in the six-site table, and that absence
*is* the defect. `/scaffold/run` mounts `scaffold/_shared.html` — the same
`cm.field` as picker — with no action set, so before the guard it rendered
`action=""` live. This is what the uniform **1864 B delta across run's five
states** measured: the field being removed. The guard fixed a live class-1 bug.

Correct denominator, enumerated from the **render** side (`cm.field` mounts,
where the defect is observable) rather than the assignment side:

| mount | fed by | action set? |
|---|---|---|
| `design/_shared.html:76` | `design_facade` (2 sites) | unconditional mount |
| `intake/_shared.html:235` | `intake_facade` (1 site) | unconditional mount |
| `build/loop/loop_view.html:86` | `build_facade` (2 sites) | unconditional mount |
| `scaffold/_shared.html:75` | `scaffold_facade` **and** `scaffold_run_facade` (0 sites) | guarded |

Scaffold is the only guarded mount, and it is the only one where two facades
feed one view — which is why the gap surfaced here first, not why it is unique.

**Still unmeasured, and stated as unmeasured.** The other three mounts are
unconditional. Whether any design/intake/build surface reaches one of them via a
return path that sets no action is *not* established by either instrument I ran:
the assignment grep is blind to absence, and the route probe can only probe
targets that exist. Two mounts against one or two assignment sites is not proof
of coverage. That is the sweep's job, and it is the strongest argument for
run-screen's `unreachable`-as-explicit-failure constraint.

Corrected net: **two** live defects, one per class — `scaffold_facade.js:205`
set-but-unrouted (open), and `scaffold.run` actionless (fixed by the guard,
verified). The guard is load-bearing, not hygiene.

**Tree state for the probe.** The route probe above ran against a working tree
containing picker's uncommitted `routes.scaffold.js` edit. It does not change
the two 404s — that edit never adds `/scaffold/messages` — but this document
demands tree state be stated whenever measurements are, so it is stated.

## Mount coverage, measured render-side (closes the flagged gap)

chrome-integration's denominator is exactly right: 4 `cm.field` mounts —
`design/_shared.html:76`, `intake/_shared.html:235`, `build/loop/loop_view.html:86`,
`scaffold/_shared.html:75`. Confirmed by grep over `ui/ --include=*.html`.

Their retraction is confirmed from my side: `grep -c composerAction
services/facades/scaffold_run_facade.js` → **0**, and the file exports only
`context` and `setPanelSize`. My screen was the live `action=""` instance. The
guard is load-bearing, not hygiene.

**A candidate I raised and refuted.** `design_facade.js` has 29 exports and only
2 `composerAction` sites (`:916` in `stageContext`, `:1245` in `freezeContext`) —
neither in the primary `design` export at `:32`. I read that as a probable fourth
actionless mount. Rendering refutes it: `/design` emits
`action="/design/chat/messages"`. The primary path inherits through delegation,
the same collapse chrome-integration found with `showArtifact`. I had committed
the error this document is about — reading assignment sites and inferring path
coverage — one message after naming it. Render-side caught it; source-side
would not have.

**Rendered probe, controls embedded:**

```
/design                        200  action="/design/chat/messages"
/design/freeze                 200  action="/design/freeze/messages"
/intake/brief                  200  action="/intake/brief/messages"
/scaffold                      200  action="/scaffold/messages"   (picker's 404 route)
/scaffold/run                  200  no form                       (guarded)
/scaffold/run?state=completed  200  no form                       (guarded)
/build/loop                    404  UNREACHABLE — not measured  [VOID: not a route]
/build  (+9 more GETs)         200  no form — state-unreached    [corrected]
```

The `/build/loop` row is superseded: that URL never existed, and the real mount
is `/build` plus nine sibling GETs, all 200. See "The fourth mount" for the full
ten-route table. The corrected reading is *state-unreached*, not *unreachable* —
the surface renders, but `empty()` short-circuits before the composer branch.

**Result as originally written: of 4 mounts, 3 resolved, 1 unverifiable.** That
last count was wrong for the stated reason. `loop_view.html:86` has no
GET route, so no rendered probe can reach it. Its status is *unknown*, not pass.
This is the `unreachable`-as-explicit-failure constraint arriving as a real case
rather than a hypothetical: the strongest instrument we have is blind to exactly
one of the four surfaces, and only an explicit failure keeps that visible.

## Two corrections to my own record

**1. A predicted blind spot, measured, and empty.** `git grep` cannot see
untracked files, and three `docs/plans/` files are untracked — including the two
active Phase 3 docs. So picker's directory sweep for `appbox/lib` citations had a
structural blind spot covering our own current work. I predicted a miss. Measured:
`git grep` and plain `grep` return byte-identical results; neither untracked doc
contains the string. Their claim is correct as stated.

The *method* is still unsound for reuse: any `git grep` sweep over `docs/plans/`
is systematically blind to exactly the files being actively written. It was clean
here by luck of content, not by construction. Second prediction of mine refuted by
measurement in this document — recorded rather than quietly dropped.

**2. My durability alarm was overstated and I'm downgrading it.** The test
surfaced `docs/plans/scaffold-composer-guard.patch` — untracked, 35 lines, the
guard as a diff (19 insertions, matching `git diff --stat` on the live file
exactly). So the fix is not single-copy: `git restore designs/` destroys the
working-tree edit but leaves the patch intact.

Corrected risk: the guard survives the *likely* accident (a restore/checkout) and
dies only to `git clean -fd`, which also takes both untracked docs. That is a
materially smaller exposure than "one command from losing every measurement,"
which is what I said. The recommendation stands but the severity does not — and
the hedge was already in place before I raised the alarm, which I should have
checked for before raising it.

## No detector exists for this defect class — demonstrated, not inferred

chrome-integration argues to the lead that losing the guard would silently
reintroduce a live bug "because the selftest reads template source where the
attribute is never a literal." That is correct, and it is stronger than an
argument from mechanism: **we already ran the positive control, by accident.**

Timeline from this task's own record:

| when | state | selftest |
|---|---|---|
| before the guard landed | `/scaffold/run` rendering `action=""` live | **25/25, 0 failed**, 65 GET routes swept |
| after the guard landed | field gated, `action=""` unreachable | 25/25, 0 failed |

The suite returned a perfect score with the defect live on the screen. Its score
is invariant to the presence of the bug, so it carries zero information about it —
this is measured, not predicted from how the checker works.

That converts the commit question. It is not "how likely is an accident?" but
"if the guard is lost, what notices?" — and the answer is nothing, with a control
proving it. Re-derivation from three documents assumes someone knows to look.

**Candidate detector, already written and run.** The render-side probe used above
is the missing check: fetch each composer-bearing route, extract `action` from
`<form class="composer">`, fail on empty-or-absent. It has a natural positive
control (four routes with real actions) and it distinguishes the two defect
classes — `action=""` (no facade assignment) from set-but-unrouted (assignment,
404 target) — which is exactly the distinction source-reading collapses. Offered,
not built: edits are on hold and this belongs with the sweep's owner.

## The fourth mount: `/build/loop` never existed

The remaining unknown was `loop_view.html:86`, recorded as unreachable because
`GET /build/loop` returned 404. **That URL is not a route and never was.** The
404 was an artifact of a guessed path, not a property of the surface.

The loop viewmodel is imported at `app.routes.js:4` and mounted across **14
routes at `app.routes.js:32-45`** — ten GET, four POST. Found with an instrument
given a positive control first: the same `grep -rn` locates intake's
`${base}/messages` registration (`routes.intake.js:28`) for a surface already
proven to render, so a zero would have been a measurement.

All ten GET routes probed — not the two I first sampled, which would have
over-scoped the claim on the same denominator grounds run-screen used at 38/21:

| line | route | status | bytes | composer forms |
|---|---|---|---|---|
| 32 | `/build` | 200 | 17833 | 0 |
| 33 | `/build/panel` | 200 | 17833 | 0 |
| 34 | `/build/panel/size/left/2` | 200 | 17833 | 0 |
| 36 | `/build/artifact/gate/g1` | 200 | 17833 | 0 |
| 37 | `/build/file` | 200 | 17833 | 0 |
| 38 | `/build/artifact/evidence/surfaces/viewer` | 200 | 17833 | 0 |
| 39 | `/build/screens/shell` | 200 | **2572** | 0 |
| 43 | `/build/model/m1` | 200 | 17833 | 0 |
| 44 | `/build/chips/pin` | 200 | 17833 | 0 |
| 45 | `/build/chips/unpin` | 200 | 17833 | 0 |

**10/10 reachable, 0 composer-bearing renders, 0 empty actions.**

Nine byte-identical responses are the fingerprint that twice in this thread meant
*wrong server* or *never ran* (24509 B, 23333 B). Here it is real, and the table
carries its own control: `/build/screens/shell` returns 2572 B, so the server is
live and routes do differentiate. Identical-nine is a finding, not an artifact.

Mechanism read at source rather than inferred — `empty(c, h)` short-circuits in
**every** export, not just `page`:

```js
22  export const page     = (c, h) => { const e = empty(c, h); if (e) return emptyPage(c, h, e); ...
29  export const file     = (c, h) => { const e = empty(c, h); if (e) return emptyPage(c, h, e); ...
37  export const artifact = (c, h) => { const e = empty(c, h); if (e) return emptyPage(c, h, e); ...
45  export const model    = (c, h) => { const e = empty(c, h); if (e) return emptyPage(c, h, e); ...
```

With no run fixture seeded, every GET returns `emptyPage` before reaching the
composer branch. That is why the composer count is zero everywhere.

Precise status of mount 4, which is neither "pass" nor the "unreachable" first
recorded: **all ten routes reachable; the composer-bearing state not reachable
with current fixtures.** Exercising it requires seeding run evidence, which is
build's lane. What can be said without that: no build GET renders an empty action
today, and every path that *could* reach the mount flows through `loopContext` or
`emptyContext`, both of which set `/build/messages` — including the empty-state
context at `:457`.

This is the `unreachable`-as-explicit-failure constraint earning its place. The
sweep proposed above would score build 10/10 `no-form` and report clean — while
the one state that actually renders the composer went unmeasured. The four-result
table needs a fifth row, or `no-form` needs to be conditional on the surface
having no composer *in template source* rather than none *in this render*:

| result | meaning | verdict |
|---|---|---|
| `no-form` | template has no composer at all | pass (measured zero) |
| `state-unreached` | template has a composer; this fixture never rendered it | **fail** |

Build is the concrete case that separates them: `loop_view.html:86` mounts
`composerPanel`, so `/build` is `state-unreached`, not `no-form`. Scoring it
`no-form` is exactly the silent skip the constraint exists to prevent.

**Third instance of one failure mode, now worth naming as a rule.** Within this
thread: picker searched a fictional `appbox/` (the directory is `appboxd/`) and
read 0 hits as absence; I predicted an actionless `showArtifact` from structure;
and `/build/loop` 404ed because it was never a route. All three are the same
error at different layers — **a zero from an unverified address is not a
measurement.** The positive-control rule already adopted covers the instrument;
this adds the other half: *verify the address exists before reading a zero from
it.* A 404 has two causes — no surface, or no such URL — and only one of them is
a finding.

## Mount 4 resolved, and a fourth instance of the failure mode — mine

**chrome-integration is right and my `/build/loop` finding was void.** There is no
such route. `app.routes.js:32` is `['GET','/build', buildLoop.page]`; the full
`buildLoop` table is lines 32–45 and contains no `loop` path. I derived the URL
from the *directory* `ui/views/main_shell/build/loop/` and probed it. A 404 has two
causes — no surface, or no such URL — and I reported the wrong one. My "1 of 4
unverifiable" was a fabricated address, not a finding. The conclusion "don't score
4/4" survived, but by luck, not construction.

**Corrected status of mount 4:** both build entry points set an action —
`emptyContext:457` and `loopContext:527` each set `/build/messages` (a 200 route).
Rendered `/build` emits zero composer forms and no `action=""`. So there is no
class-1 exposure on either branch. Residual unknown is narrow and stated: the
non-empty render is unprobed because it needs a seeded run fixture (build's lane).

## The two-checkout hazard — a false-citation generator

Verifying their line numbers, I ran `cd <main-repo>/designs/appbox-studio 2>/dev/null || cd <worktree>/...`.
**The main path exists**, so the fallback never fired and I read the wrong copy:

```
worktree app.routes.js:32  ['GET','/build', buildLoop.page]        <- what they cited
main     app.routes.js:32  ['POST','/build/run/control', ...]      <- what I read
57 lines vs 54 — the files differ
```

I was one step from telling a teammate their three citations were fictional. They
were exact. The error would have been confident, specific, and entirely produced by
my own path.

This is worse than a fictional path, because a fictional path fails loudly (`ls:
No such file`). A *second real checkout of the same file* returns plausible content
at every line number and fails silently. Every line-number citation in this task is
only meaningful relative to a checkout, and none of us has been stating which.

**Constraint:** cite line numbers with the tree they were read from, and pin the
tree explicitly rather than relying on a relative `cd` — in a repo with a worktree,
`cd A || cd B` is not a fallback, it is a coin flip that always lands on A.

## The sweep's verdict table, and the residual hole in it

The two-row table earlier in this document (`rendered` / `unreachable`) is wrong as
written, and would have flagged the remedy as the defect. Under it, `scaffold.run`
scores FAIL: its facade sets no action, `_shared.html:75` gates on it, the field
never renders, and a sweep that reads "no form" as failure indicts the guard that
is working exactly as designed. The discriminator is not whether a form rendered,
it is **why** it didn't — and that is readable in the template, not the output:

| result | template mount | facade | verdict |
|---|---|---|---|
| `no-mount` | absent | — | pass |
| `rendered` | renders | action set, route registered | pass |
| `state-unreached` | ungated | action set, fixture never reached | **fail** — real debt (`/build/loop`) |
| `guard-closed` | gated | no action | conditional — see below, **then instances 8 and 9** |

> **Read the later sections before using this table.** Two of its columns have since
> been corrected and it is not self-contained: the `null` declaration offered below
> as the remedy is **inert unless its checker ships with it** (instance 8), and the
> view-local grep originally proposed to populate `template mount` **scores
> inverted** on any screen that inherits its composer (instance 9). A reader who
> stops here gets the pre-correction answer.

`state-unreached` is the row that matters for coverage: the mount is real, the
sweep cannot reach it, and reporting that as clean is how a sweep silently scores
3/3 on a surface it never rendered. It must fail loudly rather than skip.

**Where `guard-closed` is still not a pass.** A gated mount renders nothing whether
the omission was deliberate or an oversight, and measurement cannot separate the
two, because nothing distinguishes them in the source:

```
scaffold_run_facade.js   composerAction  key ABSENT entirely
build_facade.js:457,527  composerAction: '/build/messages'
scaffold_facade.js:205   composerAction: '/scaffold/messages'
```

This is the same silent failure the guard was introduced knowing it would create,
and it is *not* closed by the rendered-sweep, as this document earlier claimed.
The sweep sees no form, classifies `guard-closed`, and passes. A facade whose
author simply forgot the key is byte-identical to one that has nothing to say.

**Remedy: make the intent declarable — but only behind a gated mount.**

```js
composerAction: null,  // read receipt; no mutation originates here
```

**This rule is scoped to gated mounts, and stating it generally would seed the very
defect this document exists to kill.** `cm.field` hardcodes the action twice with no
guard of its own (`composer.html:44-45`), and `loop_view.html:86` mounts it
**ungated**. Behind that mount, an absent key already renders `action=""` — the
class-1 defect, measured by run-screen — and `null` is equally falsy, so declaring
it there changes an undetectable state into an identical undetectable state while
*reading* as though the surface had been made safe. For an ungated mount the fix is
not a declaration, it is the guard.

**And it takes two instruments, not one.** The rendered sweep cannot carry this
check: absent and null both render nothing, so the distinction is invisible at the
layer where the sweep looks. This is the layer error of instance 5 reappearing
inside the fix for it. The claim "the author declared no mutation" is a claim about
**authored schema**, so it is answerable only in source:

- *rendered sweep* — every emitted `<form class="composer">` action resolves to a
  registered route. Catches `action=""` and `action="/nowhere"`.
- *source assertion* — every facade backing a gated mount has the
  `composerAction` key **present**; absent is a failure, `null` is a pass.
  "Backing a gated mount" is an **import-graph** property and must be resolved
  from registry.json's authored `shell` field, never from a grep of the view
  file — see Instance 10. Implemented in `composer-action-check.js`.

Neither subsumes the other, and each is on the same side of the pipeline as the
claim it settles. `scaffold.run` is currently the undeclared kind: correct in
behaviour, unverifiable in source.

The four-row discriminator above is run-screen's, from the observation that my
two-row table would have scored `scaffold.run` as FAIL and flagged the remedy as
the defect.

### Instance 7 — a sampled enumeration, one message after correcting a sampled enumeration

I wrote that "every export short-circuits through `empty(c, h)`" from reading four
sites. There are thirteen. The claim survived full enumeration — all 13 are
followed by the identical `if (e) return emptyPage(c, h, e);`, and the two exports
without the guard are `surfaceId` (a constant) and `screenStub` (the 2572 B stub,
no composer) — but it was a 4/13 sample asserted as a census, sent one message
after I had corrected a teammate for a 2/10 sample. Surviving verification is not
the same as having been verified; the reason to enumerate is that the sampler
cannot know which case they are in.

## The guard's actual blast radius, and two defects with two owners

Measured with the guard live in the tree, against a correctly-launched design
server on :4319:

```
/scaffold      <form class="composer" action="/scaffold/messages">
POST /scaffold/messages  ->  404
/scaffold/run  no composer form
```

**The guard is inert on `/scaffold`.** `scaffold_facade.js:205` sets
`composerAction` unconditionally, so `{% if c.composerAction %}` never takes its
false branch there; picker stashed the hunk out and re-rendered byte-identical
(82716 / 27424 either way). It is load-bearing only on `/scaffold/run`, whose
facade sets no action at all — the 1864 B delta run-screen measured.

So the two defect classes have two owners, and the guard is not a single fix:

| defect | surface | remedy | owner |
|---|---|---|---|
| action set, route never registered → POST 404 | `/scaffold` | route it, or drop `:205` | picker |
| no action set, ungated mount → `action=""` | `/scaffold/run` | the `:75` guard | this lane |

I escalated the guard to the lead as "the fix for a live 404." It is not; it does
nothing to the 404. The estimate of one line was wrong, and the correction is the
useful artifact: a fix whose blast radius I had never rendered.

### The mount population, fully enumerated

```
GATED    scaffold/_shared.html:75      {% if c.composerAction %}{{ cm.field(c) }}{% endif %}
UNGATED  design/_shared.html:76        {{ cm.field(c) }}
UNGATED  intake/_shared.html:235       {{ cm.field(c) }}
UNGATED  build/loop/loop_view.html:86  {{ cm.field(c) }}
```

One gated mount, serving both scaffold screens, so the population the source
assertion governs is exactly **two facades** — one declares (`scaffold_facade.js:205`),
one omits (`scaffold_run_facade.js`). If the guard ever migrates into `cm.field`
itself, all four mounts become gated and the denominator jumps to every
composer-bearing facade; it should be re-stated at that point, not inherited.

### Instance 8 — a fix authored at a layer nothing checks

Under the guard, `null` and absent produce byte-identical output in all five
states. Nothing at runtime reads the difference, so the declaration's entire value
lives in an instrument that does not exist yet. Shipping `composerAction: null`
without its checker leaves a convention that *reads* as a safeguard and enforces
nothing — worse than the honest gap, because the next author sees it as handled.
This is instance 5's layer error one turn deeper: not "I measured at the wrong
layer" but "I fixed at a layer nothing measures." **The declaration and its
assertion are one change or neither.** (run-screen)

### Instance 9 — the right file, read at the wrong scope

I proposed `grep -c 'composerPanel('` per view to separate `no-mount` from
`state-unreached`. It scores exactly inverted:

| view | grep | my verdict | forms actually rendered |
|---|---|---|---|
| `picker_view.html` | 0 | pass | **1** — the live 404 defect |
| `run_view.html` | 0 | pass | 0 |
| `build/loop/loop_view.html` | 2 | flagged | 0 |

The scaffold screens never *name* `composerPanel`; they inherit it through
`{% import %}` of `_shared.html`, which mounts it unconditionally at `:113`. Build
is the only screen mounting its own, which is exactly why it is the only one the
check finds. A view-local grep cannot see a shell-mounted macro: it reads a real
file, returns a true zero, and answers a narrower question than the one asked.

The distinction survives; the detector doesn't. Score on rendered output across the
state matrix — one `grep -c 'class="composer"'` per URL — or resolve imports first.
(picker)

**The unifying shape.** Wrong tree, suppressed stderr, sampled enumeration, wrong
layer, and now wrong scope are one failure mode: *an instrument that answers a
narrower question than the claim it is asked to support*, and returns a clean
result that reads as confirmation. Path-confirmation, tree-pinning,
stderr-preservation and full enumeration are all special cases of the same
discipline — state the question the instrument actually answers, and check it
against the question asked.

### The guard's positive control — and a non-mutating form of it

picker drove the false branch by deleting their `:205` and rendering: composer
forms went 1 → 0 across six states (`186dc40`, §0c). That is the first
observation of `:75` doing work rather than sitting inert, and the counterfactual
is known — an *ungated* mount with no action still emits `<form action="">`, so
forms reaching 0 rather than 1-with-empty-action isolates the guard specifically.

**The same control is available without mutating a shared file.** `thread(c)` sits
at `:74`, outside the guard, and emits `<div class="chat-thread">`
unconditionally. So on `/scaffold/run` — whose facade sets nothing — thread
markup present *proves the macro body executed*, and zero composer forms proves
`:75` took its false branch. Measured, all five run states:

| surface | thread mounted | rows | composer forms | panel bytes |
|---|---|---|---|---|
| `/scaffold` (action set) | yes | 2 | 1 | 2764 |
| `/scaffold/run` ×5 states | yes | 2 | **0** | 926 |

Prefer this form: it needs no apply/revert round-trip on a file three agents
share, which is the operation that has already cost this thread two incidents.

**Two byte quantities, not two estimates of one** (picker's correction, verified
independently): **926 B** is what *survives* on the gated surface — eyebrow, ctx
chips, two `bt-event` rows; **1898 B** is the composer field itself, what
field-level gating removes. Panel delta 1838 B. Both real, different questions.
The 240–280px empty column I was warned about does not occur, because `:75` gates
`cm.field(c)` only and leaves `thread(c)` at `:74` outside — run-screen's
correction, now vindicated by render rather than argument.

**Durability, resolved without a commit.** `_shared.html:75` is an unstaged edit
on a branch three agents share, and its only backup was an untracked patch that
`git clean -fd` removes. Fixed by pinning the working tree in the object database:
`git stash create` produces a dangling commit **without** pushing to `refs/stash`
(so the shared stash-stack hazard does not apply), and `git update-ref
refs/backup/composer-guard <sha>` makes it a gc root. Survives `git clean -fd`
and `git restore designs/`; touches neither branch, index, nor stash stack.
Recover with `git show refs/backup/composer-guard:<path>`. Verified: stash stack
still empty, working tree unchanged.

### Instance 11 — citing a number in the wrong role (mine, caught by advisor)

I told the lead the `null` declaration leaves "all five states byte-identical at
**1864 B**." The conclusion was right; the number was not mine and was not even
the same *kind* of quantity. 1864 B is run-screen's **delta** figure. The five run
states are not uniform at all — they are byte-identical *to themselves* across the
change, at five different sizes. Measured, my file, apply → restart → measure →
revert:

| state | before | after | delta | forms | undefined |
|---|---|---|---|---|---|
| completed | 26801 | 26801 | 0 | 0 | 0 |
| pre | 24650 | 24650 | 0 | 0 | 0 |
| warning | 28359 | 28359 | 0 | 0 | 0 |
| failed | 25288 | 25288 | 0 | 0 | 0 |
| blocked | 22124 | 22124 | 0 | 0 | 0 |

**"Zero render change" is confirmed — by measurement, not by falsiness reasoning.**
The baseline is also restart-stable: an unrelated restart reproduced all five
byte-for-byte, which rules out restart-induced drift as an explanation.

This is a distinct failure from the thread's others. It isn't a fictional citation
(1864 B is real, and run-screen measured it correctly), nor a blind instrument.
It's a **type error on a borrowed quantity**: a delta re-used as an absolute. Grep
and render checks both miss it, because the number is genuine — only its role is
wrong. The single defence is the one this thread keeps re-deriving: *if the number
is load-bearing on someone else's decision, measure it yourself.* I had a
one-command way to do that and cited instead.

**Operational note, paid for.** My first attempt aborted between apply and revert
(`appbox` is not on `PATH`; the entrypoint is `dart appboxd/bin/appbox.dart design
serve`). That left my file modified *and* the shared `:4319` server down for two
teammates. Any measurement that mutates a file must put the restore in a `finally`
that also relaunches the server, and must verify both — as the corrected run does,
reporting `file byte-identical | server UP | residue none` before printing any
result.

### Instance 10 — the same scope error, re-entering through the remedy

Instance 9 killed a view-local grep used as a *detector*. The identical error then
re-entered through the **source assertion** written above as the remedy, because
its load-bearing phrase — "every facade backing a gated mount" — is an
import-graph property stated as if it were file-local. Implemented per view, the
population resolves empty (`picker_view.html` and `run_view.html` both grep 0 for
`composerPanel(`), so the rule is **vacuously satisfied on precisely the file it
exists to catch**, `scaffold_run_facade.js`. It reports clean. (run-screen, who
proposed it and then retracted it before anyone implemented it.)

Note what this is invisible to: path exists, right tree, stderr visible, full
enumeration, and the grep is correct about the file it read. Every guard in this
document passes. The empty set is produced for a *structural* reason and is
indistinguishable, at the checker's own layer, from a substantive zero.

**The proposed replacement fails differently.** *Render each route; if no composer
form appears, require the facade's key* conflates `guard-closed` with `no-mount`.
Measured across the route tables: **28 of 40** probeable GET routes render no
composer form, against a gated population of **2**. It would demand a
`composerAction` declaration from `/splash`, `/auth`, `/dashboard`, `/workspace`
— surfaces with no composer and no prospect of one. Re-restricting the rule to
"gated" reintroduces the import-graph problem the render-binding existed to solve.
*(Gap, labelled: 25 of 65 GET tuples take path params and were not probed; 2 more
returned 204. Unmeasured, not absent.)*

**Resolution — take the population from a declared fact.** `registry.json` carries
an authored `shell` per screen. Resolving mount → shell's `_shared.html` macro body
(or a view-local override) classifies all 38 screens with no template edit and no
inference from absence:

| | count |
|---|---|
| GATED — `scaffold/_shared.html:75` | **2** (`scaffold.picker`, `scaffold.run`) |
| UNGATED — design `:76`, intake `:235`, build `loop_view.html:86` | 15 |
| no mount | 21 |

Denominator 2, independently matching run-screen's facade-side count. Verdict:
`scaffold_facade.js` 1 hit → pass; `scaffold_run_facade.js` 0 → **fail**. The one
defect, found by a checker that ships alone.

**The generalisation this earns.** Every prior guard here validates the instrument
against the *world* — right file, right tree, real stderr. None validates it
against its own **population**. A checker that enumerates its subjects can be
blinded by enumerating none, and silence then reads as health. So:
`composer-action-check.js` **exits 2 on an empty population** and refuses to
report clean — verified by negative control (guard stripped from a scratch copy →
BLIND, not pass). An instrument that cannot produce a hit has not produced a pass.

---

## Instance 12 — comparing at the wrong macro layer (mine, caught pre-send)

**Claim I was about to send the lead:** "scaffold/_shared.html passes neither `size:`
nor `sizeHref:` into `pa.open`/`cp.open`, where design's `_shared.html:203` passes
both — so the fix is three coordinated edits across two facades and one template."

**The error.** design `:203` is `activitySwap`, which calls `pa.top`/`pa.bottom` —
the *swap* path. My `:98` is `activityPanel`, which calls `pa.open`/`pa.close`.
I compared a swap-path call site against an open-path call site, found a difference,
and attributed it to the shell rather than to the macro.

**Corrected by enumerating every `pa.open`/`cp.open` call site instead of one sibling:**

| shell | `cp.open` spec | `pa.open` spec |
|---|---|---|
| design `:73/:192`  | `{eyebrow, chips}` | `{label, views, size, sizeHref, panelSizePx}` |
| intake `:232/:307` | `{eyebrow, chips}` | `{label, views, size, sizeHref}` |
| build `:83/:267`   | `{eyebrow, chips}` | `{label, views, size, sizeHref}` |
| scaffold `:72/:97` | `{eyebrow, chips}` | `{label, views}`  <- outlier |

**What changed in the conclusion.** The composer half is *not* a defect: all four
shells pass `{eyebrow, chips}` identically, and `composer_panel.html`'s `open()`
does not read `spec.size`/`spec.sizeHref` at all (its `resize` is unconditional at
`edge: 'end'`). Only the activity half diverges, 3-vs-1.

Had I sent it, the "fix" would have included a composer-template edit that is a
no-op on render and would have made scaffold the only shell diverging from a
convention it currently follows correctly. The wrong diagnosis proposed a real
regression.

**Why the instruments in this doc don't catch it.** Both the grep instrument and
the render instrument answer "does this file do X". Neither answers "is X the
right comparand". A single-sibling comparison is a sample of one presented as a
convention; the remedy is enumeration of the whole population of call sites —
the same denominator discipline from Instance 8, applied to comparands rather
than to assignments.

**Rule.** Before citing a sibling as the convention, enumerate every call site of
the *same macro*. A difference between two call sites is evidence about the call
sites only when they call the same thing.

Caught by advisor review, not by measurement — worth noting, because the
measurement I had run was correct and still supported a wrong claim.

---

## Instance 13 — my own scope error, ten minutes after being warned about it

picker-screen sent a warning: *"If your checker's fixture set doesn't contain at
least one endpoint independently known to work, it cannot detect its own scope
errors."* They had built the route join twice and got it wrong both times.

I then built the same join and got it wrong the same way. My walk was rooted at
`ui/` and matched `/^app\.routes\.js$|^routes\..*\.js$/`. It found 4 route files
and missed `app.routes.js`, which sits at the design **root**. Output:

```
build_facade.js:457  /build/messages  *** UNROUTED ***   <- false, routed at app.routes.js:41
build_facade.js:527  /build/messages  *** UNROUTED ***   <- false, same
scaffold_facade.js:205 /scaffold/messages *** UNROUTED *** <- true
```

Two false alarms on live endpoints, and a total of 3 where picker measured 1.

**Why my positive control missed it.** I had one: "did any declaration resolve?"
Three did, so the instrument looked alive. But all three resolved from files the
walk had already found. **A control drawn from the same source as the finding
cannot detect a missing source.** The aggregate form of the control is worthless
against scope errors; the control must be *per-source* — specific endpoints known
to live in specific files, chosen so that a missing file breaks an anchor.

v2 implements this as `ANCHORS`, requiring resolution from ≥2 distinct route
files, exiting 2 (BLIND) otherwise. Both directions are now exercised:

| control | expectation | result |
|---|---|---|
| fixture without `app.routes.js` | BLIND, exit 2 | exit 2, both anchors named |
| inject real `POST /scaffold/messages` | green, exit 0 | exit 0, `:205` reads `routed` |

The second matters most: it proves green is reachable by **routing** the action,
not only by deleting the key. run-screen's blocking objection to v1 was that its
green state was reachable *only* by committing the defect class. That is now
false by construction and by test.

## Instance 14 — a revert check that raised a false alarm

Verifying the control-B revert I ran `git diff --quiet <file>`, which reported
`*** RESIDUE ***`. There was none. The file already carried picker's uncommitted
routes edit, so a diff against HEAD can never be empty, whatever I do.

The check answered "does this file differ from HEAD" while I was asking "does
this file differ from how I found it." In a shared worktree with concurrent
uncommitted edits those are different questions, and only the second is mine to
answer. Correct instrument: diff against a snapshot taken before the mutation —
`git show refs/backup/composer-trail:<path>`, which returned IDENTICAL.

Failure direction was safe (false alarm, not false pass), but it is the same
wrong-comparand shape as Instance 12. Worth recording because the backup ref
turned out to be an *audit* instrument, not merely a recovery one — it is the
only artifact here that can answer "how did I find it."

## Instance 15 — three subcommands, three argument conventions, one silent shape

`appbox` resolves its design argument differently per subcommand. This has now
cost time in three lanes, so it is worth stating exactly:

| invocation | correct form | wrong form does |
|---|---|---|
| `design serve` | design **name** (`appbox-studio`) | — |
| `design selftest` | artifact **dir** (`designs/appbox-studio`) | name → `PathNotFoundException`, exit 255 |
| `design lint` | artifact **dir** | name → lints the *unrelated* top-level `appbox-studio/`, reports a real-looking failure |
| `emit structure` | **top-level**, `--design-dir <dir>` | `design emit structure <dir>` → help text, exit 2 |

run-screen's "the correct invocation needs the design name" is true of `serve`
and false of the other three; I generalised it and lost a gate run to that.

The dangerous one is `design lint appbox-studio`: it does not fail, it succeeds
against the wrong directory and emits `non-vendor <script> tag` — a plausible,
specific, entirely false lint failure. That is the same shape as Instance 11's
false-citation generator: **a wrong path that returns plausible content is worse
than one that errors.** Correct-form lint is clean, W1–W6.

### A measurement error of my own in the same block

Checking whether the wrong form silently passed, I ran `dart … | head -3` and
read `$?`. That is `head`'s exit status, not dart's. I reported "wrongarg exit=0
— silent pass" and was about to escalate a fabricated hazard. The pipeline had
discarded the exit code I was claiming to measure.

Re-run without the pipe: real exit 0, 37 lines, `passed 25, failed 0, skipped 0
of 25`. So the artifact-dir form was correct all along and **the 25/25 baseline
in the escalation is verified, not an artifact of a bad invocation.** My only
error was `appbox/` for `appboxd/`, which fails loudly.

Rule this adds to the sweep: *never read `$?` through a pipe.* It silently
substitutes the wrong process's verdict, which is this document's entire subject.

## Instance 13 — a stale server nearly manufactured a defect on someone else's screen (mine)

After committing my route I measured `POST /scaffold/messages -> 404` and was one message away
from telling picker their composer was broken again. The route line was correct in the tree AND
in HEAD, and `export const sendMessage` was present at `picker_viewmodel.js:55` — three static
reads all agreed the wiring was sound, against one dynamic read that said it wasn't.

The static reads were right. The server predated picker's commit; ESM cache. After a restart
with a real readiness gate, `POST /scaffold/messages -> 200`.

What makes this the sharpest instance so far: my own route returned 200 from the same file in the
same request cycle, which read as proof the file was loaded and therefore that the 404 was about
picker's half specifically. It wasn't — my route entered the process at a different time than
theirs did. A live 200 next to a live 404 in one file is not evidence the file is current; it is
only evidence that *something* is loaded. The positive control has to be the thing under test at
the time under test, not a neighbour of it.

Standing form of the rule, now paid out four times: a zero is admissible only from an instrument
proven capable of non-zero **for that subject, at that moment**. Restart-after-edit is the
mechanical way to buy the "at that moment" half, and it stays the default.

## Ruling compliance for `/scaffold/run` — measured, not asserted

Instruments proved capable of non-zero before each zero was admitted. Two of my
first-pass selectors (`run-thread-row`, `href=*size*`) were incapable and their
zeros were discarded, not reported.

| ruled requirement | measurement | result |
|---|---|---|
| thread append, user's own text only | `bt-user` 0→1, `bt-agent` 1→1 across POST | +1 exactly, no invented reply |
| append persists | re-GET, same jar | marker present |
| `h.render(c, VIEW#panelsSwap)` | POST body | no `<!DOCTYPE`, no `<html>` — fragment |
| empty text → `h.noContent(c)` | POST `text=` | 204 |
| zero new l10n keys | 5 states swept for `MISSING`/`undefined`/raw `scaffold.run.*` | 0 |
| scalar `size` + `sizeHref` | facade `:79`,`:80` vs design `:893`, intake `:732`, build `:477` | identical shape |
| five states unchanged until action set | pre-flip baseline vs post | byte-identical, 0 forms |

**Positive control that mattered:** my "no resize href renders" finding reproduced
exactly on `/design/freeze` — a known-good sibling. A defect that reproduces on the
control is not a defect; it is the convention, and my grep was aimed at markup the
grip does not use. Reported as parity, not as a bug.

**Two disclosures.** (1) The action carries `?state=` — a deviation from the ruling's
literal `'/scaffold/run/messages'`. Behavior is the ruled one; the suffix exists so a
note left on the `failed` receipt is not answered with the `completed` one. Lead may
strike it. (2) A note is session-held and therefore visible from every lens state,
`?state=completed` included. That is a property of the run, not of the view, so I
believe it is right — but it was measured, not designed, and is stated so it can be
overruled.
