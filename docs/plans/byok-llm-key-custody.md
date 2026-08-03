# BYOK LLM key custody

Source: `docs/plans/scaffold-shell-kit-picker-decisions.md` D29 (supersedes the
provisional part of D26); `docs/research/byok-cors-practices.md` (CORS table +
2026-08-03 empirical preflight verification).

## Scope & non-goals

In scope: how a user's own LLM API key is entered, held, and used to call a
provider, on both platforms that ship BYO-LLM at v1 — the macOS app (`kit/genui_bridge`,
Dart) and the hosted web studio. Per intake decision 19, BYO-LLM is free-tier-forever
and also available on paid tiers; v1 ships **BYO-LLM only** — no credits, no
Totem Labs-hosted LLM, no pooled/metered inference. Non-goals: model selection
UX, prompt/response persistence, cost metering, a future credits system layered
over BYO-LLM (intake decision 19 notes it must coexist without punishing
BYO-LLM, but designing that coexistence is out of scope here).

## Architecture

**Per-provider routing matrix** (D29, evidence in the CORS research doc):

| Provider | Path | Basis |
|---|---|---|
| Anthropic | Direct from browser/app, header `anthropic-dangerous-direct-browser-access: true` | Documented, supported opt-in (shipped Aug 2024, current 2026) |
| DeepSeek | Direct | Empirically confirmed 2026-08-03: reflected-origin CORS (200, credentials allowed) |
| Moonshot/Kimi | Direct | Empirically confirmed 2026-08-03: reflected-origin CORS (204, credentials allowed) |
| Z.ai (GLM) | Direct | Empirically confirmed 2026-08-03: reflected-origin CORS (200, credentials allowed), both `api.z.ai` and `open.bigmodel.cn` |
| OpenAI | Proxy only | No documented CORS opt-in; SDK explicitly warns against browser use in production |
| Google Gemini | Proxy only | Technically reachable cross-origin, but Google's own docs carry a `[!CAUTION]` against client-side key exposure in production |

The three empirically-direct providers (DeepSeek, Moonshot, Z.ai) are
**undocumented, reflected-origin behavior** — not a contractual guarantee like
Anthropic's. D29 requires this be treated as "working today," revocable
silently, and re-verified before ship.

**macOS app** already has the right shape: `kit/genui_bridge`'s `ChatStream`
abstraction (`kit/genui_bridge/lib/src/chat_stream.dart`) is provider-agnostic
— `Stream<String> complete(...)`, auth is an injected header per request,
nothing stored by the bridge itself. Two adapters exist today
(`anthropic_chat_stream.dart`, `openai_chat_stream.dart`); this plan adds
adapters for Gemini, DeepSeek, Moonshot, Z.ai behind the same interface. Key
storage on macOS: OS keychain (the project already uses keychain for OAuth
tokens per D14 — same pattern, same trust boundary, applies here for
consistency even though direct-provider keys aren't strictly a "secret held by
us" the way OAuth tokens are).

**Hosted web studio**: no keychain equivalent, so custody follows the research
doc's recommended hybrid. Client key storage: in-memory (JS variable/store)
for the session as the default; `sessionStorage` as an explicit user opt-in
for reload persistence; `localStorage` is never used (OWASP: XSS reads
`localStorage`/`sessionStorage` wholesale — in-memory is strictly safer,
`sessionStorage` is the least-bad persistent fallback). For OpenAI and Gemini,
requests route through a **same-origin, stateless passthrough proxy**: accepts
key + request per call, forwards to the provider, streams the response back,
never writes the key to disk, logs, or a database. This mirrors Google AI
Studio's own exported-app pattern for Gemini.

**CORS health probe**: a periodic preflight check (OPTIONS, matching the
empirical test shape already run manually on 2026-08-03) per direct-eligible
provider, with automatic client fallback to the proxy path if a provider
tightens its CORS posture. This turns "undocumented behavior might vanish"
into a detected-and-handled condition instead of a silent outage.

## Workstreams

1. **Provider adapters (macOS app, `kit/genui_bridge`)** — implement
   `ChatStream` for Gemini, DeepSeek, Moonshot, Z.ai; each thin HTTP over
   `dart:io`/`dart:convert` per existing convention; auth header injected per
   request, never persisted by the bridge.
2. **Proxy service (hosted web)** — thin same-origin endpoint, OpenAI + Gemini
   only, streaming passthrough, stateless (no request/key logging, no DB
   write). Needs redaction on any error-reporting path (Sentry/etc.) so a key
   never lands in an exception payload.
3. **CORS health probe** — scheduled preflight check against the four
   direct-eligible endpoints; client-side fallback switch to proxy path on
   failure; surfaced as a status the key-management UI can show ("using
   direct connection" vs. "routed through appbox").
4. **Key-management UI states** — entry, validation (a cheap round-trip call
   to confirm the key works before saving), in-memory-vs-sessionStorage
   choice presented to the user, revoke/clear. Surface each provider's own
   scoping controls (Anthropic workspace spend caps, OpenAI project limits,
   Gemini key restrictions) as a compensating control, per the research doc's
   recommendation.
5. **Re-verification checklist before ship** — re-run the empirical CORS
   preflight test for DeepSeek, Moonshot, Z.ai; re-check Gemini's key-sunset
   timeline (flagged for Sept 2026 in the research doc); re-check OpenAI's
   CORS stance hasn't changed. This is a named pre-ship gate, not a one-time
   check already discharged by the 2026-08-03 test.

## Risks

- **Gemini key-sunset (Sept 2026)** — if Google removes the current key
  mechanism before ship, the Gemini adapter/proxy path needs rework; track
  against the ship date now.
- **OpenAI policy change** — no committed CORS behavior either way; low risk
  since already proxied, but the proxy is now a hard dependency, not an
  optional path.
- **Reflected-origin CORS silently tightened** — DeepSeek/Moonshot/Z.ai give
  no contractual guarantee; the health-probe-plus-fallback (workstream 3) is
  the mitigation, but it must ship in the same release as the direct paths,
  not after.
- **Proxy becomes an accidental key logger** — access logs, error monitoring,
  and request tracing all commonly capture headers/bodies by default; this
  needs an explicit redaction pass, not just "we didn't add a `db.save()`
  call."
- **XSS on the hosted studio** — any XSS defeats in-memory storage too (a
  compromised page can just intercept the key at use-time), but in-memory
  narrows the exposure window relative to `sessionStorage`, which narrows it
  relative to `localStorage`. This is a mitigation, not a solution — normal
  web app XSS hardening (CSP, output encoding) remains the actual control.

## Open questions

- Does the CORS health probe run client-side (each session) or as a
  server-side scheduled job feeding a shared status flag? Client-side is
  simpler and needs no infra; server-side avoids every user's browser hitting
  four providers' OPTIONS endpoints on every load.
- Should `sessionStorage` opt-in be per-provider or a single global toggle?
- Does the macOS app need the same CORS-style health check, or is it exempt
  because it's not subject to browser CORS at all (native HTTP client) — if
  exempt, does that mean the macOS app should just call DeepSeek/Moonshot/Z.ai
  direct unconditionally, with no fallback path needed there at all?
- Who owns the proxy service operationally (which repo, which deploy target)
  — this plan assumes it rides along with the existing hosted web studio
  deploy but that isn't yet confirmed against `kit/deploy`'s target classes.
