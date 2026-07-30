# app-box memory + payment — decisions record

Status: **decided 2026-07-30, not yet built.** Companion to
`appbox-engine-llm-fabric.md` (engine). Decisions were grilled out with the
operator against `docs/research/agent-memory-and-caching.md`,
`docs/research/monetization-and-licensing.md`, and
`docs/research/engine-decision-digest.md`.

## M1 — app-box-memory: dedicated appboxd module

A **dedicated memory module inside appboxd** owns memory read/write/consolidation
across three layers. app-box manages its own memory — it does not depend on
stacked_kit's `memory/` (that repo's pattern is the template, not a dependency).

- **Consumers (all three layers):** the engine (self-tuning), the operator
  (briefings), generated apps (per-app runtime memory ships as a kit inside the
  emitted app, never in this repo).
- **Write path — hybrid:** deterministic writers (gates, runner, gateway) append
  raw events always; a cheap-tier consolidation stage promotes durable lessons,
  and its output passes a gate like every other artifact. Rationale (repo's own
  doctrine, `web-research-drift.md`): memory rots unless a gate consumes it.
- **Coverage mandate (operator, explicit):** logs for **every gate, event, and
  pipeline happening in production** plus analytics and anything useful to the
  user and the system. If appboxd manages all of it, that satisfies the mandate.
- **Storage, split by volatility:**
  - Raw events, scorecards (`pipeline/state/scorecard.jsonl`,
    `pipeline/state/usage.jsonl`), response cache → appboxd data dir (JSONL,
    git-ignored, high-volume).
  - Curated facts + per-stage `LESSONS.md` → repo `memory/` (git-tracked,
    human-editable, gate-consumed — the stacked_kit pattern, ~200-line caps).
  - Per-app runtime memory → a kit inside generated apps.

## M2 — What the memory module is NOT (research-backed skips)

From `agent-memory-and-caching.md` (A/B-graded): no mem0/Letta/Zep-class
agent-memory framework (mem0 production audit: 97.8% junk memories; Zep killed
self-hosted CE; graph DBs die on the local-first constraint). No semantic
cache, no vector retrieval (`cat` beats ANN at this scale). Self-learning =
Fugu-style scorecard affinity + gate-triggered `LESSONS.md` + cache-first
prompt assembly (static prefix, one Anthropic breakpoint, ~82% input-cost
reduction) + exact-match response cache keyed `(stage, model, prompt hash)`.

## P1 — Monetization: charge for the tool, never for the output

- **Flat annual licence + perpetual fallback** (12 paid months → keep that
  version forever). No per-seat, no usage credits (BYO-key = no inference cost
  to meter). Price point still open (INDEX O2).
- **Free tier: full product, watermarked.** Vault/state encrypted by default +
  provenance/watermark block in generated outputs. **Paid: clean outputs +
  deployable** (deploy gate enforces the licence, per §17-as-amended).
- **Do NOT encrypt emitted source.** Zero precedent of user acceptance
  (research, C-by-absence); contradicts §17's "not crippled, merely smaller";
  any local decrypt key is extractable — a speed bump with ransomware optics.
  The VS Code bypass (strip watermark, deploy by hand) is accepted as a design
  constant and handled by licence terms, not crypto — businesses pay for
  liability reasons, individuals who strip watermarks were never customers
  (industry norm: Sublime/JetBrains/TablePlus; Unity Personal splash is the
  accepted watermark precedent).
- **Encrypt app-box's own sensitive state at rest:** LLM-key vault, licence
  file, memory/analytics store (XChaCha20-Poly1305 / age-class). Users expect
  this; it protects *their* data.

## P2 — Licence mechanics: offline signed licence file

Ed25519-signed licence file (email, expiry, tier), verified **fully offline**
by appboxd. No activation server, no machine limits (unenforceable offline).
Matches the consolidation plan: "licence unlock must run outside the kit,
offline (no Totem Cloud at launch)". Online activation (Supabase-class
accounts, machine transfer) is a later, optional layer.

## P3 — Cloud generation: parked, not adopted

Docker-on-VPS generation would close the export bypass only by becoming
FlutterFlow (server-side generation, export paywall) — which kills E1's
standalone/BYO-key promise and turns inference cost into our problem (the
Cursor-credit trap). An optional hosted tier ("app-box Cloud") for teams is a
legitimate **v2 expansion**, decided separately — never a replacement for the
local product.

## Open items carried forward

- Licence price point (INDEX O2).
- Watermark design: exact form of the provenance block in emitted code +
  deploy artifacts (build with the deploy gate work).
- Memory module build order vs. engine landing: scorecard/usage JSONL writers
  already exist (engine build 2026-07-30); consolidation stage + `memory/`
  curation gate are the next slice.
