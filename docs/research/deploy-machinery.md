# Deploy machinery inventory

Read-only inventory of existing deploy machinery, to ground a "deploy shell" design.
All claims cite `file:line`. Worktree: `scaffold-shell-worktree`.

## Summary

**Correction to the brief's hypothesis: Shorebird / fastlane / Vercel / Cloudflare are NOT absent — they are the entire deploy runtime, and there are TWO independent implementations of it.** `arxa/lib/deploy.dart:275-283` declares seven wired targets: `fastlane-ios`, `fastlane-android`, `shorebird-release`, `shorebird-patch`, `cloudflare-pages`, `cloudflare-workers`, `vercel`. Each is a function that shells the real CLI (`fastlane run gym`, `vercel deploy --prod`, etc.). Separately, **`kit/deploy/` is a full Dart package** implementing the same seven targets behind a proper port interface, with its own CLI and tests (see "Two implementations" below). The two have divergent contracts and neither calls the other.

What exists is a **command-shape layer**, not a deployment product. Targets are ports over `ProcessRunner`; `ScriptedRunner` (`deploy.dart:44`) lets `--self-test` assert every command shape with no toolchain and no credentials. The design is deliberately gated: `Deployer.deploy` requires the triple (target, version, account) **plus a non-empty human approval token**, and never mints one (`deploy.dart:391-417`). Every attempt — shipped or halted — is appended to `pipeline/state/deploy-ledger.json` (`deploy.dart:347-364`, `379`).

Three real gaps for a deploy shell: **(1) no version/build-number/changelog/git-tag stamping anywhere** — `--version` is an opaque caller-supplied string; **(2) no CI** — `.github/workflows` does not exist; **(3) the studio has a `ship.deploy` screen registered but no view implementing it** (`registry.json:228-235`, `surface: null`, no file).

Note: the repo-root `deploy/` directory is **remote mesh infra** (headscale, Caddy, docker-compose, WireGuard), unrelated to app deployment.

---

## Q1 — What does `arxa deploy` do today?

**Dispatch.** `arxa/bin/arxa.dart:84-85` routes `deploy` to `deployMain(rest)`; `arxa.dart:23` imports `deploy_cli.dart`. Help text at `arxa.dart:144`: "deploy `<sub>` — Deploy runtime — doctor, deploy, --self-test".

**Three verbs** (`arxa/lib/deploy_cli.dart:42-62`), exit contract `0 ok / 1 halt / 2 usage`, HALT to stderr (`deploy_cli.dart:4`, `36`):

| Verb | Inputs | Output | Side effects |
|---|---|---|---|
| `--self-test` (`deploy_cli.dart:51`, `64-75`) | none | PASS/FAIL per suite; FAIL to stderr (`:70`) | none — no toolchain, no credentials (`deploy_cli.dart:24-26`) |
| `doctor [--config <f>]` (`:53`, `77-83`) | optional JSON `{"targets":[...]}` | `DoctorReport` JSON: `offered`, `stub_not_offered`, `configured_targets`, `ready` (`deploy.dart:313-318`) | **none** — explicitly not a gate (`deploy.dart:297`, `321-324`) |
| `deploy --target --version --account --approval [--ledger]` (`:55`, `85-111`) | all four required (`:88-93`) | `DeployResult` w/ `artefactId` | runs real CLIs; **appends to ledger** |

**Ledger resolution** (`deploy_cli.dart:113-136`): `--ledger` flag → `$ARXA_DEPLOY_LEDGER` → repo-root default `pipeline/state/deploy-ledger.json` (`deploy.dart:379`).

**Targets handled** (`deploy.dart:275-283`) — all seven marked `'wired'`, none `'stub'`:

- **iOS**: `fastlane-ios` → `fastlane run gym --version V`, `run match`, `run upload_to_testflight`; artefact = stdout, fallback `tf_build_demo` (`deploy.dart:166-176`)
- **Android**: `fastlane-android` → `flutter build appbundle --build-name V` then `fastlane run upload_to_play_store --track internal`; fallback `play_vc_demo` (`:179-190`)
- **OTA**: `shorebird-release` → `shorebird release release-version --version V` (`:193-203`); `shorebird-patch` → `shorebird release patch --version V`, "no store round-trip, patches Dart only" (`:205-215`)
- **Web**: `cloudflare-pages` → `wrangler pages deploy --commit-dirty --version V` (`:218-228`); `cloudflare-workers` → bare `wrangler deploy`, **no flutter build step** because "a Worker ships from its own wrangler.toml" (`:230-243`); `vercel` → `flutter build web --release` then `vercel deploy build/web --prod --yes` (`:249-262`)

**No macOS, Windows or Linux desktop target exists.** `offered` = wired targets, sorted (`deploy.dart:288-290`); `targetStatus()` at `:293`.

**Halt semantics** (`deploy.dart:391-469`) — attempt recorded as `halted`, `DeployHalted` thrown, for: any empty field of the four (approver recorded as `null`, `:402-417`); unknown target (`:419-432`); stub target (`:436-450`); target port returning `!ok` (`:466-468`). Comment at `:390`: "The function never synthesises an approval token."

**Self-test suites** (`deploy.dart:517-766`): one per target, plus four contract suites. `_suiteOfferedIsExactlyTheWiredSet` (`:626-642`) asserts `offered` equals the seven names sorted (`:630-638`). `_suiteDoctorIsPreflightNotGate` (`:644-649`) asserts `rep.ready` contains "gate" (`:646`), `stubNotOfferered` is empty (`:647`), and `doctor.offered == offered` (`:648`). Also `_suiteDeployHaltsWithoutApproval` (`:657`), `_suiteDeployRecordsFullAttempt` (`:697`), `_suiteDeployShipsVercelWithApproval` (`:724`) — names only, bodies not read. Self-tests write to a temp ledger (`_selftestLedger`, `:654-655`). Entry `runDeploySelfTest` at `:780`.

## Two implementations — `arxa/lib/deploy.dart` vs `kit/deploy/`

`deploy.dart:248` points at the duplication itself: the Vercel port is "Same command shape as kit/deploy's VercelTarget." `kit/deploy/` is a separate package (`kit/deploy/pubspec.yaml`) with 20+ files:

- **Port interface** `KitDeployTarget` (`kit/deploy/lib/src/kit_deploy_target.dart:5-17`): `name` (`:8`), `doctor(config)` (`:11`), `deploy(config)` (`:16`). Contract: "Never throws for tool failures — returns `ok: false` with `failureReason`" (`:13-15`).
- **Five target classes**: `FastlaneTarget` (`targets/fastlane_target.dart:7`), `ShorebirdTarget` (`shorebird_target.dart:13`), `CloudflarePagesTarget` (`cloudflare_pages_target.dart:13`), `CloudflareWorkersTarget` (`cloudflare_workers_target.dart:13`), `VercelTarget` (`vercel_target.dart:15`).
- **Service** `KitDeployService` (`lib/src/kit_deploy_service.dart:6`): registry keyed by target name (`:8`), `targetNamed` throwing `ArgumentError` on unknown (`:14-23`), `doctor` across all targets (`:27-34`), `deployTo(name, config)` (`:37`).
- **Config model** `KitDeployConfig` (`models/kit_deploy_config.dart:2`): `projectName`, `workingDirectory`, `releaseVersion` (`:20`), `patchNumber` (`:23`), `flutterVersion` (`:26`), `dartDefines` (`:29`), `environment` (`:33`).
- **Own CLI** `bin/arxa_kit_deploy.dart`: `doctor` (`:46`), `deploy <target>` (`:54`), flags `--project-name`, `--release-version`, `--flutter-version` (`:69-72`); usage exit **64** (`:11`, `:63`) — different from `deploy_cli`'s 2.
- **Tests**: `targets_test.dart`, `kit_deploy_service_test.dart`, `live_smoke_test.dart`; docs `README.md`, `deploy_playbook.mdx`.

**Contract divergences that a deploy shell must resolve:**

| | `arxa/lib/deploy.dart` | `kit/deploy/` |
|---|---|---|
| Approval token | **required**, halts without it (`:391-417`) | **absent** — no approval concept |
| Ledger | append-only, every attempt (`:347`) | none |
| Failure mode | throws `DeployHalted` (`:467`) | returns `ok: false`, never throws (`kit_deploy_target.dart:13-15`) |
| `doctor` | global, constant `ready`, no env checks (`:475-487`) | **per-target, real checks** (CLI installed, tokens set) (`:11`) |
| Credentials | ambient env (`:232`, `:247`) | explicit `config.environment` (`kit_deploy_config.dart:33`) |
| Version | opaque `String version` | `releaseVersion` + `patchNumber` + `flutterVersion` |
| Usage exit code | 2 (`deploy_cli.dart:36`) | 64 (`bin:11`) |

`kit/deploy` has the better runtime model (real doctor, explicit credentials, structured config, no-throw); `arxa` has the governance (approval gate, ledger, licence check). Neither is a superset.

## Q2 — Shorebird / fastlane / Vercel / Cloudflare / GitHub integration

**Present, not absent** — contrary to the brief's expectation:

- Shorebird: `deploy.dart:193`, `:206`, `:278-279`; `kit/deploy/lib/src/targets/shorebird_target.dart:13`; `SHOREBIRD_TOKEN` in catalog. **No `shorebird.yaml` anywhere in the repo** (`find` returns nothing) — so releases are driven by CLI args only, with no Shorebird app config checked in.
- fastlane: `deploy.dart:166`, `:179`, `:276-277`; `kit/deploy/lib/src/targets/fastlane_target.dart:7`. **No `Fastfile` and no `fastlane/` directory exist** — the code shells `fastlane run <action>` directly, bypassing lanes.
- Vercel: `deploy.dart:249`, `:282`; `vercel_target.dart:15`. Cloudflare: `:218`, `:234`, `:280-281`; `cloudflare_pages_target.dart:13`, `cloudflare_workers_target.dart:13`.
- **GitHub: absent.** `.github/workflows` does not exist. No CI invokes deploy.

Also note the repo-root **`deploy/` directory is unrelated to app deployment** — it is remote mesh infrastructure: `deploy/remote/headscale/config.yaml`, `deploy/remote/Caddyfile`, `deploy/remote/docker-compose.yml`, `deploy/remote/scripts/gen-mesh-cert.sh`, `deploy/remote/.env.example`, `deploy/remote/README.md` (WireGuard/headscale mesh). Do not mistake it for a deploy pipeline.

So integration is "command shapes wired, config files absent" — the toolchains are called but nothing in-repo configures them.

## Q3 — Credentials consumed

`config/credentials.catalog.json` — `schema_version` + `credentials` (38 entries, 14 modules). A dedicated **`kit/deploy` module** holds 10 entries:

| Provider | Keys |
|---|---|
| cloudflare | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` |
| vercel | `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` |
| fastlane | `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY`, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` |
| shorebird | `SHOREBIRD_TOKEN` |

Other modules are `kit/auth`, `kit/data`, `kit/maps`, `kit/notifications`, `kit/payments`, and eight `llm/*`.

**The two implementations consume credentials differently — this is the sharpest divergence.**

- **`arxa/lib/deploy.dart` never reads the vault.** Verified by cited absence: its only imports are `dart:convert` (`:28`), `dart:io` (`:29`) and `package:arxa/process.dart` (`:31`) — no vault, credentials or secure_store import, and **no `Platform.environment` reference anywhere in the file**. Credentials are inherited ambiently by the shelled CLIs; the doc comments say so explicitly: "with CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID in the ambient environment" (`:232-233`), "with VERCEL_TOKEN in the ambient environment" (`:247`).
- **`kit/deploy` injects credentials explicitly.** `KitDeployConfig.environment` is a `Map<String, String>` (`kit/deploy/lib/src/models/kit_deploy_config.dart:33`), passed to the process runner per-call (`vercel_target.dart:78`), and `doctor` checks presence rather than assuming: `config.environment.containsKey('VERCEL_TOKEN')` (`vercel_target.dart:32`), reporting "not set — vercel deploy will fail non-interactively" (`:46`).

Neither implementation reads `config/credentials.catalog.json`; the `kit/deploy` module's 10 entries are declared but nothing populates `KitDeployConfig.environment` from them. There is no signing-material handling (no keychain, no provisioning profile, no `match` password plumbing) beyond `fastlane run match` (`deploy.dart:168`). Support files exist (`credentials.dart` 149 L, `credential_cli.dart` 196 L, `secure_store.dart` 172 L, `vault.dart` 158 L, `runtime_config.dart` 126 L) but are not wired into either deploy path.

## Q4 — FSM: deploy phase, gate, done-artifact

`arxa/lib/phases.dart:13` declares `phases`, with `'deploy'` at `:20` (last). `phaseGates` (`:54`) maps `'deploy': ['deploy', 'advertise']` (`:61`) — the deploy phase must pass **two** gates. `runPhase` looks up `phaseGates[phase]` at `:69`.

**The gate** — `arxa/lib/gate_deploy.dart`, dispatched from `arxa.dart:344-345` (`deployGate(ctx)`):

1. **Licence assertion first, fail-closed** (`gate_deploy.dart:24-31`, `94-135`). Only `status == 'paid'` permits deploy (`:117-125`); `none`/`free` → "PRECONDITION NOT MET" (`:134`). `ARXA_DEV_LICENCE=1` is a documented dev bypass (`:97-102`, "dev/dogfood only, never ship").
2. **State must exist** — missing state file fails: "a gate that cannot find its input never passes quietly" (`:44-46`).
3. **The deploy triple**: `state.targets` non-empty (`:52-56`); `approvalTokens.deploy.version` (`:59-68`); `approvalTokens.deploy.account` (`:71-77`).

Pass line: "deploy: PASS — target, version and account confirmed." (`:83`). Failures also emit SARIF (`:37`).

**Artifact marking deploy done:** two distinct things — the gate reads `approvalTokens.deploy` in pipeline state, while the runtime writes `pipeline/state/deploy-ledger.json` with `{target, version, account, approver, timestamp, artefactId, status}` (`deploy.dart:347-364`, `DeployAttempt` `:117`). **These are not connected**: the ledger is append-only evidence that no gate reads. `artefactId` (TestFlight build id / deployment URL) is the closest thing to a deploy receipt.

**`targets.derivation.json`** lives at `pipeline/state/targets.derivation.json`, produced by the scaffold stage (`arxa/lib/scaffold.dart`, `derivationPath`/`deriveFactors`), and is referenced by `pipeline/state/README.md`. It feeds build-target derivation, not the deploy target vocabulary — `_targets` (`deploy.dart:275`) is a fixed kit vocabulary, explicitly "not project-varying config" (`:272-274`).

## Q5 — Versioning

**Nothing stamps anything.** No git tagging, no build-number increment, no changelog generation in the deploy path. Searched `arxa/` for `git tag|pubspec.*version|build_number|buildNumber|CHANGELOG|bumpVersion`: only unrelated hits — `docs_lint.dart:88-94` (lints `docs/changelog.md` for supersede back-pointers), `kit_facts.dart:3`, `:132` (parses pubspec name/version for kit inventory), `kit_lock_test.dart:34` (fixture).

`--version V` is an opaque string passed through to each target (`deploy.dart:166`, `:249`, …). Nothing validates it is semver, matches `pubspec.yaml`, or is monotonic. The gate only checks `approvalTokens.deploy.version` is present and non-empty (`gate_deploy.dart:63-68`).

## Studio: deploy UI today

`designs/arxa-studio/models/screens_model/registry.json:228-235` registers:

```
id: "ship.deploy", label: "Deploy", surface: null,
shell: "ship", comp: "ShipDeploy", route: "/ship/deploy"
```

`surface: null` and **no view file exists** — `find designs/arxa-studio/ui -ipath '*ship*' -o -ipath '*deploy*'` returns nothing. The screen is a registry placeholder only.

Related copy exists in the build model: `build_model/run.en.json:122` "TestFlight upload and release notes are staged; nothing moves until a human confirms ship."; `:152` "TestFlight upload + release notes. Reachable after build acceptance." (mirrored in `run.pl.json`, `build_seed.{en,pl}.json:74,:100`).

## Implications for a deploy shell

0. **Decide which runtime the shell drives first.** Two implementations exist with incompatible contracts (see table above). This is the blocking design question — a shell built on `arxa` inherits the approval gate and ledger but a fake `doctor`; one built on `kit/deploy` inherits real readiness checks but no governance. Merging them is plausible (kit runtime + arxa governance) but is a code change, not a shell.
1. Target vocabulary is **fixed and closed** (`deploy.dart:272-274`) — a shell should render the seven, not invent a picker.
2. The **approval token is the load-bearing human gate** — a shell must capture it from a human, never generate it (`deploy.dart:390`).
3. **Ledger ↔ gate are disconnected** — a shell showing deploy history reads the ledger; a shell showing readiness reads `approvalTokens.deploy`. Reconciling them is a design decision, not existing behaviour.
4. **Version is unstamped and unvalidated** — the largest missing piece.
5. **Credentials are declared but unwired** — `kit/deploy` exists in the catalog; nothing injects it.
6. `doctor` is deliberately non-authoritative (`deploy.dart:321-324`) — a shell must not present it as a go/no-go.
