# MCP account provisioning — feasibility research

Researched 2026-08-03 against current official docs. Verified claims are cited; anything
unverified is flagged **[uncertain]**.

## Summary

The desired flow — *email in → detect accounts → create them → sign in → sync repo →
provision Supabase project* — breaks at one line: **appbox can never create a GitHub or
Supabase account, and can never answer "does this email have an account?"** Neither
platform exposes signup over an API. GitHub's `POST /admin/users` is GitHub Enterprise
Server, site-admin-only; SCIM is Enterprise Managed Users only. Supabase's Management API
has no user resource.

Existence-by-email is deliberately unavailable: GitHub search matches only *public* email
and forbids domain search; Supabase has no lookup. Reframe: **the OAuth authorize redirect
*is* the existence check** — the provider's screen offers sign-in *or* sign-up and appbox
never learns which branch ran. That is the privacy-correct outcome.

Two further ceilings sit just below account creation. **Neither platform lets a
third-party app create an *organization* on a user's behalf**: Supabase's OAuth scope table
lists `Organizations / Write` as **N/A**, and github.com's REST orgs reference has no
create endpoint. A brand-new user therefore lands in the dashboard at least once.

Everything after that is automatable. Appbox holds a **delegated token, not a session**:
repo create + push via GitHub REST/MCP, project create + migrations via Supabase Management
API or its hosted MCP server. The email field is a workspace label, not a provisioning
input.

## Q1 — GitHub

### Can an account be created programmatically? No.

- `POST /admin/users` is documented **only** in the GitHub Enterprise Server REST reference
  (`enterprise-server@3.21`), targets `http(s)://HOSTNAME/api/v3/admin/users`, and is
  restricted: *"These endpoints are only available to authenticated site administrators.
  Normal users will receive a `403` response."* It also *"only support[s] authentication
  using a personal access token (classic)"*.
  <https://docs.github.com/en/rest/enterprise-admin/users>
- There is no counterpart in the github.com REST Users reference — the public API surface is
  read/update of the *authenticated* user only. **[uncertain — inferred; the github.com
  Users reference was not fetched this session. Re-verify.]**
  <https://docs.github.com/en/rest/users/users>
- Nor is there any org-creation endpoint on github.com: the orgs reference documents
  **List / Get / Update / Delete** only (`Update` requires the caller be an existing
  organization owner with `admin:org`). Org creation is dashboard-only for github.com and
  `POST /admin/organizations` on GHES.
  <https://docs.github.com/en/rest/orgs/orgs>
- The only other machine path to a new github.com identity is SCIM provisioning, which is
  scoped to Enterprise Managed Users (an enterprise IdP creates managed accounts; they are
  not ordinary github.com accounts and cannot be created ad hoc by a third-party app).
  <https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/provisioning-user-accounts-with-scim>
  **[uncertain]** — cited from the doc's scope statement, not re-fetched in full this session.

Signup on github.com is a browser flow with CAPTCHA and email verification. Automating it
would also breach the Acceptable Use Policies' prohibition on automated bulk account
creation **[uncertain — policy text not fetched this session; verify wording before citing
it to a customer]**.
<https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies>

### Can existence be checked by email? Effectively no.

The user search qualifiers doc is explicit about the limits:

- *"With the `in` qualifier you can restrict your search to the username (`login`), full
  name, **public email**…"*
- *"For privacy reasons, you cannot search by email domain name."*

So `in:email` matches only addresses the user chose to publish. A miss proves nothing — the
account may exist with a private email. Treat the result as unusable for a
create-or-not decision. <https://docs.github.com/en/search-github/searching-on-github/searching-users>

### What IS automatable post-consent

- **Device flow** (`RFC 8628`), for headless/CLI-shaped hosts:
  `POST https://github.com/login/device/code` returns `device_code`, `user_code`
  (e.g. `WDJB-MJHT`), `verification_uri`, `expires_in=900`, `interval=5`; poll
  `POST https://github.com/login/oauth/access_token` with
  `grant_type=urn:ietf:params:oauth:grant-type:device_code`, handling
  `authorization_pending` / `slow_down` / `expired_token`.
  <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow>
- **Web application flow** (`GET https://github.com/login/oauth/authorize` → code →
  `POST /login/oauth/access_token`) when a browser is available. GitHub's own note:
  *"Consider building a GitHub App instead of an OAuth app"* — GitHub Apps give
  fine-grained permissions, per-repository user control, and short-lived tokens.
  Same URL as above.
- **Repo create + push**: `create_repository` (`name`, `private` defaults to `true`,
  `autoInit`, `organization`) and `create_or_update_file` (server base64-encodes for you)
  in the official MCP server; both require OAuth scope `repo`. Note push ≠ MCP in general —
  for a real multi-file sync prefer the Git Data API or `git push` over HTTPS with the
  token as password; the Contents API is one-file-per-commit.

### Official GitHub MCP server toolsets

Default toolset = `context`, `repos`, `issues`, `pull_requests`, `users`. Others are opt-in
via `GITHUB_TOOLSETS` (env var takes precedence over the CLI flag), `--tools` for individual
tools, `--dynamic-toolsets` for discovery. Read-only mode acts as a strict filter that takes
precedence over other configuration. **No account-creation toolset exists.**
<https://github.com/github/github-mcp-server/blob/main/README.md> ·
<https://github.com/github/github-mcp-server/blob/main/docs/server-configuration.md>

## Q2 — Supabase

### Account vs organization

- **Account creation: not exposed.** The Management API reference documents projects,
  organizations, branches, functions, secrets — no user/account resource.
- **Organization creation: the endpoint exists, but not for OAuth apps.**
  `POST /v1/organizations`, body: `name` (required), creates a billing entity owned by the
  caller — it does *not* create a Supabase user.
  <https://supabase.com/docs/reference/api/create-an-organization>
  **However**, the OAuth scope table lists:

  | Name | Type | Description |
  | --- | --- | --- |
  | `Organizations` | `Read` | Retrieve an organization's metadata / members |
  | `Organizations` | `Write` | **N/A** |

  There is no grantable write scope for organizations, so an OAuth2 token — the only auth
  mode appropriate for end users — **cannot create an org**. `POST /v1/organizations` is
  reachable only with a PAT, i.e. only for your own account. Practical consequence: a
  brand-new Supabase user must create their first organization in the dashboard; appbox
  then reads it via `list_organizations` and creates projects inside it
  (`Projects / Write` → *"Create a project"* **is** grantable).
  <https://supabase.com/docs/guides/integrations/build-a-supabase-oauth-integration/oauth-scopes>
- **Project creation:** `POST /v1/projects`, required body `name`, `db_pass`,
  `organization_slug` (`organization_id` and `region` are now **Deprecated**; use
  `region_selection`). Response `201` returns `{ id, ref, organization_slug, status }` with
  `status: "INACTIVE"` — provisioning is **asynchronous**, so appbox must poll before
  running migrations. <https://supabase.com/docs/reference/api/v1-create-a-project>

### Auth

Two options, both requiring an existing Supabase user:

1. **PAT** (`sbp_…`) — long-lived, *"carry the same privileges as your user account"*.
   Fine for the developer's own automation, wrong for end users.
2. **OAuth2** — *"generate tokens on behalf of a Supabase user… Tokens generated via OAuth2
   are short-lived and tied to specific scopes."* This is the correct mode for appbox.
   Flow: register an OAuth app under an org's **OAuth Apps** tab, redirect to
   `https://api.supabase.com/v1/oauth/authorize` with `client_id`, `redirect_uri`,
   `response_type=code`, `state` (`redirect_uri` + `state` ≤ 4kB), **PKCE `S256` strongly
   recommended**; exchange at `POST /v1/oauth/token` (grants: `authorization_code`,
   `refresh_token`, and beta `jwt-bearer`, the latter Team/Enterprise only) returning
   `access_token`, `refresh_token`, `expires_in`.
   `organization_slug` is optional and only *pre-selects* an org on the consent screen —
   the user still picks. <https://supabase.com/docs/guides/integrations/build-a-supabase-oauth-integration>
   · <https://supabase.com/docs/reference/api/introduction>

Rate limit: 120 req/min, per user **per project/organization scope**; back off on `429`
using `X-RateLimit-Reset`.

### Existence by email

No endpoint. Same reframe as GitHub — the authorize redirect handles both sign-in and
sign-up and appbox never learns which happened.

### Official Supabase MCP server

Hosted at `https://mcp.supabase.com/mcp` (OAuth 2.1 in-client; a PAT is *"no longer
required"*). Local CLI (`http://localhost:54321/mcp`) and self-hosted variants expose a
reduced tool set and **no OAuth 2.1**.

Account-management tools — `list_projects` / `get_project`, `create_project` /
`pause_project` / `restore_project`, `list_organizations` / `get_organization`,
`get_cost` / `confirm_cost`. **There is no `create_organization` tool** — org creation is
Management-API-only. Account tools are **disabled in project-scoped mode**
(`?project_ref=<id>`).

Config query params: `read_only=true`, `project_ref=<id>`, `features=<groups>` (combinable).
<https://supabase.com/docs/guides/ai-tools/mcp>

### Stated production-safety warnings (verbatim posture)

Supabase names **prompt injection as the primary attack vector** unique to LLMs and
recommends: don't connect to production — use a development project or a
[branch](https://supabase.com/docs/guides/deployment/branching); enable **read-only** mode
for data querying; **project-scope** the server; require **manual approval** of tool calls;
limit access to your own projects rather than customers'. Branching is a paid feature.

## Q3 — Fallback UX for the non-automatable step

Do not try to detect-then-create. Replace it with a **consent handoff** that is
simultaneously the existence check:

1. **Browser present (appbox desktop/web):** OAuth authorization-code + PKCE, one button
   per provider ("Connect GitHub", "Connect Supabase" — Supabase publishes brand assets and
   asks for a *Connect Supabase* button). The provider's page offers sign-in **or** sign-up;
   a brand-new user completes signup inline and lands back on your `redirect_uri` with a
   code. Zero extra UX for the "no account" case.
2. **Headless / SSH / CI:** GitHub **device flow** — show `user_code` + `verification_uri`,
   poll. Supabase has no device flow **[uncertain — not documented; assume browser
   required]**, so fall back to pasting a PAT, which should be a clearly-marked
   power-user path.
3. **Repo access scoping:** prefer a **GitHub App installation flow** over an OAuth app —
   the user picks *which* repositories the app may touch, tokens are short-lived, and
   revocation is a single click. This matters because appbox writes code into repos.
4. **Email field's real job:** label the workspace / prefill the provider's signup form via
   `login=` (GitHub `authorize` accepts a `login` hint). Never present it as "we'll make you
   an account".
5. **Supabase first-org gap:** because `Organizations / Write` is not grantable, a
   first-time Supabase user returns from consent with **zero organizations**. Handle it:
   call `list_organizations`; if empty, show "Create your first Supabase organization"
   with a deep link to `https://supabase.com/dashboard/new`, then a *"I've done it"*
   re-check rather than silently failing `create_project`. Optionally pre-select with
   `organization_slug` on the authorize URL for returning users.

## Q4 — Security posture

| Concern | Position |
| --- | --- |
| Token storage | OS-keychain vault is right. Store **refresh tokens** and mint short-lived access tokens; Supabase OAuth tokens are documented as short-lived and scope-bound, and GitHub App user access tokens are short-lived with refresh (**[uncertain — the exact 8-hour figure was not re-verified; read the token-expiry doc before hard-coding it]**). Never persist a Supabase PAT on a user's behalf — it is account-equivalent. |
| Blast radius | Supabase PAT = full account. GitHub classic PAT = all repos. Prefer GitHub App installation tokens (per-repo) and Supabase OAuth scopes. |
| MCP + write scopes | Both vendors warn about prompt injection. GitHub ships **content sanitization by default** and a `--lockdown-mode` that suppresses content from authors without push access in public repos; Supabase names injection its primary vector and recommends read-only + project-scoping + manual tool-call approval. |
| Appbox-specific | Content pulled from an issue/PR/DB row can reach the agent. If appbox drives these servers, run GitHub read paths in read-only/lockdown, keep write tools on an explicit, non-agent code path (direct REST call from appbox, not a tool the model can choose), and gate `create_project` behind `get_cost`/`confirm_cost` — it spends the user's money. |
| Revocation | Surface a "Disconnect" that deletes the keychain entry **and** calls the provider revoke endpoint; a deleted local token that is still live upstream is a silent liability. |

## Feasibility table

| Step | Automatable? | Mechanism | Fallback |
| --- | --- | --- | --- |
| Take user email | Yes | local form | — |
| Check GitHub account exists by email | **No (by design)** | search `in:email` matches public email only; domain search forbidden | none needed — authorize screen resolves it |
| Check Supabase account exists by email | **No** | no endpoint | same |
| Create GitHub account | **Impossible** | `POST /admin/users` is GHES site-admin only; SCIM is EMU only | user signs up on GitHub's page inside the OAuth redirect |
| Create Supabase account | **Impossible** | no Management API resource | user signs up inside Supabase's authorize screen |
| "Sign them in" | **Reframe** — appbox gets a *delegated token*, not a session | OAuth code+PKCE / GitHub device flow | PAT paste (power user) |
| Create GitHub org | **No** | github.com orgs REST has no create endpoint (List/Get/Update/Delete only) | not needed — repos live in the user's personal namespace |
| Create repo at intake | Yes | `create_repository` (MCP) or `POST /user/repos`; scope `repo` | — |
| Push project files | Yes | Git Data API or `git push` over HTTPS w/ token; MCP `create_or_update_file` for single files | — |
| Create Supabase org | **No, for end users** | `POST /v1/organizations` exists but `Organizations / Write` scope is **N/A** — PAT-only | user creates first org in dashboard; appbox reads it via `list_organizations` |
| Create Supabase project at kit-pick | Yes | `POST /v1/projects` (`name`, `db_pass`, `organization_slug`) or MCP `create_project`; poll until `status` leaves `INACTIVE` | — |
| Run migrations | Yes | Supabase MCP `apply_migration` / CLI `db push` | — |

## Risks

1. **Async provisioning.** `POST /v1/projects` returns `INACTIVE`; a kit that immediately
   runs migrations will fail intermittently. Needs an explicit poll-to-ready state in the
   kit runtime.
2. **Cost consent.** `create_project` bills the user's org. `get_cost` → user confirm →
   `confirm_cost` must be a real UI gate, not an agent decision.
3. **Rate limits.** 120/min per user per scope; the Supabase MCP server and appbox's own
   Management API calls share the user's budget.
4. **Deprecation drift.** `organization_id`, `region`, `plan`, `kps_enabled` are marked
   Deprecated on `POST /v1/projects` — pin to `organization_slug` + `region_selection`.
5. **Token liability.** Any stored credential that can create billable resources is a
   support and security incident waiting to happen. Short-lived + revocable only.
6. **Injection reaching write scopes.** If the same agent both reads repo content and holds
   write tools, a malicious README is a code-execution vector. Separate the paths.
7. **First-org dead end.** The single most likely production failure: consent succeeds,
   `list_organizations` returns `[]`, `create_project` 400s, and the user sees a generic
   error. Build the empty-org branch before shipping.
8. **[uncertain]** Supabase device-code flow, GitHub SCIM scope details, the github.com
   Users endpoint list, the AUP wording, and GitHub App token TTL were reasoned from scope
   statements rather than fully re-fetched; re-verify before implementation.

## Sources

- <https://github.com/github/github-mcp-server/blob/main/README.md>
- <https://github.com/github/github-mcp-server/blob/main/docs/server-configuration.md>
- <https://docs.github.com/en/rest/enterprise-admin/users>
- <https://docs.github.com/en/rest/orgs/orgs>
- <https://supabase.com/docs/guides/integrations/build-a-supabase-oauth-integration/oauth-scopes>
- <https://docs.github.com/en/search-github/searching-on-github/searching-users>
- <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps>
- <https://supabase.com/docs/reference/api/create-an-organization>
- <https://supabase.com/docs/reference/api/v1-create-a-project>
- <https://supabase.com/docs/guides/integrations/build-a-supabase-oauth-integration>
- <https://supabase.com/docs/guides/ai-tools/mcp>
- <https://github.com/supabase-community/supabase-mcp/blob/main/README.md>

Indexed sources for follow-up `ctx_search`: `github-mcp-readme`,
`github-rest-enterprise-admin-users`, `github-searching-users`, `github-oauth-device-flow`,
`github-rest-orgs`, `supabase-mcp-readme`, `supabase-mcp-security`,
`supabase-mgmt-api-create-org`, `supabase-oauth-integration`, `supabase-oauth-scopes`.
