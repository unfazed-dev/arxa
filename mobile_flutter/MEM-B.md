# MEM-B — mobile_flutter

> arxa MEM-B (architecture §4): what happened to THIS app. Travels with the delivered codebase and is readable without arxa installed. Regenerated write-on-diff at scaffold time — edit the sources (repo memory/, pipeline state), not this file.

## Build
- targets: ios, android
- derived form factors: mobile, tablet
- surfaces scaffolded: 6 (pairing_shell_pairing_scan_view, pairing_shell_connecting_view, pairing_shell_push_permission_view, studio_shell_studio_session_view, approvals_shell_approvals_view, settings_shell_settings_view)

## Pipeline state
- no recorded stage runs (pipeline/state/scorecard.jsonl absent)

## Facts (MEM-A — memory/facts/)
- E1: all N provider keys (Kimi, z.ai, Anthropic, OpenAI, DeepSeek, Gemini, Grok, ...) live only in arxa's vault; every consumer receives a scoped token minted at spawn, raw keys never enter another process.
- E2: arxa serves an OpenAI-compatible AND Anthropic-compatible loopback gateway on 127.0.0.1 — token check, provider adapters, per-module usage/spend attribution feeding the routing scorecard.
- E3 (corrected): headless stage run = `kimi -p "<prompt>" --output-format=stream-json` with a throwaway KIMI_CODE_HOME/config.toml (base_url + scoped token + default_permission_mode=auto); env injection via KIMI_MODEL_NAME/API_KEY/BASE_URL/PROVIDER_TYPE; resume = -r <session_id>. There is no --print, --afk, or --config.
- E4: one model fabric catalog at config/model-fabric.json (schema_version 1) with 3 neutral tiers — frontier owns the plan and the truth; cheaper tiers do mechanical, bounded, or evidence work; never own truth-judgment.
- Escalation: gate fail re-runs that stage one tier up, bounded once; never a silent cross-tier downgrade. Maker/checker split: review model != build's provider.
- Scorecard per run appended to pipeline state: {stage, tier, provider, model, tokens_in, tokens_out, cost, gate_pass, retries}; routing-regret metric = per-stage gate-pass-rate per tier (Fugu measured-affinity at zero training cost).
- Built 2026-07-30: config/model-fabric.json, arxa/lib/fabric.dart, arxa/lib/gateway.dart (scoped tokens, routing, param_policy, Anthropic<->OpenAI translation, usage.jsonl), arxa/lib/engine.dart (registry from gates/run_all.sh order, headless runner, manifests, scorecard.jsonl).
- Reasoning-effort switching is session-level only — per-request dial changes invalidate the provider prompt cache.
- M1: the memory module is a dedicated arxa module owning memory read/write/consolidation. arxa manages its own memory — no dependency on stacked_kit's memory/ (its pattern is the template, not a dependency).
- Write path is hybrid: deterministic writers (gates, runner, gateway) append raw events always; a cheap-tier consolidation stage promotes durable lessons, and its output passes a gate like every other artifact — memory rots unless a gate consumes it.
- Storage split by volatility: raw events/scorecards/response cache -> arxa data dir (JSONL, git-ignored, high-volume); curated facts + per-stage LESSONS.md -> repo memory/ (git-tracked, human-editable, gate-consumed, ~200-line caps); per-app runtime memory -> a kit inside generated apps.
- Coverage mandate (operator, explicit): logs for every gate, event, and pipeline happening in production plus analytics — arxa managing all of it satisfies the mandate.
- M2 skips (research-backed): no mem0/Letta/Zep-class agent-memory framework (mem0 production audit: 97.8% junk memories; Zep killed self-hosted CE; graph DBs die on local-first), no semantic cache, no vector retrieval — cat beats ANN at this scale.
- Self-learning = Fugu-style scorecard affinity + gate-triggered LESSONS.md + cache-first prompt assembly (static prefix, one Anthropic breakpoint, ~82% input-cost reduction) + exact-match response cache keyed (stage, model, prompt hash).
- LESSONS.md writes are appended ONLY on observed gate failure, one file per stage, 'gate X failed because Y; do Z', capped, human-editable, read into the stage prompt's static (cached) prefix.
- P1: charge for the tool, never the output — flat annual licence + perpetual fallback (12 paid months -> keep that version forever). No per-seat, no usage credits (BYO-key = no inference cost to meter). Price point still open (INDEX O2).
- Free tier: full product, watermarked — vault/state encrypted by default + provenance/watermark block in generated outputs. Paid: clean outputs + deployable; the deploy gate enforces the licence.
- Do NOT encrypt emitted source — zero precedent of user acceptance, any local decrypt key is extractable, ransomware optics. The strip-watermark-and-deploy-by-hand bypass is a design constant handled by licence terms, not crypto.
- Encrypt arxa's own sensitive state at rest: LLM-key vault, licence file, memory/analytics store (XChaCha20-Poly1305 / age-class).
- P2: Ed25519-signed licence file (email, expiry, tier), verified fully offline by arxa. No activation server, no machine limits (unenforceable offline). Online activation is a later, optional layer.
- P3: cloud generation parked, not adopted — Docker-on-VPS generation kills the standalone/BYO-key promise (the Cursor-credit trap). An optional hosted tier for teams is a v2 expansion, decided separately, never a replacement for the local product.
- D17/D18 SUPERSEDE the pay-at-deploy facts above: the paywall moved from the deploy gate to the scaffold boundary — an offline, machine-bound entitlement JWT (~/.arxa/entitlement.jwt, 7-day exp + 30-day grace) verified fail-closed by arxa/lib/entitlement.dart, enforced in scaffoldMain and gate_scaffold. The Ed25519 licence file, the deploy-gate licence assertion, the ARXA_DEV_LICENCE bypass, and watermark.dart are all retired (deleted in 0a9c87b). Hosted backend (Supabase entitlements + Stripe) is a deployment runbook, not yet built: docs/plans/entitlement-backend-runbook.md.

## Stage lessons (MEM-A — memory/stages/)
- (none recorded)
