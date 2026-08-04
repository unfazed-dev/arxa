# Scaffold shell — kit picker decision log (grilling round 2)

Context correction from user: kit usage is NOT reliably derivable from the design.
A design may run entirely on seeds (seeded users, no auth kit, no database kit)
while the Flutter build still needs real kits. Kit selection therefore has three
entry points: intake (optional), design (declarations), scaffold (final pick).

## Decisions (confirmed with user)

1. **Authority: scaffold is final.** Intake + design pre-populate the scaffold
   picker; only the scaffold-confirmed set reaches the build. Last responsible
   moment; scaffold is the single authoritative merge point.
2. **Removal: removable + forced fallback.** Design-declared kits can be
   unchecked at scaffold, with a warning listing the exact declaring screens;
   removal forces a fallback (seed/fake provider stub) so the build compiles.
   No hard locks, no silent breakage.
3. **Intake role: intent + optional kit pins.** Plain-language capability
   intent is primary (LLM maps intent → candidate kits at scaffold time);
   power users can pin exact kits. Rides on intake's existing simple/advanced
   mode split — pins live in advanced mode.
4. **Detection: three provenance tiers.**
   - *Declared* — mechanical, from registry kit declarations.
   - *Inferred* — studio LLM reads the frozen design and infers capabilities
     with cited evidence ("checkout flow on screen X suggests payments kit");
     pre-checked only at high confidence.
   - *Requested* — intake intent.
   Every entry provenance-labeled for auditability.
5. (Prior round) Dependency-ordered kit list; auto-included dependencies
   flagged distinctly from hand-picked.
6. **Readiness: inform only, block at deploy.** Picker badges are driven by
   `appbox credentials check --module kit/<x>` (credential_cli.dart; catalog =
   config/credentials.catalog.json with required/kind/url/simulator_note per
   key). Missing keys get a 'get key' deep-link; unready picks emit seed-backed
   with a manifest TODO. Deploy gate owns the hard stop.

7. **Run surface: dedicated scaffold shell.** scaffold.picker → scaffold.run →
   result/hand-off to build.loop; remove the scaffold fixture row (4-of-7,
   run.en.json:58-70) from build.loop's timeline so the stage isn't shown twice.

8. **Mechanism: sidecar kit-manifest.json** beside frozen structure.json.
   `wishlist` (intake) + `resolved` (picker-confirmed, provenance-labeled)
   sections; freeze contract untouched (emit_structure.dart:234-255);
   scaffold() takes it as an extra input like targets/derivationPath and
   consumes `resolved` verbatim (plan/apply semantics), writing the final
   set into .shell-structure.json's `kits` map (precedent scaffold.dart:443-451).

9. **Deploy shell scope: fleet-first, two layers.** deploy.fleet landing
   screen (all apps × channels: stores/web, current release, live patch,
   pending rollouts) → deploy.app per-project screen (release/patch/rollback);
   the FSM's deploy phase lands on deploy.app.

10. **GitHub repo content: one repo per app, SSOT + generated.** Design
    artifacts versioned from intake (email provided); generated Flutter from
    scaffold onward with the generated-vs-owned boundary committed; appbox
    commits at pipeline gates (freeze, scaffold, release) with release tags.
    Constraint from user: folder organization must be sound — design separate
    from build, separate from deployment tags.

11. **Free/paid line: take-away free, operated-for-you paid.** `appbox design
    eject` (hardened htmx artifact, self-hosted anywhere) stays free — the
    Webflow export-vs-host split. Paid: appbox operating on your behalf —
    scaffold → Flutter build, store releases, Shorebird patches, managed
    Vercel/Cloudflare pushes, custom domains, GitHub auto-deploys,
    deploy.fleet tracking.

12. **Iteration model confirmed (was deferred).** structure.json SSOT; one-way
    regen with marked generated-vs-owned boundary; LLM-mediated 3-way merge
    (baseline = last-generated) only for boundary-crossing hand-edits; plus a
    patch-vs-release classifier on the regen diff: Shorebird hard gates
    (native/assets/deps → release; Dart-only → patchable) → store-policy gates
    → `shorebird patch --dry-run` verification → default release on ambiguity.
    Scenario validation: .arb typo → OTA patch in minutes (app_localizations
    is patchable); checkout redesign → store release. deploy.app surfaces the
    classifier verdict as Patch/Release.

13. **Deploy engine: unify — kit runtime + appboxd governance.** kit/deploy's
    KitDeployTarget port + target classes become THE runtime; appboxd's
    approval token + append-only ledger + licence gate wrap it as
    orchestration; both rewired to read config/credentials.catalog.json
    (kit/deploy module, 10 keys); gate_deploy asserts against the ledger;
    deploy.dart's duplicate target code retired. Shell drives only the
    unified surface (studio's ship.deploy route gets its missing view).
14. **Account connections: OAuth-first, placed by use.** No email-based
    detection/creation (confirmed impossible: no GitHub/Supabase account or
    org creation APIs, no email lookup). GitHub connect lives on the
    home/dashboard shell; provider connects (Supabase and any other
    kit-backed service) happen where the kit is used. OAuth authorize
    redirect serves as existence-check + signup. Tokens in keychain vault;
    zero-org Supabase case deep-links to dashboard once; project creation
    behind cost confirmation; write-scoped MCP tools stay human-gated.
15. **Appbox/studio's own auth: Supabase Auth + Google + Apple.** To be
    smoke-tested when the designer kit implements the auth shell.

16. **Sign-in gate: local-first, sign-in on first need.** Anonymous design is
    fully local; Supabase-auth sign-in is demanded at the first
    identity-needing action (GitHub sync, provider connect, paid feature).
    Dashboard shell renders a signed-out state with "sign in to sync".
    Anonymous work is free by construction — no identity to meter.

17. **Scaffold IS paid — user overrode the research recommendation.** The moat
    is the automated design→Flutter conversion with minimal LLM/user
    intervention; giving it away was a mistake in the earlier
    paywall-at-deploy placement (gate_deploy.dart:9 era thinking). A user
    rebuilding the ejected htmx design by hand costs them more time and more
    tokens than appbox charges — that asymmetry is the accepted leak. Free
    tier keeps design + eject (decision 11's take-away artifact); paid starts
    at scaffold, not at deploy. The degrade-don't-block philosophy
    (watermark.dart:16-17) is explicitly superseded for the scaffold
    boundary.

18. **Entitlement architecture adopted (7 steps) + watermark retired.**
    Supabase Auth PKCE/deep-link CLI login (no device-code flow in Supabase —
    documented gap); Postgres subscriptions/entitlements/machines tables,
    service-role-only writes, synced from Stripe Entitlements (vendor dunning
    clock ≈8 retries/2 weeks kept separate from client offline-grace clock);
    /activate Edge Function issues ~7-day appbox-signed JWT bound to machine
    fingerprint; `emit scaffold` verifies locally — no network on hot path,
    silent background refresh; Ed25519 licence demoted to signed+TTL
    offline-continuation file; env bypass compiled out of release; 3
    seats/machines with self-service deactivation. Offline continuation must
    survive Supabase downtime (Edge Function = first owned trust surface).
    Watermarking (watermark.dart) is removed entirely — it belonged to the
    previous degrade-based payment model.

19. **Three tiers adopted: Free / Pro / Scale.**
    - *Free, forever, written into licence text:* design + eject (htmx
      artifact), BYO-LLM.
    - *Pro (~$20-40/seat/mo):* scaffold entitlement (decision-18 gate),
      local builds, web deploys (web margin thin — not metered).
    - *Scale (price TBD — web research running):* store releases, Shorebird
      OTA with metered install overage passed through at cost+margin
      ($1/2500 installs base), fleet, custom domains. ~~Shorebird orgs
      per-customer or customer-owned — never pooled on Totem Labs' plan.~~
      *(SUPERSEDED by Decision 33: Totem owns a pooled Shorebird org;
      overage at $1.50/2,500. User-confirmed 2026-08-03.)*
    - *Scale add-on direction (user):* managed kit features — e.g. appbox
      manages the customer's database (Supabase or future Totem Labs
      offering). Billing shape under research.
    - *LLM roadmap (user):* BYO-LLM stays on free AND paid at v1. Future
      versions add credits (Cursor-style) + a Totem Labs fine-tuned LLM as
      a new income stream; credits model must coexist with BYO-LLM without
      punishing it.

20. **Distribution legal layer — all four fixes now (text-only).** Repo stays
    private as policy; root proprietary LICENSE + short free-tier EULA (user
    owns ejected output; no redistribution/reverse-engineering of appbox
    components); re-scope both MIT grants (skills/appbox-designer/LICENSE,
    skills/appbox-story-mapper/LICENSE.txt) with explicit carve-outs —
    upstream attribution kept, derived files enumerated, everything else
    © Totem Labs; name the missing copyright holder. Basis:
    docs/research/distribution-protection-inventory.md.

21. **Ship form — AOT + embed is a hard distribution precondition.**
    `dart compile exe` + embed worker_assets/, runtime/vendor/, ladder.json,
    needed reference text; eliminate source-tree reads
    (design_server.dart:326, design_tools.dart:451/452/1046/1170).
    `publish_to: 'none'` added to appboxd/pubspec.yaml immediately.
    New redistribution gate in the gate suite (sibling of gate_coverage C5):
    fail on LICENSE outside third-party allowlist or source-tree read
    escaping the embed set. Free designer never ships as cleartext.

22. **Distribution channel: direct download + auto-update.** Signed/notarized
    installers from Totem Labs' site, built-in auto-updater, Homebrew cask
    for the CLI, Stripe-only billing outside app stores (0% cut, no review
    latency, no sandbox friction with build toolchains). EULA presented at
    first-run accept. Store presence revisited later as marketing only.
    (Confirmed: repo has no installer/packaging/update machinery yet — this
    is net-new work gated behind decision 21's AOT+embed precondition.)

## Open branches

- **Appbox-system distribution protection (new, round 5).** User requirement:
  none of the appbox system itself — including the free designer — may be
  made available/redistributable. Inventory of existing protections pending.

- **Scale price + managed-kit billing + credits model (round 5).** Tier
  skeleton settled (decision 19); awaiting web research
  (docs/research/scale-pricing-and-credits.md) for: Scale monthly price
  band, managed-database resale billing shape, credits economics.

- **Post-scaffold iteration — deferred, new constraint.** Proposed SSOT +
  generation-gap + LLM 3-way merge model must be validated against
  versioning + Shorebird code-push reality. Test scenario from user:
  (a) checkout view completely redesigned, (b) one-word typo fix in another
  shell — how does each flow through regen → build → Shorebird patch vs
  store release? Awaiting shorebird-release research.
- **Deploy shell (new).** Manages deployment of all appbox apps: app stores
  (Shorebird + fastlane), web (Vercel/Cloudflare), GitHub for project
  versioning. Grilling to begin; repo already has deploy.dart/deploy_cli.dart
  (doctor, deploy, --self-test).
- **Account automation (new).** Can Supabase MCP + GitHub MCP automate user
  signup/signin through appbox — user provides email, appbox checks for
  existing accounts, creates with user approval, signs in; GitHub project
  sync from intake, Supabase provisioned when the kit is needed. Feasibility
  research required (GitHub account creation via API is likely impossible —
  verify).

23. **Platform pivot (round 6): v1 = macOS + controller + hosted web.**
    v1 surfaces: native macOS app (app + daemon, unchanged), iOS/Android
    controller app, and a Totem-hosted web version of appbox studio —
    free access, same Supabase-backed gates, BYO LLM on macOS and web.
    Native Windows/Linux (daemon + local web or runners) deferred to a
    later version; the hosted web version covers those users in v1.
    Supersedes the Win/Linux portions of decision 22's installer scope.

24. **Hosted web pipeline stops at scaffold.** Totem servers run only
    intake → design → freeze → scaffold. Scaffold is the existing
    deterministic appboxd emitter (structure.json + --targets +
    kit-manifest → Dart source text; no LLM, no Flutter SDK, no
    subprocess) — byte-identical to local output, cheap and
    sandbox-trivial. No build farm: Totem never compiles or ships
    binaries; `flutter build` is the user's machine/CI. iOS builds
    require the user's own Mac.

25. **Web delivery + post-scaffold responsibility.** Scaffolded project
    delivered as zip download, or written to a user-chosen local folder
    via the File System Access API (Chromium-only; Safari/Firefox fall
    back to zip). After delivery it is the user's responsibility to
    install Flutter and build — no hosted preview, no Totem-side
    tooling commitment. (Emitting install/build instructions in the
    scaffolded README remains open as a zero-cost courtesy.)

## Open branches (round 6)

- **BYO-LLM key custody on hosted web** — client-held key with direct
  browser→provider calls vs proxying through Totem servers.
- **Hosted multi-tenancy/auth** — first appbox server ever; Supabase
  login binding, per-user project storage, quotas/abuse posture.
- **Controller app pairing target** — macOS daemon only, hosted web
  session, or both.

26. **BYOK key custody on hosted web: hybrid.** Anthropic called direct
    from the browser (`anthropic-dangerous-direct-browser-access: true` —
    the one documented browser-BYOK path); all other fabric providers
    (OpenAI, Gemini, DeepSeek, Moonshot, Z.ai) via a stateless
    same-origin streaming passthrough — key sent per-call, never
    persisted, redacted from logs. Client storage: in-memory per
    session, sessionStorage as opt-in reload survival; never
    localStorage. UI surfaces provider spend-cap/key-scoping controls
    at key entry. Ship-time re-check required: Gemini standard keys
    rejected from Sept 2026 (service-account-bound keys replace them).
    Evidence: docs/research/byok-cors-practices.md.

27. **Hosted web tenancy: local-first + opt-in sync.** Anonymous design
    runs entirely in-browser (IndexedDB/OPFS holding artifacts +
    structure.json); Totem stores nothing for anonymous users —
    decision 16's local-first principle carried to web. Supabase
    sign-in at first identity-needing action (scaffold gate, GitHub
    sync) unchanged. Signed-in users get opt-in server-side project
    sync as a convenience. Acknowledged scope cost: sync engine +
    per-user project storage is net-new v1 work (storage quota and
    sync-conflict story TBD in design).

28. **Controller app pairs with both daemon + hosted session.** v1
    controller (iOS/Android) attaches to (a) the user's macOS daemon
    over the existing SHA-256 fingerprint-pin pairing channel
    (companion-mined security/ layer), and (b) a Totem-hosted web
    session. Acknowledged net-new server scope for (b): session
    binding to Supabase identity + a real-time relay channel between
    controller and browser session. Design must keep one pairing
    abstraction with two transports so the shells stay identical.

## Decision 29 — BYOK key custody: direct-first hybrid (supersedes provisional part of Decision 26)

Browser-direct for the four providers verified browser-callable (Anthropic — documented opt-in header; DeepSeek, Moonshot/Kimi, Z.ai GLM — empirically confirmed 2026-08-03, undocumented reflected-origin CORS). Stateless passthrough proxy only for OpenAI and Gemini. Requirements this creates:
- Per-provider CORS health probe (periodic preflight check) with automatic client fallback to proxy when a direct path tightens.
- Keys held in memory for session, sessionStorage fallback; never localStorage, never server-persisted.
- Re-check Gemini key-sunset (Sept 2026) and DeepSeek/Kimi/GLM reflected-origin status before ship — undocumented behavior treated as working-today, not contractual.
Evidence: docs/research/byok-cors-practices.md (CORS table + empirical verification section).

## Decision 30 — SCALE tier price: $149/mo per org

Unlimited seats, 3 released apps, 50k bundled patch installs, +$49/app/mo beyond 3. Per-org, never per-seat (deliberate anti-FlutterFlow positioning). Band evidence: docs/research/scale-pricing-and-credits.md. *(AMENDED 2026-08-03: was +$9/app — no cost basis; $49 is the load-bearing figure in the cited research's margin logic. User-confirmed.)*

## Decision 31 — Managed Supabase kit: NOT in v1

BYO-Supabase only at launch. Avoids pooled-org liability, PAT abuse surface ($0.09/GB egress), free-tier arbitrage, and the unrotatable-DB-password problem. Managed provisioning ($39/project/mo shape, project-claim escape hatch) is a later upsell once demand is proven.

## Decision 32 — Credits/metered inference: deferred to next version

v1 is BYO-LLM only (custody per Decision 29). Credits exist only if/when Totem ships its own LLM provider solution — next version, not v1. No metered inference billing infra in v1. When built: zero-markup principles from research apply (no expiring credits, no per-plan credit value differences, BYO parity forever).

## Decision 33 — Shorebird install billing: pooled on Totem org

Totem owns the Shorebird org; 50k installs bundled in SCALE; overage billed at $1.50/2,500 (1.5x markup over Shorebird's first-party $1/2,500 rate). PRE-SHIP GATE: confirm real per-tier Shorebird prices in the console — current tier dollar figures are aggregator-sourced (flagged in docs/research/scale-pricing-and-credits.md). *(AMENDED 2026-08-03: was zero-margin passthrough — research flags negative-margin OTA resale as the single biggest financial hazard; 1.5x buffer adopted. User-confirmed. Supersedes D19's "never pooled" clause — see annotation there.)*

## Decision 34 — Windows packaging: research commissioned, not decided

No prior record exists for Windows packaging (MSIX/winget/Azure Trusted Signing) — an earlier "decision recorded" framing was wrong (verified 2026-08-03). Windows/Linux distribution remains deferred per D23, but the user commissioned the packaging research NOW rather than at revisit time. Research agent tasked with: MSIX vs installer trade-offs, winget submission mechanics, Azure Trusted Signing cost/requirements, Flutter-on-Windows packaging precedent. Output: docs/research/windows-packaging.md. No shipping decision until that lands.

## Registry `states` cannot carry `signedOut` / `notEntitled` / `success`

picker-screen asked (t=197) for `signedOut` to be added to the `scaffold.picker`
lens-state list in `models/screens_model/registry.json`. It cannot go there.

- `states` on a screens_model registry entry is a CLOSED vocabulary:
  `const surfaceStates = ['loading', 'empty', 'error']` (appboxd/lib/intake.dart:62).
- `appbox emit structure` hard-FAILs on any other value
  (appboxd/lib/emit_structure.dart:271) — "the screen-state vocabulary is closed".
- No screen in appbox-studio's registry declares `states` today; the field is
  optional passthrough into structure.json, not the preview source.
- Preview of gated variants works through the free-form `?state=` query param,
  which picker_viewmodel.js already reads and forwards to the facade. Both
  `?state=signedOut` and `?state=notEntitled` resolve without a registry change.

Registry entries for `scaffold.picker` / `scaffold.run` therefore stay as
authored (id/label/surface/shell/comp/labelKey/route), with no `states` key.

## Decision 35 — Composer reply source: fixed ARB acknowledgement, not a reply corpus

Ratified post-hoc. `scaffold_repository` exports no reply seed (`kits`, `groups`,
`counts`, `manifest`, `entitlement`, `essentials`, `states` only), so the picker
composer's agent reply is one fixed ARB string ("Noted. Nothing is applied until
you continue.") whose copy promises nothing the screen does not do. Inventing a
reply corpus no fixture backs would violate the seed-SSOT discipline. Generated
replies, if ever wanted, are a `scaffold_repository` change — scoped separately,
not assumed.

## Decision 36 — Facade signature convention: local canon wins over cross-surface

Ratified post-hoc. `sendMessage(session, text, t, locale, screen)` mirrors its
sibling `setPanelSize` inside `scaffold_facade.js`, not intake's
`(sd, surface, text, prefs, t, locale)`. Same rule as prior local-canon rulings.
Known hazard, recorded: the trailing `screen` arg is load-bearing — transposing
it silently collapses all six lenses to `success` on POST re-render and no gate
catches it (documented in scaffold-picker-phase3-verification.md §8).

## Decision 37 — Checker matches rendered composer actions by pathname

The render-bound checker phase compares the emitted `action` to registered POST
routes by pathname only, because the runtime router strips the query before
lookup (`worker_shim.js:149,235`). Full-string comparison produced a false
"RENDERED BUT UNROUTED" on `/scaffold/run/messages?state=…` (fixed in f8d8e65).
