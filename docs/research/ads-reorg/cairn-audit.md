# cairn repo audit — pre-move fact sheet

Repo: `/Volumes/developer_ssd/Developer/cairn` (Rust workspace, branch `main`, remote `github.com/unfazed-dev/cairn`)
Audit date: 2026-09-02. **Read-only audit — nothing in cairn was moved, edited, deleted, or committed.**

Note on volatility: cairn is under active, live development. During this audit, 7 new commits landed (40→47 ahead of `origin/main`) and 12 previously-dirty files were committed, all in the space of about an hour. Facts below are a snapshot as of the last check; re-verify anything time-sensitive before acting on it.

---

## 1. SIZE — where the ~46G "unaccounted" space is

Team-lead's arithmetic (`du -sh` total 55G; target/=7.3G, archive/=1.0G, .git=18M, crates/=5M ≈ 8.3G accounted) leaves ~46G unexplained. Found it:

| Dir | Size | What it is |
|---|---|---|
| `sdk/` | 39G | 9 platform SDKs, each with its own gitignored build cache |
| `apps/` | 7.9G | `atlet` Flutter app, gitignored build cache |
| **sdk + apps** | **46.9G** | **= the missing 46G, almost exactly** |

`sdk/` breakdown by platform: cairn_swift 9.4G, cairn_flutter 9.3G, cairn_kotlin 5.7G, cairn_tauri 4.8G, cairn_dotnet 3.7G, cairn_react_native 3.2G, cairn_node 2.6G, cairn_capacitor 42M, cairn_web 21M.

Every one of those top-level SDK dirs is **git-tracked** (confirmed via `git check-ignore`, none matched). The bulk of each dir's size is a nested build-output subdirectory that **is** gitignored even though its parent is tracked:

- Rust `target/`: cairn_swift 9.0G, cairn_flutter/rust 7.6G, cairn_kotlin 5.6G, cairn_tauri 4.8G, cairn_dotnet 3.7G, cairn_node 2.6G — subtotal **33.3G**
- Flutter/JS/native caches: cairn_flutter/example/.dart_tool 1.1G, cairn_flutter/example/build 451M, cairn_react_native/android/build 315M, cairn_react_native/example/node_modules 306M, cairn_react_native/node_modules 203M, cairn_flutter/build 105M, cairn_swift/swift/.build 102M, cairn_kotlin/android/build 83M, cairn_swift/ios-test/build 75M, cairn_flutter/.dart_tool 51M, cairn_capacitor/node_modules 41M, cairn_web/node_modules 20M — subtotal **2.85G**
- **sdk/ known-junk total: ~36.15G of 39G (93%)**. Remaining ~3G in sdk/ not drilled past depth-3 — likely more per-platform caches (CocoaPods `Pods/`, deeper `node_modules`, Gradle caches). Uncertainty, not verified further.

`apps/atlet`: `.dart_tool` 4.1G + `build` 3.8G + `android/.gradle` 12M + `web/node_modules` 2.7M = 7.91G of 7.9G total — **fully accounted, ~100% junk.**

## 2. TRACKED vs JUNK

- **Zero git-tracked files exceed 50MB.** Largest tracked file repo-wide is a 340KB wasm binary.
- `git count-objects -vH`: 5.48 MiB loose + 12.57 MiB packed ≈ **18MB total git object store** — this is what a fresh clone actually costs.
- Net: of the 55G on disk, **at least ~52G (94%) is regenerable build/cache junk** (Rust `target/`, Flutter `.dart_tool`/`build`, JS `node_modules`, Gradle/Xcode caches). The real payload that needs to move is the ~18MB git history plus a working tree of source/docs/assets that's almost certainly under a few GB once the known caches are excluded.
- `archive/` is 1.0G on disk but mostly **not** what it looks like: inside the archived `sdk/cairn_flutter/example/`, the `build/`, `.dart_tool/`, and `macos/Flutter/ephemeral/` subdirs are all `git check-ignore`-confirmed **untracked** leftover build cruft that was never cleaned before the 2026-07-30 `git mv` archival. The actual git-tracked archived content (109+4+1 files per `archive/README.md`) is much smaller than 1.0G.

## 3. MOVE BREAKAGE

**(a) Absolute `/Volumes/developer_ssd` paths — git-tracked hits only (`git grep`), 16 hits total:**

Docs (8 hits, 6 files):
- `docs/plans/HANDOFF.md:14`
- `docs/plans/cairn-integration-tauri-flutter-push.md:4`
- `docs/plans/cairn-completion-assessment-2026-07-29.md:198` (prose about a past bug, not a live path)
- `docs/plans/flutter-pomodoro-persona-e2e-baseline.md:49,1294`
- `docs/plans/atlet-cairn-vs-powersync-app-suite.md:32,130` — **points outside cairn entirely**, to `/Volumes/developer_ssd/Developer/applications/asko/...` (design-asset source)
- `apps/atlet/flutter/tool/PUSH_SMOKE.md:122`

Code/scripts (7 hits, 3 files — these are functional, not documentation, so they actually break):
- `sdk/cairn_kotlin/scripts/run-live-e2e.sh:31,32` (`ROOT=`, `REPO_ROOT=`)
- `sdk/cairn_react_native/scripts/build-android.sh:18,19,20` (`CAIRN_RN=`, `CAIRN_KT=`, `REPO_ROOT=`)
- `sdk/cairn_react_native/scripts/run-android-e2e.sh:27,28` (`CAIRN_RN=`, `REPO_ROOT=`)

Binary (1, ignorable): `apps/atlet/flutter/web/cairn/cairn_ffi_wasm_bg.wasm` — coincidental byte match in a compiled wasm blob.

Config: 0 hits. Docker/deploy/packaging/Makefile/.github checked clean.

**(b) Symlinks:** exactly one git-tracked symlink repo-wide: `AGENTS.md -> CLAUDE.md` (relative, safe).

**(c) Path dependencies outside the workspace:** none found. All Cargo `path =`, pubspec `path:`, and package.json `file:` dependencies are relative and internal to the repo. No `.gitmodules`.

**(d) `git worktree list`:** 2 entries. One is a **stale, prunable worktree checkout of cairn nested inside arxa-studio's `.claude/worktrees/.../cairn-pin` directory** — an inbound cross-repo artifact worth cleaning up before/during the move.

**(e) Things on this machine pointing into cairn:** no hits in `~/.claude/skills`, `~/.agents/skills`, `~/.agents/skills.shared`, or LaunchAgents. The only home-directory references are Claude Code's own path-keyed session data under `~/.claude/projects/-Volumes-developer-ssd-Developer-cairn/` (transcripts + memory files) — these will be orphaned, not broken, after a move; Claude Code keys new sessions to the new path.

## 4. STALE REFERENCES

- **`fixtures/flutter/` — referenced but does not exist.** Cited in `docs/plans/HANDOFF.md:14` and claimed DONE in `docs/plans/README.md`'s table for `flutter-pomodoro-persona-e2e-baseline.md`. Confirmed missing via `test -e`. This matches `archive/README.md`'s own admission that the fixtures/ replacement plan (`multi-sdk-pomodoro-fixture-matrix.md`) "has not landed" — a real, acknowledged open gap, not a doc bug.
- **Retired advisor path** in `docs/plans/HANDOFF.md`: `~/.agents/skills/consultant/scripts/consult.sh ...` — that path no longer exists per current tooling conventions. Low-impact since HANDOFF.md carries its own SUPERSEDED banner.
- **`docs/plans/README.md` index is significantly incomplete.** Corrected count: the index text mentions 27 distinct `.md` filenames; there are 54 actual files in `docs/plans/`. **30 files (56%) are not referenced anywhere in the index at all** — including the most recently active work: `v0-2-0-security-audit.md`, `close-all-open-security-findings.md`, `v0-2-0-red-rail-findings.md`, `release-v0.2.0-handoff.md`, `cairn-integration-tauri-flutter-push.md`. The index's own claim to be "authoritative" doesn't hold up.
- One false alarm, not reported as a finding: `docs/adr/0013` looked missing but the real file is `docs/adr/0013-direct-write-back-design.md`, which exists (my test path was truncated, not a real gap).

## 5. PLANS

- **54 files** in `docs/plans/`.
- **`HANDOFF.md`** (~80 lines): self-marked SUPERSEDED via its own banner — "do NOT start here... Current front door: `cairn-completion-assessment-2026-07-29.md` → `README.md`." Contains the stale advisor path and the `fixtures/flutter/` claim above.
- **`README.md`**: the plans index itself. Defines CURRENT/GATED-ON-GO/DONE/SUPERSEDED tables with a "basis: verified/inferred" column, states it is authoritative — but see the 56%-uncovered gap above.
- **12 most recently modified** (all 2026-09-01/09-02, i.e. today's live work): `close-all-open-security-findings.md`, `v0-2-0-security-audit.md`, `v0-2-0-red-rail-findings.md`, `release-v0.2.0-handoff.md`, `cairn-integration-tauri-flutter-push.md`, `adr-0041-d5-field-leg.md`, `cairn-remaining-work-2026-08-05.md`, `adr-0041-decision-memo.md`, `ponytail-ledger-2026-08-24.md`, `powersync-sdk-parity-plan.md`, `p5-sync-streams-design.md`, `README.md`.
- **Archive candidates:** the 30 unindexed files above are the natural first pass — either fold them into the index or move to an archive tier.
- **Plans referencing arxa/arxa-studio:** `cairn-integration-tauri-flutter-push.md` (12 word-boundary hits — the deepest one, includes the "Supabase DB belongs to arxa digital solutions, not arxa studio" business-context note and "fixes happen in cairn, arxa-studio only consumes tagged versions, no vendoring"), `release-v0.2.0-handoff.md` (6), `v0-2-0-red-rail-findings.md` (3), `adr-0041-decision-memo.md` (1), `adr-0041-d5-field-leg.md` (1), plus ADRs `0041-transport-abstraction-ws-iroh.md` (4) and `0042-mirror-ingest-sidecar.md` (3).

## 6. UNCOMMITTED

As of this audit: **`?? benches/results/raw/`** (one untracked directory) — clean otherwise. The 12 dirty files reported earlier in this same audit session (touching `cairn-application`, `cairn-cli`, `cairn-infra`, `cairn-server`, ADR-0016/0043, plus two security-plan docs) were **committed mid-audit** — see reflog, 12 commits landed in the last ~80 minutes, all legitimate (`fix(auth): enforce nbf and issuer allowlist...`, `feat(cli): cairn pull token hardening...`, `feat(server): keep 1 GiB CAIRN_SLOT_MAX_LAG default...`, etc.). `main` is now **47 commits ahead of `origin/main`**, 0 behind — up from 40 at the start of the audit.

## 7. CROSS-REPO (arxa ↔ cairn)

- **arxa consumes cairn via a pinned git dependency, not a filesystem path.** `arxa/kit/cairn/pubspec.yaml`: `cairn_flutter` comes from `git: {url: https://github.com/unfazed-dev/cairn.git, ref: fabc1a163953c27aba33617dae72e704bcef4e11 (full SHA), path: sdk/cairn_flutter}`. Resolves via network/pub-cache. **Zero local-path coupling — the move is safe from arxa's build side.**
- The v0.2.0 release plans (`release-v0.2.0-handoff.md`, `v0-2-0-red-rail-findings.md`) show that pin is about to flip from the full SHA to `ref: v0.2.0` (a tag) — 2 mentions of `kit/cairn` there, plus 1 in `docs/plans/v0-2-0-red-rail-findings.md:339`.
- **Inbound coupling found instead**: cairn's own source code has "the arxa integration plan" (tracked as work item **B2**) baked into comments across a wide swath of files — `crates/cairn-infra/src/auth.rs`, `iroh_sync.rs`, `replicator/mirror.rs`, `crates/cairn-push/{auth,coalescer,config,limit,store}.rs`, `crates/cairn-cli/src/commands/push.rs`, `crates/cairn-server/src/ingest.rs`, `.github/workflows/ci.yml:122`, `sdk/cairn_tauri/tests/conformance.rs`, `sdk/cairn_flutter/test/http_base_test.dart`. `auth.rs` even uses the literal string `"arxa"` as a test tenant ID. This is not just a downstream doc reference — cairn's push-daemon/auth/mirror-ingest work was explicitly engineered for/because of arxa, tracked as milestone B2 directly in code comments.
- No "arxa-agency" or "business plan" string hits found anywhere in tracked content. "arxa digital solutions" appears once, in `docs/plans/cairn-integration-tauri-flutter-push.md`.

---

## Uncertainties / not fully exhaustive

- The ~3G residual in `sdk/` not accounted for by known junk dirs (checked to depth 3 only) — likely more build caches, not drilled further.
- Objective 4 was a targeted spot-check (~13 paths + the two systemic findings above), not an exhaustive top-30 sweep of every doc-vs-code claim in 54 plan files.
- Repo state is a moving target — see the volatility note at the top. Section 6 in particular should be re-checked immediately before any move.
