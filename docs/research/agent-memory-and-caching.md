# Agent memory, self-learning, and caching for app-box

Reading-research (web sources, not measured findings), 2026-07-30. Every
load-bearing claim carries a grade: **A** = official docs / primary paper,
**B** = corroborated secondary, **C** = single-source. This is the same
question the LLM-fabric plan already half-answers (`../plans/appbox-engine-llm-fabric.md`);
this doc fills in the memory, lesson-log, and cache layers.

## Verdict (recommended architecture, up front)

1. **No agent-memory framework.** Not mem0, not Letta, not Zep. The 2026
   production evidence says unconstrained LLM-decided memory writes rot:
   one audited mem0 deployment was **97.8% junk** after 32 days (B, but
   unusually well-evidenced — full audit dataset in the issue).
2. **Files are the memory.** The settled 2026 practice is the Claude Code
   model: small human-editable index file + topic files on demand, plain
   markdown, git-versioned, zero infra (A). app-box already has the bones:
   per-run scorecards in pipeline state, gate outputs, the skills tree.
3. **Gates are the reward signal; reflexion is the loop.** app-box's
   pass/fail gates are exactly the reliable evaluator Reflexion requires.
   Add a per-stage `LESSONS.md` written only on gate failure → fixed,
   human-reviewable, and cache-friendly.
4. **Keep the Fugu-style scorecard → routing affinity.** Learned
   stage→model affinity from gate-pass-rate at zero training cost is
   sound; that is the "self-learning" that survives scrutiny.
5. **Cache the prefix, not the response.** Provider prompt caching is the
   cheapest win in a deterministic-stage pipeline: static stage prompts
   first, variable content last, reason at 0.1× input cost on
   Anthropic/Kimi/Gemini (A). Exact-match response cache for gate-fixed
   inputs only. **Skip semantic caching** — false-positive risk on
   near-identical-but-different app specs, and the class leader
   (GPTCache) is in maintenance mode (A).
6. **Everything above is local-first by construction**: SQLite + markdown
   on one laptop, no memory service, no embeddings model required.

## 1. Agent memory systems as of mid-2026

The category went from research to production in 2025–2026. Three
architectures dominate (B, corroborated across several independent
comparisons):

- **mem0** — extract-and-retrieve layer. An LLM extraction step pulls
  "facts" from each turn into a vector store (+ optional graph); retrieval
  is embedding similarity scoped by `user_id`/`agent_id`/`run_id`. The
  write path is **the pipeline's extraction prompt** deciding what is a
  fact — the developer does not curate. OSS runs fully locally (Qdrant +
  Ollama is a documented deployment). Paper claims +26% over OpenAI's
  memory on LOCOMO, 91% lower p95 latency and >90% token savings vs
  full-context (A, but vendor-authored paper: [arXiv 2504.19413](https://arxiv.org/abs/2504.19413)).
  **Failure mode, measured**: [mem0 issue #4573](https://github.com/mem0ai/mem0/issues/4573)
  audited 10,134 production memories across 32 days — **97.8% junk**.
  Dominant causes: system-prompt restating (52.7% of junk), a recall→
  re-extraction feedback loop that amplified one hallucination into
  **808 copies of "User prefers Vim"**, and transient task state stored
  as permanent fact. Key finding: upgrading the extraction model from a
  2B local model to Sonnet 4.6 *did not fix it* — a better model follows
  a permissive extraction prompt more faithfully. "The extraction prompt
  is the bottleneck, not the model." Earlier issue
  [#3009](https://github.com/mem0ai/mem0/issues/3009): extraction
  silently returning empty, 3 of 5 memory creations lost (B).
- **Letta (née MemGPT)** — OS-inspired runtime: tiered memory (core
  blocks always in context / recall / archival), and **the agent itself
  decides** what to remember via memory-editing tool calls (A,
  [letta-ai/letta](https://github.com/letta-ai/letta), MemGPT paper
  lineage). Strongest "self-improving agent" story of the three. Failure
  modes: self-editing is a consistency liability — self-hosted users hit
  tools ignoring configured embedders and hardcoding OpenAI
  ([issue #3210](https://github.com/letta-ai/letta/issues/3210), B), and
  the repo README itself notes the V1 API server is legacy while active
  development moved to a new agent repo (A) — churn risk. Secondary
  analyses call out "consistency and observability costs that most teams
  underestimate" (B, [n4n.ai](https://n4n.ai/blog/memgpt-and-letta-managing-agent-memory-beyond-context/)).
- **Zep / Graphiti** — temporal knowledge graph: entities, facts with
  validity windows, bi-temporal invalidation, hybrid retrieval
  (semantic + BM25 + graph traversal) (A,
  [getzep/graphiti](https://github.com/getzep/graphiti)). Best paper
  numbers of the three (Zep paper: 94.8% DMR, +18.5% on LongMemEval vs
  baseline, vendor-authored, A: [arXiv 2501.13956](https://arxiv.org/abs/2501.13956)).
  **But the local-first story collapsed**: Zep Community Edition was
  discontinued April 2025 (A,
  [getzep blog](https://blog.getzep.com/announcing-a-new-direction-for-zeps-open-source-strategy/));
  Graphiti is OSS but needs a graph DB (Neo4j/FalkorDB; the embedded Kuzu
  backend is deprecated upstream) and an LLM for ingestion, with
  documented failure on small/local models ("very small models
  frequently emit JSON that doesn't match the requested schema" — A,
  Graphiti README). Heavy machinery for one laptop.
- **LangGraph store** — not a product, a pattern: namespaced JSON
  documents + optional embedding index, with the honest framing that
  semantic/episodic/procedural memory are different problems (A,
  [LangGraph memory docs](https://langchain-ai.github.io/langgraph/concepts/memory/)).
  Its most useful contribution is vocabulary: **procedural memory =
  editing the agent's own prompts/instructions from feedback**, which is
  exactly what a lesson log does, without any vector store.
- **Claude Code (CLAUDE.md + auto memory)** — the local-first incumbent,
  and the model to copy. Two tiers (A,
  [Claude Code memory docs](https://code.claude.com/docs/en/memory)):
  human-written `CLAUDE.md` (loaded every session, target <200 lines —
  "longer files reduce adherence") and agent-written auto memory:
  `MEMORY.md` index capped at 200 lines/25KB loaded each session, detail
  pushed to topic files read on demand. Machine-local, per-repo, plain
  markdown, auditable. Documented limits: it is "context, not enforced
  configuration" — vague or conflicting instructions are followed
  arbitrarily; enforcement needs hooks/gates, not memory. app-box already
  has gates; competitors mostly don't.
- **Aider / Cursor conventions** — the same file-based pattern converged
  everywhere: `.cursor/rules` + `.cursorrules`, `CONVENTIONS.md`,
  `AGENTS.md` (Claude Code's `/init` ingests all of them — A, same docs
  page). The industry settled on *declared, versioned files* over
  *learned, opaque stores* for coding agents.

**The contrarian data point that survived 2026**: the most-upvoted
r/ClaudeCode memory thread of the cycle was "Please stop creating memory
for your agent frameworks" — the argument that CLAUDE.md/skills/tasks
are adequate primitives and bolted-on memory frameworks bloat context
(tripling token usage in some reports) and raise hallucination rates
(B, via [agenticbrew summary](https://www.agenticbrew.ai/news/1851b23a-e0dc-40b7-a69b-bd93653c4f5c/ai-memory-systems-for-agents)).
Related failure mode: compaction of file-memory is lossy — large learned
notes get compressed away (B, OpenClaw reports via
[36kr](https://eu.36kr.com/en/p/3723836073343622)); and a documented
"self-poisoning" bug class where a failed retrieval is summarized and
stored as authoritative fact (C, single source,
[selina.ai](https://selina.ai/blog/when-ai-memory-corrupts-itself-the-self-poisoning-summary-bug)).

### Comparison table

| system | storage | retrieval | who decides what to remember | runs on one laptop? | headline failure mode |
|---|---|---|---|---|---|
| mem0 (OSS) | vector store (+ optional graph), Qdrant local OK | embedding similarity, scoped filters | extraction-prompt LLM, uncurated | yes (A: #4573 ran Qdrant+Ollama) | extraction junk: 97.8% in one audited prod deployment; recall→re-extract feedback loops (B) |
| Letta | Postgres + vector, agent-addressable blocks | agent tool calls over tiers | **the agent itself** (self-editing) | yes, but V1 server now legacy; new stack churning (A) | self-edit consistency/observability cost; self-host tool bugs (B) |
| Zep/Graphiti | temporal knowledge graph (Neo4j/FalkorDB) | hybrid semantic+BM25+traversal | ingestion LLM + schema | partially: Graphiti OSS, but CE discontinued; needs graph DB + capable LLM (A) | small/local LLMs break extraction; infra weight (A) |
| LangGraph store | namespaced JSON docs, any DB | filter + optional embedding | your application logic | yes, trivially | none inherent — it makes you build the write policy (A) |
| Claude Code auto memory | markdown files per repo | index in context + on-demand file reads | the agent, capped & auditable (200 lines/25KB) | yes — machine-local by design (A) | advisory not enforced; adherence degrades with size (A) |
| semantic cache (GPTCache class) | SQLite + FAISS etc. | embedding similarity on query | threshold config | yes | maintenance mode — "we no longer add support for new API or models" (A, repo README) |

## 2. Self-learning without training

Three mechanisms, in order of evidence quality:

**Gate-signal routing affinity (build this).** The LLM-fabric plan's
Fugu inheritance — scorecard `{stage, tier, provider, model, tokens,
cost, gate_pass, retries}` → per-stage gate-pass-rate per tier → retune
the routing map — is the strongest "learning" available, because the
reward is a **deterministic gate**, not an LLM judging itself. This is
the Fugu/Sakana principle (measured worker performance as the SFT
signal) applied at zero training cost, and it requires no memory system
at all: the scorecard table *is* the memory. (A for the mechanism being
in-repo: `../plans/appbox-engine-llm-fabric.md` §Scorecard.)

**Reflexion-style lesson logs (build a constrained version).** Reflexion
(Shinn et al., A: [arXiv 2303.11366](https://arxiv.org/abs/2303.11366))
showed verbal self-feedback stored in an episodic buffer beats more
attempts — *when a reliable evaluator exists*. app-box's gates are that
evaluator; most agent products don't have one, which is why reflexion
underdelivers for them. The 2026-durable form is Anthropic's "structured
note-taking" (A, [context engineering post](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)):
notes persisted outside the context window, pulled back later, kept
small. Constrain it hard: lessons written **only on gate failure**, one
file per stage (`gates/<stage>/LESSONS.md`), appended as
"gate X failed because Y; do Z", capped, and read into the stage prompt.
The mem0 audit shows exactly why the write path must be gate-triggered
and append-only: unconstrained "what's worth remembering" prompts
produce junk at 97.8% rates; "the gate failed, record why" cannot
hallucinate Vim preferences because the trigger is an observed event,
not an inference. Voyager's skill library (A:
[arXiv 2305.16291](https://arxiv.org/abs/2305.16291)) is the same idea
one level up — app-box's skills tree already is the executable-skill
store; don't build a second one.

**Context engineering, durable vs hype (2025–2026 settled practice).**
From Anthropic's own engineering post (A): the durable practices are
(1) smallest high-signal token set, (2) "just-in-time" retrieval with
lightweight references over pre-computed stuffing — Claude Code itself
uses hybrid: CLAUDE.md up front, grep/glob JIT, (3) compaction +
structured note-taking + subagents for long horizons, (4) treat context
rot as real — attention degrades with length (corroborated by "lost in
the middle", A: [arXiv 2307.03172](https://arxiv.org/abs/2307.03172),
and Chroma's context-rot study, B). The hype that didn't survive:
autonomous knowledge-graph construction for coding agents, and
memory-as-a-service for single-operator tools. Note the design synergy:
lesson files are *inputs* to a deterministic stage prompt, so they sit
inside the cached prefix and cost ~0 on repeat runs; a vector-memory
lookup injects varying text mid-prompt and *breaks* the cache.

## 3. Caching: provider economics and when it pays

### Provider prompt caching (all verified against official docs, 2026-07-30)

| provider | mechanism | write cost | read cost | TTL | minimum prefix |
|---|---|---|---|---|---|
| Anthropic | explicit `cache_control` breakpoints (≤4) or top-level automatic caching (A, [prompt caching docs](https://docs.claude.com/en/docs/build-with-claude/prompt-caching)) | 1.25× base (5m) / 2× base (1h) | **0.1× base** | 5 min default, refreshed free on each hit; 1h option | 1,024 tok (Sonnet 4.6/5, Opus 4.8); 4,096 (Haiku 4.5, Opus 4.5/4.6); 512 (Fable 5) |
| OpenAI | fully automatic, ≥1,024 tok; `prompt_cache_key` to steer routing (A, [prompt caching guide](https://platform.openai.com/docs/guides/prompt-caching)) | none | "up to 90%" off, 50% typical on standard models (B) | 5–10 min in-memory (max 1h); opt-in 24h extended retention on gpt-5.x/4.1 at same price | 1,024 tok |
| Gemini | **implicit only as of the current docs page** (updated 2026-07-07): automatic, savings passed through (A, [caching docs](https://ai.google.dev/gemini-api/docs/caching)); explicit `CachedContent` caching no longer documented on that page | n/a | automatic discount on hit | system-managed | 2,048 tok (2.5 Flash/Pro); 4,096 (3 Pro preview, 3.5 Flash) |
| Kimi (Moonshot) | fully automatic, no cache ID / TTL / params; prefix must be >256 tok to be cached at all (A, [context caching guide](https://platform.kimi.ai/docs/guide/use-context-caching-feature-of-kimi-api)) | none | **0.1× base** (K3: $3.00 in / **$0.30** cache-hit / $15 out per MTok — B, pricing per official page as reported 2026-07; re-verify before quoting) | system-managed | 256 tok |

Load-bearing mechanics worth designing around (all A, Anthropic docs):

- Cache writes happen **only at breakpoints**; reads walk back ≤20 blocks
  looking for *prior writes*, not stable content. A breakpoint on a block
  containing a timestamp pays a full write every call and never reads.
- Changing tool definitions invalidates everything below them;
  `tool_choice` and images invalidate the message cache.
- Per-request **reasoning-effort switching invalidates the cache** — the
  fabric plan already pins effort at session level for this reason
  (`appbox-engine-llm-fabric.md`, A-in-repo). Anthropic's table confirms.
- Since 2026-02-05 Anthropic caches are isolated **per workspace**, not
  per org — irrelevant for BYO-key single-user, but kills any
  shared-cache-across-customers idea.
- OpenAI's routing hashes the first ~256 tokens; >~15 req/min on one
  prefix overflows to other machines and hit rate drops (A).

**When caching pays in a deterministic-stage pipeline:** this is the
best-case workload. Stage prompts are identical across runs modulo the
app spec, so: static prefix = system + stage instructions + primitives
catalog + `LESSONS.md`, breakpoint at its end; variable suffix = spec +
gate output. Expected effect at app-box scale (Sonnet 4.6, 20K-token
stage prefix, 8 stages, one retry each): without cache ≈ 16 × 20K × $3/M
≈ $0.96 of input; with prefix caching ≈ one 1.25× write ($0.075) +
15 reads × 0.1× ($0.09) ≈ **$0.17 — an ~82% input-cost cut**, plus
the documented latency win (up to 80–85% on cached prefixes, A for
OpenAI's number, B for Anthropic's). Break-even on Anthropic's 5m write
is **one hit**; on 1h, two. The only stage where caching does *not* pay
is a stage whose prompt is fully reassembled per call — which is the
lesson: **prompt assembly order is a cache API**. Put anything
run-varying last; keep per-run scorecard summaries out of the prefix or
the cache dies every run.

### Semantic caches (GPTCache class) — skip

Exact-match response caching is safe and worth having for gate-fixed
inputs (same spec + same stage version + same model → same prompt hash).
**Semantic** response caching serves a *stored answer* to a *different
question*: false positives are the documented failure (A, GPTCache's own
README names the hit/miss error classes; B,
[Portkey on thresholds](https://portkey.ai/blog/semantic-caching-thresholds)),
and two app specs differing only in "add a payment screen" are precisely
the near-duplicate inputs a semantic cache confuses. Compounding the
verdict: GPTCache is in maintenance mode ("we no longer add support for
new API or models", A, repo README) and still demos `gpt-3.5-turbo`.

## 4. The local-first constraint: what survives

| candidate | survives one-laptop, no cloud service? |
|---|---|
| Claude-Code-style markdown memory (index + topic files) | **yes, natively** — machine-local, per-repo, git-versioned (A) |
| Scorecard → routing affinity (SQLite/JSONL in pipeline state) | **yes** — it's already the plan |
| Gate-triggered `LESSONS.md` per stage | **yes** |
| Provider prompt caching | **yes** — server-side feature of APIs the user already pays for; nothing to run locally |
| Exact-match response cache | **yes** — SQLite + prompt hash |
| mem0 OSS | technically yes (Qdrant + Ollama documented), but carries the extraction-junk failure mode — the local story works, the memory doesn't (B) |
| Letta | yes, but heavy: server + Postgres, V1 API legacy, new agent stack mid-migration (A) |
| Zep | **no** — Community Edition discontinued; Graphiti needs a graph DB + a structured-output-capable LLM, weak on local models (A) |
| Semantic cache | technically yes, fails on merits (above) |
| mem0 Platform / Zep Cloud / any memory SaaS | **no** — violates the constraint by definition, and contradicts BYO-key positioning (`competitors-and-pricing.md`) |

## What we'd build / what we'd skip

**Build, in order:**

1. **Scorecard → affinity loop** (already planned) — the only "learning"
   with a trustworthy reward. Ship it first; it needs no other piece.
2. **Gate-triggered lesson logs** — `gates/<stage>/LESSONS.md`,
   append-only, written only on gate failure from the gate's own output,
   capped like Claude Code's 200-line index; read into the stage prompt's
   static prefix. Human-editable and git-diffable — the audit trail
   competitors' opaque memory stores can't offer.
3. **Cache-first prompt assembly** — static-then-variable ordering as a
   hard contract in the LLM gateway; one explicit Anthropic breakpoint
   per stage prompt; record `cache_creation/cache_read` token fields in
   the scorecard so cache hit rate is a measured pipeline metric.
4. **Exact-match response cache** keyed on `(stage, model, prompt hash)`
   — makes re-runs of deterministic stages free and gives the regression
   suite (~20 app specs) a near-zero marginal cost.

**Skip:**

- **mem0/Letta/Zep or any agent-decided memory store.** The 2026
  production evidence (97.8% junk audit; Zep CE shutdown; Letta stack
  churn) says the category's write path is unsolved, and app-box's
  gates make the curated alternative strictly better.
- **Semantic response caching.** Wrong tool for near-duplicate inputs;
  upstream project in maintenance mode.
- **Vector embeddings for memory retrieval.** Lesson logs per stage are
  small enough to read whole; retrieval is `cat`, not ANN search.
  Revisit only if a lessons file ever exceeds the ~25KB that Claude
  Code's cap implies is the adherence ceiling (A).
- **A memory MCP server / memory-as-a-service.** Contradicts local-first
  and BYO-key; the differentiator is that app-box's memory is *files in
  the user's repo* — inspectable, diffable, deletable.

The positioning angle: every competitor's "memory" is an opaque store the
user cannot audit; app-box's would be **deterministic, git-versioned, and
written only by gates** — the same "a gate that cannot fail is not a
gate" doctrine (see README §three findings) applied to learning.

Sources: [Claude Code memory docs](https://code.claude.com/docs/en/memory) (A),
[Anthropic prompt caching](https://docs.claude.com/en/docs/build-with-claude/prompt-caching) (A),
[OpenAI prompt caching](https://platform.openai.com/docs/guides/prompt-caching) (A),
[Gemini caching](https://ai.google.dev/gemini-api/docs/caching) (A),
[Kimi context caching](https://platform.kimi.ai/docs/guide/use-context-caching-feature-of-kimi-api) (A),
[Anthropic context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) (A),
[Graphiti](https://github.com/getzep/graphiti) (A),
[Letta](https://github.com/letta-ai/letta) (A),
[LangGraph memory](https://langchain-ai.github.io/langgraph/concepts/memory/) (A),
[GPTCache](https://github.com/zilliztech/GPTCache) (A),
[Zep CE discontinuation](https://blog.getzep.com/announcing-a-new-direction-for-zeps-open-source-strategy/) (A),
[mem0 audit #4573](https://github.com/mem0ai/mem0/issues/4573) (B),
[mem0 paper](https://arxiv.org/abs/2504.19413) / [Zep paper](https://arxiv.org/abs/2501.13956) (A, vendor-authored),
[Reflexion](https://arxiv.org/abs/2303.11366) / [Voyager](https://arxiv.org/abs/2305.16291) / [Lost in the Middle](https://arxiv.org/abs/2307.03172) (A),
[Kimi K3 pricing](https://routerplex.com/blog/kimi-k3-api-pricing-setup) (B — re-verify at official pricing page before customer-facing use),
["stop building memory frameworks" summary](https://www.agenticbrew.ai/news/1851b23a-e0dc-40b7-a69b-bd93653c4f5c/ai-memory-systems-for-agents) (B).
