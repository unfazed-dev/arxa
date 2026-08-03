# Accounts, auth, and provisioning

Governs studio's own sign-in, OAuth account connections (GitHub, Supabase, future
kit-backed services), and the provisioning flows those connections unlock. Authority for
every D-number is `docs/plans/scaffold-shell-kit-picker-decisions.md`. Provider
feasibility and security posture are `docs/research/mcp-account-provisioning.md`.
Entitlement/session mechanics are `docs/research/entitlement-enforcement-practices.md`.

## Scope & non-goals

In scope: studio's own auth (D15), the sign-in gate (D16), OAuth connections for GitHub
and Supabase (D14), and the provisioning flows that follow a successful connection (repo
create+push, Supabase project create+migrate).

Non-goals: the kit picker itself — governed by D2/D4/D5/D6/D8, not D14/D15/D16, despite an
earlier citation error in a sibling design brief that attributed kit-picker readiness to
this decision cluster; managed Supabase kit (D31, not v1); credits/metered
inference (D32); email-based account detection or creation for either provider — both are
confirmed impossible, not merely deferred; organization creation automation for either
provider — neither exposes a grantable write scope for OAuth apps; the hosted web sync
engine's storage/conflict design (D27) and controller-pairing's real-time relay (D28) —
both acknowledged as net-new server scope in their own decisions, out of scope here beyond
noting they bind to the same Supabase identity this plan establishes.

## UX architecture

**Anonymous-by-default, gated on identity-need (D16).** Design work is fully local with no
identity and nothing metered — "anonymous work is free by construction." Sign-in is
demanded only at the first identity-needing action: GitHub sync, a provider connect
(Supabase or any kit-backed service), or a paid feature (the scaffold gate — D17, "scaffold
IS paid"). "Sign-in required up-front" was explicitly rejected. The dashboard/home shell
renders a signed-out state with a "sign in to sync" affordance rather than blocking entry.
On web, D27 carries the same local-first principle: anonymous design runs entirely in
IndexedDB/OPFS, Totem stores nothing for anonymous users, and signed-in users additionally
get opt-in server-side project sync.

**Studio's own identity (D15).** Supabase Auth + Google + Apple sign-in. Timing is an
external dependency: smoke-testing waits on the designer kit implementing the auth shell
— flag this as a blocking handoff, not schedule this plan can control.

**Connection placement (D14).** GitHub connect is global, lives on the home/dashboard
shell, connected once. Provider connects (Supabase, future kit-backed services) are
contextual — they happen where the kit that needs them is used, not centralized. Tokens
live in the OS keychain vault, never elsewhere.

**Browser-handoff pattern for the impossible steps** (`mcp-account-provisioning.md` Q3).
Neither GitHub nor Supabase exposes signup or existence-by-email over an API — GitHub's
`in:email` search matches public email only and forbids domain search; Supabase has no
lookup at all. The fix is not detect-then-create, it's a consent handoff that doubles as
the existence check: one "Connect GitHub" / "Connect Supabase" button per provider,
routing through the provider's own OAuth authorize screen, which offers sign-in *or*
sign-up — appbox never learns which branch ran, and does not need to. The email field is
never framed as "we'll make you an account"; it's a workspace label / `login=` prefill
hint on GitHub's authorize URL.

Two hand-offs are structurally unavoidable, not just for v1:
1. A brand-new Supabase user returns from consent with **zero organizations**, because
   `Organizations / Write` is not a grantable OAuth scope (PAT-only). UX: call
   `list_organizations`; if empty, one-time deep-link to the Supabase dashboard to create
   the first org, then resume in-app.
2. Headless/CLI-shaped hosts (no browser reachable) use GitHub's device flow (RFC 8628:
   show `user_code` + `verification_uri`, poll). Supabase has **no documented device
   flow** — headless Supabase connect falls back to pasting a PAT, explicitly marked as a
   power-user path, since a PAT is account-equivalent and a materially worse posture than
   the GitHub headless path.

## Backend workstreams

**1. Supabase auth for studio (D15).** Configure a Supabase Auth project with Google and
Apple OAuth providers. Session/JWT handling should lean on documented primitives rather
than invent new ones: access tokens are short-lived (5 min–1 hr), refresh tokens are
single-use and non-expiring, and asymmetric JWT signing keys + JWKS let the Dart client
validate a session locally without round-tripping to the Auth server
(`entitlement-enforcement-practices.md` Q5). Time-boxed sessions, inactivity timeout, and
single-session-per-user are Supabase Pro-plan+ features — confirm Totem's plan tier covers
these before treating them as available for v1 entitlement enforcement (open question
below).

**2. OAuth connections per provider (D14).**
- **GitHub:** prefer a GitHub App installation flow over a classic OAuth app — it gives
  per-repository user-controlled scoping, short-lived tokens, and one-click revocation,
  which matters because appbox writes code into these repos. Fall back to the OAuth web
  app flow if no App is registered yet (open question: no GitHub App exists in this repo
  today — registering one is a prerequisite task, not covered here). Device flow for
  headless hosts per above.
- **Supabase:** OAuth code+PKCE with `Projects / Write` scope (grantable) — never
  `Organizations / Write` (not grantable to OAuth apps regardless).
- Store **refresh tokens** in the OS keychain, mint short-lived access tokens for use.
  Never persist a Supabase PAT on the user's behalf — it is full-account-equivalent.

**3. Provisioning flows with consent gates.**
- **Repo create + push:** `create_repository` (or `POST /user/repos`) with scope `repo`,
  then Git Data API or `git push` over HTTPS with the token as password for real
  multi-file sync — the Contents API's `create_or_update_file` is one-file-per-commit and
  should not carry a full scaffold push.
- **Supabase project create:** `POST /v1/projects` (`name`, `db_pass`,
  `organization_slug`, `region_selection` — `organization_id`/`region` are deprecated).
  The response returns the project `INACTIVE`; poll `get_project` until
  `ACTIVE_HEALTHY` before running migrations. **Gate this call behind
  `get_cost`/`confirm_cost`** — it spends the user's money, and D14 states this
  explicitly. This is a hard requirement, not optional UX polish.
- **Migrations:** applied once the project is active, via the Management API or
  Supabase's hosted MCP server.

## Security section

**Prompt injection is the primary risk**, not a secondary concern — Supabase names it
their #1 attack vector for MCP-style tool use, and GitHub ships content sanitization by
default plus a `--lockdown-mode` that suppresses untrusted-author content in public repos.
Appbox-specific consequence: content pulled from an issue, PR, or DB row can reach the
agent. Mitigations: run any GitHub read paths in read-only/lockdown mode; and — per D14's
"write-scoped MCP tools stay human-gated" — keep `create_repository`, `create_project`,
and push operations off any path the model can choose. These are direct calls from appbox
code, never tools exposed for agent selection.

**Key custody boundaries.** OS-keychain vault for refresh tokens only. Never a Supabase
PAT (full-account-equivalent) or a GitHub classic PAT (all-repos) on the user's behalf —
prefer GitHub App installation tokens (per-repo, short-lived) and Supabase OAuth scopes.
"Disconnect" must delete the keychain entry **and** call the provider's revoke endpoint; a
locally-deleted token still live upstream is a silent liability.

**Adjacent but distinct: BYOK LLM-key custody (D29).** Already decided separately —
direct-first hybrid (browser-direct for four LLM providers, stateless proxy for two),
keys held in memory or sessionStorage, never localStorage, never server-persisted. Do not
conflate LLM API keys with the GitHub/Supabase OAuth tokens this plan covers — different
threat models, same non-negotiable: never persist an account-equivalent secret client-side
or server-side beyond what its lifetime requires.

## Risks

- Two dashboard hand-offs (Supabase first-org creation; provider-side signup itself)
  cannot be eliminated, only made one-time and clearly labeled — do not scope-creep into
  trying to remove them.
- Supabase's lack of a documented device flow degrades headless connect to PAT paste, a
  worse posture than GitHub's device-flow path. Re-verify before ship in case Supabase
  ships a device flow.
- GitHub App user-access-token lifetime was flagged uncertain in the underlying research
  (not re-verified against current docs) — confirm before hardcoding refresh logic.
- `entitlement-enforcement-practices.md` Q5 flags (grade B, documented absence) that no
  first-party Supabase guide exists for desktop/CLI licensing. The composition of
  JWKS-local-verification + Custom Access Token Hook + Edge Function auth modes into an
  actual entitlement backend is our design, not a vendor-blessed pattern — validate with a
  spike before it becomes load-bearing for the paid scaffold gate (D17).
- D27/D28 both bind to the Supabase identity this plan establishes but carry their own
  unscoped server work (sync engine, real-time relay) — this plan assumes that identity
  layer exists but does not design either consumer.

## Open questions

- Custom Access Token Hook claim schema (entitlement tier? org id?) — unspecified.
- GitHub App registration is a prerequisite this plan assumes but does not cover — who
  owns creating it, and on which GitHub org.
- D15's smoke-test is gated on the designer kit's auth shell — no visibility into that
  kit's timeline from here; treat as an external blocking dependency.
- Does Totem's Supabase plan tier include Pro-plan+ session features (time-boxed
  sessions, inactivity timeout, single-session-per-user) required for v1 entitlement
  enforcement, or does that require a plan upgrade?
