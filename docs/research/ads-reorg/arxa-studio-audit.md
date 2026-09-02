# arxa-studio move-readiness audit

Repo: `/Volumes/developer_ssd/Developer/totem_labs/arxa-studio` (branch `master`, remote `github.com/unfazed-dev/arxa-studio`, clean tree, ~963M on disk).
Target: `/Volumes/business_ssd/arxa_digital_solutions/arxa-studio`.
Method: read-only. Nothing in arxa-studio was moved, edited, deleted, or committed. All commands run via context-mode sandbox tools per project CLAUDE.md.

---

## 1. STRUCTURE

| Dir | Size | Purpose | Flag |
|---|---|---|---|
| `.claude/worktrees/` | 389M | 9 live git worktrees (agent sessions), some `locked` | **junk/ephemeral** — duplicates tracked content, tied to absolute paths via `.git/worktrees/*/gitdir`; will break on move |
| `node_modules/` | 309M | npm deps (gitignored) | **junk** — regenerable via `npm install` |
| `plugins/` | 108M | 27 dsh plugins — the actual product code (cairn-rail, memory, git-workspace, workspace-index, artifact-viewer, arxa-frame, theme-accent, etc.) | keep — core |
| `designs/` | 66M | design-mockup exports/screenshots, 9 subdirs; `prism-step1/` alone is 59M | keep, but heavy — mostly binary design artifacts |
| `docs/` | 652K | plans (34), research (7), upstream (1) | keep — core |
| `scripts/` | 136K | CI/tooling scripts (`ci.mjs` etc.) | keep |
| `bin/` | 72K | entrypoints `arxa-studio.mjs`, `arxa-explore.mjs` | keep |
| `profile/` | 16K | `cordis.patch.yml` — materialized runtime profile config | keep, **needs path fix** (see §2) |
| `research/` | 12K | top-level research notes (separate from `docs/research/`) | keep |
| `pi/` | 4.0K | `arxa-memory.ts` — Pi adapter | keep |
| `keys/` | 4.0K | gitignored — updater signing keys | keep, **sensitive**: never commit, move with care/perms preserved |
| `.claude-flow/` | small | gitignored session cache, ~38 files reference absolute paths | junk — ephemeral, safe to drop |

**Bottom line:** of ~963M, roughly 698M (worktrees 389M + node_modules 309M) is disposable/regenerable and should NOT be copied — just `git worktree remove` all 9 worktrees and `rm -rf node_modules` before the move, then `npm install` fresh at the new location. Real payload is closer to ~265M (plugins + designs + docs/scripts/bin/etc).

---

## 2. MOVE BREAKAGE

**(a) Files with absolute `/Volumes/developer_ssd` paths** (worktree duplicates excluded — those are counted separately in §1): 49 total — **9 tracked, 40 untracked**.

*Tracked (real, in-repo):*
- **CONFIG (highest impact):** `profile/cordis.patch.yml:54,56,67` — hardcodes absolute paths into **both** sibling repos: `.../arxa/harness/dsh-external-gate/index.mjs`, `.../arxa/harness/verdict.sh`, and `.../arxa-studio/plugins/memory/index.mjs`. This is a materialized runtime profile — **will break on move**, needs path remediation as part of the move, not optional cleanup.
- **DATA/CODE (low impact):** `designs/org-model-v2/f/first-run/shoot.json:13,30,47` and `.../renamed-state/shoot.json:13,30,47` — absolute PNG output paths from a screenshot tool; cosmetic metadata, likely regenerable, not runtime-critical.
- **DOCS (6 plan files, prose-only mentions):** `docs/plans/arxa-isolation-levels.md`, `cairn-maturity-audit.md`, `cairn-rail-spike.md`, `git-card-sessions-worktree-rewire.md`, `HANDOFF-file-org-shell.md`, `mobile-flutter-conventions.md` — all reference sibling-repo absolute paths in prose. No functional impact; find/replace for accuracy only.

*Untracked (not real breakage — ephemeral/gitignored):* 38 files under `.claude-flow/` (session cache, incl. `pending-insights.jsonl`) + `.claude/settings.local.json` (one absolute-path Bash permission-allowlist string spanning both arxa and arxa-studio paths). Low importance, local-machine only.

**(b) Symlinks:** 4 found, all inside `.claude/worktrees/agent-*/node_modules`, each an absolute-path symlink back to the main repo's `node_modules`. Worktree-local, untracked — will dangle regardless once worktrees are pruned (see §1), non-issue if worktrees are removed before the move as recommended.

**(c) Path dependencies reaching outside the repo:** **none found.** No `pubspec.yaml`, no `Cargo.toml` in this repo. `package.json` has zero `file:` deps — all dependencies are real npm-registry packages, exact-pinned `@deepseek-ai/dsh*@0.1.1-rc.2` ("depend, never fork"). No `.gitmodules`. `git worktree list` shows only the 9 agent worktrees, all children of this repo's own `.git` — none reach into arxa or cairn.

**(d) Env/config/launchd/scripts:** no `.plist` files anywhere in the repo. No hardcoded paths in `scripts/` or `bin/`. `.mcp.json` (gitignored) contains only a Supabase HTTPS URL, no filesystem paths. Only hardcoded-path config is `profile/cordis.patch.yml` (above).

---

## 3. STALE REFERENCES

- **Retired-name search** (probe-runner, consultant skill, flutter-crew, old product names) across all docs: **zero hits.** Docs are clean on this front.
- Path-existence check on ~180 backticked path-like tokens across `docs/*.md`: ~30 point into the sibling `arxa`/`cairn` repos by design (not resolvable from within arxa-studio, not stale — expected). Of the remainder, the large majority are **forward-looking spec paths** describing not-yet-built files (e.g. the Flutter migration spec's target file layout, `entitlement-auto-refresh.md`'s planned modules) — these read as aspirational, not dead references to something that used to exist.
- **No high-confidence "doc says code exists but it doesn't" findings.** I did not find a clean case worth reporting as a false claim; forcing a top-30 list here would mostly be noise. Listing the clearest candidates instead, with the caveat that these are unresolved-path signals, not confirmed staleness:
  1. `docs/plans/mobile-flutter-conventions.md` — several referenced arxa-repo Flutter file paths not independently verified (cross-repo, can't check from here).
  2. `docs/plans/entitlement-auto-refresh.md` — references planned module paths that don't yet exist (explicitly forward-looking per the doc's own framing).
  3. A handful of plugin-relative paths in older plans that read naturally as "path relative to that plugin's own dir," which my flat-repo-root check flagged as false negatives.
- **Recommendation:** this section's automated signal is weak; a human skim of the ~10 most-referenced docs during the actual move would catch more than the heuristic did.

---

## 4. PLANS INVENTORY

**Total:** 34 files directly in `docs/plans/` (plus `docs/plans/phase0b-snapshots/` — 3 incident-snapshot files, not plans themselves).

**12 most recent (by mtime, all dated 2026-09-02 except where noted):**

| Plan | Status |
|---|---|
| `git-card-sessions-worktree-rewire.md` | active — records today's phase0b incident; central rewire plan |
| `open-items-completion.md` | active — continuation tracker of session-execution-log.md |
| `session-execution-log.md` | active/superseded-by-above |
| `arxa-studio-vocabulary-collisions.md` | active, explicitly blocking — inventory done, resolutions pending |
| `zai-latency-bench-report.md` | done — verdict reached (TTFT investigation) |
| `shell-language-decision.md` | done — Accepted (ADR, user-approved 2026-08-29) |
| `rust-port-feasibility.md` | done — verdict: do not port to Rust |
| `mobile-flutter-migration-spec.md` | active spec (Tauri → Flutter) |
| `mobile-flutter-conventions.md` | active/reference |
| `dsh-plugin-ui-conformance.md` | done — confirmed |
| `arxa-studio-grill-decisions.md` | active — running decision log, open questions remain |
| `arxa-isolation-levels.md` | in progress — "nothing settled" per the doc itself |

**Status counts — caveat:** only 2 of the 34 files have a machine-checkable `Status:` header (`arxa-studio-vocabulary-collisions.md`, and one sub-item line in `git-card-sessions-worktree-rewire.md`). The rest state status in prose ("Accepted", "Grilled and confirmed", "in progress"). Sampling the top 14 by mtime: **~4 done/accepted, ~5+ active/in-progress**, rest not fully sampled. Do not trust an automated done/active/stale split beyond this.

**Archive candidates:** none confidently identified. Every plan I checked was touched within the last 7 days (Aug 26 – Sep 2, 2026); nothing is stale by mtime, and there's no consistent status field to hang an archive decision on. Recommend a manual pass rather than automation.

**Plans touching cairn and/or arxa (~9 of 34):** `cairn-maturity-audit.md`, `cairn-rail-spike.md`, `mobile-flutter-conventions.md`, `mobile-flutter-migration-spec.md`, `arxa-studio-vocabulary-collisions.md`, `git-card-sessions-worktree-rewire.md`, `HANDOFF-file-org-shell.md`, `arxa-studio-grill-decisions.md`, `org-model-v2-implementation.md`.

**`session-execution-log.md` (148 lines):** Execution log for an unattended run — assistant proceeded with full permission after the user stepped away, cross-checking work against an independent 44-item worklist, recording what's done and what cost extra time.

**`open-items-completion.md` (58 lines):** Direct continuation of the log above; mandate to close every open item/gap/miss with smoke/pressure/stress/e2e testing via fanned-out subagents. Contains a 13-row table of open items (B2, S1, B7, B8, B12, Gap1, D110, D111, Phase2-4, Phase0b, L1/L2 tiers) each mapped to spec, code location, and status, plus a record of blanket-permission decisions made on the user's behalf.

**Phase0b incident (commit `3690f26`):** the assistant ran `scripts/phase0b-cleanup.mjs --apply` without user confirmation while intending only to test its refusal path, deleting 14 rows (TESTO/TOPO registry entries, branches, 4 live worktrees). All deleted branches were 0-commits-ahead of main (recoverable); a pre-apply snapshot existed. The script was hardened afterward (commit `d3cc820`) to fail closed.

---

## 5. CROSS-REPO LINKAGE

- **To `dsh`** (external DeepSeek package — not one of the 3 repos being moved): real npm dependency, exact-pinned `@deepseek-ai/dsh*@0.1.1-rc.2`. This is the repo's core premise — "depend, don't fork."
- **To `arxa`:** doc-only, no code/path dependency. `README.md` states the SSOT decisions record lives at `arxa/docs/plans/arxa-harness-and-distribution.md` (a prose cross-repo pointer). Several plans coordinate changes with arxa (Flutter conventions/migration, HANDOFF-file-org-shell, vocabulary-collisions, worktree-rewire) but no code in arxa-studio imports or builds against arxa. Note: **`kit/studio_transport` was not found anywhere in this repo** — if that name came from the task brief, it does not exist here; may be worth checking with whoever supplied it.
- **To `cairn`:** `plugins/cairn-rail/` is arxa-studio's own plugin implementing a JSON wire contract pinned to a specific cairn-core commit (per `docs/plans/cairn-rail-spike.md`) — not a compiled or path dependency. `plugins/cairn-rail/lib/adapter.js` is explicitly documented as "the only file in arxa-studio that knows cairn's wire shape." No cairn package exists in `node_modules`. `plugins/cairn-rail/README.md` is empty. `plugins/push-doorbell/README.md` separately references a "cairn-pushd sidecar" and a relative link to `../../arxa/docs/plans/doorbell-decision-2026-08-29.md`.
- **"Arxa Digital Solutions" mentions:** top-level `CLAUDE.md`, section "Ownership & database boundary — READ FIRST," names Arxa Digital Solutions as the parent company that owns the Supabase instance, with an explicit rule that arxa-studio features must never *require* that company's database — local-only fallback is mandatory. Also mentioned in `docs/plans/arxa-studio-grill-decisions.md`, `org-model-v2-implementation.md`, `mobile-flutter-conventions.md`, `mobile-flutter-migration-spec.md`.
- **"arxa-agency" / "business plan":** no literal hits. The string "agency" only appears in the unrelated filename `docs/plans/agency-backend-provider-abstraction.md` (a backend-provider abstraction plan, not a business/agency reference).
