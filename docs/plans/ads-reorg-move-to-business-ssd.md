# ADS re-org: move arxa, arxa-studio, cairn to business_ssd

Status: PLANNED — awaiting go for Phase A
Date: 2026-09-02
Audit inputs: `docs/research/ads-reorg/{arxa,arxa-studio,cairn}-audit.md`

## Goal

Move three repos off the nearly-full `developer_ssd` (13.9 GB free) into one
company tree on `business_ssd` (197 GB free, APFS), without losing uncommitted
work, xattrs, git history, or the skill symlinks that other tools depend on.

| Repo | Old | New |
|---|---|---|
| arxa | `/Volumes/developer_ssd/Developer/totem_labs/arxa` | `/Volumes/business_ssd/arxa_digital_solutions/arxa` |
| arxa-studio | `/Volumes/developer_ssd/Developer/totem_labs/arxa-studio` | `/Volumes/business_ssd/arxa_digital_solutions/arxa-studio` |
| cairn | `/Volumes/developer_ssd/Developer/cairn` | `/Volumes/business_ssd/arxa_digital_solutions/cairn` |

Business plans stay in Google Drive (SSOT); nothing from Drive is copied into
the repo tree. (Decision recorded in session; confirm on review.)

## Decisions (all confirmed by user in session)

1. Commit in-progress work in arxa (40 dirty files) and cairn (16) as WIP
   commits before copying. arxa-studio is clean.
2. Copy tool: Homebrew `rsync` 3.x (`brew install rsync`). Apple `openrsync`
   drops xattrs and is not used.
3. arxa-studio: remove all 9 agent worktrees under `.claude/worktrees/` and
   delete their branches. Verified `ahead=0` for every one (fully contained in
   master, 19–20 behind). The one "dirty" file was untracked `node_modules`.
   cairn's stray detached worktree (nested in a deleted studio worktree dir)
   is pruned.
4. Cutover: rename old dirs to `*.bak-2026-09-02`, **no compat symlinks**, so
   any stale reference breaks visibly. Delete the `.bak` dirs after 7 days.
5. Skill symlinks (`~/.claude/skills`, `~/.kimi-code/skills`,
   `~/.agents/skills.shared`) are re-pointed to the real new path.

## Facts that shape the sequence

- Both volumes are APFS (`diskutil info`). Symlinks, xattrs, exec bits safe.
- Sizes (from audits): arxa 53G on disk, ~37.7G is untracked build junk
  (desktop Rust `target/` 18G, Flutter `build/` ~10G, other gen ~10G) — real
  content ~15G, of which 1.7G is `archives/spikes/` (git-tracked, retired,
  copied as-is, not pruned in this pass). arxa-studio ~963M, ~698M is
  worktrees + `node_modules`, real payload ~265M (`plugins/` 108M, `designs/`
  66M, plus gitignored `keys/` — sensitive, perms preserved by `rsync -a`).
  cairn 55G, ≥94% regenerable caches under `sdk/` and `apps/`; git objects 18MB.
  Expect roughly 15G + 0.3G + 3G to actually copy.
- **cairn is live**: another session committed 12 dirty files and 7 commits
  during the audit (now 47 ahead of origin, 1 untracked dir
  `benches/results/raw/`). The cairn freeze (A.5) requires that session to
  be idle or closed; re-check `git status` and `git log -1` right before.
- arxa has 821 symlinks; the relative ones (kit/ 499, mobile_flutter/ 294)
  survive a copy, the absolute ones point outside the repo
  (`~/.pub-cache`, `/Volumes/developer_ssd/dev/fvm/...`) and are unaffected.
- Cross-repo linkage is via **git**, not filesystem: `arxa/kit/cairn/pubspec.yaml`
  pins `cairn_flutter` to `github.com/unfazed-dev/cairn.git`. No `path:`,
  `path =`, or `file:` deps cross repo boundaries. No `.gitmodules`.
- Live processes at audit time: `cargo test --workspace -- --include-ignored`
  in cairn (must finish before cairn's final pass); VS Code with cairn files
  open; `cairn-server` (pid 42160) and `cairn-pushd` (45200) running from
  `~/.cargo/bin` (installed binaries — check with `lsof -p` whether they hold
  files under the repo before cutover); Docker `cairn-postgres`.
- Docker: compose project name is `docker` (from `cairn/docker` basename —
  unchanged after move). Data is the named volume `docker_pgdata` (survives).
  Only bind mount is `cairn/docker/pg-init` → recreate container from new path.
- Claude Code keys per-project history/memory/permissions by cwd under
  `~/.claude/projects/<path-with-slashes-and-underscores-as-dashes>`. Four dirs
  to migrate (see Phase B.6).
- This Claude session's cwd is inside old arxa. Phase B must run from a **new
  session opened in the new arxa path**.

## Hardcoded old-path references to fix after the move

Functional (break on move):
- cairn `sdk/cairn_kotlin/scripts/run-live-e2e.sh:31,32` (`ROOT=`, `REPO_ROOT=`)
- cairn `sdk/cairn_react_native/scripts/build-android.sh:18-20`
- cairn `sdk/cairn_react_native/scripts/run-android-e2e.sh:27,28`
  → fix at source: derive from `$(git rev-parse --show-toplevel)`.
- arxa-studio `profile/cordis.patch.yml:54,56,67` — config, hardcodes paths
  into **both** arxa and arxa-studio. The one real studio breaker.
- arxa-studio: 8 further git-tracked files with absolute `/Volumes/developer_ssd`
  paths (2 `shoot.json` design metadata, 6 plan docs — cosmetic) →
  `git grep -l developer_ssd` and fix case by case.
- Skill symlinks on this machine (35 under `~/.claude/skills`, plus
  `~/.kimi-code/skills/arxa-*`, `~/.agents/skills.shared`).
- Docker compose working dir label (recreate).

Prose only (inert, fix opportunistically): ~28 mentions across arxa
`docs/plans/*.md`; cairn docs (6 files); arxa `docs/plans/widget-panel-vocabulary-reconciliation.md:111`
and `inspector-everything-as-widgets.md:21` reference `~/.agents/...` skill paths.

## Phase A — prepare and copy (this session, old paths still live)

A.1 Commit WIP
```sh
git -C /Volumes/developer_ssd/Developer/totem_labs/arxa add -A && git -C /Volumes/developer_ssd/Developer/totem_labs/arxa commit -m "wip: mobile_flutter responsive layout refactor, snapshot before move to business_ssd"
git -C /Volumes/developer_ssd/Developer/cairn status --short   # audit end-state: 1 untracked dir benches/results/raw/ — decide gitignore vs commit
```
arxa's 40 dirty files are one coherent mobile_flutter responsive-layout
refactor (audit §5), hence the descriptive message. Review `git status --short`
first in both repos; anything that should not be committed (secrets, junk)
gets `.gitignore`d, not committed. cairn's earlier 16 dirty files were
committed by the other live session during the audit.

A.2 Remove studio worktrees and branches
```sh
cd /Volumes/developer_ssd/Developer/totem_labs/arxa-studio
for wt in .claude/worktrees/agent-*; do b=$(git -C "$wt" branch --show-current); git worktree remove --force "$wt"; git branch -D "$b"; done
git worktree prune
git -C /Volumes/developer_ssd/Developer/cairn worktree prune
git worktree list; git -C /Volumes/developer_ssd/Developer/cairn worktree list   # expect 1 entry each
```

A.3 Install rsync, create target
```sh
brew install rsync && /opt/homebrew/bin/rsync --version | head -1   # expect 3.x
mkdir -p /Volumes/business_ssd/arxa_digital_solutions
```

A.4 First pass (repos stay live; excludes are regenerable caches only)
```sh
EX='--exclude=node_modules --exclude=target --exclude=.dart_tool --exclude=build --exclude=.gradle --exclude=Pods --exclude=ephemeral --exclude=.claude/worktrees'
R=/opt/homebrew/bin/rsync
$R -aHAX --info=progress2 $EX /Volumes/developer_ssd/Developer/totem_labs/arxa/        /Volumes/business_ssd/arxa_digital_solutions/arxa/
$R -aHAX --info=progress2 $EX /Volumes/developer_ssd/Developer/totem_labs/arxa-studio/ /Volumes/business_ssd/arxa_digital_solutions/arxa-studio/
$R -aHAX --info=progress2 $EX /Volumes/developer_ssd/Developer/cairn/                  /Volumes/business_ssd/arxa_digital_solutions/cairn/
```
Note: `--exclude=build` also skips any *tracked* `build/` dir. A.6 catches
that (it shows as deleted in the new repo's `git status`); re-sync that path
without the exclude if it happens.

A.5 Freeze, then final pass
- Wait for `cargo test` to exit (`ps -eo command | grep '[c]argo test'` → 0).
- Close VS Code windows on the three repos.
- Re-run the three A.4 commands with `--delete` added.

A.6 Verify (all three must be true per repo)
```sh
for r in arxa arxa-studio cairn; do
  old=/Volumes/developer_ssd/Developer/totem_labs/$r; [ $r = cairn ] && old=/Volumes/developer_ssd/Developer/cairn
  new=/Volumes/business_ssd/arxa_digital_solutions/$r
  echo "== $r"; git -C $new fsck --no-dangling 2>&1 | tail -2
  diff <(git -C $old status --porcelain) <(git -C $new status --porcelain) && echo "status identical"
  [ "$(git -C $old rev-parse HEAD)" = "$(git -C $new rev-parse HEAD)" ] && echo "HEAD identical"
done
```
Anything other than clean fsck + identical status + identical HEAD stops the
move here. Old dirs are untouched at this point, so stopping is free.

A.7 Re-point skill symlinks **before** the new session starts (otherwise the
new session loads skills from the old copy)
```sh
OLD=/Volumes/developer_ssd/Developer/totem_labs; NEW=/Volumes/business_ssd/arxa_digital_solutions
for d in ~/.claude/skills ~/.kimi-code/skills ~/.agents/skills.shared; do
  find "$d" -maxdepth 1 -type l | while read l; do t=$(readlink "$l"); case "$t" in "$OLD"/*) ln -sfn "${t/$OLD/$NEW}" "$l";; esac; done
done
find ~/.claude/skills ~/.kimi-code/skills ~/.agents/skills.shared -maxdepth 1 -type l ! -exec test -e {} \; -print   # expect empty
```

**Stop. Quit this session. Open a new Claude Code session at
`/Volumes/business_ssd/arxa_digital_solutions/arxa` for Phase B.**

## Phase B — cutover (new session, cwd in new arxa)

B.0 Close the write gap. This session (ruflo memory, context-mode index,
`.claude/` state) kept writing into the old tree after A.5. From the new
session, one more delta pass old → new, then re-run the A.6 checks:
```sh
$R -aHAX --delete $EX /Volumes/developer_ssd/Developer/totem_labs/arxa/        /Volumes/business_ssd/arxa_digital_solutions/arxa/
$R -aHAX --delete $EX /Volumes/developer_ssd/Developer/totem_labs/arxa-studio/ /Volumes/business_ssd/arxa_digital_solutions/arxa-studio/
$R -aHAX --delete $EX /Volumes/developer_ssd/Developer/cairn/                  /Volumes/business_ssd/arxa_digital_solutions/cairn/
```
SQLite files copied mid-write (`*.db`, `*.db-wal`) are the risk here; no
session may be open on the old paths when this runs.

B.1 Rename old dirs (no symlinks)
```sh
mv /Volumes/developer_ssd/Developer/totem_labs/arxa        /Volumes/developer_ssd/Developer/totem_labs/arxa.bak-2026-09-02
mv /Volumes/developer_ssd/Developer/totem_labs/arxa-studio /Volumes/developer_ssd/Developer/totem_labs/arxa-studio.bak-2026-09-02
mv /Volumes/developer_ssd/Developer/cairn                  /Volumes/developer_ssd/Developer/cairn.bak-2026-09-02
```
`cairn-server` / `cairn-pushd` (checked 2026-09-02): binaries live in
`/Volumes/developer_ssd/dev/.cargo/bin` (not moving); one of them has its
**cwd in old arxa**. macOS keeps a renamed cwd valid, but restart both after
B.1 so their cwd is the new path:
```sh
pkill -x cairn-server; pkill -x cairn-pushd
cd /Volumes/business_ssd/arxa_digital_solutions/arxa && (cairn-server &) && (cairn-pushd &)   # or however they are normally launched
```

B.2 Confirm skill symlinks (done in A.7) still resolve from the new session
```sh
~/.claude/skills/consult-mode/scripts/consult.sh gate skill consult-mode        # SSOT check resolves to the new path
```

B.3 Fix the three cairn scripts at source (`REPO_ROOT=$(git rev-parse --show-toplevel)`), then
`git -C $NEW/cairn grep -n developer_ssd -- '*.sh'` → expect 0 hits.

B.4 arxa-studio tracked files: `git -C $NEW/arxa-studio grep -l developer_ssd` → fix each, expect 0 hits.

B.5 Docker
```sh
cd /Volumes/business_ssd/arxa_digital_solutions/cairn/docker && docker compose up -d --force-recreate
docker inspect cairn-postgres -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'   # expect new path
docker volume ls | grep docker_pgdata                                                                   # still present
```

B.6 Claude Code project state (history, memory, permissions)
```sh
P=~/.claude/projects
cp -a $P/-Volumes-developer-ssd-Developer-totem-labs-arxa                         $P/-Volumes-business-ssd-arxa-digital-solutions-arxa
cp -a $P/-Volumes-developer-ssd-Developer-totem-labs-arxa-studio                  $P/-Volumes-business-ssd-arxa-digital-solutions-arxa-studio
cp -a $P/-Volumes-developer-ssd-Developer-cairn                                   $P/-Volumes-business-ssd-arxa-digital-solutions-cairn
cp -a $P/-Volumes-developer-ssd-Developer-totem-labs-arxa-docs-research-ads-reorg $P/-Volumes-business-ssd-arxa-digital-solutions-arxa-docs-research-ads-reorg
```
Worktree-keyed project dirs are left to age out.

B.6b `~/.claude.json` holds per-path `allowedTools`, `enabledMcpjsonServers`,
`disabledMcpjsonServers`, `hasTrustDialogAccepted` for all three repos.
Duplicate each entry under its new path key (jq, with a backup first):
```sh
cp ~/.claude.json ~/.claude.json.bak-2026-09-02
jq '.projects["/Volumes/business_ssd/arxa_digital_solutions/arxa"]        = .projects["/Volumes/developer_ssd/Developer/totem_labs/arxa"]
  | .projects["/Volumes/business_ssd/arxa_digital_solutions/arxa-studio"] = .projects["/Volumes/developer_ssd/Developer/totem_labs/arxa-studio"]
  | .projects["/Volumes/business_ssd/arxa_digital_solutions/cairn"]       = .projects["/Volumes/developer_ssd/Developer/cairn"]' \
  ~/.claude.json.bak-2026-09-02 > ~/.claude.json
jq -r '.projects | keys[]' ~/.claude.json | grep -c business_ssd   # expect 3
```
Do this while no Claude Code session is running (it rewrites the file on exit).

B.7 Sweep for remaining old-path references outside the repos
```sh
grep -l developer_ssd ~/.zshrc ~/.zprofile ~/.config/**/*.{json,toml,yml,yaml} ~/Library/LaunchAgents/*.plist 2>/dev/null
```
(launchd plists were checked during audit: 0 hits.)

B.8 Rebuild caches on demand: `npm install` / `flutter pub get` / `cargo build`
per package as needed. Not done proactively.

B.9 Commit the reference fixes in each repo (one commit per repo, message
`chore: fix hardcoded developer_ssd paths after move to business_ssd`).

## Phase C — plans hygiene (after the move, separate commit)

- arxa `docs/plans/`: 110 plans; 15 carry an explicit COMPLETE/DONE/SHIPPED/
  SUPERSEDED/CLOSED header → move to `docs/plans/archive/` (list in
  `arxa-audit.md` §4; confirm the list before moving).
- arxa-studio `docs/plans/`: 34 plans, all touched in the last 7 days — no
  archive candidates.
- cairn `docs/plans/`: 54 files; `docs/plans/README.md` calls itself
  authoritative but omits 30 of them (incl. all live security-audit work) —
  regenerate the index. `HANDOFF.md` is self-marked SUPERSEDED.
  `fixtures/flutter/` is referenced in HANDOFF.md and README.md's DONE table
  but does not exist.
- arxa stale references worth a fix (audit §3):
  1. `docs/plans/widget-panel-vocabulary-reconciliation.md:111` and
     `docs/plans/inspector-everything-as-widgets.md:21` instruct running the
     retired `consultant` skill script → point at `consult-mode`.
  2. `gate_runner.dart` `gateOrder` lists 14 gates, 15 `gate_*.dart` files exist
     (`gate_design_styles`, `gate_design_widgets` unwired) — needs code-owner
     call, not a mechanical fix.
  3. `docs/plans/media-3d-animation-games.md` describes arxa-studio as nested
     under arxa; it is a sibling repo.
  4. `docs/plans/handoff-reveal-drawer-remaining.md:13` says branch `master`;
     actual is `main`.
- The ~28 inert old-path mentions in plan prose: fix when a plan is next
  touched, not as a bulk edit.
- Note: `kit/studio_transport` (named in the audit brief) does not exist in
  arxa-studio — the name came from the brief, not the repo.

## Phase D — 2026-09-09: delete backups

Only if nothing has referenced the `.bak` dirs for 7 days
(`ls -lu` access times, and no reported breakage):
```sh
rm -rf /Volumes/developer_ssd/Developer/totem_labs/arxa.bak-2026-09-02 /Volumes/developer_ssd/Developer/totem_labs/arxa-studio.bak-2026-09-02 /Volumes/developer_ssd/Developer/cairn.bak-2026-09-02
```

## Rollback

Any time before Phase D: `mv` the `.bak` dirs back to their original names,
re-run A.7 with OLD/NEW swapped, `docker compose up -d --force-recreate` from
the old `cairn/docker`. Nothing in Phase A modifies the old dirs except the
WIP commits and worktree removal (A.1, A.2), both of which are wanted anyway.
Caveat: the B.9 fix commits exist only in the new copy — before rolling back,
`git push` them or `git -C <old> fetch <new> && git merge` so they are not lost.

## Out of scope for this pass

- Pruning `archives/spikes/` (1.7G tracked history) from arxa.
- Rewriting inert prose paths in plans.
- The ~3G of unexplained cache under cairn `sdk/` (audit uncertainty).
