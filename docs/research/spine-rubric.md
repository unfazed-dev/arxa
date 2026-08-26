# arxa spine rubric — PRE-REGISTERED

Written **before** any suite was run or any repo scored. The point of writing it
first is that a rubric authored after the measurements is not a rubric, it is a
justification. If a dimension turns out to be unmeasurable, that gets recorded
as "unmeasurable" rather than quietly swapped for one that flatters a winner.

Candidates: `factory/flutter-crew`, `applications/asko`, `totem_labs/stacked_kit`.

Hypothesis under test (advisor's framing, adopted): **flutter-crew is the spine.**
The runs confirm or refute it. "Blend all three" is the failure mode, not the answer.

## Scoring

Each dimension 0–3, every score citing the command that produced it.

| | meaning |
|---|---|
| 0 | absent |
| 1 | present but manual / unenforced |
| 2 | enforced, with a known gap |
| 3 | enforced and the gap is closed by a test that fails when it regresses |

## Dimensions

### D1 — Determinism
*Proxy:* fraction of pipeline stages that produce their output with **no LLM call**.
*Measure:* count stage modules invoking a model vs total stage modules.
*Why it matters:* the user ships a paid product. Per-run model variance is a
support burden that scales with customers.

### D2 — Invalidation
*Proxy:* mutation experiment — perturb one input, does a previously-green stage
turn red **without a human remembering to re-run it**?
*Measure:* run it. Binary per repo, plus how the mechanism is keyed.
*Why:* this is the single mechanism stacked_kit is missing and the reason the
question was asked.

### D3 — Verification depth
*Proxy:* adversarial assertions per KLOC of production code.
*Measure:* count executed assertions (not test functions — a test function with
one assert is one assertion) ÷ non-test LOC.
*Caveat recorded up front:* this proxy rewards small codebases. Read alongside D1.

### D4 — Portability / shippability
*Proxy:* count of absolute paths, hard-coded usernames, and assumed sibling
repos in code that would ship.
*Measure:* grep for `/Volumes/`, `/Users/`, `~/Developer`, `../<sibling>`.
*Why:* a buyer has none of those paths. This is a hard filter, not a preference.

### D5 — Harness agnosticism
*Proxy:* number of distinct harness adapters shipped **and** whether a
non-LLM entrypoint is documented and runnable.
*Measure:* inventory plugin/adapter manifests; try the CLI entrypoint cold.

### D6 — Observability
*Proxy:* fraction of gates/stages emitting a **structured, machine-readable**
record (findings + provenance) to a known location.
*Measure:* count gates writing JSON/SARIF sidecars vs gates writing only stdout.
*Why:* the desktop UI has to render this. Gates that only print cannot be drawn.

### D7 — Decoupling
*Proxy:* can the tool run against an arbitrary target directory while writing
**nothing** outside its own input/process/output roots?
*Measure:* read the entrypoint's write paths; look for writes into the target app.
*Why:* stated requirement — "any output must be decoupled, self-contained and
isolated to the input and outputs."

### D8 — Human gates
*Proxy:* number of formal approval points in the state machine that a script
**cannot** advance past.
*Measure:* read the state machine.
*Why:* client work has approval semantics. An autopilot that self-approves a
design is not sellable to someone with a client.

## Recording rule

Every score gets the command and the number. A dimension I cannot measure gets
`?` and a sentence on why — never a guess dressed as a measurement.
