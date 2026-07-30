# Provider fabric — re-verification pass (2026-07-30)

Re-check of the "Flagged unverified" items in
[../plans/appbox-engine-llm-fabric.md](../plans/appbox-engine-llm-fabric.md) against
current official docs, plus three A-grade spot-checks. Sources fetched live on
2026-07-30; official docs preferred, secondary corroboration marked.

## Drift table

| claim (as written in plan) | plan grade | verdict | evidence | corrected value |
|---|---|---|---|---|
| gemini-3.1-pro $2/$12 per 1M | B ⚠ | **confirmed** | [ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing) | $2/$12 ≤200k prompts; **$4/$18 >200k** (tiered) |
| gemini-3.5-flash $1.50/$9 | B ⚠ | **confirmed** | same page | unchanged; note **gemini-3.6-flash now exists at $1.50/$7.50** (cheaper output, launched 2026-07-21) |
| gemini-3-flash $0.50/$3 | B ⚠ | **confirmed** | same page | unchanged (still `gemini-3-flash-preview`) |
| gemini-3.1-flash-lite $0.25/$1.50 | B ⚠ | **confirmed** | same page | unchanged; **gemini-3.5-flash-lite now GA at $0.30/$2.50** |
| z.ai Anthropic endpoint "Coding Plan only, PAYG unverified" | ⚠ | **corrected** | [zcode.z.ai/en/newdocs/configuration](https://zcode.z.ai/en/newdocs/configuration) (official harness docs) | `api.z.ai/api/anthropic` **does bill PAYG balance, but only if the account has never purchased a Coding Plan**; once any plan was purchased (even expired), the route needs manual allowlisting |
| Kimi rate-limit tier table | B | **confirmed (values refreshed)** | [platform.moonshot.ai/docs/pricing/limits](https://platform.moonshot.ai/docs/pricing/limits) | see §3 table — Tier0–Tier5, recharge-based |
| Kimi limits per-USER across all models | A | **confirmed** | [platform.kimi.ai/docs/introduction](https://platform.kimi.ai/docs/introduction) | "Rate limits are enforced at the user level, not the key level… shared across all models" |
| Empty balance returns 429 | B | **confirmed (still B — official docs silent)** | [geotoolbox.ai](https://geotoolbox.ai/blog/kimi-api-pricing) + openclaw issue | behavior persists; mitigation = check balance endpoint on 429 |
| `/v1/users/me/balance` documented | — | **confirmed** | [platform.moonshot.ai/docs/api/balance](https://platform.moonshot.ai/docs/api/balance) | GET, returns `available_balance`/`voucher_balance`/`cash_balance` |
| `.ai` vs `.cn` keys/balances separate | A | **confirmed** | [platform.kimi.ai/docs/api/balance](https://platform.kimi.ai/docs/api/balance) | "API Keys from platform.kimi.ai and platform.kimi.com are completely independent" (note rebrand: platform.kimi.ai ↔ platform.kimi.com) |
| Grok 4.3 / 4.1-fast undocumented | ⚠ | **corrected** | [docs.x.ai/docs/models](https://docs.x.ai/docs/models) | **grok-4.3 now documented** (1M context, ~$1.25/$2.50 per embedded price data, aliases `grok-4.3-latest`/`grok-latest`); **no grok-4.1-fast exists**; grok-4.20 family also listed |
| grok-4.5 $2/$6, 500k context | — | **confirmed** | [docs.x.ai/docs/models](https://docs.x.ai/docs/models) | exact match; current flagship; cached input $0.30–0.50 |
| Kimi CLI env-var key injection "not officially documented" | ⚠ | **refuted (now documented)** | [kimi-code docs: env-vars](https://github.com/MoonshotAI/kimi-code/blob/main/docs/en/configuration/env-vars.md) | `KIMI_MODEL_NAME` + `KIMI_MODEL_API_KEY` + `KIMI_MODEL_BASE_URL` + `KIMI_MODEL_PROVIDER_TYPE` synthesize an in-memory provider — the official env-injection path |
| Headless contract `kimi --print -p … --afk` | A | **corrected** | [kimi-code docs: kimi command](https://github.com/MoonshotAI/kimi-code/blob/main/docs/en/reference/kimi-command.md) | no `--print` flag; `-p`/`--prompt` is the non-interactive mode; `--output-format stream-json` valid (only with `-p`); **no `--afk` flag — `-p` already implies auto permissions** |
| `--continue` / `--resume` official | A | **confirmed** | same page | `--continue` (`-c`); `--resume`/`-r` is a hidden alias for `--session` (`-S`) |
| config.toml `base_url` + `api_key` to point at gateway | A | **confirmed** | [kimi-code docs: config-files](https://github.com/MoonshotAI/kimi-code/blob/main/docs/en/configuration/config-files.md) | `[providers.<name>]` with `type` (`kimi`/`anthropic`/`openai`/`openai_responses`/`google-genai`/`vertexai`), `base_url`, `api_key` |
| `--config <file>` exists | — | **refuted** | same pages | no `--config` flag in the official command reference; relocate the whole data dir with `KIMI_CODE_HOME` instead |
| Fugu pricing (C) + OpenAI-compatible API | C | **corrected (now official)** | [sakana.ai/fugu](https://sakana.ai/fugu/) | Fugu Ultra **$5/$30 per 1M** ($10/$45 >272k ctx, cached $0.50); Fugu Cyber $6/$36; base Fugu billed at underlying-model rate; OpenAI-compatible API live; subs $20/$100/$200/mo; **not available EU/EEA** |
| SPOT-CHECK: Kimi `response_format` json_object only | A | **refuted (outdated)** | [platform.kimi.ai/docs/api/chat](https://platform.kimi.ai/docs/api/chat) | **`json_schema` now officially supported** (Structured Output, "recommended"); json_object still documented |
| SPOT-CHECK: DeepSeek `reasoning_content` echo in tool loops or 400 | A | **confirmed** | [api-docs.deepseek.com/guides/thinking_mode](https://api-docs.deepseek.com/guides/thinking_mode/) | exact match; also: thinking default ON, sampling params silently ignored |
| SPOT-CHECK: Anthropic has no official OpenAI shim | A | **refuted** | [platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk) | official OpenAI-SDK compatibility layer at `https://api.anthropic.com/v1/` (testing-oriented; `response_format`, prompt caching, >1 temperature unsupported) |

## 1. Gemini 3.x prices — CONFIRMED, with two new entries

From the official [Gemini API pricing page](https://ai.google.dev/gemini-api/docs/pricing)
(fetched 2026-07-30; the page redirect-loops for some fetchers, use curl):

- **Gemini 3.1 Pro** (`gemini-3.1-pro-preview`): $2.00 input / $12.00 output per 1M
  for prompts ≤200k; **$4.00 input above 200k** (plan's single number hides the
  tier). Matches plan.
- **Gemini 3.5 Flash** (`gemini-3.5-flash`): $1.50 / $9.00. Matches plan.
- **Gemini 3 Flash Preview** (`gemini-3-flash-preview`): $0.50 text/image/video
  ($1.00 audio) / $3.00 output. Matches plan; still a `-preview` ID.
- **Gemini 3.1 Flash-Lite** (`gemini-3.1-flash-lite`): $0.25 / $1.50. Matches plan.

Drift worth cataloging:

- **Gemini 3.6 Flash** (`gemini-3.6-flash`) launched 2026-07-21 at **$1.50 / $7.50** —
  same input price as 3.5-flash with cheaper output; the standard-tier Gemini
  candidate should probably move to it.
- **Gemini 3.5 Flash-Lite** is GA at **$0.30 / $2.50** — a newer fast-tier option
  alongside 3.1-flash-lite.

## 2. z.ai PAYG Anthropic-compatible endpoint — CORRECTED (conditional yes)

The plan flagged `api.z.ai/api/anthropic` as "documented for Coding Plan only, PAYG
unverified." The official ZCode (Z.ai's own harness)
[configuration docs](https://zcode.z.ai/en/newdocs/configuration) now state:

> **The Anthropic Base URL does not apply to resource packages / prepaid balance**:
> it only draws from your balance if the account has **never purchased a Coding
> Plan**. Once a plan has been purchased — whether used up or expired — this route
> no longer bills against balance and requires manual allowlisting.

So: PAYG keys *can* use the Anthropic endpoint, but the billing path is fragile
(account-purchase-history dependent, allowlisting after any plan purchase). For the
fabric, treat the z.ai Anthropic route as **available but second-class** — the OpenAI
endpoint (`api.z.ai/api/paas/v4`) remains the safe default for PAYG. Coding Plan
endpoint table per [docs.z.ai/devpack/tool/others](https://docs.z.ai/devpack/tool/others):
Anthropic Messages → `https://api.z.ai/api/anthropic`; OpenAI →
`https://api.z.ai/api/coding/paas/v4` (coding scenarios only, tool-restricted by
policy per [docs.z.ai/devpack/faq](https://docs.z.ai/devpack/faq)).

## 3. Kimi rate limits — CONFIRMED, table refreshed

Current tier table from
[platform.moonshot.ai/docs/pricing/limits](https://platform.moonshot.ai/docs/pricing/limits)
(recharge-based; the table is JS-embedded, not in the extracted text):

| level | cumulative recharge | concurrency | RPM | TPM | TPD |
|---|---|---|---|---|---|
| Tier0 | $1 | 1 | 3 | 500,000 | 1,500,000 |
| Tier1 | $10 | 50 | 200 | 2,000,000 | Unlimited |
| Tier2 | $20 | 100 | 500 | 3,000,000 | Unlimited |
| Tier3 | $100 | 200 | 5,000 | 3,000,000 | Unlimited |
| Tier4 | $1,000 | 400 | 5,000 | 4,000,000 | Unlimited |
| Tier5 | $3,000 | 1,000 | 10,000 | 5,000,000 | Unlimited |

Notes on the same page: minimum $1 recharge to start; $5 voucher at $5 cumulative;
vouchers don't count toward the tier total; temporary downward adjustment under
cluster load.

- **Per-user, all models**: confirmed verbatim in
  [Main Concepts](https://platform.kimi.ai/docs/introduction): "Rate limits are
  enforced at the user level, not the key level. Currently, we share rate limits
  across all models."
- **Balance endpoint**: `GET /v1/users/me/balance` still documented
  ([api/balance](https://platform.moonshot.ai/docs/api/balance)), returning
  `available_balance`, `voucher_balance`, `cash_balance`.
- **Empty balance → 429**: still **not stated in official docs**; corroborated
  2026-07-18 by [geotoolbox.ai](https://geotoolbox.ai/blog/kimi-api-pricing) citing
  the openclaw issue ("Kimi/Moonshot 'Rate Limit' error masks insufficient funds").
  The plan's mitigation (call `/v1/users/me/balance` on the 429 path) remains the
  right one. Grade stays B.
- **.ai vs .cn separation**: confirmed; note the rebrand — the balance page states
  "API Keys from platform.kimi.ai and platform.kimi.com are completely independent"
  (international ↔ China; API bases `api.moonshot.ai` ↔ `api.moonshot.cn`).

## 4. Grok — CORRECTED

From [docs.x.ai/docs/models](https://docs.x.ai/docs/models) (page updated
2026-07-09; model catalog embedded in the page data):

- **grok-4.5**: $2.00 / $6.00 per 1M, 500k context, aliases `grok-4.5-latest` /
  `grok-build-latest`, reasoning efforts low/medium/high/xhigh (default high).
  Confirmed exactly as the plan's frontier candidate.
- **grok-4.3 is now documented** (plan said undocumented): 1M context
  (`maxPromptLength` 1,000,000), aliases `grok-4.3-latest` / `grok-latest`,
  embedded price data ≈ $1.25 / $2.50 per 1M (2× above 200k). A **grok-4.20**
  family (`grok-4.20-reasoning`, `grok-4.20-0309-non-reasoning`) is also listed at
  the same price points with 1M context.
- **grok-4.1-fast does not exist** anywhere in the current catalog — drop it.
- `grok-code-fast-1` (256k context) survives as the fast/cheap coding model.

## 5. Kimi CLI — MAJOR CORRECTIONS

The CLI is now the Node-based **Kimi Code CLI** (`MoonshotAI/kimi-code`, data dir
`~/.kimi-code/`; legacy Python `~/.kimi/` is migrated by `kimi migrate`). Official
references: [kimi command](https://github.com/MoonshotAI/kimi-code/blob/main/docs/en/reference/kimi-command.md),
[env-vars](https://github.com/MoonshotAI/kimi-code/blob/main/docs/en/configuration/env-vars.md),
[config-files](https://github.com/MoonshotAI/kimi-code/blob/main/docs/en/configuration/config-files.md).

- **Headless contract**: the plan's `kimi --print -p "<prompt>" --output-format=stream-json --afk`
  is stale. Current documented form:
  `kimi -p "<prompt>" --output-format stream-json`. There is **no `--print` flag**
  and **no `--afk` flag** in the official reference — `-p` (`--prompt`) *is* print
  mode, and it runs with auto permissions by default ("In `-p` mode, no human
  approval is requested — regular tool calls are handled under the `auto`
  permission policy"). stdout = Assistant stream (JSONL in stream-json), thinking
  and tool progress on stderr. Only `--output-format` is documented; the
  `--input-format stream-json` some third-party wrappers use is **not** in the
  official reference.
- **`--continue` / `--resume`**: `--continue` (`-c`) continues the most recent
  session in the cwd; `--session` (`-S [id]`) resumes a specific/picked session;
  `--resume` (`-r`) exists as a **hidden alias for `--session`**.
- **Exit codes 0/1/75** (plan E3): not stated in the official command reference —
  treat as UNVERIFIED (third-party docs claim them).
- **Env-var key injection — now officially documented** (plan said "not officially
  documented"): the `KIMI_MODEL_*` family synthesizes an in-memory provider:
  `KIMI_MODEL_NAME` (required), `KIMI_MODEL_API_KEY`, `KIMI_MODEL_BASE_URL`,
  `KIMI_MODEL_PROVIDER_TYPE` (`kimi`|`anthropic`|`openai`). This is the cleanest
  gateway-injection path: `KIMI_MODEL_PROVIDER_TYPE=openai` +
  `KIMI_MODEL_BASE_URL=http://127.0.0.1:…` + a scoped token as
  `KIMI_MODEL_API_KEY`. Warning from the same page: bare `KIMI_API_KEY` /
  `ANTHROPIC_API_KEY` etc. in the shell are **deliberately not read** — config.toml
  or the `KIMI_MODEL_*` channel only.
- **config.toml gateway path**: confirmed — `[providers.<name>]` with `type`,
  `base_url`, `api_key`; provider types include `openai` (chat completions) and
  `anthropic`, both sufficient for a loopback gateway. `default_model` +
  `[models.<alias>]` completes the setup.
- **`--config <file>`: does not exist.** No such flag in the official reference.
  The supported relocation is `KIMI_CODE_HOME=<dir>` (whole data dir incl.
  `config.toml`, sessions, credentials). A stage runner should set
  `KIMI_CODE_HOME` to a stage-scoped dir with a pre-written `config.toml`.

## 6. Fugu (Sakana) — CORRECTED, now official

[sakana.ai/fugu](https://sakana.ai/fugu/) now publishes full pricing — the plan's
C-grade flag can be cleared:

- **OpenAI-compatible API is live** for all three models (Fugu, Fugu Ultra, Fugu
  Cyber): "Point your existing client or coding harness at the Fugu endpoint with
  your API key — no SDK migration required."
- **Fugu Ultra** (`fugu-ultra-v1.1`/`v1.0`): **$5 input / $30 output / $0.50 cached
  per 1M**; above 272k context $10 / $45 / $1.00.
- **Fugu Cyber** (`fugu-cyber-v1.0`, token plan only): $6 / $36 / $0.60 cached.
- **Fugu (base)**: billed at the underlying model's standard rate; multi-agent
  runs never stack fees — single rate of the top-tier model involved.
- Subscriptions: Standard $20/mo, Pro $100/mo, Max $200/mo (Fugu + Fugu Ultra).
- Per-request token/cost reporting; training-data opt-out in console; pool opt-outs
  only for base Fugu (Ultra's pool is fixed). **Not available in EU/EEA.**

## 7. A-grade spot-checks

- **Kimi `response_format` — plan is outdated.** The
  [chat API reference](https://platform.kimi.ai/docs/api/chat) now documents three
  values: `text` (default), `json_object`, and **`json_schema` (Structured Output,
  "recommended")**. The `genui_bridge` note in the plan ("map/omit `json_schema`
  per provider `param_policy` for Kimi") is no longer needed for Kimi — though
  keeping the policy costs nothing. The older
  [JSON Mode guide](https://platform.kimi.ai/docs/guide/use-json-mode-feature-of-kimi-api)
  still only shows `json_object` (docs lag internally).
- **DeepSeek `reasoning_content` echo — confirmed verbatim** on
  [api-docs.deepseek.com/guides/thinking_mode](https://api-docs.deepseek.com/guides/thinking_mode/):
  "for turns that do perform tool calls, the `reasoning_content` must be fully
  passed back to the API in all subsequent requests… otherwise the API will return
  a 400 error." Same page confirms thinking defaults ON and temperature/top_p/
  penalties are silently ignored in thinking mode. Widely enforced since ~2026-04
  (multiple client bug reports).
- **Anthropic "no official OpenAI shim" — refuted.** Anthropic now ships an
  official [OpenAI SDK compatibility layer](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk):
  point the OpenAI SDK at `https://api.anthropic.com/v1/` with a Claude key.
  Caveats: "primarily intended to test and compare… not a long-term or
  production-ready solution"; `response_format` ignored, no prompt caching,
  temperature capped at 1, system messages hoisted/concatenated, `n` must be 1.
  The fabric can keep Messages-native as primary, but the shim is a real fallback
  that removes one adapter special-case.

## Items that remain UNVERIFIABLE from official docs

- Kimi empty-balance 429 (behavior corroborated, undocumented).
- Kimi CLI exit codes 0/1/75 for print mode.
- Kimi CLI `--input-format stream-json`.
- z.ai PAYG Anthropic endpoint **stability** (documented behavior is
  purchase-history-dependent; no SLA statement).
