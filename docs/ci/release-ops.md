# Release operations runbook (desktop updater)

Procedures for the Arxa Studio auto-update feed. Decision numbers refer to
the 2026-09-05 amendment in `docs/plans/arxa-harness-and-distribution.md`
(ADR-0002 records the shape). Build pipeline: `.github/workflows/desktop-release.yml`.
Updater config: `desktop/src-tauri/tauri.conf.json`.

## Release channels and the ladder

Two lanes, one pipeline (D21):

| Channel | Trigger tag | Example | Feed path |
|---|---|---|---|
| stable | `studio-v<semver>` | `studio-v1.2.3` | `desktop/stable/<target>/<arch>/latest.json` |
| beta | `studio-beta-v<semver>` | `studio-beta-v1.2.3-beta.1` | `desktop/beta/<target>/<arch>/latest.json` |

- The workflow derives `CHANNEL` + `VERSION` from the tag in its first step;
  every artifact follows: the GitHub Release is created **on the triggering
  tag**, the manifest is committed to the channel's feed path.
- **Time-ladder (D21):** a release rides **beta at T+0**; **stable at T+N**
  where N ≥ the worst-case bug-discovery window (plan T3 gate: ~1 week plus
  one booted-DENY proof). A human pushes the stable tag — **D3 makes the tag
  push the human release button.**
- **Opt-in:** installs are stable by default; a machine joins beta with
  `ARXA_UPDATE_CHANNEL=beta`. The shell swaps the `/stable/` segment in the
  *configured* endpoints (`lib.rs check_for_updates`), preserving endpoint
  order — D6 failover only on non-2xx, first 200+valid wins.
- **One shared minisign key (D7)** signs both channels. Acceptable only
  while beta signing is protected exactly like stable — both lanes run in
  the same protected `release` environment (below).

## Rollback

Doctrine: the Tauri updater **structurally never downgrades** — it refuses
any version lower than the running one. The kill switch stops **new update
offers only**; it cannot reach installs that already applied the bad
version. Recovery is always **ship a HIGHER version**, optionally carrying
the previous engine bundle (the bundle is atomic — ADR-0002 — so "app fix
with old engine" is expressed as one higher-numbered bundle).

1. **Kill the feed** for the affected channel (see below) so no further
   installs pick the bad manifest up.
2. **Assess blast radius.** The feed is static JSON — no staged-rollout
   percentages exist yet, so every install on the channel saw the manifest
   within ~the 300 s feed cache (D6) + its next launch check. The exposure
   window is "since the manifest landed", not a cohort percentage.
3. **Ship higher.** Tag the fix (or the revert) as a **higher semver** —
   even a `0.1.1` if that is what ordering needs — and let the normal
   pipeline publish it. Installs on the bad version update to it; installs
   that never took the bad version update to it too. Same procedure for
   both channels; a stable regression can also be cut as a beta first if
   you want the ladder to work for you.
4. **Post-mortem note** in `docs/plans/arxa-harness-and-distribution.md`
   (what shipped, what caught it, what gate changes).

## Kill switch

`desktop/scripts/kill-switch.sh` halts a rollout by deleting the feed
manifests — the updater treats non-2xx on **all** endpoints as "no update".

```sh
desktop/scripts/kill-switch.sh stable                 # R2 (if live) + arxa-releases main
desktop/scripts/kill-switch.sh beta --github          # only the arxa-releases copy
desktop/scripts/kill-switch.sh beta --r2              # only the R2 copy
desktop/scripts/kill-switch.sh stable --target darwin --arch aarch64 \
  --bucket arxa-releases --repo unfazed-dev/arxa-releases   # explicit everything
```

- Each action is printed before it runs; a missing file is success
  (the goal state is "gone").
- `--r2` requires `CLOUDFLARE_API_TOKEN`; `--github` requires `gh` auth with
  contents-write on `unfazed-dev/arxa-releases`.
- It does **not** un-install anything already applied (see Rollback), does
  not touch GitHub Release assets (the manifest steers installs; assets
  stay for manual download), and there are no rollout percentages to dial
  back (nothing stages yet).

## Signing key custody (D10)

Current state after migration:

- The minisign private key lives **only** in the protected `release` GitHub
  environment (secrets `TAURI_SIGNING_PRIVATE_KEY`,
  `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`), tag-policy-restricted. The
  workflow's `environment: release` is what gates exposure — not repo-level
  secrets readable by every run.
- The local `~/.arxa/updater/arxa-updater.key` is the **offline backup**,
  not a build input for releases. (Local manual builds via
  `desktop/scripts/build-release.sh` may still sign from it; nothing in the
  release pipeline reads that file.)
- The **public** key is committed in `tauri.conf.json > plugins.updater.pubkey`;
  updates install only if signed by its keypair.

### Rotation (minisign has NO revocation — rotation is a transition release)

1. Generate the new keypair **offline** (`tauri signer generate`; encrypted
   media, air-gapped machine).
2. Ship one **transition release**: `tauri.conf.json` takes a single pubkey
   string, so the sequence is — a release **signed with the OLD key** whose
   build **embeds the NEW pubkey**, followed by the next release **signed
   with the new key**. Every install that takes the transition release can
   then verify the new-key releases that follow.
3. Update `TAURI_SIGNING_*` secrets in the `release` environment.
4. After **one clean cycle** (fleet updating + a fresh release verifying
   against the embedded pubkey), destroy the old key material everywhere.
5. Precedent: qwen-code PR #8511 rotated a lost Tauri key this way
   (Aug 2026; see D10).

### Retiring the local key file

- [ ] Keep one **encrypted offline copy** (external media, not the build
      machine, not the repo).
- [ ] Verify the first CI-signed release end-to-end against the embedded
      pubkey (download the `.app.tar.gz` + `.sig` from the Release, verify
      with `minisign -V -P <pubkey from tauri.conf.json>` or an updater
      check on a test install).
- [ ] Then delete `~/.arxa/updater/arxa-updater.key` from the dev machine.

## R2 feed (D6)

**Current state: NOT yet enabled** — the bucket does not exist. Feed is
GitHub-raw only. CI's R2 publish step self-skips (warning) until the
secret exists.

One-time enablement (dashboard action with billing):

1. Enable R2 in the Cloudflare dashboard (requires a payment method on the
   account).
2. `npx wrangler r2 bucket create arxa-releases`
3. Repo secret `CLOUDFLARE_API_TOKEN` — an R2-edit-scoped token.
4. Optional repo variable `R2_FEED_BUCKET` (defaults to `arxa-releases`).

Publishing/mirroring: `desktop/scripts/publish-feed.mjs` (used by CI; also
runnable by hand — `--dry-run` prints the wrangler commands).

**Flip checklist** (once the first manifest is on R2):

1. Make the R2 public URL the **FIRST** endpoint in
   `tauri.conf.json > plugins.updater.endpoints`.
2. Keep the `raw.githubusercontent.com` URL **second** as fallback — the
   updater fails over only on non-2xx and the **first 200 + valid wins**,
   so a stale-but-200 primary masks the fallback; that is why the primary's
   cache discipline is load-bearing.
3. Verify headers: manifests serve `Cache-Control: public, max-age=300`,
   bundles serve `public, max-age=31536000, immutable`
   (`curl -sI <url> | grep -i cache-control`).

Why R2 at all: raw.githubusercontent.com works but is single-origin with
cache rules you don't control; R2 gives controlled cache headers + the
future home of staged-rollout gating (percentage cohorting via a Worker —
D21 follow-on, not built).

## Protected environment "release"

A GitHub Actions environment that holds the two `TAURI_SIGNING_*` secrets;
the release job declares `environment: release`, so those secrets are
injected only into environment-scoped runs, and the environment's
deployment tag policy (`studio-v*`, `studio-beta-v*`) restricts which refs
may deploy. `GH_RELEASES_TOKEN` and `ARXA_STUDIO_CHECKOUT_TOKEN` stay
repo-level (they protect different, broader things and are fine as repo
secrets).

- Inspect: `gh api repos/unfazed-dev/arxa/environments`
- Tag policy: environment settings → deployment branch and tag policies →
  allowed tags `studio-v*`, `studio-beta-v*`.
- Required reviewers can be added later if the tag-push human gate ever
  feels insufficient — D3 already makes the tag push the release button,
  so a second approval is redundancy, not the primary control.
