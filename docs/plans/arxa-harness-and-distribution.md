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
   DeepSeek branding dropped. dsh is rc-quality (**0.1.0-rc.7** — verified
   installed 2026-08-21; this decision originally said rc.5): **pin to a
   known-good commit, upgrade deliberately, never track master.** Pi is
   **0.84.2** (originally 0.80.7). Corrected in place rather than only in the
   amendment below, because H3 executes from this decision text.
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

> ### Amendment 2026-08-21 — DEPEND, do not fork (supersedes "fork" in 2 and 5)
>
> Ratified by the operator. Decisions 2 and 5 assumed a source fork of the dsh
> monorepo. Inspection of the installed tree says that is the expensive way to
> get the cheap thing.
>
> **Evidence.** dsh ships as **~190 separately published npm packages** under
> `@deepseek-ai/*` (`dsh-agent`, `dsh-tools`, `dsh-app-boot`, `dsh-client-ui-*`,
> `dsh-credentials`, …), none marked `private`, each carrying `main` **and**
> `exports` — verified against `0.1.0-rc.7` in the npx cache. Only the top-level
> `dsh` CLI wrapper lacks an entrypoint (`main: null`, `exports: null`, `bin:
> {dsh: lib/bin.js}`), and arxa does not need that one: it ships its own bin.
>
> **So arxa is a package that depends on dsh's components**, not a fork of its
> repo. Upstream tracking becomes:
>
> ```
> arxa update   →  bump the @deepseek-ai/* version range, run the suite
> ```
>
> No merge, no conflict resolution, no divergence debt — ever. A fork would have
> paid a rebase tax on every upstream release, forever, and that tax compounds
> precisely with how thoroughly the rebrand is done.
>
> **Correction to an earlier claim in this session:** `@deepseek-ai/dsh-brand`
> is **not** product branding and must not be planned against as a rebrand seam.
> It is a type-only nominal-typing utility (`Branded<B>`, so a `SessionId` is not
> interchangeable with a `CallId`); its `lib/index.js` is literally
> `export {};`.
>
> **Rebrand surface — audited 2026-08-21, and it does NOT justify a fork.**
> (An earlier note in this session said "24 packages"; that was a case-sensitive
> grep and is superseded by the numbers below.)
>
> | bucket | count | packages | verdict |
> |---|---|---|---|
> | `@deepseek-ai/…` import specifiers | ~4,100 | 193 | functional — invisible |
> | comments / JSDoc | 1,955 | 186 | invisible |
> | DeepSeek-the-provider (`api.deepseek.com`, model ids, `deepseek-official`) | ~127 | 6 | functional — it *is* DeepSeek |
> | **user-visible brand strings** | **47** | **9** | the only real surface |
>
> Of those 47, **32 are in `dsh-client-ui-settings-models`** — the DeepSeek
> *provider onboarding* UI (`DeepSeekModelsEditor`, `DeepSeekOnboardingDialog`,
> `onboarding-copy`). Those are not branding to strip: keep the provider and the
> strings are correct; drop it and the plugin simply is not loaded. A
> plugin-inclusion decision, not a rename.
>
> That leaves **15**, and most evaporate on inspection: `dsh/bin.js:77` is the
> `dsh` CLI's own help (arxa ships its own bin, never loads it),
> `dsh-skill-badge` is a "powered by dsh" badge plugin (don't load it), the five
> `dsh-client-connection` hits are demo fixtures (the package describes itself as
> "fixture api"), and `dsh-cordis-client-runner:3141` is a UI-slot diagnostic.
>
> **The genuinely-must-replace set is 4 strings in 2 packages**, and two of them
> are the important kind — *model-facing*, not chrome:
> - `dsh-system-prompt/lib/index.js:169` — `"You are an AI agent powered by
>   DeepSeek Harness."` This ships in the system prompt and shapes how the model
>   identifies itself. Highest priority of anything in this table.
> - `dsh-web-app/lib/index.js:56` — tells the model it is in the "DeepSeek
>   Harness Web GUI".
> - `dsh-web-app/lib/startup.js:22` and `lib/index.js:98` — CLI help and a
>   variable description.
>
> **Both are swappable without touching source.** `dsh-system-prompt` exports
> `SystemPrompt extends Service` — a cordis Service, replaceable by
> registration. And `dsh-app-boot/lib/index.js:324` holds the profile→plugin
> list as ordinary data (`web: ["@deepseek-ai/dsh-base",
> "@deepseek-ai/dsh-web-app"]`), so arxa composes its own list rather than
> editing dsh's.
>
> **Conclusion: zero source edits required.** Every user-visible brand string is
> in a package arxa either replaces with its own plugin or never loads. The
> depend-don't-fork decision stands, with no residual rebrand debt. H3 is
> unblocked on this question.
>
> Pi is unaffected: it was never forked. It is a dependency, so its updates are
> an ordinary version bump.

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

## Amendment 2026-08-21 — H1 built; three assumptions corrected by evidence

H1 is **implemented and tested** (`install.sh`, `tools/portable-core-test.sh`,
`hooks/appbox-guard.js`, `harness/`). Building it falsified three things this
plan asserted. Corrections, with the evidence that forced them:

1. **There is no dsh Claude-hooks bridge.** Decision 12's "dsh hook bridge
   config (official Claude-hooks compatibility path)" is **unbuildable as
   written**. Verified absent from installed `@deepseek-ai/dsh@0.1.0-rc.7`: no
   `PreToolUse`/`PostToolUse` events anywhere, and nothing in `@deepseek-ai/*`
   spawns a user-configured command. `dsh-session/lib/types/known-event-types.js`
   declares `hook/invoked` + `hook/result`, but that file is generated and
   nothing emits them — the subsystem exists in DeepSeek's monorepo and is not
   published in rc.7.
   **Replacement:** the interception seam is `tools/pre-execute`
   (`dsh-tools/lib/types/index.d.ts:38`), an async cordis waterfall returning
   `{kind:'allow'|'deny'|'ask'}`. Implemented as `harness/dsh-external-gate/`.
   Note `ctx.tools.guard()` is synchronous (cannot await a subprocess) and
   `permission.defaultPreset` is a declarative 3×2 matrix — neither can host a
   gate that shells out.
2. **Version drift.** dsh is `0.1.0-rc.7` (plan said rc.5) — pin exactly, no
   caret, a caret range on a prerelease moves under you. Pi is
   `@earendil-works/pi-coding-agent@0.84.2` (plan said 0.80.7); its extension
   veto is a **return value** — `{block:true, reason}` from `pi.on('tool_call')`
   — not a throw.
3. **`AGENTS.md` + `CLAUDE.md` are NOT symlinked.** Decision 12 called for it;
   doing so would be destructive. `CLAUDE.md` is entirely context-mode MCP
   routing rules that apply only to Claude Code, while `AGENTS.md` is
   harness-agnostic repo law. Symlinking either direction either hides the law
   from Claude Code or feeds dsh/Pi instructions about MCP tools they lack. Both
   files stay, each cross-referencing the other.
   **Follow-on (verified):** dsh reads BOTH by default —
   `@deepseek-ai/dsh-agent-instructions` sets `instructionFileCandidates` to
   `['AGENTS.md','CLAUDE.md']`, deduping only byte-identical siblings. So dsh
   ingests the MCP routing rules regardless of symlinks. Fix is config, not file
   layout: set `instructionFileCandidates: [AGENTS.md]` in the profile patch
   (recorded in `harness/README.md`). Pi and dsh both read `AGENTS.md`, so the
   repo law does reach them.

Two further findings that reshape later workstreams:

- **AOT compilation is a functional prerequisite, not a D21 product nicety.**
  Measured: `dart run` = 1420ms/invocation, AOT = 10ms — 142×. A gate that fires
  per tool call is unusable at 1.4s. `install.sh` therefore compiles by default,
  and the binary must live **inside** the checkout or the designer silently
  loses its runtime assets (`scriptRepoRoot()` walks up from the executable).
- **No per-tool-call policy verb exists in the engine.** Every `appbox gate`
  subcommand is a stage-level batch check, so H5's "tool-call interception
  shelling to the engine for verdicts" had nothing to call. Rather than invent
  one, the guard enforces an already-ratified rule that genuinely needs
  per-call granularity — rust-port-closure decision 12, "using-sessions never
  write into appbox". An engine verdict verb remains **unbuilt**; add it only
  when a policy needs engine state.

4. **dsh never scans `.claude/skills`** — its roots are `<root>/.dsh/skills`,
   `<root>/.agents/skills`, `customSkillDirs`, `~/.dsh/skills`,
   `~/.agents/skills` (`dsh-skill-filesystem/lib/index.js:150`); Pi scans
   `.pi/skills` + `.agents/skills`. The repo reached Claude Code through
   `.claude/skills -> ../skills`, so **dsh and Pi were seeing zero appbox
   skills**. Fixed by a committed `.agents/skills -> skills` symlink, which
   serves both. Regression-pinned in the portable-core suite.
5. **dsh CAN drive Anthropic models — H1's open auth item is answered.**
   `dsh-llm-pi-ai` forwards to `@earendil-works/pi-ai`, whose built-in catalog
   includes `anthropic` (`pi-ai/dist/models.generated.js:43`, api type
   `anthropic-messages`). Two auth paths: an API key via `apiKeyEnv`, or —
   leaving the key blank — pi-ai's built-in Anthropic **OAuth** against a Claude
   Pro/Max subscription (`pi-ai/dist/auth/oauth/anthropic.js`; authorize
   `claude.ai/oauth/authorize`, scopes include `user:inference`), the same shape
   as Claude Code's own OAuth client. There is no `dsh login` command; it is
   triggered from the Settings UI's ProviderEditor. Not configured on this
   machine (`.credentials.yaml` holds ZAI/DEEPSEEK keys only). **Untested** —
   the subscription-OAuth path should be verified before it is planned against.
   **Pre-flighted 2026-08-21 (code read, flow not run):** pi-ai's
   `anthropic.js` (301 lines, npx cache) is authorization-code + **PKCE
   S256**, local callback server at `http://localhost:53692/callback`, scopes
   `org:create_api_key user:profile user:inference user:sessions:claude_code
   user:mcp_servers user:file_upload`, token exchange at
   `platform.claude.com/v1/oauth/token`, refresh-token grant implemented. A
   **terminal paste fallback exists** ("paste the authorization code /
   redirect URL here"), so the check does not strictly need the Settings UI —
   any pi-ai-driven login can complete from a terminal. Remaining is
   operator-interactive by nature: authorize in the browser against a
   Pro/Max subscription, then one inference call proves the token. Nothing
   further is verifiable without that click.

**RESOLVED 2026-08-21 — guard scope inverted to an allowlist.** The widening
raised here was put to the operator and settled by neither ratifying nor
narrowing it, but by inverting the list.

The original denylist mirrored `appbox-doc-enforce.js`'s source set — nine dirs
(`appboxd kit pipeline gates tools skills config hooks harness`; this document
previously said eight, a miscount). Auditing the checkout showed that of its 18
top-level dirs, the denylist left `appbox-studio/`, `deploy/`, `memory/` and
`archives/` writable, along with every repo-root file (`install.sh`, `AGENTS.md`,
`pubspec.yaml`), and would have admitted every future top-level dir writable by
default. A denylist over engine source drifts open silently.

Inverted, the rule states the actual intent — a using-session records findings,
it does not touch the engine:

```js
const WRITABLE = ['docs', 'designs', 'logs'];   // everything else is engine
```

Three follow-on facts, each pinned by a test in `tools/portable-core-test.sh`:

1. **The two lists are now deliberately independent.** `appbox-doc-enforce.js`
   answers "which dirs' changes require a doc update" and stays a denylist over
   source. Re-syncing them re-opens the holes above; the code comment says so.
2. **The failure direction of shell extraction flipped.** `writeTargets()` is
   deliberately conservative — under a denylist a bad guess fell through to
   *allow*; under an allowlist the same guess *denies*. So candidates containing
   `$ \` * ? ~` are now discarded at extraction: `echo x > "$OUT"` and
   `mkdir "${TMPDIR}/p"` were never literal paths. Verified: without that filter
   both become false refusals (exit 2).
3. **The four new DENY assertions were confirmed non-tautological** by running
   them against `HEAD`'s guard (allowed, exit 0) — with a sanity assertion that
   the old guard still denies `appboxd/`, because a first attempt at this proof
   ran the variant from a scratch dir, where `__filename`-derived `repoRoot`
   pointed outside the checkout and made *every* target look external.

**Not verified:** that `docs/`, `designs/`, `logs/` is the complete set of places
a using-session legitimately writes inside the checkout. It comes from the
previous code comment, not from observing a real client-project session, and no
evidence-dir path is configured in `config/appbox.config.json` to confirm it
against. The list was deliberately not widened on speculation; a missing target
will surface as a refusal, and the documented escape is
`APPBOX_GUARD_MODE=dev <command>`.

⚠️ **Operational — MIGRATED 2026-08-21 11:06, rotation still owed.** The 3
plaintext lines in `~/.dsh/profiles/web/cordis.patch.yml` are now
`!!js process.env.ZAI_API_KEY` references (the dsh loader evaluates `!!js`
scalars at entry activation — `cordis-plugin-loader/lib/index.js:279`), and
the value lives in the appbox vault (Keychain, catalog key `ZAI_API_KEY`,
verified `set`). Verified clean by fingerprint: zero non-comment lines with
28+‑char secret-shaped runs. Still owed, operator-only: (1) **rotate the
exposed key** — it sat plaintext on disk since at least Aug 19; (2) delete
`cordis.patch.yml.pre-vault-20260821-110610` (0600 backup holding the old
plaintext) after rotation; (3) launch dsh as
`appbox credentials exec ZAI_API_KEY -- <dsh boot>` or the providers see an
empty env.

## Workstreams

- **H1 — portable core** — **DONE 2026-08-21.** install.sh + generated PATH
  wrapper + AOT build; the shared guard and its three harness adapters; dsh
  pinned to 0.1.0-rc.7; **62 checks green** (47 portable-core + 6 dsh + 9 Pi).
  Guard scope later inverted to a `docs/designs/logs` allowlist (see RESOLVED
  note above). Not done: a booted-session end-to-end check of dsh/Pi dispatch
  (needs model credits), and dsh Anthropic auth (no Anthropic provider is
  configured; the machine runs Z.ai/GLM).
  **Staged 2026-08-21 — two operator commands from done.** Found while
  staging: the web profile's patch has NO appbox-gate insert row (its 4
  entries are all MCP servers) and no profile declares `dsh-external-gate`,
  so the gate has never been mounted in a booted session — the 6 dsh checks
  test the plugin in isolation. A `headless` profile now exists
  (`~/.dsh/profiles/headless/package.json`, bundles dsh-base + dsh-headless —
  a one-shot no-browser Agent driver). The gate insert row is templated at
  `harness/headless-profile/cordis.patch.yml` (patch files are
  operator-protected, so the copy is yours):
  **Superseded within the hour by H3's bin — now ONE command** (`arxa
  --headless` materializes its own gate-wired profile at runtime, so no
  manual patch copy):
  ```sh
  cd <app-box> && APPBOX_GUARD_MODE=using appbox credentials exec \
    ZAI_API_KEY -- node ../arxa-harness/bin/arxa.mjs --headless \
    "append a one-line comment to appboxd/lib/cdp.dart"
  ```
  PASS = the reply quotes the guard's deny reason (using-sessions cannot
  write into the engine) — and doubles as H3's booted identity check. Only a
  DENY is proof-of-life — an allow is indistinguishable from an unmounted
  gate (harness/README.md:163). Cost: one turn, ~2K tokens on Z.ai. (The
  manual-copy variant via `harness/headless-profile/` stays as the
  arxa-free fallback.)
  **CLOSED 2026-08-21 — booted DENY observed.** The reply quoted the guard's
  deny text verbatim (policy hint + override line included), file untouched.
  The proof-of-life rule earned its keep: the first booted run silently
  ALLOWED the mutation. Three defects only a booted session could catch,
  all fixed: (1) the patch row filtered on Claude-cased tool names but dsh
  registers `write`/`edit`/`str_replace_editor`/`bash` (dsh-tool-fs) — the
  gate matched nothing; (2) appbox-guard's WRITE_TOOLS regex was anchored so
  `str_replace_editor` fell outside it; (3) the plugin read
  `ctx.sandboxPolicy` by property, which cordis refuses without `inject` —
  crashed the hook once names matched (now `ctx.get('sandboxPolicy')`).
  Model auth saga en route: coding-CN key dead (401), catalog `zai` route
  secretly points at the CODING endpoint (pi-ai providers/zai.js:9), coding
  weekly quota spent till Aug 24 (code 1310, per-subscription so rotation
  won't reset it), glm-5.3 tier-limited on pay-as-you-go (1302) — the check
  ran on `zai`/glm-4.6v against wallet balance. `~/.dsh/settings.yaml` now
  carries: `zai` pinned to the general endpoint, `zai-coding-cn` re-pointed
  to the international coding endpoint on ZAI_API_KEY with glm-5.3
  reasoningEfforts declared — flip default back to zai-coding-cn/glm-5.3
  effort max after the Aug 24 10:04 reset. No `credentials exec` wrapper
  needed: dsh auths from its own store.
  **Pi half CLOSED same day + home discipline (operator correction ×2).**
  arxa now owns `~/.arxa` outright (`~/.arxa/dsh` = DSH_HOME,
  `~/.arxa/pi` = PI_CODING_AGENT_DIR) and never writes into `~/.dsh`/`~/.pi`
  — settings + credentials seeded on first boot (env still wins), Pi
  models.json + extension symlinks refreshed per launch. The booted Pi check
  first silently ALLOWED a protected write: jiti reports a symlinked
  extension's link path, so appbox-gate.ts resolved the guard under the
  extensions dir, found nothing, and the fail-open swallowed it — fixed with
  realpathSync + a loud load-time "gate INACTIVE" stderr line. Re-run: both
  dsh and Pi quote the guard's deny verbatim from the isolated home, file
  untouched. Pi runs on `zai-wallet` (models.json custom provider, general
  endpoint, apiKey shelled from the appbox vault at request time).
  **Note for W1:** H1 already delivered one of W1's five items — "read-only
  gate on `appboxd/` in using-sessions" is the shared guard, and it landed
  wider than W1 asked (whole checkout, not just `appboxd/`). W1 inherits it;
  do not build it twice.
- **H2 — legal**: DONE in this commit (root LICENSE, designer re-scope,
  story-mapper proprietary). Remaining D20 items (free-tier EULA) ride the
  product horizon.
- **(W1 from the previous plan runs here — lens spine, on the new daily
  surface.)**
- **H3 — harness skeleton.** **BUILT 2026-08-21, config-verified** —
  `totem_labs/arxa-harness/` (decision 5's separate home — it briefly landed
  in `app-box/harness/` and was moved out the same day; the depend-don't-fork
  amendment voided the fork lineage, not the address): the package
  (exact-pinned `@deepseek-ai/*` deps, own bin),
  `bin/arxa.mjs` (materializes the arxa profile into `$DSH_HOME/profiles/arxa`
  and execs dsh's bin; `--headless` swaps dsh-web-app for dsh-headless), and
  `profile/cordis.patch.yml` (three patches: identity via
  `includeHarnessIdentity: false` + arxa persona — a CONFIG override, one rung
  above the planned plugin swap, since dsh-base's `system-prompt` entry ships
  the DeepSeek line behind that flag; `instructionFileCandidates: [AGENTS.md]`
  per amendment 3; the appbox-gate insert row). Verified in a sandbox
  `DSH_HOME` via `--dump-config`: composed entry list carries the arxa
  persona, `includeHarnessIdentity: false`, AGENTS.md-only instructions, and
  the gate row — and zero "powered by DeepSeek" anywhere. Remaining for a
  FULLY booted validation: the one operator dispatch command below (it also
  closes H1's open check). Original rewrite rationale follows.
  **REWRITTEN 2026-08-21** — the original text
  ("fork dsh into `totem_labs/arxa-harness`, rebrand, strip, pin") is void. The
  depend-don't-fork decision above replaced it, and the rebrand-surface audit
  removed its last objection: zero source edits are required, so there is
  nothing to fork *for*. Left as written, H3 would have executed a decision this
  plan already overturned. What it is now:
  1. **A package, not a repo.** `arxa` depends on `@deepseek-ai/*` components at
     a pinned `0.1.0-rc.7` (exact — a caret on a prerelease moves). No clone, no
     rebase tax.
  2. **Compose the plugin list, don't edit it.** `dsh-app-boot/lib/index.js:324`
     holds profile→plugin as ordinary data, so arxa declares its own list. This
     is also how the 43 of 47 user-visible brand strings that live in packages
     arxa never loads simply stop existing.
  3. **Register two replacement plugins** for the 4 strings that do ship. The
     model-facing one first: `dsh-system-prompt` exports `SystemPrompt extends
     Service`, so an arxa Service registered in its place changes what the model
     is told it is. `dsh-web-app` carries the other.
  4. **Ship arxa's own `bin`** — the only dsh package with no entrypoint is the
     top-level CLI wrapper, and arxa does not want it anyway.
  5. `arxa update` = bump the version range, run the suite. That is the whole
     upstream story.
  6. Then the UI work the original bullet ended on: Clients/stages side panel,
     CLI panel.

  **Verify by running, not by reading:** boot a composed profile and assert the
  system prompt contains arxa's identity and not DeepSeek's. That check is the
  one that fails if step 3 silently didn't take — a plugin that fails to
  register leaves dsh's default in place and everything still boots.
- **H4 — design panel**: viewer first (iframe + live reload + rungs);
  drag overlay after the engine `design patch` verb exists.
  **Viewer BUILT 2026-08-21** (`9f48fa37`, now
  `arxa-harness/plugins/design-panel/`) —
  web-UI plugin in the `__ModuleLoader__` factory shape, registered into
  `shell.overlay` (the additive slot; `details` is occupied and would be
  replaced), docked iframe over a live `appbox design serve` with the
  390×844 / 744×1133 / 1280×832 rung ladder, URL field, remount button.
  Wired into the arxa profile by package name (client discovery needs the
  package.json `dsh.client` declaration); `arxa` pnpm-installs it on first
  boot. Composed-config verified in a sandbox DSH_HOME; visual check rides
  the first operator `arxa` web boot. Drag overlay stays deferred until
  `design patch` exists.
- **H5 — memory + context**: engine memory verbs + store, dsh plugin + Pi
  extension adapters, lazy-skills refactor of the 13 skills, compaction
  discipline.
  **Verbs + adapters BUILT 2026-08-21** (`c891ec15`, `9f48fa37`):
  `appbox memory add|recall|why` (project-scoped `<project>/memory/facts/`,
  `{fact, source, ts}` schema shared with the engine's repo memory,
  provenance mandatory, 200-fact cap refuses — the M1 write-path doctrine at
  the verb layer; 11 tests). Adapters (in `arxa-harness/`):
  `plugins/memory/` (dsh, registers
  an `arxa:memory` system-prompt section at mount — tested end-to-end against
  the compiled binary) and `pi/arxa-memory.ts` (Pi, one persistent
  message on the session's first `before_agent_start`; verified contract).
  **Lazy-skills refactor SCOPED, deliberately not bulk-executed:** all three
  harnesses already load skills on demand from the frontmatter description
  line, and 7 of 13 SKILL.md files are ≤143 lines. The real targets are the
  six over 250 (scaffolder 543, designer 347, intake 329, story-mapper 304,
  moodboarder 293, cicd 264 — 2,762 total), and those bodies are ratified
  engagement law: shrinking them is per-skill editorial work behind the
  `gate skill` SSOT check, its own pass, not a mechanical sweep.
  Compaction discipline: gates already sit outside compactable context by
  architecture (they are hooks); stage-boundary compaction is session
  practice, nothing buildable until a dsh compaction plugin config exists.
- **H6 — product builds** (product horizon, reopens D-series): Studio
  bundle (locked harness + compiled engine + embedded/streamed skills),
  BYO edition (stub skills + `arxa brief` + canaries), entitlement wiring.
  **Status 2026-08-21:** the engine half already exists —
  `appbox entitlement status|verify|mint --dev` (ed25519, machine-bound JWT,
  grace handling) and the AOT compile path (`install.sh`). Everything else is
  operator-provisioned before it can be built: production keypair, Apple
  Developer ID + notarization, the P1/P2 licence decisions' price point, and
  the outward name check (decision 10). Blocked on those inputs, not on
  engineering.
- **H7 — full rename** (gated on harness validation): binary, skills,
  repo, docs → arxa in one pass. **Gate status 2026-08-21:** one operator
  command from open — the staged dispatch check under H1 is the validation
  this gate names. Even then, execute as its own deliberate pass (live
  design servers run from this checkout; the rename moves their ground).

## Pi plan items — build pass 2026-08-21 (decisions 3, 12, 17)

- **Design exploration on Pi's session DAG (decision 17) BUILT + booted** —
  `arxa-harness/bin/arxa-explore.mjs`: one Pi session file, one branch per
  design option (`session.navigateTree` back to the base node, prompt down a
  fresh branch, label the leaf), optional `--summarize` branch summaries,
  JSON out with each branch's final assistant text and a
  `pi --session <file>` resume line. Booted proof on `zai-wallet`/glm-4.6v
  from `~/.arxa/pi`: two branches, each answering only its own prompt.
  Two findings the booted run forced:
  1. **`appbox credentials exec` anchored its catalog on the CWD** —
     `bin/appbox.dart:103` fell back to `Directory.current` when the cwd walk
     found no repo marker, so Pi's `!appbox credentials exec …` apiKey shell
     (models.json) crashed from any directory outside the checkout, and pi
     swallows that into an empty assistant message (`prompt()` resolves;
     errors ride the event stream). Fixed with the existing
     `scriptRepoRoot()` executable anchor — the same 821a5f58 family bug.
     The driver now subscribes to the event stream and hard-fails on empty
     branch answers (a silent-empty branch is the PASS-that-did-not-run
     shape).
  2. **sdk.md drifts from the shipped build** — docs' `SessionManager
     .getPath()` is `getBranch()` in dist (`core/session-manager.d.ts:261`);
     the package exports only an `import` condition so `require.resolve`
     cannot see it. Both pinned in the driver with comments.
- **Operator raw-surface gating (decision 12) documented** —
  `arxa-harness/README.md` now carries the operator's own copy step for
  gating raw `~/.dsh` (patch row with dsh-native tool names) and raw `~/.pi`
  (symlink, safe since the gate realpaths), each proven by a booted DENY.
- **Lazy-skills refactor (decision 3i / H5) DONE** — the six >250-line
  skills went progressive-disclosure: a lean every-run core in SKILL.md plus
  verbatim-relocated law under `references/` with a load-when index. Core
  lines: scaffolder 543→135, designer 347→211, intake 329→165, story-mapper
  304→133, moodboarder 293→82, cicd 264→122 (2,080→848). Executed as six
  parallel per-skill passes, each behind a `consult.sh gate skill` SSOT
  check (all convergent); verified centrally: sorted-diff shows ZERO
  original lines missing (the only `<` lines are seven disclosed
  heading-level changes, text intact at the new level) and all six
  frontmatter blocks byte-identical (the description line is the lazy-load
  surface all three harnesses show). Not one normative line rewritten —
  relocation only, per the ratified-engagement-law constraint H5 recorded.
- **Delegated-Pi tool in arxa sessions (decision 3ii) BUILT + booted** —
  `arxa-harness/plugins/pi-delegate/` registers `delegate_pi` via
  `ctx.tools.register(defineTool(...))` (the dsh-tool-fs/-bash seam;
  registration alone advertises the schema to the model — no separate
  exposure list). One-shot `pi -p --no-session` in the workspace, default
  `zai-wallet`/glm-4.6v, provider/model/cwd overridable per call; the child
  inherits `PI_CODING_AGENT_DIR=~/.arxa/pi`, so delegated runs carry the
  appbox gate. Booted proof: `arxa --headless` dispatch on `zai`/glm-4.6v —
  session log shows the `tool/result` event returning Pi's answer verbatim
  ("delegated"), not a model shortcut. Two seam facts pinned in comments:
  dsh's schema compiler rejects `required: false` (omit the key on optional
  params), and dsh-tool-subagent's `ctx.subagents` provider contract was
  deliberately NOT implemented — decision 3ii needs bounded delegation, not
  continuable dsh-child machinery. arxa's seeded default stays
  zai-coding-cn/glm-5.3/max (works after the Aug 24 quota reset; the booted
  check temporarily ran on the wallet endpoint and the default was
  restored).
