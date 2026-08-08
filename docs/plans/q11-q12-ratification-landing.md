# Q11/Q12 ratification landing (Task #11)

Follow-on to the Q11 shell spike (`docs/plans/q11-shell-spike.md`). The spike's
five verdicts were reported against the *pre-ratification* contract. The user
ratified decisions (a)–(d) plus F1 in
`docs/plans/designer-scaffolder-grill-decisions.md` (commit `c4b4531`), which
lifts the mid-spike freeze on contract files. This document is the execution
record for landing them.

## Order of operations

| # | Ratification | Edit | Verdict it moves |
|---|---|---|---|
| 1 | (d) | `showcase_notes_shell_viewmodel.dart` gains the missing `Relationships:` section | V5 red → green |
| 2 | (a) | `InspectAttrs` gets a real home in kit core; anatomy-node vocabulary closed in `kind-resolution.registry.json` (version bump) | V4 unratified → ratified |
| 3 | (b) | Showcase back-stamped with the ratified triple; `SKILL.md:270` exemption removed | V4 showcase warn → checked arm |
| 4 | (c) | `design-system.md` gains a typed artifact entry in the manifest | V1 warn → gone |
| 5 | (F1) | Three-override obligation written into the manifest | contract explains the emitted pubspec |
| 6 | — | Emitter reads the kit-core shape; golden tree re-emitted and re-committed | keeps V3 honest |
| 7 | — | Probe re-run, five verdicts reported | — |

## Decisions taken while executing

### The Dart field is `anatomyNodeId`, not `nodeId`

`app-architecture.md:169` shows the **JS** form, whose third key is `nodeId`
with the comment `// anatomy-node id`. The manifest's own
`inspectAttrs.triple` already reads `["screenId","surfaceId","anatomyNodeId"]`,
and the team-lead's assignment names the Dart fields the same way. JS `nodeId`
and Dart `anatomyNodeId` are the same triple member spelled for two language
surfaces; "1:1 with the JS form" is about the *triple*, not the identifier
text. What was spike-invented — and what gets replaced — is the `InspectAttrs`
class living in the emitter carrying a `PROVISIONAL VOCABULARY` banner.

### The anatomy-node closed set is 8 ids, derived not invented

`showcase-anatomy.md` contains **no** `anatomy:` literals, so the closed set
cannot be lifted from it verbatim; it is *derived* from two normative
statements in that document:

- §1 (The tree) distinguishes exactly two positions that render:
  `ui/views/<shell>/` — the shell frame — and
  `ui/views/<shell>/<surface>/` — a surface inside it.
- §Per-surface split (Q3): every view is five files — a dispatcher plus the
  three variants `.desktop` / `.mobile` / `.tablet`.

Cross-product: `{shell.frame, view.body} × {∅, .desktop, .mobile, .tablet}` = 8.
**RETRACTED — see §Correction below. The breakpoint axis is not authored;
the derivation yields 2, not 8, and this line was my own reasoning, not a source.**
Nothing beyond what the showcase's own structure needs. The registry is the
home because the doc holds no literals to extend.

### Showcase back-stamp covers 14 of 20 view files — the other 6 are a finding

`manifest#/inspectAttrs/source` declares the triple comes from
"intake/registry.json ids". Showcase's `intake/registry.json` is a flat
14-entry list, every entry `surface: null`. Those 14 ids cover the 13 non-shell
surface views plus `showcase.application` (the application shell). The
remaining **6 structural shell frames** — home, notes, profile, search,
startup, unknown — have no registry id of their own; their leaves carry the
ids. Manufacturing ids for them would be exactly the invention the ratification
was meant to end, so they are left unstamped and reported red with cause, per
the standing instruction. The gap is in the showcase registry's shape, not in
the scaffolder.

## Flagged, not fixed

- `skills/appbox-designer/references/showcase-anatomy.md:140` asserts
  "Closed at registry v1.0.0 (Q7); resolver-reachable at v1.1.0 … All 15
  kinds". The registry version bump for the anatomy vocabulary stales that
  line. Designer-owned prose; scaffolder owns the registry. Flagged per the
  assignment's explicit instruction not to fix beyond the registry itself.
- The team-lead's acceptance message verified HEAD `01bb5a7`; the spike's final
  HEAD was `409c44c`. Possible stale-commit verification, surfaced for
  confirmation.

## Correction (post-ratification audit)

Three claims above and in `app-architecture.md` were mine, not sources, and two
were wrong. Recorded here because both were later cited back to me as evidence.

1. **The `= 8` cross-product is retracted.** Pre-session authorship
   (`54c5c5f`, `06f1f68` — both ancestors of the first spike commit `c4b4531`)
   stamps `nodeId: 'anatomy:view.body'` with **no** breakpoint suffix, and
   `inspectAttrs` has exactly three slots with no breakpoint member. The
   authoring encodes a **base id with no breakpoint axis**, so breakpoint
   variants are not vocabulary members. Derivation yields **1**, not 8 —
   see the second correction below; my own "yields 2" was also overstated.

2. **"`anatomy:view.body` … is currently the entire set" (`6a2cf68`) is my own
   sentence**, written this session. It is not independent authority and must
   not be cited as ratification of a 1-member set.

3. **The 1-member set has a concrete defect.** Six `screenId`s are each carried
   by two view files — the shell frame and its leaf:
   `showcase.home`, `.notes`, `.profile`, `.search`, `.startup`, `.unknown`.
   Pre-session text requires the triple on every emitted surface, *"shells
   included"*. With a constant `anatomyNodeId`, the slot whose job is to say
   which tree position renders carries zero information and cannot distinguish
   a frame from the body inside it. That is a real cost, independent of any
   document I wrote.

**Open, not decided here:** the *name* of the second member. `shell.frame`
appears in **no** pre-session commit — I coined it. Adding it is a vocabulary
addition, and the standing rule is that these are ratified deliberately with a
version bump, never invented mid-task. The need for a second member is derived;
the spelling is not, and is referred up rather than stamped.

## Correction to the correction (team-lead provenance, accepted)

I wrote above that the derivation "yields 2". That overstates it, and the
error is the same species as the one I flagged. Team-lead traced provenance
independently: `anatomy:shell.frame` and every breakpoint variant exist **only**
under `tool/spike-q11-shells/` — my emitter and its golden output. Confirmed:
`git grep -c 'shell.frame' c4b4531` finds nothing pre-spike.

So the pre-session corpus authorizes exactly **one** id, `anatomy:view.body`.
Deriving a second member from a name my own emitter emitted would have had the
probe verify its own output — the tautology this registry exists to prevent,
arrived at by a subtler route than the grep did.

**The closed set stays at 1 member. Registry v1.2.0 stands.**

What survives is a *design question*, not a derivation, and it is the user's to
answer, not an agent's to infer:

> Six `screenId`s are each carried by two files — a shell frame and its leaf
> (`showcase.home`, `.notes`, `.profile`, `.search`, `.startup`, `.unknown`).
> The triple stays unique because `surfaceId` differs, so nothing is broken.
> But `anatomyNodeId` is constant across all 20 surfaces, so the slot whose
> job is to say which tree position renders currently distinguishes nothing.

Whether that slot should ever distinguish frame from body is a call for
whoever authors `showcase-anatomy.md`. Until they author such an id, there is
nothing to ratify and nothing to stamp. Recorded, not resolved.
