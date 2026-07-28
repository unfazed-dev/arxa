# Journeys

Personas in [personas.md](personas.md); diagrams in [flows.md](flows.md);
surfaces and states in [brief.md](brief.md).

Each journey names **whose** it is, because Evan and Michelle want opposite
things from the same screen.

---

## J0 — Intake *(optional phase)*

**Evan, intake mode.** A conversation with a client becomes a brief.

app_box asks — it does not generate. Who is this for, what are the three things
it must do, what exists today, which platforms, what is the brand. Output:
`docs/design/brief.md` plus a **seeded `registry.json`** the designer consumes.

Optional by design: a brief can be hand-written, and Michelle will skip it
entirely on her first run. But it is the **only phase whose output a
non-technical client can read and correct**, which makes it the cheapest place
to be wrong.

**Done when:** every registry entry traces to something the brief asked for.

---

## J1 — First run

**Michelle.** Twenty minutes, no docs read.

Install → brand splash → credentials → **the showcase app launches by itself**.
That launch is the pitch; nothing she reads will convince her faster than
seeing the output.

Credentials fork: BYO key (→ OS vault, and the UI *states which vault*) or
shell out to an already-authenticated harness CLI.

**Fails if:** she reaches an empty Projects screen before seeing any output.

---

## J2 — New project

**Both.** Name, brand, **targets**, brief.

Targets chosen here are written to pipeline state and are what every later gate
reads. Choosing `ios, android` here is what makes freeze produce two widths and
scaffold emit the matching form factors.

**Michelle's constraint:** she should not need to know what a "target" implies.
Show the consequence — *"iPhone and iPad layouts, no desktop"* — not the flag.

---

## J3 — Design *(GATE 1)*

**Evan.** Three directions in htmx, iterate, approve exactly one.

An agent may generate, revise and present. **It cannot approve.** The approval
token is minted by a person or not at all.

**Michelle's version:** one direction, generated from the brief, accepted or
regenerated. The three-direction discipline is Evan's practice, not a
requirement of the machine.

---

## J4 — Freeze

**Evan, mostly invisible.** Six inputs, render gate, structure gate. Findings
as SARIF so the same data drives the GUI, the companion and a CI log.

**Fails if:** it reports success while a surface 404s its fonts. That has
happened; three verification layers agreed the output was fine.

---

## J5 — Build *(GATE 2)*

**Evan, autonomous mode** — start it and walk away. Real kits, real seeded
data, gates.

**Michelle** stays and watches, because she does not trust it yet. So progress
must be legible without knowing what a gate is.

💳 The licence precondition runs **here**, before the phase. It is not a gate
and never shows red.

---

## J6 — Red-gate recovery

**Evan, recovery mode.** The failure names the file, the line, the rule and
what would change. Escalation is capped (`ESC_LIMIT=3`) — after that a human is
required, by design.

**Michelle:** a red gate on her first build must not read as *"the tool is
broken."* Say what failed, in her vocabulary, and what to do.

---

## J7 — Ship *(GATE 3 — strictest)*

**Evan, ship mode.** Names **target, version and account**; the person confirms
that exact triple.

Every other gate is a read-only assertion. This one writes to the world and
cannot be undone by re-running a stage. An agent may run `doctor()` preflight,
reach the gate, and stop.

---

## J8 — Remote

**Evan.** Pair by QR (LAN-local, TLS fingerprint pinned from the payload) →
drive the pipeline → **Serve prototype** → fullscreen WebView at true device
width → state-bearing FAB back to controls.

The FAB shows **channel** state, never "did the WebView paint." A dead server
showing a stale render during a client demo is the failure this feature
invents.

---

## J9 — CRUD a feature

**Both.** Add, rename, or remove a feature.

Always writes the **registry and the view/viewmodel pair** — never scaffolded
Dart. Delete additionally requires a human confirm, because removing code is
not recoverable by re-running a stage. Full operational detail in
[feature-crud.md](../plans/feature-crud.md).

---

## J10 — Evaluate and leave

**Michelle, deliberately included.** She must be able to take her code and go.

Output is ordinary Stacked MVVM in her own repo. No export tier, no runtime
lock-in, no proprietary format. This journey existing *is* the positioning
against the incumbent's one-way export — and it must keep working, which means
somebody tests it.
