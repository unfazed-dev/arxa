# Personas

Two people. Everything app_box does serves one of them.

Personas are **proto-personas** — grounded in the product spec
([`architecture.md`](../plans/architecture.md) §1) and measured research
([`docs/research/`](../research/README.md)), not in user interviews. Every
behavioural claim below is a design hypothesis to validate (brief §8).

---

## Evan — founder, Totem Labs

> "I need the quality to not depend on how tired I was that week."

Solo Dart / Rust / Flutter / Stacked developer. Builds bespoke apps for
clients: designs for them, then builds autonomously. app_box is both his tool
and his product. One person doing intake, design, architecture, build, review
and ship — no design partner to hand off to, no reviewer to catch mistakes, no
QA. The pipeline is the colleague he does not have.

He operates in **four modes**, and the product should feel different in each:

### Intake mode (P1)

> "How many surfaces is this, what's already covered by kits, what's bespoke?"

- **Context:** has a signed client, a brief, maybe a Figma or HTML mocks. Needs
  to turn that into a frozen, approvable design and quote a delivery date.
- **Jobs to be done:**
  1. *When a client signs, I want a surface count and coverage estimate within
     an hour, so I can quote honestly.* Success: a surface inventory and kit
     coverage estimate before any design work starts.
  2. *When I elicit requirements, I want the client to correct my
     understanding, not admire my confidence.* Success: intake asks and records;
  it never generates (architecture.md §22).
- **Frustrations:** nothing gives a surface count before work starts. Features
  appear because someone thought of them — no traceability to the brief.
- **Flows that must work:** `projects-shell/new-project.md`,
  `projects-shell/showcase-first-run.md`.
- **Design must get right:** intake is the only phase whose output a
  non-technical client can read and correct — make it legible, make inferences
  visible.

### Autonomous-build mode (P2)

> "Start it and let me walk away. Stop on a red gate, don't plough on."

- **Context:** design is frozen and approved. Wants to come back to graded work,
  each surface with a green gate record and a diff he can actually review.
- **Jobs to be done:**
  1. *When I start a build, I want it to run unattended and stop on failure, so
     I can trust what completed.* Success: the loop runs, stops on a red gate,
     leaves a legible trail (`architecture.md` §5).
  2. *When I come back, I want to see what was built and what failed, without
     reading a scrollback.* Success: the build view shows stage timeline, SARIF
     findings grouped by gate, file/line, reproduce command.
- **Frustrations:** every surface costs a model call and nothing is reproducible
  — re-running produces different code. Gates that pass while broken.
- **Flows that must work:** `build-shell/run-build.md`,
  `build-shell/accept-build.md` (Gate 2).
- **Design must get right:** progress legible at a glance; the licence
  precondition runs before the phase, never as a red gate (`architecture.md`
  §17).

### Red-gate recovery mode (P3)

> "Which gate, which check, which file, which line — without reading a scrollback."

- **Context:** something failed. This is where tools are actually judged. Wants
  the finding with file/line and the exact command to reproduce it.
- **Jobs to be done:**
  1. *When a gate goes red, I want the finding pinned to the file and line that
     caused it, so I can fix in minutes.* Success: click the red gate in the UI,
     see the SARIF finding, the command, and the suggested fix.
  2. *When the fixer retries, I want it capped so I am not watching an infinite
     loop.* Success: `ESC_LIMIT=3` — after that, a human is required
     (`architecture.md` §6).
- **Frustrations:** 16 of 22 gates print to stdout only — if the terminal is
  gone, the finding is gone.
- **Flows that must work:** `build-shell/red-gate-recovery.md`.
- **Design must get right:** a red gate must not read as "the tool is broken."
  Say what failed, where, and what to do.

### Ship mode (P4)

> "Proof that what I'm shipping is what was approved — and stop me if it isn't."

- **Context:** client approval, then release. Wants per-platform builds that are
  genuinely native, not a phone layout stretched.
- **Jobs to be done:**
  1. *When I ship, I want to confirm the exact target, version and account, so I
     never ship the right build to the wrong place.* Success: Gate 3 names the
     triple and requires explicit confirmation (`architecture.md` §17).
  2. *When I approve a design, I want that approval bound to a hash, so a design
     change after approval is caught.* Success: `done` exits non-zero if the
     design moved after approval.
- **Frustrations:** approval is not bound to a design hash today — an approved
  review can survive a design change.
- **Flows that must work:** `ship-shell/select-targets.md`,
  `ship-shell/confirm-ship.md` (Gate 3).
- **Design must get right:** ship is the strictest gate — the only one that
  writes to the outside world and cannot be undone by re-running a stage.

**Evan abandons app_box if:** red stops meaning broken.

---

## Michelle — indie iOS + Android developer

> "Give me twenty minutes. If I don't see output quality by then, I'm gone."

Ships her own apps to both stores. Solo, unfunded, time-poor. Has no context on
app_box's architecture and will not read the docs before trying it. Evaluates
app_box against FlutterFlow on a Tuesday evening.

- **Context:** has been burned by a tool that made export a paid tier and
  another whose generated code she could not extend.
- **Jobs to be done:**
  1. *When I install it, I want to see what it produces before I type anything,
     so I can judge output quality in the first minute.* Success: the showcase
     app launches on install, automatically.
  2. *When I build my first project, I want native-feeling layouts on both
     platforms without hand-writing scaffolding, so I save the fifth
     repetition.* Success: `--targets ios,android` produces two freeze widths
     and matching form factors.
  3. *When I evaluate, I want to take my code and leave, so I am not locked
     into someone else's runtime.* Success: output is ordinary Stacked MVVM in
     her own repo — no export tier, no proprietary format.
- **Frustrations:** discovering a limitation at build time that was knowable at
  selection time. Paying to get her own code out. A kit listed as available that
  throws `UnimplementedError`.
- **Flows that must work:** `projects-shell/first-run-showcase.md`,
  `settings-shell/byo-key-setup.md`, `ship-shell/take-code-and-leave.md`.
- **Design must get right:** honesty above polish. A kit that is a stub says so
  *before* she builds against it (`stub-inventory.md`). The credential tier is
  stated on screen — *"stored in the macOS Keychain."* Empty states carry
  wording, not blank surfaces. The price is not per-seat theatre.

**What earns her trust, in order:**
1. The showcase app launches on install.
2. The code is hers — ordinary Stacked MVVM, readable and extensible.
3. Nothing lies — a stub is labelled before she builds against it.
4. The price is not per-seat theatre.

**Michelle abandons app_box if:** she hits `UnimplementedError` on something
the UI offered her — or if the free tier is crippled rather than merely smaller.

---

## What the split means

Evan needs **depth**: gates, ledgers, SARIF findings, drift detection, escape
hatches. Michelle needs **honesty and a fast first win**, and will never see
most of the machinery.

Where the two conflict, **Michelle wins on the first ten minutes** and **Evan
wins on everything after**. A surface that serves neither is the one to cut.

The three human gates are the product's core claim — the one thing an agent
cannot do alone. They must be visually distinct from anything automated, because
approval is what Evan sells and what Michelle is checking for when she asks
"does this tool actually let me stay in control?"

---

## Sources

- [`architecture.md`](../plans/architecture.md) §1 (P1–P5 personas), §5 (findings/UI contract), §6 (state machine), §17 (payment gate), §22 (intake).
- [`docs/research/competitors-and-pricing.md`](../research/competitors-and-pricing.md) — FlutterFlow / Adalo / Lovable pricing, per-seat backlash.
- [`docs/research/stub-inventory.md`](../research/stub-inventory.md) — what is wired vs what throws.
- [`docs/research/remote-control-and-chat.md`](../research/remote-control-and-chat.md) — credential storage, OS vault.

*Maintenance: update when the persona model, mode set, or trust conditions
change. Last verified against `architecture.md` §1: 2026-07-28.*
