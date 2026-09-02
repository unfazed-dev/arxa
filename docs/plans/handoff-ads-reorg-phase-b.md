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
