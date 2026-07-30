# app-box engine + LLM fabric — decisions record

Status: **decided 2026-07-29, not yet built.** This is the architecture contract for the
engine effort that follows the i18n launch work. Each decision was made against
docs-grounded research (sources cited inline; grades: A = official docs, B = corroborated
secondary, C = unverified single source).

Purpose (operator's words): app-box operates **standalone with the user's LLM
credentials** and produces bespoke applications — one credential set powers the whole
pipeline journey and every module that needs an LLM (genui included).

## E1 — Credential home: appboxd vault, N keys

All N provider keys (Kimi, z.ai, Anthropic, OpenAI, DeepSeek, Gemini, Grok, …) live
**only** in appboxd's existing vault. Everything else — headless stage runs, genui
runtime, future modules — receives scoped access minted at spawn; raw keys never enter
another process. Matches the Zed/Cline keychain norm (A); ahead of the plaintext-TOML
CLI norm (Aider, Continue, `~/.kimi/config.toml`). Cursor-style cloud brokering is
disqualified by the standalone promise.

## E2 — Access: appboxd loopback gateway

appboxd serves an OpenAI-compatible **and** Anthropic-compatible endpoint on
`127.0.0.1`: token check + provider adapters (genui_bridge already ships both
`ChatStream` adapters). It mints **scoped tokens per consumer** (pipeline-stage token,
genui-runtime token), normalizes per-provider quirks from the fabric catalog (E4), and
produces per-module usage/spend attribution — which feeds the routing scorecard.

- Stage CLIs officially support this shape: Kimi CLI takes `base_url` + `api_key` in
  config.toml (A); Claude Code documents `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`
  for gateways (A).
- Full gateways (LiteLLM→Postgres, Kong→Redis) are operationally wrong for one laptop
  (A). Thin loopback broker is the documented single-user sweet spot.

## E3 — Engine: deterministic stage-runner inside appboxd

appboxd absorbs three things it half-has:

1. **Stage registry** (from `pipeline.sh` / `gates/` — the FSM already exists).
2. **Headless runner adapter** — a stage = `kimi --print -p "<skill prompt>" --output-format=stream-json --afk` (A: official print mode; exit codes 0/1/75-retryable) with the CLI config pointed at the loopback gateway and a stage-scoped token. Skills stay as **Markdown files** (Agent Skills is an open standard since 2025-12, A) — no consolidation rewrite.
3. **Run manifests + session IDs** for checkpoint/resume (`pipeline/state/` already implies it; `--continue`/`--resume` are official, A).

Rationale: Anthropic's canon (A) — app-box's pipeline is a *workflow* (finite,
predefined paths with programmatic gates), and deterministic drivers beat LLM
commanders there. MAST (A, 1600+ traces): task-routing errors and error propagation
are the top multi-agent failure modes; multi-agent burns ~15× tokens. A home-grown
Fugu needs a *trained* router (thousands of verifiable runs — we don't have them) and
Sakana's product is proprietary/API-only (A).

**The honest Fugu inheritance** (sakana.ai/fugu-release, A; tech report arXiv
2606.21228): the commander is the frontier-tier *session* (can be Fugu's
OpenAI-compatible API itself as a catalog entry); stage→model affinity is **learned
from the gates** over time (Fugu's SFT signal = measured worker performance; our
gates already emit pass/fail — the same reward); two operating points (single model
per stage by default; multi-model only on gate failure); **maker/checker split** —
reviewer model ≠ builder model; access-list discipline — each stage receives only the
artifacts it needs, not the whole transcript.

## E4 — Model fabric: one catalog, 3 neutral tiers

One JSON catalog (home: `config/model-fabric.json`, schema versioned). Three parts:

### providers[]

Per provider: `name`, `base_url` (+ `anthropic_url` where it exists), `protocol`,
`key_ref` (vault key name), `param_policy` (e.g. `omit_temperature`, `omit_sampling`),
`notes`. Default catalog ships 7 providers + Fugu as optional frontier entry.

Protocol reality (A-grade unless noted): Kimi `api.moonshot.ai/v1` OpenAI-compat
(`response_format: json_object` only; **fixed temperature/top_p — omit them or it
errors**; Anthropic-compat `/anthropic` exists, B); z.ai `api.z.ai/api/paas/v4`
OpenAI-compat (Anthropic-compat documented for Coding Plan only, PAYG unverified ⚠);
Anthropic Messages API native, **no official OpenAI shim** (A, absence verified);
OpenAI Responses-primary, chat/completions live (5.x reasoning **rejects explicit
temperature** — omit); DeepSeek OpenAI-format native + first-party `/anthropic`
(thinking default ON, sampling **silently ignored**; `reasoning_content` must echo in
tool loops or 400, A); Gemini OpenAI-compat endpoint still documented (3.x prices
B-grade ⚠ — verify before shipping); xAI OpenAI-style, Anthropic SDK deprecated (A).

### tiers{} — ordered candidate lists (runner takes first with a vault key)

| tier | candidates (model — provider, price in/out per 1M, notes) |
|---|---|
| frontier | kimi-k3 ($3/$15, 1M, `reasoning_effort` low/high/max) · claude-fable-5 ($10/$50, 1M) · glm-5.2 ($1.40/$4.40, 1M) · gpt-5.6-sol ($5/$30) · gemini-3.1-pro ($2/$12 ⚠B) · grok-4.5 ($2/$6, 500k) · deepseek-v4-pro ($0.44/$0.87) · fugu-ultra (optional, ⚠C pricing) |
| standard | kimi-k2.7-code ($0.95/$4, thinking always on) · claude-sonnet-5 ($3/$15, intro $2/$10 thru 2026-08-31) · glm-5 ($1/$3.20) / glm-4.7 ($0.60/$2.20) · gpt-5.6-terra ($2.50/$15) · gemini-3.5-flash ($1.50/$9 ⚠B) |
| fast | kimi-k2.7-code-highspeed (≈3× quota — **real fan-out only**) · claude-haiku-4.5 ($1/$5) · glm-4.7-flashx ($0.07/$0.40) / glm-4.7-flash (free) · gpt-5.6-luna ($1/$6) · gemini-3-flash ($0.50/$3 ⚠B) / 3.1-flash-lite ($0.25/$1.50 ⚠B) · deepseek-v4-flash ($0.14/$0.28) |

Tier semantics are the fable/fakimi invariant (verbatim across all three ports):
**frontier owns the plan and the truth; cheaper tiers do mechanical, bounded, or
evidence work; never own truth-judgment.**

### stages{} — stage → tier defaults

| stage | tier | notes |
|---|---|---|
| intake / story-mapping | frontier | client-facing elicitation judgment |
| design | frontier | first-idea-might-be-wrong = Hard band |
| scaffold | standard | mostly deterministic scripts; bounded agent part |
| build | standard | executes; **review stays frontier** (Moderate = orchestrator pattern) |
| review | frontier, **≠ build's provider** | maker/checker split (Fugu) |
| test | standard | probe/golden runs are deterministic anyway |
| gates | — | deterministic code, no LLM (already true) |

**Escalation**: gate fail → re-run that stage one tier up, bounded once (gate-driven,
not judge-model — our gates are deterministic, strictly more reliable than FrugalGPT's
scorer, A). **Never silent cross-tier downgrade** (documented quality cliff).
Reasoning effort per band maps to each model's dial (`reasoning_effort`/`effort`):
Hard→max, Moderate→medium, Trivial→low (session-level switching only — dials
invalidate prompt cache, A).

**Scorecard** (per run, appended to pipeline state): `{stage, tier, provider, model,
tokens_in, tokens_out, cost, gate_pass, retries}` — routing-regret metric = per-stage
gate-pass-rate per tier; tune the map from it (Fugu's measured-affinity principle at
zero training cost). Regression suite: ~20 representative app specs before changing
tier assignments (A: Anthropic small-sample eval guidance).

## Recorded implementation notes (for the engine build)

- **genui_bridge Kimi compat**: `openai_chat_stream.dart:57-61` sends
  `response_format: {type: 'json_schema'}` when a schema is supplied — Kimi documents
  `json_object` only (A); map/omit per provider `param_policy`. Adapter already omits
  temperature (verified safe).
- **SSE decoding**: verify `genui_bridge/lib/src/sse_transport.dart` decodes UTF-8
  *incrementally* (Polish diacritics are 2-byte and split across chunks; MDN/A-grade
  pitfall).
- **Kimi rate limits**: per-USER across all models (A) — one key for everything is
  consistent; metered against declared `max_completion_tokens`, don't set huge (A).
  Empty balance returns 429 like throttling (B) — check `/v1/users/me/balance` on that
  path. Global `.ai` vs China `.cn` keys/balances are separate (A).
- **Kimi CLI headless contract**: pre-write config (or `--config`) with
  base_url=127.0.0.1 + scoped token; `--print` implies `--afk`; stream-json in/out;
  env-var key injection **not officially documented** — config file is the path (A).
- **z.ai**: Coding Plan is tool-restricted by policy (A) — app-box engine use needs
  PAYG keys, not a Coding-Plan subscription.
- **Fugu-as-provider**: OpenAI-compatible (A) — slots in as a frontier candidate with
  no adapter work; pool opt-outs map to catalog config.
- Flagged unverified (re-check at build time): Gemini 3.x prices (B), z.ai PAYG
  Anthropic endpoint (⚠), Kimi rate-tier table (B), Grok 4.3/4.1-fast (undocumented),
  Kimi CLI env var name (undocumented), Fugu pricing (C).

## Out of scope here

i18n launch work (separate approved plan, in progress). Store-metadata locales.
Per-app (generated-product) runtime routing — produced apps inherit the fabric for
their own genui features via kit-i18n's directive + the gateway, designed when the
engine build starts.

## Corrections (2026-07-30 — appended, originals left intact)

Sources: `docs/research/provider-fabric-recheck.md` (official-doc re-verification,
2026-07-30) and the E1–E4 build itself (kimi CLI 0.29.2 verified live).

- **E3 headless contract corrected.** There is no `--print`, no `--afk`, no
  `--config`. Headless = `kimi -p "<prompt>" --output-format=stream-json` with a
  throwaway `KIMI_CODE_HOME/config.toml` (`base_url` + scoped token +
  `default_permission_mode = "auto"` — `-p` rejects `--auto`/`-y`). Env injection
  **is** now documented: `KIMI_MODEL_NAME/API_KEY/BASE_URL/PROVIDER_TYPE`.
  Resume = `-r <session_id>` (alias of `--session`); `-c/--continue` exists.
  stream-json emits no usage/token lines in 0.29.2 → scorecard tokens are null
  until the CLI adds them. Exit 75 not found in the binary; kept as a constant.
- **E4 drift corrections.** grok-4.1-fast **does not exist** (removed from the
  catalog); grok-4.3 documented (1M ctx, ~$1.25/$2.50). gemini-3.6-flash
  ($1.50/$7.50, 2026-07-21) supersedes the 3.5-flash note; 3.5-flash-lite GA
  $0.30/$2.50. Fugu pricing now official: Ultra $5/$30 ($10/$45 >272k), Cyber
  $6/$36, OpenAI-compat API live, no EU/EEA. z.ai Anthropic-compat bills PAYG
  **only if the account never bought a Coding Plan**. Anthropic now ships an
  official OpenAI-compat layer (testing-oriented; `response_format` ignored; no
  prompt caching). Kimi documents `json_schema` Structured Output — the
  `json_object_only` param_policy is no longer mandatory for Kimi (kept in the
  policy set; genui_bridge uses it). Kimi platform rebranded:
  platform.kimi.ai / platform.kimi.com — keys and balances fully independent.
- **genui_bridge path fix.** The Kimi-compat note's file is
  `genui_bridge/lib/src/adapters/openai_chat_stream.dart` (not `lib/src/`).
  Fixed 2026-07-30: `OpenAIParamPolicy` enum (`fullJsonSchema` default unchanged,
  `jsonObjectOnly` for Kimi); SSE transport verified incrementally correct with a
  split-multibyte regression test; no sampling params are sent by either adapter.
- **Built (2026-07-30).** `config/model-fabric.json` (schema_version 1),
  `appboxd/lib/fabric.dart`, `appboxd/lib/gateway.dart` (E2: scoped tokens,
  routing, param_policy, Anthropic↔OpenAI translation, usage.jsonl attribution),
  `appboxd/lib/engine.dart` (E3: registry from `gates/run_all.sh` order —
  `pipeline/pipeline.sh` is the stacked_kit FSM and never invokes `gates/*` —
  headless runner, manifests, scorecard.jsonl). Anthropic URLs are unversioned in
  the catalog; the gateway appends `/v1/messages`.
