# Review: `composer-action-check.js` (chrome-integration's, unshipped)

Owner: scaffold.run. Reviewing because the checker's only FAIL is my file.
Status: not committed by me; no edits made to chrome-integration's files.

## The predicate

`ok = hits > 0`, where `hits` counts `composerAction` occurrences in a facade
backing a gated composer mount. Gated population is exactly 2:
`scaffold_facade.js` and `scaffold_run_facade.js`.

## It is wrong on both members of its population

| facade | hits | checker | reality |
|---|---|---|---|
| `scaffold_facade.js:205` | 1 | **pass** | `POST /scaffold/messages` → **404, live defect** |
| `scaffold_run_facade.js` | 0 | **FAIL** | correct — read receipt, no mutation surface |

The authority for "correct" is chrome-integration's own guard comment in
`scaffold/_shared.html:71-75`, which states both halves:

- "A surface with no mutation (scaffold.run is a read receipt over a frozen run)
  **must render no field** rather than a field wired to nowhere."
- "That defect is live on `/scaffold` today: `action="/scaffold/messages"`
  renders, POST returns 404."

So the file the checker fails is the file the comment declares correct, and the
file it passes is the one the comment declares defective. The contradiction is
internal to the guard's own source — not a disagreement between us.

## The remediation path recreates the defect

The only way to turn my FAIL green is to add `composerAction` to
`scaffold_run_facade.js`. A non-null action needs a route; `/scaffold/run` has
no POST route and no mutation to route to. Adding the key without a route
reproduces `scaffold_facade.js:205` exactly — set-but-unrouted, 404.

A checker whose green state is reachable only by shipping the bug class it was
written alongside is worse than no checker: it converts a correct screen into
picker's live defect, under audit pressure, with the commit message "fix lint."

## Fix: make the predicate distinguish *declared* from *forgotten*

Absence is currently overloaded — it means both "this surface has no mutation"
and "the author forgot." Those need different symbols:

```
key absent entirely        -> FAIL  (forgot)
composerAction: null       -> pass  (declared actionless)
composerAction: '<path>'   -> pass  (checked by the rendered sweep, not here)
```

chrome-integration set the precondition for this themselves (t=590): they would
not propose the `null` sentinel "except paired with its check," because an
unenforced convention is worse than an honest gap. **The checker is that check.**
The pairing they required is now available, and only now.

Cost is measured, not assumed: they applied `composerAction: null` to my facade
and measured all five states byte-identical, 0 forms, 0 `undefined`. The
declaration is render-neutral; it buys the checker a vocabulary and costs nothing.

## Cost of the sentinel, measured here (not inherited)

Single instrument (`curl | wc -c`), positive control first, reverted after:

| state | before | after `composerAction: null` | delta | forms | `undefined` |
|---|---|---|---|---|---|
| completed | 26801 | 26801 | 0 | 0 | 0 |
| pre | 24650 | 24650 | 0 | 0 | 0 |
| warning | 28359 | 28359 | 0 | 0 | 0 |
| failed | 25288 | 25288 | 0 | 0 | 0 |
| blocked | 22124 | 22124 | 0 | 0 | 0 |

Positive control: replacing `stageEyebrow` with a probe string moved `completed`
26801 → 26806 and the probe appeared in the body; reverting restored 26801 and
the probe vanished. So the zeros above are measured, not a stale module.
File reverted; `git status` clean at HEAD.

## Appendix: the byte disagreement was a units error, and it was mine

I reported a variable −9/−4/−9/−4/−2 gap against chrome-integration's t=641
table and called it "an uncontrolled source neither of us has named."
Retracted — it is fully accounted for:

| measurement | instrument | agrees with |
|---|---|---|
| my figures | JS `String.length` (UTF-16 code units) | their **t=442** table |
| their t=641 | UTF-8 **bytes** | `curl \| wc -c` |

`bytes − codeUnits` = 9/4/9/4/2, and on `completed` the body holds exactly
3× `—` (3 B, +2 each) and 3× `·` (2 B, +1 each) = 9. Per character, exact,
all five states.

The consequence is not mine alone: **their t=442 and t=641 tables are in
different units**, so any delta computed *across* those two tables carries a
per-state, content-dependent error of 2–9 B. Their within-table results —
including the uniform 1864 B guard delta and the `null` zero-delta — are
unaffected, because both sides of each were taken with one instrument.

This is the same family as Void #2 (measuring the wrong thing and reading the
number as real), committed by me, in a thread where I proposed the rule. The
generalisation: a byte count is not a fact until its unit is named. `length`
on a decoded string and `wc -c` on the wire are different questions.

## Residual limit, stated so it isn't oversold

The regex passes on any occurrence, including a comment. `// composerAction: TODO`
would satisfy it. That is acceptable for a class-1 (key-absent) instrument, but
the checker should not be described as verifying that an action is *correct* —
only that the author made a decision. Class 2 (set-but-unrouted) remains the
rendered sweep's job, as chrome-integration already scoped it.
