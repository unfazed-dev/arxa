# Michelle — Buyer Journey: The 20-Minute Evaluation

**Actor:** Michelle (indie iOS + Android developer — the buyer, evaluating
app_box against FlutterFlow)
**Journey:** install → see output quality → try a project → watch a build →
evaluate → take her code and leave. Twenty minutes, no docs read. Every surface
must be legible to someone who has read none of these documents.
**Status:** proto-persona journey — pipeline mechanics are repo truth (cited,
`architecture.md`); thoughts/feelings are design hypotheses to validate (brief
§8). Each mechanic references its flow doc in `docs/design/flows/michelle-buyer/`
— the library holds the mechanics, this doc holds the narrative.

## Phases

### 0. Install & first run — the showcase is the pitch

- **Doing:** Installs app_box on a fresh machine with no `~/Developer`. The
  brand splash appears, then the credentials fork: BYO key (→ OS vault, and the
  UI *states which vault* — "stored in the macOS Keychain") or shell out to an
  already-authenticated harness CLI. Then the **showcase app launches by
  itself** — that launch is the pitch; nothing she reads will convince her
  faster than seeing the output.
- **Touchpoints:** `projects-shell/first-run-showcase.md`,
  `settings-shell/byo-key-setup.md`; `architecture.md` §1 (P5 — the buyer on a
  fresh machine), §15 (credentials — OS vault, UI states the tier).
  Flows: `flows/michelle-buyer/projects-shell/first-run-showcase.md`,
  `flows/michelle-buyer/settings-shell/byo-key-setup.md`.
- **Thinking:** "I haven't typed anything yet and I'm already looking at a real
  app. That's either impressive or a trick — let me see if the code behind it
  is real."
- **Feeling:** Curious; unpressured. The output arrived before the ask.
- **Frictions:** Reaching an empty Projects screen before seeing any output —
  the one thing that kills the evaluation in minute one. A credential wall that
  reads as a signup, not a config step.
- **Opportunities:** The showcase app is the dogfood — app_box shows itself.
  Every rough edge in the generated architecture is one she sees immediately,
  which is the argument for dogfooding at all (`architecture.md` §8).

### 1. Credentials — BYO key, stated plainly

- **Doing:** Chooses BYO key. The UI states the vault tier plainly — "stored in
  the macOS Keychain." She never hand-rolls crypto, and the tool never pretends
  to. The harness path is available if she already has a CLI authenticated;
  app_box never sees a token it does not have to store.
- **Touchpoints:** `settings-shell/byo-key-setup.md`; `architecture.md` §15
  (credentials — `flutter_secure_storage` → macOS Keychain; write → restart →
  read back in a signed and notarised build; two macOS failure modes fail
  silently and green).
  Flows: `flows/michelle-buyer/settings-shell/byo-key-setup.md`.
- **Thinking:** "It says where my key lives. That's either honest or naive —
  but it didn't hide it behind a 'secure cloud' euphemism."
- **Feeling:** Cautiously trusting; the vault statement is a small honesty that
  matters.
- **Frictions:** A credential flow that hides where the key is stored. A
  hand-rolled crypto implementation. A failure that goes silently green after
  notarisation.
- **Opportunities:** BYO key is a structural cost advantage, not a discount —
  inference is her key, her cost, her control (`docs/research/competitors-and-pricing.md`).

### 2. First project — consequences, not flags

- **Doing:** Creates her first project. Name, brand, `--targets`. She should
  not need to know what a "target" implies — the surface shows the consequence:
  *"iPhone and iPad layouts, no desktop."* Not the flag. Targets chosen here
  are what makes freeze produce two widths and scaffold emit matching form
  factors.
- **Touchpoints:** `projects-shell/new-project-first.md`; `architecture.md` §11
  (targets are platform-only; viewports derive — `ios,android` = two widths,
  not three).
  Flows: `flows/michelle-buyer/projects-shell/new-project-first.md`.
- **Thinking:** "I picked two platforms and it told me what I get — two layout
  sets. No mystery flags, no hidden cost."
- **Feeling:** In control; the tool speaks in outcomes.
- **Frictions:** A target selection that requires domain knowledge to predict
  its effect. Flags that drift between the GUI and the CLI.
- **Opportunities:** Mobile is always present — the viewport set is the union,
  so she never accidentally ships a desktop layout she didn't ask for.

### 3. Design — one direction, accepted or regenerated

- **Doing:** Michelle's version of the design phase. One direction, generated
  from the brief, accepted or regenerated. The three-direction discipline is
  Evan's practice, not a requirement of the machine. She sees a design at her
  viewport widths and accepts it or asks for another.
- **Touchpoints:** `design-shell/accept-single-direction.md`; `architecture.md`
  §6 (Gate 1 — the approval token is minted by a person or not at all).
  Flows: `flows/michelle-buyer/design-shell/accept-single-direction.md`.
- **Thinking:** "One direction, I can take it or regenerate. The three-option
  thing is for someone with more time than I have."
- **Feeling:** Efficient; the tool respects her time constraint.
- **Frictions:** Being forced through Evan's three-direction workflow when she
  has 15 minutes left. A design surface that requires understanding the pipeline.
- **Opportunities:** The approval still binds to a hash — even Michelle's
  single-direction accept is enforceable. The machinery is the same; the
  ceremony is lighter.

### 4. Build — watching, not operating

- **Doing:** The build runs. Michelle stays and watches, because she does not
  trust it yet. Progress must be legible without knowing what a gate is — stage
  timeline, green/red states, a clear "done" signal. If a gate goes red, it
  must not read as "the tool is broken" — it should say what failed, in her
  vocabulary, and what to do.
- **Touchpoints:** `build-shell/watch-build.md`; `architecture.md` §5 (the UI
  is a viewer — everything it renders comes from `work/`), §6 (deterministic
  gates fail loud and HALT).
  Flows: `flows/michelle-buyer/build-shell/watch-build.md`.
- **Thinking:** "I don't know what a 'scaffold coverage gate' is, but I can see
  it's green. If it goes red, the words should tell me what happened, not throw
  a stack trace."
- **Feeling:** Watchful; the trust is being built in real time, or destroyed.
- **Frictions:** Progress shown as raw log output. A red gate with no plain-
  language explanation. The licence check appearing as a red gate (which would
  read as "the tool is broken" to someone who hasn't read §17).
- **Opportunities:** The build view is where Michelle's trust is earned or lost.
  Legible progress (not log spew) is the retention lever for the buyer persona.

### 5. Evaluate & leave — ordinary Stacked MVVM, no lock-in

- **Doing:** The build is green. She inspects the output: ordinary Stacked MVVM
  in her own repo. No export tier, no runtime lock-in, no proprietary format.
  She can read the code, extend it, and build with plain `flutter build` on a
  machine that has never seen app_box. She takes her code and goes — and that
  journey existing *is* the positioning against the incumbent's one-way export.
- **Touchpoints:** `ship-shell/take-code-and-leave.md`; `architecture.md` §3
  (`output/app/` contains no reference to app_box — the delivered app builds
  with plain `flutter build` on a machine that has never seen this tool).
  Flows: `flows/michelle-buyer/ship-shell/take-code-and-leave.md`.
- **Thinking:** "The code is mine. Stacked MVVM, readable, extensible. No
  export button, no 'upgrade to download,' no runtime I don't control. If I
  want to leave, I just leave."
- **Feeling:** Autonomous; the tool gave her something she owns.
- **Frictions:** Discovering a limitation at build time that was knowable at
  selection time — `UnimplementedError` on a kit the UI offered her. Paying to
  get her own code out. A shipped app that depends on a private registry that
  stops resolving when her licence lapses.
- **Opportunities:** Vendoring the kit at a pinned SHA means the shipped app
  has no external dependency (`architecture.md` §17, decision O1). Michelle's
  code keeps building even if she never pays app_box again — that is the feature,
  not legacy.

## Emotion curve

```
Install          Credentials      First project    Design           Build
 ▃ curious       ▃ cautiously     ▃ in control     ▃ efficient      ▂ watchful
 │ if empty      │ if vault       │ if flags       │ if forced      │ if red gate
 │ Projects      │ hidden: ▼      │ not shown      │ through 3-dir:  │ has no plain
 │ before output:▼                │ as effect: ▼    ▼                │ words: ▼
                                                    Evaluate & leave
                                                      ▃ autonomous
                                                      │ if UnimplementedError
                                                      │ on offered kit: ▼▼
                                                      │ if export is paid: ▼▼
```

Design-critical dips: (1) **Install** — an empty Projects screen before any
output kills the evaluation in minute one. The showcase must launch first.
(2) **Build** — a red gate with no plain-language explanation reads as "the
tool is broken" to someone who has read no docs. (3) **Evaluate & leave** — an
`UnimplementedError` on a kit the UI offered, or a paid export tier, are the
two failures that end the evaluation permanently. Both are knowable at design
time and must be designed against here.

## What would break this journey

- **Empty Projects before output** — the showcase app must auto-launch on first
  run. If she reaches a blank Projects screen before seeing any output, she
  leaves (`architecture.md` §1, P5).
- **`UnimplementedError` on an offered kit** — a kit that throws must be
  labelled STUBBED before she builds against it. `settings.kits` shows
  wired-vs-stubbed honestly (`docs/research/stub-inventory.md`; brief §5.4).
- **Crippled free tier** — the free designer + prototype is genuinely useful
  standing alone. Someone who uses it forever and hand-builds is a funnel, not
  a leak (`architecture.md` §17). The free tier is smaller, not crippled.
- **One-way export** — the output is ordinary Stacked MVVM with no external
  dependency. No export tier, no runtime lock-in, no proprietary format
  (`architecture.md` §3, §17; decision O1 — vendoring survives publication).
- **State inferred from paint** — the FAB shows channel state, never "did the
  WebView paint." A dead server showing a stale render during a demo.
- **Red for payment** — the licence check is a precondition, not a gate. If
  Michelle sees red for money, she reads it as "broken" — and she's right, just
  not in the way she thinks (`architecture.md` §17).

## Sources

- [`architecture.md`](../../plans/architecture.md) §1 (P5 — the buyer), §3 (output/app/ contains no reference to app_box), §7 (LLM surface — `api` mode for the buyer), §8 (desktop app — dogfooding), §11 (targets → viewports), §15 (credentials — OS vault), §16 (form-factor emission), §17 (kit/payment/free-tier/deployer).
- [`docs/research/competitors-and-pricing.md`](../../research/competitors-and-pricing.md) — FlutterFlow / Adalo / Lovable pricing, per-seat backlash, BYO-key advantage.
- [`docs/research/stub-inventory.md`](../../research/stub-inventory.md) — 5/23 kits partial; Stripe/PayPal/Vercel throw.
- [`docs/research/remote-control-and-chat.md`](../../research/remote-control-and-chat.md) — credential storage, macOS Keychain.
- [`flows/michelle-buyer/_index.md`](../flows/michelle-buyer/_index.md) — the 6 flow docs cited per phase.
