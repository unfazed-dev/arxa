# Handoff — ADS re-org, Phase B onward

Written 2026-09-02 at the end of Phase A by the session that ran it.
Master plan: `docs/plans/ads-reorg-move-to-business-ssd.md` (read Phases B–D
and "Rollback" there; this file is the operational entry point, not a
replacement). Audits: `docs/research/ads-reorg/{arxa,arxa-studio,cairn}-audit.md`.

## State at handoff (verified, not assumed)

| Repo | Old path (frozen, do not edit) | New path (work here) | HEAD both sides |
|---|---|---|---|
| arxa | `/Volumes/developer_ssd/Developer/totem_labs/arxa` | `/Volumes/business_ssd/arxa_digital_solutions/arxa` | `4bd78e7f` |
| arxa-studio | `/Volumes/developer_ssd/Developer/totem_labs/arxa-studio` | `/Volumes/business_ssd/arxa_digital_solutions/arxa-studio` | `ed1ec3c` |
| cairn | `/Volumes/developer_ssd/Developer/cairn` | `/Volumes/business_ssd/arxa_digital_solutions/cairn` | `12e7a2c` |

**After Phase B (2026-09-02):** old trees frozen at arxa `11f5c14e`, studio
`ed1ec3c`, cairn `12e7a2c` (clean). New trees at arxa `7569123b`, studio
`c971f5a`, cairn `a7cfe54`, all pushed 0/0. See "Phase B — done" below.

- `git status --porcelain`, `for-each-ref`, stash list, `fsck` identical old vs
  new for all three. All pushed to origin (arxa `main` 0/0, studio and cairn
  pushed by the user).
- Copies exclude regenerable dirs: `node_modules target .dart_tool build
  .gradle Pods ephemeral .claude/worktrees`. Everything else, including
  gitignored secrets (`.env`, `keys/*.pem`, `google-services.json`,
  `GoogleService-Info.plist`, `local.properties`), is present in the copies.
- Nothing on this machine respawns from the old paths: no LaunchAgent,
  crontab, shell rc, docker label, or pm2 entry references
  `developer_ssd/Developer/{totem_labs,cairn}` (checked at handoff).
- Old-path processes still running at handoff (cwd in old trees, no write
  handles inside the repos): `cairn-server` 42160, `cairn-pushd` 45200
  (binaries in `~/.cargo/bin`), studio `node bin/arxa-studio.mjs --no-open`
  9259/9546, `node /tmp/wkwtest/serve5.mjs` 53840, Flutter/adb tooling
  2472/2474/81666, the Phase A Claude session 55010.

## Step 0 — before opening the new session (plain terminal)

Do this after the Phase A Claude session (pid 55010) is closed, so its
transcript is complete when copied.

```sh
cd ~/.claude/projects
for p in \
  "-Volumes-developer-ssd-Developer-totem-labs-arxa:-Volumes-business-ssd-arxa-digital-solutions-arxa" \
  "-Volumes-developer-ssd-Developer-totem-labs-arxa-studio:-Volumes-business-ssd-arxa-digital-solutions-arxa-studio" \
  "-Volumes-developer-ssd-Developer-cairn:-Volumes-business-ssd-arxa-digital-solutions-cairn" \
  "-Volumes-developer-ssd-Developer-totem-labs-arxa-docs-research-ads-reorg:-Volumes-business-ssd-arxa-digital-solutions-arxa-docs-research-ads-reorg"
do old=${p%%:*}; new=${p##*:}; [ -d "$old" ] && [ ! -e "$new" ] && cp -a "$old" "$new" && echo "copied $new"; done
cp ~/.claude.json ~/.claude.json.bak
```

Then edit `~/.claude.json`: duplicate each `projects["/Volumes/developer_ssd/..."]`
entry under the new path key (keeps `hasTrustDialogAccepted`, `allowedTools`,
`enabledMcpjsonServers`, `disabledMcpjsonServers`). Leave the old keys until
Phase D.

Open the new session:

```sh
cd /Volumes/business_ssd/arxa_digital_solutions/arxa && claude
```

## Phase B — fix references (new session, cwd = new arxa)

Order matters: B.1 first, so nothing keeps writing into the old tree while
you edit the new one.

B.1 Restart daemons from the new paths.
- `kill 42160 45200 53840 9259 9546`; leave 2472/2474/81666 (IDE-owned, they
  respawn on next Flutter run) — or kill them too, harmless.
- Restart `cairn-server` and `cairn-pushd` with cwd in the new cairn (same
  invocations; find them with `ps -o command= -p 42160` **before** killing if
  the args are not known). Restart studio with
  `cd …/arxa-studio && node bin/arxa-studio.mjs --no-open`.
- Docker: `cd /Volumes/business_ssd/arxa_digital_solutions/cairn/docker &&
  docker compose up -d --force-recreate` (project name `docker`, volume
  `docker_pgdata` — data survives; only the `pg-init` bind mount moves).

B.2 Hardcoded paths that break on move (fix at source, commit per repo).
- cairn: `sdk/cairn_kotlin/scripts/run-live-e2e.sh:31,32`,
  `sdk/cairn_react_native/scripts/build-android.sh:18-20`,
  `sdk/cairn_react_native/scripts/run-android-e2e.sh:27,28` → derive from
  `REPO_ROOT=$(git rev-parse --show-toplevel)`.
- cairn: `rm .claude/skills/consultant .claude/skills/probe-runner` (retired /
  already-broken symlinks).
- arxa-studio: `profile/cordis.patch.yml:54,56,67` (paths into both arxa and
  arxa-studio) — the one real studio breaker. Then `git grep -l developer_ssd`
  for the 8 remaining tracked files (2 `shoot.json`, 6 plan docs — cosmetic).
- arxa-studio: `.claude/settings.local.json` — sed the allowlist prefixes
  (gitignored, no commit).
- Verify per repo: `git grep -n 'developer_ssd/Developer' | grep -v docs/plans`
  returns nothing functional.

B.3 Skill symlinks (35 under `~/.claude/skills`, `~/.kimi-code/skills/arxa-*`,
`~/.agents/skills.shared`).

```sh
old=/Volumes/developer_ssd/Developer/totem_labs/; new=/Volumes/business_ssd/arxa_digital_solutions/
for l in $(find ~/.claude/skills ~/.kimi-code/skills ~/.agents/skills.shared -maxdepth 1 -type l 2>/dev/null); do
  t=$(readlink "$l"); case "$t" in "$old"*) ln -sfn "${new}${t#$old}" "$l"; echo "relinked $l";; esac; done
```

Then `~/.claude/skills/consult-mode/scripts/consult.sh gate skill <name>` for
one arxa skill to confirm the SSOT check resolves to the new path.

B.4 CocoaPods symlinks (gitignored, point at the **old** arxa until
regenerated): in `mobile_flutter` and `kit/showcase_app` run
`flutter pub get && (cd ios && pod install)`. Confirm
`ios/.symlinks/plugins/arxa_kit_studio_transport` now resolves under
`business_ssd`.

B.5 Smoke checks, one per repo, from the new paths: arxa
`flutter analyze` in `mobile_flutter`; arxa-studio `node bin/arxa-studio.mjs
--no-open` boots and serves; cairn `cargo check --workspace`.

B.6 Update this file and the plan: mark Phase B done with the commit hashes.

## Phase B — done (2026-09-02, session cwd = new arxa)

Everything below was observed, not assumed.

- B.1 daemons: killed 42160 45200 53840 9259 9546. Restarted with the exact
  old env (replayed from `ps -E` of the old pids; both `Application Support`
  paths verified) and cwd = new **arxa** (that is what the old ones used, not
  cairn): `cairn-server` pid 42833 → 127.0.0.1:8190, `cairn-pushd` pid 42835 →
  127.0.0.1:8090, studio pid 45796/45867 → 127.0.0.1:7951 (dsh bin under the
  new `arxa-studio/node_modules`). Logs now in `~/Library/Logs/arxa/*.log`
  (old ones were writing into `~/.Trash/`). `/tmp/wkwtest/serve5.mjs` (9919)
  not restarted. No LaunchAgent exists for any of these — after a reboot,
  start them by hand with the same env (`CAIRN_*`/`ARXA_*` vars listed in the
  "Handoff snapshot" of the master plan).
- Docker: `docker compose -p docker up -d --force-recreate` from the new
  `cairn/docker`; container `3d0c8c50cec3`, `pg-init` bind now under
  business_ssd, `docker_pgdata` intact (24 public tables).
- B.2 commits: cairn `a7cfe54` (3 e2e scripts → `git rev-parse`, dead skill
  symlinks removed); arxa-studio `ddd9a47` (`profile/cordis.patch.yml`) and
  `c971f5a` (`profile/agent-presets/arxa/agent.cordis.yml:82,299` — missed by
  the audit); arxa `c9810ff3` (`harness/headless-profile/cordis.patch.yml:9,11`
  — also missed). `git grep 'developer_ssd/Developer'` outside docs/plans,
  archives, benches/results, designs, evidence: empty in all three.
  `arxa-studio/.claude/settings.local.json` allowlist sed'ed (gitignored).
- B.3: 35 skill symlinks relinked, 0 still point at the old tree;
  `consult.sh gate skill arxa-intake` resolves SSOT to the new path.
- B.4: `npm ci` in arxa-studio and arxa (copies exclude `node_modules`; the
  studio refuses to fall back to `~/.dsh`, so this is mandatory — the original
  B list missed it). `flutter pub get` + `pod install` in `mobile_flutter`
  and `kit/showcase_app` — needed `mkdir -p build/ios/SourcePackages` first
  (rsync in the firebase_messaging pod hook is not recursive). Then
  `flutter build ios --config-only` in both, because `ios/Flutter/
  Generated.xcconfig` still had `FLUTTER_APPLICATION_PATH` on the old tree.
  All `ios/.symlinks/plugins/*` now resolve under business_ssd. Side effect
  committed as arxa `7569123b`: showcase_app `pubspec.lock` moved
  `cairn_flutter` `ed5205f`→`fabc1a1` (mobile_flutter already pinned that)
  and SwiftPM `Package.resolved` refreshed.
- B.5: `flutter analyze` mobile_flutter — no issues; studio serves 7951;
  `cargo check --workspace` cairn — Finished, 0 warnings (cold, 54 s).
- Write-gap check (rsync `--update -n`, old → new, regenerables excluded):
  only `arxa/.claude-flow/sessions/undefined.json` differs (mtime only).
- Still rooted in the old trees: context-mode `sbx daemon` 11313 (harness
  sandbox, cwd old arxa-studio, restarts on its own) and IDE pids
  2472/2474/81666. Harmless for Phase C; they hold no write handles.

## Phase C — cutover (same session)

- Confirm nothing has cwd in the old trees:
  `lsof -d cwd -Fn | grep -E 'totem_labs/(arxa|arxa-studio)|Developer/cairn'` → empty.
- Rename, no compat symlinks (a stale reference must break visibly):

```sh
mv /Volumes/developer_ssd/Developer/totem_labs/arxa        /Volumes/developer_ssd/Developer/totem_labs/arxa.bak-2026-09-02
mv /Volumes/developer_ssd/Developer/totem_labs/arxa-studio /Volumes/developer_ssd/Developer/totem_labs/arxa-studio.bak-2026-09-02
mv /Volumes/developer_ssd/Developer/cairn                  /Volumes/developer_ssd/Developer/cairn.bak-2026-09-02
```

- Re-run the B.5 smoke checks. Anything that now fails was a missed old-path
  reference — fix it in the new tree, do not restore the old dir.

## Phase C — done (2026-09-02, same session)

Everything below was observed, not assumed.

- Pre-rename: no VS Code window on the old paths (`workspace.json` grep = 0;
  the 29 `workspaceStorage` hits are history only). Only cwd-holders were
  `iproxy` ×2 and the `adb` server (device tooling, no files open). The one
  write-mode handle was `diskimages-helper` 72543 on a stale Tauri bundle DMG
  (`arxa/desktop/src-tauri/target/.../rw.72300.Arxa Studio_0.1.0_aarch64.dmg`,
  mounted at `/Volumes/dmg.GTdpHV`) — `hdiutil detach /dev/disk11s1`, then
  lsof write-mode = 0. New trees: `.git` is a dir, `git worktree list` = 1
  each, no `developer_ssd` refs in `.git/config`, `.dart_tool`, `Podfile.lock`,
  `*.xcconfig`, `.env*`, `.vscode`.
- Renamed (mv, no symlinks): `totem_labs/arxa` → `arxa.bak-2026-09-02` (53G),
  `totem_labs/arxa-studio` → `arxa-studio.bak-2026-09-02` (577M),
  `Developer/cairn` → `cairn.bak-2026-09-02` (63G). Old paths no longer exist.
- Post-rename smoke: cairn `cargo check --workspace` Finished; studio still
  serving 7951 and a fresh `--no-open` boot serves on 7960; `flutter analyze`
  mobile_flutter — No issues found (4.6 s). `lsof` shows 0 processes with
  anything open under the `.bak` dirs; 8190/8090 answer. New HEADs clean:
  arxa `848bcf07`, arxa-studio `c971f5a`, cairn `a7cfe54`.
- Fixed after the sweep: `~/.claude/settings.json` "Trusted repo" line pointed
  at the old arxa-studio path → new path. `~/.claude.json` intentionally keeps
  the 3 old-path project entries next to the 3 new ones (Step 0 duplicated
  them; drop the old ones in Phase D).
- Not this reorg's problem, left alone: 30 dangling symlinks in
  `~/.claude/skills` all target `~/.agents/skills.shared/*` or
  `~/.hermes/skills/*` (never under `developer_ssd`).

## Phase D — after 7 days (≥ 2026-09-09)

- `rm -rf` the three `.bak-2026-09-02` dirs (frees ~110 GB on developer_ssd).
- Delete the old `~/.claude/projects/-Volumes-developer-ssd-…` dirs and the
  old keys in `~/.claude.json`.

## Rollback (any time before Phase D)

- Before Phase C: nothing to undo — old trees are untouched; delete the new
  copies if abandoning.
- After Phase C: `mv` the `.bak-2026-09-02` dirs back to their original names.
  If commits were made in the new copies after cutover, push them to origin
  first and `git pull --ff-only` in the restored old tree; do not rsync
  backwards.

## Out of scope for this pass (deliberately not done)

- Pruning `archives/spikes/` (1.7 GB, git-tracked) in arxa.
- Archiving the ~95 unclassified arxa plans and the studio/cairn stale-ref
  sweeps flagged in the audits.
- Prose-only old-path mentions in `docs/plans/*.md` (arxa ~28, cairn 6).
