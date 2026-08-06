# Deploy engine unification

Basis: `docs/plans/scaffold-shell-kit-picker-decisions.md` D13 ("Deploy engine:
unify — kit runtime + appboxd governance"), `docs/research/deploy-machinery.md`
(two-implementation inventory), `docs/research/kit-system.md` (catalog/tier
plumbing).

## Scope & non-goals

In scope: merging `appboxd/lib/deploy.dart` and `kit/deploy/` into one deploy
engine per D13's three clauses — kit runtime as base, appboxd governance
wrapping it, both rewired onto `config/credentials.catalog.json`'s `kit/deploy`
module (10 keys, deploy-machinery.md Q3) — plus wiring `gate_deploy.dart`
against the resulting ledger.

Out of scope: the deploy.app/deploy.fleet shell UI (D9, D13's last sentence —
"shell drives only the unified surface... studio's ship.deploy route gets its
missing view" is a consumer of this work, not part of it); the patch/release
classifier (D13's opening clause, already a separate concern); adding new
targets (macOS/Windows/Linux desktop — confirmed absent from both
implementations, deploy-machinery.md Q1); Shorebird billing/org model (D19).

## Target architecture

**Base: `kit/deploy`'s runtime.** `AppBoxKitDeployTarget` port, its five target
classes (`FastlaneTarget`, `ShorebirdTarget`, `CloudflarePagesTarget`,
`CloudflareWorkersTarget`, `VercelTarget` — `kit/deploy/lib/src/targets/`),
`AppBoxKitDeployService`, and `AppBoxKitDeployConfig` survive as the sole target-execution
path. Rationale (single sentence, per report requirement): kit/deploy already
has real per-target `doctor` checks, explicit credential injection via
`config.environment`, a structured version model, and a never-throws contract
— appboxd's parallel target functions (`fastlaneIos`, `shorebirdRelease`,
`cloudflarePages`, `vercel`, etc., `deploy.dart:166-262`) duplicate this with a
weaker (ambient-env, opaque-version, throwing) contract and are deleted
outright, not kept as a fallback.

**appboxd supplies orchestration, not execution.** Three things wrap the kit
runtime, unchanged in spirit from today's `deploy.dart`:
1. **Approval gate** — the four-field confirmation (target/version/account/
   approval) stays mandatory; a missing field still halts before any target
   runs (today: `deploy.dart:391-417`). The halt path now records a
   `DeployAttempt` row and returns without calling `AppBoxKitDeployService` at all.
2. **Append-only ledger** — `DeployAttempt`/`DeployResult` (the row shape at
   `deploy.dart` — target/version/account/approver/timestamp/artefactId/
   status) is retained as the ledger schema. `AppBoxKitDeployResult`'s `ok`/
   `failureReason` is translated into that row's `status`/`error` fields
   after every call, shipped or failed — this is new mapping code, not a
   reuse of either side verbatim.
3. **Licence gate** — `gate_deploy.dart`'s existing §17 licence-first check
   (fail-closed, never a sarif finding) is unchanged; it runs before the
   ledger assertion described below.

**Catalog becomes the read path for credentials.** Today neither
implementation reads `config/credentials.catalog.json` — appboxd relies on
ambient environment, kit/deploy declares `config.environment` but nothing
populates it from the catalog (deploy-machinery.md Q3). A new resolver reads
the `kit/deploy` module's 10 keys and populates `AppBoxKitDeployConfig.environment`
before every `doctor`/`deploy` call, with the vault/secure_store as the
credential source of truth and ambient env as an explicit, logged fallback —
not a silent one, so dev workflows relying on ambient env today don't
regress invisibly.

**`gate_deploy.dart` asserts against the ledger.** Currently it only checks
`approvalTokens.deploy` (target/version/account presence) and licence — it
never opens the ledger file at all (confirmed: no ledger read in the file).
D13 requires closing this gap: the gate additionally requires a ledger row
matching the confirmed triple with a shipped status before the deploy phase
passes. This is the fix for "ledger ↔ gate are disconnected" (deploy-
machinery.md, Implications #3).

## Migration workstreams (ordered)

1. **Target vocabulary reconciliation.** Verify `AppBoxKitDeployService`'s registry
   (keyed by name, `appbox_kit_deploy_service.dart:8`) actually exposes all seven
   wired names (`fastlane-ios`, `fastlane-android`, `shorebird-release`,
   `shorebird-patch`, `cloudflare-pages`, `cloudflare-workers`, `vercel`) even
   though there are only five target *classes* — `FastlaneTarget` and
   `ShorebirdTarget` likely need a platform/mode parameter or two registry
   entries each. This is pre-work: read `appbox_kit_deploy_service.dart` and the two
   target files before writing the wrapper, don't assume parity.
2. **Credential resolver.** New module populating `AppBoxKitDeployConfig.environment`
   from `config/credentials.catalog.json`'s `kit/deploy` module (10 keys),
   vault-first with logged ambient-env fallback. Tests: each of the 10 keys
   missing surfaces through the per-target `doctor` message, matching
   existing `vercel_target.dart:46`-style wording.
3. **Orchestration wrapper.** Replace `deploy.dart`'s direct target-function
   calls with calls into `AppBoxKitDeployService.deployTo`/`.doctor`, built from a
   `AppBoxKitDeployConfig` assembled from the approval-confirmed
   target/version/account plus the resolver's environment map. Halt-without-
   approval and ledger-append-on-every-attempt semantics preserved exactly;
   `DeployHalted` continues to model the halt path, `AppBoxKitDeployResult`
   failures no longer throw (translated to a `failed` ledger status instead).
4. **Version model upgrade.** Replace `deploy.dart`'s opaque `String version`
   with `AppBoxKitDeployConfig`'s `releaseVersion`/`patchNumber`/`flutterVersion`
   triple. Deploy-machinery.md flags version as "unstamped and unvalidated —
   the largest missing piece" (Implications #4); this workstream is where
   that gets real validation, not just plumbing.
5. **Ledger-aware gate.** Extend `gate_deploy.dart` to load the ledger
   (default `pipeline/state/deploy-ledger.json`, override via `--ledger` /
   `$APPBOX_DEPLOY_LEDGER`, per today's resolution order) and assert a
   shipped row exists for the confirmed triple. Handle "ledger file doesn't
   exist yet" (true in this worktree — no deploy has run) as a legitimate
   hard-fail, not a crash.
6. **CLI unification.** Single user-facing CLI stays `appbox deploy`
   (`doctor`/`deploy`/`--self-test`, exit contract `0/1/2`). `kit/deploy`'s
   own CLI (`bin/appbox_kit_deploy.dart`, usage exit **64**) is demoted to
   internal/test-harness use only, not a second public entrypoint — decide
   in this workstream whether it's deleted or kept for `kit/deploy`'s own
   package tests (`targets_test.dart`, `appbox_kit_deploy_service_test.dart`,
   `live_smoke_test.dart`).
7. **Test consolidation.** `deploy.dart`'s self-test suites (`:517-766`,
   scripted `ProcessRunner` argv assertions per target) and kit/deploy's
   three test files currently assert overlapping CLI shapes independently.
   Merge so each target's argv contract has exactly one source of truth;
   preserve the "no toolchain, no credentials" self-test property
   (deploy.dart header comment) since it's what makes this stage testable at
   all.
8. **Deletion.** Remove `deploy.dart:166-262`'s seven target-port functions
   once workstream 3 replaces their call sites. Confirm no other module
   imports them directly before deleting (`grep` for `fastlaneIos`,
   `shorebirdRelease`, etc. outside `deploy.dart` and its tests).

## Risks

- **Exit code divergence (2 vs 64).** If `bin/appbox_kit_deploy.dart` survives
  as a kept-around entrypoint, any script depending on its usage exit code
  silently disagrees with `appbox deploy`'s contract. Resolve explicitly in
  workstream 6, don't leave both alive by default.
- **Silent credential fallback.** If the resolver's ambient-env fallback
  isn't logged, `doctor`'s new "real checks" could report false-ready in dev
  environments that relied on ambient env under the old appboxd path,
  masking exactly the gap this unification is meant to close.
- **Ledger schema loss.** `AppBoxKitDeployResult.failureReason` is richer than a
  boolean; mapping it into the existing `status`/`error` ledger row risks
  dropping detail `gate_deploy.dart` or a future deploy.app view would want.
- **New-strictness regressions.** Version validation (workstream 4) and
  ledger-backed gating (workstream 5) are both net-new hard requirements
  where today's `deploy.dart` accepts an opaque string and the gate never
  checks the ledger at all. A deploy that would have "passed" (i.e., not
  halted) under old rules can now fail the gate — treat this as an
  intentional tightening, but call it out to whoever owns deploy.app's UX so
  it isn't read as a regression.

## Open questions

- Does the credential resolver live inside `kit/deploy` (making the package
  catalog-aware, coupling it to appboxd's config layout) or as an
  appboxd-side adapter that only populates `AppBoxKitDeployConfig.environment`
  (keeping `kit/deploy` standalone)? Affects whether `kit/deploy` remains
  usable outside the appboxd tree.
- Is `bin/appbox_kit_deploy.dart` deleted outright in workstream 6, or kept
  as an internal harness solely for `kit/deploy`'s own package tests?
- Does the approval token stay a CLI flag (`--approval`) on `appbox deploy`,
  or move exclusively into pipeline state's `approvalTokens.deploy` (which
  `gate_deploy.dart` already reads), making the flag redundant with the gate?
