# Evan — Founder Journey: From Client Conversation to Shipped App

**Actor:** Evan (founder, Totem Labs — solo Dart/Rust/Flutter/Stacked developer)
**Journey:** the full pipeline across his four operating modes — intake → design
→ freeze → build → red-gate recovery → ship → remote → CRUD — the state machine
(`architecture.md` §6) walked end-to-end by the person who owns every
irreversible decision.
**Status:** proto-persona journey — pipeline mechanics are repo truth (cited,
`architecture.md`); thoughts/feelings are design hypotheses to validate (brief
§8). Each mechanic references its flow doc in `docs/design/flows/evan-founder/`
— the library holds the mechanics, this doc holds the narrative.

## Phases

### 0. Intake — eliciting what the client actually wants

- **Doing:** A conversation with a client becomes a brief. app_box asks — it
  does not generate. Who is this for, what are the three things it must do, what
  exists today, which platforms, what is the brand. Output: a design brief plus
  a **seeded `registry.json`** the designer consumes. Where app_box must infer,
  it marks the inference explicitly — never confident fiction. Optional by
  design: a hand-written brief is valid input, and Michelle will skip it
  entirely.
- **Touchpoints:** `projects-shell/new-project.md`, `projects-shell/showcase-first-run.md`;
  `architecture.md` §22 (intake elicits, never generates).
  Flows: `flows/evan-founder/projects-shell/new-project.md`.
- **Thinking:** "The client can read this brief and correct it — that's the
  cheapest place in the whole pipeline to be wrong."
- **Feeling:** Focused; the conversation is captured, not interpreted.
- **Frictions:** A brief that reads as generated fiction — requirements nobody
  asked for, stated with the same authority as ones they did. Features that
  appear because someone thought of them, not because the brief asked for them.
- **Opportunities:** Every registry entry traces to something the brief asked
  for — that traceability is a real assertion that can fail, and intake is the
  only phase whose output a non-technical client can validate.

### 1. New project — name, brand, targets

- **Doing:** Names the project, sets the brand, chooses `--targets`. Targets
  chosen here are written to pipeline state and are what every later gate
  reads. Choosing `ios, android` is what makes freeze produce two widths and
  scaffold emit the matching form factors.
- **Touchpoints:** `projects-shell/new-project.md`; `architecture.md` §11
  (targets are platform-only; viewports derive), §16 (form-factor emission).
  Flows: `flows/evan-founder/projects-shell/new-project.md`.
- **Thinking:** "I pick the platforms and the tool figures out the rest —
  iPhone and iPad layouts, no desktop. No flags to get wrong."
- **Feeling:** In control; the consequence is visible, not the mechanism.
- **Frictions:** Targets as flags that drift between the GUI, the skill
  invocation, and the CLI. A design frozen for two viewports getting scaffolded
  for three.
- **Opportunities:** Targets live in pipeline state, not flags — every gate
  reads the same source. The GUI and CLI both *write* state; gates *read* it.

### 2. Design — three directions, one approved *(GATE 1)*

- **Doing:** Prototypes the design in htmx, three directions, iterates. The
  designer produces authored structure — a `registry.json`, a `surfaceId` in
  every viewmodel, a route table — while designing, not after. An agent may
  generate, revise and present. **It cannot approve.** The approval token is
  minted by a person or not at all. Gate 1 binds the approval to the design's
  content hash — `done` exits non-zero if the design moved after approval.
- **Touchpoints:** `design-shell/prototype-directions.md`,
  `design-shell/approve-design.md`, `design-shell/iterate-direction.md`;
  `architecture.md` §6 (approval binds to hash), §12 (human gates), §13 (htmx
  producer is already MVVM), §14 (authored registry → derived tree → generated
  structure.json), §19 (designer is a fork).
  Flows: `flows/evan-founder/design-shell/prototype-directions.md`,
  `flows/evan-founder/design-shell/approve-design.md`,
  `flows/evan-founder/design-shell/iterate-direction.md`.
- **Thinking:** "I approve one direction and it's pinned — if the design moves
  after I approve, the build fails. That's the hash doing its job."
- **Feeling:** Deliberate; the approval is a commitment, not a checkbox.
- **Frictions:** Approval not bound to a hash — an approved review survives a
  design change, and the shipped app is not what was approved. A producer that
  invents layout instead of carrying declared structure.
- **Opportunities:** Gate 1 is where the product's core claim is visible: the
  human holds the design decision, and the hash makes it enforceable.

### 3. Freeze — six inputs, render gate, structure gate

- **Doing:** Six frozen inputs (the authored `registry.json` + view/viewmodel
  tree + surfaces + routes + brand tokens + targets), the render gate (every
  surface resolves its assets — path resolution, not string-checks), and the
  structure gate (drift check via `git status --porcelain`, not `git diff` — a
  producer that *adds* a surface is the expected case). Findings emitted as
  SARIF so the same data drives the GUI, the companion and a CI log.
- **Touchpoints:** `architecture.md` §13 (what the freeze keeps: 37 flat HTML
  files; what it discards: 8,454 lines of MVVM structure), §14 (the hybrid:
  authored layer is a different shape from the generated one), §5 (SARIF
  sidecars — 22/22 emit valid SARIF).
  Flows: this phase is mechanical — no dedicated flow doc; it sits between
  Gate 1 and the build.
- **Thinking:** "If it reports success while a surface 404s its fonts, the gate
  lied. That has happened — three verification layers agreed the output was
  fine."
- **Feeling:** Cautious trust; the freeze is where the producer's honesty is
  tested.
- **Frictions:** A gate that cannot fail for the right reason is not a gate.
  `dep_hash` on mtime, a self-test asserting the defective value, an asset check
  that verified strings instead of resolving paths — every one was green
  (research: `spine-findings.md`).
- **Opportunities:** The drift gate exists because `structure.json` is a pure
  function of the authored side. Content-hashed, not mtime-hashed — the stale-
  green defect is the failure mode content addressing was invented to remove.

### 4. Build — autonomous, gated *(GATE 2)*

- **Doing:** Starts the build and walks away. Real kits, real seeded data,
  gates. The loop runs unattended, stops on a red gate rather than ploughing on,
  and leaves a legible trail. The licence precondition (💳) runs **here**, before
  the phase — it is not a gate and never shows red. Comes back to N surfaces
  built, each with a green gate record and a diff he can actually review.
  Gate 2: accept the green build, or reject → recovery.
- **Touchpoints:** `build-shell/run-build.md`, `build-shell/accept-build.md`;
  `architecture.md` §6 (deterministic gates fail loud and HALT — never self-loop;
  only the LLM-authored portion may retry, bounded by ESC_LIMIT), §17 (licence
  is a precondition, not a gate; payment gate sits at builder).
  Flows: `flows/evan-founder/build-shell/run-build.md`,
  `flows/evan-founder/build-shell/accept-build.md`.
- **Thinking:** "Start it, walk away, come back to graded work. If something's
  red, it stopped — it didn't plough on and bury the failure."
- **Feeling:** Trust, earned by the trail; the loop is the colleague he doesn't
  have.
- **Frictions:** Every surface costs a model call and nothing is reproducible —
  re-running produces different code. The licence check appearing as a red gate.
- **Opportunities:** The `none` harness mode is not degraded — it is the
  measurement that keeps the determinism claim truthful. The fraction of the
  app producible under `none` is app_box's determinism, reported per run
  (`architecture.md` §7).

### 5. Red-gate recovery — P3 mode

- **Doing:** Something failed. The finding names the gate, the check, the file,
  the line, what it expected — with the exact command to reproduce it. SARIF
  `partialFingerprints` answer "is this the same failure as Tuesday?" Escalation
  is capped (`ESC_LIMIT=3`) — after that a human is required, by design.
- **Touchpoints:** `build-shell/red-gate-recovery.md`; `architecture.md` §1 (P3
  persona — 16 of 22 gates print to stdout only; if the terminal is gone, the
  finding is gone), §5 (SARIF — partialFingerprints, stable identity across
  runs).
  Flows: `flows/evan-founder/build-shell/red-gate-recovery.md`.
- **Thinking:** "Which gate, which check, which file, which line — without
  reading a scrollback. Click the red gate in the UI, see the finding."
- **Feeling:** This is where tools are actually judged; the finding either
  pinpoints the problem or it doesn't.
- **Frictions:** A fixer that retries infinitely. A finding that exists only in
  a scrollback that has scrolled away.
- **Opportunities:** MEM-A (`process/memory/`) feeds prior failure notes back
  into the next run's error message — "this check fails this way for this
  reason" lessons compound across all customers (`architecture.md` §4).

### 6. Ship — the triple *(GATE 3 — strictest)*

- **Doing:** Names **target, version and account**; the person confirms that
  exact triple. An agent may run `doctor()` preflight, reach the gate, and stop
  — never mint the token. Every other gate is a read-only assertion; this one
  writes to the outside world and cannot be undone by re-running a stage.
- **Touchpoints:** `ship-shell/select-targets.md`, `ship-shell/confirm-ship.md`;
  `architecture.md` §17 (deploy is a third human gate, and the strictest —
  names the triple; an App Store submission cannot be rolled back by re-running
  a stage).
  Flows: `flows/evan-founder/ship-shell/select-targets.md`,
  `flows/evan-founder/ship-shell/confirm-ship.md`.
- **Thinking:** "The two existing gates protect quality; this one protects
  against shipping the right build to the wrong place. The blast radius is
  named before I confirm."
- **Feeling:** Deliberate caution; this is the one irreversible act, and the
  tool makes me stop for it.
- **Frictions:** A ship step that is just "gate number six" — indistinguishable
  from the read-only assertions. A bare "Are you sure?" instead of the triple.
- **Opportunities:** Deploy targets are already wired: `fastlane-android` /
  `fastlane-ios` / `shorebird-release` / `shorebird-patch` / `cloudflare-pages`.
  Vercel throws and must not be advertised (`architecture.md` §17).

### 7. Remote — pair, serve, control

- **Doing:** Pairs the phone by QR (LAN-local, TLS fingerprint pinned from the
  payload). **Serve prototype** → the desktop starts the htmx producer's server
  and returns the URL over the paired channel → the companion opens it
  fullscreen in a WebView at true device width. A floating, draggable FAB rides
  above the WebView: app_box controls, stop server, back to the companion. The
  FAB carries **channel** state (live / reconnecting / dead), driven by the
  paired channel's heartbeat — never by whether the WebView last painted.
- **Touchpoints:** `chat-shell/drive-pipeline.md`, `settings-shell/pair-device.md`;
  `architecture.md` §15 (the companion — remote control with the prototype as a
  mode), §15 (what the FAB must not do — a dead server showing a stale render
  during a client demo is the failure mode this feature invents).
  Flows: `flows/evan-founder/chat-shell/drive-pipeline.md`,
  `flows/evan-founder/settings-shell/pair-device.md`.
- **Thinking:** "I hand the client the phone and they see the real design at
  real device width — and the FAB tells me the server is alive, not just that
  something painted."
- **Feeling:** Confident in the demo; the channel state is the honesty layer.
- **Frictions:** A FAB that infers state from paint — the desktop process dies,
  the WebView shows the last render, and the demo looks live when it isn't.
- **Opportunities:** One surface that both drives the pipeline and shows its
  output beats two surfaces with different capabilities (`architecture.md` §15).

### 8. CRUD a feature — registry, never Dart

- **Doing:** Adds, renames, or removes a feature. Always writes the **registry
  and the view/viewmodel pair** — never scaffolded Dart. Create: registry entry
  + view/viewmodel pair + surface HTML → freeze → scaffold emits. Update:
  edit the pair, re-freeze. Rename: new id plus explicit migration (id is a
  stable key, never reused). Delete additionally requires a human confirm,
  because removing code is not recoverable by re-running a stage. The orphan
  assertion catches a scaffolded view dir whose registry entry was deleted.
- **Touchpoints:** `architecture.md` §14 (authored registry → derived tree →
  generated structure.json — a genuine hybrid because the authored layer is a
  different shape from the generated one), §18 (CRUD writes the registry, never
  scaffolded Dart; delete is the hole — orphan assertion + guarded delete path).
  Flows: no dedicated flow doc — CRUD is an operation across the authored layer,
  documented in `feature-crud.md`.
- **Thinking:** "Editing Dart directly creates a second writer and the drift
  check dies. The registry is the authored source — every CRUD operation writes
  there."
- **Feeling:** Safe to iterate; the pipeline catches drift.
- **Frictions:** A fixer that deletes before it writes — once left p2 with no
  `app.locator.dart`. An orphaned view directory that keeps compiling, keeps
  passing, keeps shipping because no check caught it.
- **Opportunities:** Guard idempotence on the *desired end state*, never on
  "was this touched" (`architecture.md` §18).

## Emotion curve

```
Intake          New project     Design (G1)     Freeze          Build (G2)
 ▃ focused      ▃ in control    ▃ deliberate    ▂ cautious      ▃ trusting
 │ if brief     │ if targets    │ if hash not   │ if gate       │ if loop
 │ reads as     │ drift: ▼      │ bound: ▼      │ can't fail: ▼ │ ploughs on: ▼
 │ fiction: ▼
                                 Recovery        Ship (G3)       Remote
                                  ▂ judged       ▃ cautious      ▃ confident
                                  │ if finding   │ if bare        │ if FAB
                                  │ unlocated: ▼ │ "are you       │ infers from
                                  │              │ sure?": ▼      │ paint: ▼
```

Design-critical dips: (1) **Intake** — a generated brief is confident fiction;
the cheapest place to be wrong becomes the most expensive if it reads as
authored. (2) **Freeze** — a gate that cannot fail for the right reason is the
product's existential risk; three verification layers once agreed a broken
output was fine. (3) **Recovery** — a finding that exists only in a scrollback
is a finding that doesn't exist; this is where tools are actually judged.
(4) **Ship** — a bare "Are you sure?" on the one irreversible act.
(5) **Remote** — a FAB that infers state from paint; a dead server showing a
stale render during a client demo.

## What would break this journey

- **A generated brief** — intake must elicit, never generate. A phase that
  *writes* the brief produces requirements nobody asked for, stated with the
  same authority as ones they did (`architecture.md` §22).
- **Approval not bound to a hash** — an approved review survives a design change,
  and the shipped app is not what was approved (`architecture.md` §6).
- **Gates that pass while broken** — `dep_hash` on mtime, a self-test asserting
  the defective value, an asset check verifying strings — every one green
  (research: `spine-findings.md`). A gate that cannot fail is not a gate.
- **Red for payment** — the licence check as a gate going red teaches people to
  distrust red. Nothing goes red for money (`architecture.md` §17).
- **State inferred from paint** — the FAB showing "did the WebView render"
  instead of channel state. A dead server showing a stale render during a demo.
- **An orphaned view dir** — a scaffolded view whose registry entry was deleted
  keeps compiling, passing, shipping. Delete needs an orphan assertion and a
  human confirm (`architecture.md` §18).
- **Ship as gate number six** — indistinguishable from the read-only assertions.
  Gate 3 must name the triple and show the blast radius.

## Sources

- [`architecture.md`](../../plans/architecture.md) §1 (P1–P4 personas), §4 (memory systems), §5 (findings/SARIF/UI contract), §6 (state machine — approval binds to hash), §7 (LLM surface — `none` mode), §11 (targets), §12 (human gates), §13 (htmx MVVM), §14 (registry hybrid), §15 (companion/FAB), §16 (form-factor emission), §17 (kit/payment/deployer — Gate 3), §18 (CRUD — delete is the hole), §22 (intake elicits).
- [`feature-crud.md`](../../plans/feature-crud.md) — the CRUD contract + round-trip test.
- [`docs/research/spine-findings.md`](../../research/spine-findings.md) — `dep_hash` stale-green; `gen_freshness` holds.
- [`docs/research/headtohead-train-shell.md`](../../research/headtohead-train-shell.md) — 1,600 lines of layout invented.
- [`docs/research/remote-control-and-chat.md`](../../research/remote-control-and-chat.md) — QR pairing, FAB, OS vault.
- [`flows/evan-founder/_index.md`](../flows/evan-founder/_index.md) — the 15 flow docs cited per phase.
