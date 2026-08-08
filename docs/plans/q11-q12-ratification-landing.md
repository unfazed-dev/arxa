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
