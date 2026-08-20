# arxa — harness, distribution and rename — grill decisions 2026-08-21

**Status:** decisions locked 2026-08-21 (second grill session, ledger
confirmed). Separate plan from
[rust-port-closure-and-surgical-lens.md](rust-port-closure-and-surgical-lens.md)
by explicit decision; that plan's W-series still stands and is sequenced
against this one in section F. Evidence: six research reports (DeepSeek
Harness openness, distribution channels, repo ground truth, multi-harness
feasibility, Pi/dsh memory features, skill-IP protection). Advisor consult
skipped (no API key), recorded per convention.

## A. Scope

1. This plan covers **operator distribution now**. The D17–D23 product
   plan in [distribution-and-platforms.md](distribution-and-platforms.md)
   is held as a compatibility constraint, not reopened; decisions here may
   force a reopen later (flagged in section H).

## B. The arxa harness

2. **arxa gets its own dedicated harness, forked from DeepSeek Harness
   (`dsh`)** — github.com/deepseek-ai/deepseek-harness, MIT, TypeScript,
   Cordis plugin kernel, "everything is a plugin" (loop, tools, UI,
   compaction all swappable). Fork obligations: MIT notices kept, all
   DeepSeek branding dropped. dsh is rc-quality (0.1.0-rc.5): **pin to a
   known-good commit, upgrade deliberately, never track master.**
3. **Pi (earendil-works/pi, MIT) contributes its DNA and runs as a
   delegated engine**: (i) design principles ported — sub-1k-token lean
   system prompt discipline, lazy skills (one description line per turn,
   full instructions on demand), DAG sessions; (ii) Pi as a delegated
   subagent engine inside arxa sessions where its strengths earn it.
   dsh + Pi are **internal machinery and operator tools exclusively** —
   no engine picker or multiplex surface in the product.
4. **The harness keeps dsh's base UI** (chat composer, model picker,
   session side panel) and grows by plugins. Engines keep their native
   LLM-provider plumbing; API keys centralize in the `appbox credentials`
   vault.
5. **Home: separate repo** at
   `/Volumes/developer_ssd/Developer/totem_labs/arxa-harness` (clean fork
   lineage from dsh, own release cadence; pins a compatible engine
   revision).

## C. Product line and payment gating

6. Three flavors, one codebase:
   - **arxa Studio** (buyers): signed/notarized installer per D22/D23 —
     the locked harness (plugin manager removed, TypeScript bundled into a
     single executable), the compiled engine (D21 AOT + embedded assets),
     skills embedded encrypted or streamed per session. Buyers install no
     SDK, no git, nothing visible.
   - **arxa BYO-harness edition**: for customers in their own agent CLI
     (Claude Code, their dsh, Pi): compiled engine binary + stub skills +
     AGENTS.md + per-harness hook shims.
   - **Operator build** (Totem Labs): open, pluggable, dsh + Pi
     first-class from source.
7. **The payment gate lives in the compiled engine at the emit boundary**
   (D17/D18 unchanged): `arxa login` device-code flow → Supabase Auth →
   machine-bound JWT → every scaffold/emit verb verifies server-side
   before producing output. Harness-proof by construction — identical for
   Studio and BYO. Harness-level locks are courtesy UX only; a client-side
   check in an open plugin system is decoration.
8. **Pi ships inside the product installer only if dogfooding proves the
   delegated-engine path** — decided by evidence, not now.

## D. Skill IP protection

9. Ground truth accepted: **prose that reaches an LLM is eventually
   public** (Cursor's and Devin's fully server-side prompts are in a
   140k-star public repo). Protection layers, per tier:
   - Studio: skills as encrypted/bytecode-compiled assets or per-session
     server streaming — deterrence-grade, plus audit.
   - BYO: **stub skills** — the shipped SKILL.md is a thin shell that
     fetches the methodology body via `arxa brief <stage>` after the
     entitlement check (Claude Code supports this natively via dynamic
     context injection). No methodology file ever rests on the customer's
     disk; every delivery is entitled, logged, and **watermarked with
     per-customer canary strings** for attribution.
   - Both: D20 legal layer (executed 2026-08-21 in this commit — root
     proprietary LICENSE added; designer LICENSE re-scoped to preserve
     only the upstream Jim Liu MIT attribution for derived portions;
     story-mapper's erroneous MIT replaced with proprietary).
   - Durable protection is architectural: methodology migrates from prose
     into compiled verbs over time; the surgical-lens program already
     moves this way.

## E. Naming — appbox → arxa

10. **arxa is the product and brand** (arxa, arxa Studio, arxa harness);
    **appbox remains the engine name** for now. Staged rename: brand-level
    immediately; the full rename (binary, skills, repo, docs) is its own
    workstream **gated on harness validation** — executed as one
    deliberate pass, never piecemeal. Before anything outward-facing: name
    check (trademark, domain, npm/pub namespaces).
11. **The semantic prefix is `arxa-` in full** (e.g.
    `<div class="arxa-container">`), superseding `abx-` from
    rust-port-closure decisions 9–10 (amendment recorded there). The
    controlled vocabulary is the **arxa dictionary**. Cheapest-ever moment
    to change: the dictionary and its gates (W4) are not yet built.

## F. Operations and sequencing

12. **Daily surface: raw dsh + Pi, immediately after the portable core
    lands.** The portable core is the prerequisite — until it lands,
    dsh/Pi sessions run without enforced gates:
    - committed `install.sh` + generated PATH wrapper (replaces the
      hand-written machine-bound shim; AOT compile stays product-horizon
      D21/D22);
    - one `AGENTS.md` with `CLAUDE.md` as symlink;
    - dsh hook bridge config (official Claude-hooks compatibility path;
      exit-2 blocking and deny>ask>allow folding preserved);
    - Pi gate extension (small TS package: `before_agent_start` +
      tool-call interception shelling to the engine for verdicts — Pi has
      no shell hooks; its extensions are strictly stronger).
    Known costs accepted: API-key model billing on dsh/Pi (test dsh's
    Anthropic auth options early), rc breakage absorbed via pinning.
13. **Order: portable core → W1 lens spine (previous plan) → harness
    skeleton + CLI panel → design panel.** W5/W7 slot in on client demand.

## G. Harness UI and engine integration

14. **Side panel = Clients → project → stages.** dsh's workspace panel is
    restructured: top level Clients; under each client project the arxa
    pipeline stages, always present, in order (intake → story-map →
    moodboard → design → scaffold → build → test → review → deploy). The
    tree renders **from the engine** (project registry + gate/verdict
    status per stage); sessions attach to a client + stage; opening a
    stage resumes its session with the stage skill and the project's
    memory slice injected.
15. **Design panel** (plugin): iframe over the existing
    `appbox design serve` with live reload while the designer streams, and
    a rung switcher rendering the viewport ladder (390×844 / 744×1133 /
    1280×832). Direct manipulation: hit-test regions via their `arxa-*`
    identity, drag handles that **snap to the design-token scale**, and
    every drag applied as a **structured patch through a new engine
    `design patch` verb** — never freeform DOM/CSS writes. Mouse in,
    deterministic artifact edit out; design lint still gates the result.
16. **CLI panel** (plugin): filtered live view of the session log's
    engine invocations (command, stdout/stderr, exit code, duration) with
    copy-logs and one-click attach-to-session-context.
17. **Memory: the engine owns it; the harnesses are its hands.**
    - The store is an **engine artifact**, project-scoped, living with the
      client project; read/written via engine verbs
      (`arxa memory add | recall | why`). Stages write memory as pipeline
      output: intake decisions, design-lock rulings, lens verdicts, fix
      history, client preferences.
    - The dsh Cordis plugin and Pi TS extension are thin adapters over
      those verbs (inject recall at session start, capture durable facts).
      One store, every surface — including bare BYO shells.
    - The engine drives session features: design exploration on Pi's
      session DAG (fork per design option, branch summarization); the
      bounded auto-fix loop and audit trail on dsh's session-log
      fork/replay; stage boundaries as deliberate compaction points.
    - Context discipline adopted: lazy-skill progressive disclosure
      refactor for the 13 skills; cache-aligned compaction (with prompt
      caching, full history often beats summarizing — compact only at
      named constraints); **gates stay outside compactable context**
      (they are hooks, not prose). The term "temporal memory" is retired —
      dsh has no memory feature, only the append-only session log; Pi has
      none either; the arxa memory plugin is ours to build.

## H. Deferred (not decided here)

- Buyer model access (BYO API key vs metered gateway) — product-horizon
  pricing question; reopens D-series.
- Pi inside the product installer — dogfooding evidence (decision 8).
- Full appbox→arxa rename pass — gated on harness validation
  (decision 10).

## Workstreams

- **H1 — portable core** (first; days): install.sh + wrapper, AGENTS.md +
  CLAUDE.md symlink, dsh hook bridge config, Pi gate extension, dsh pin,
  dsh Anthropic-auth test.
- **H2 — legal**: DONE in this commit (root LICENSE, designer re-scope,
  story-mapper proprietary). Remaining D20 items (free-tier EULA) ride the
  product horizon.
- **(W1 from the previous plan runs here — lens spine, on the new daily
  surface.)**
- **H3 — harness skeleton**: fork dsh into `totem_labs/arxa-harness`,
  rebrand, strip, pin; Clients/stages side panel; CLI panel.
- **H4 — design panel**: viewer first (iframe + live reload + rungs);
  drag overlay after the engine `design patch` verb exists.
- **H5 — memory + context**: engine memory verbs + store, dsh plugin + Pi
  extension adapters, lazy-skills refactor of the 13 skills, compaction
  discipline.
- **H6 — product builds** (product horizon, reopens D-series): Studio
  bundle (locked harness + compiled engine + embedded/streamed skills),
  BYO edition (stub skills + `arxa brief` + canaries), entitlement wiring.
- **H7 — full rename** (gated on harness validation): binary, skills,
  repo, docs → arxa in one pass.
