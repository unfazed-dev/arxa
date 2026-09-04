# arxa desktop shell

Tauri v2 shell implementing decision D30 (see
`arxa-studio/docs/plans/arxa-studio-grill-decisions.md`): a native window over
the **locally served arxa studio web UI**, with the arxa engine and CLI bundled
as sidecars. The shell contains no product logic — dsh + PI serve the real UI.

- App identifier: `solutions.arxadigital.arxa` (owner: Arxa Digital Solutions)
- Default server URL: `http://localhost:7891` — override with `ARXA_STUDIO_URL`
- Until the server answers, the shell shows a "waiting for arxa studio server"
  screen (`src/index.html`) that polls once per second, then navigates to the
  served UI.

## Layout

```
desktop/
  src/               waiting screen (static, no build step)
  src-tauri/         Rust shell
    tauri.conf.json  identity, window, CSP, sidecar (externalBin) config
    capabilities/    shell:allow-execute scoped to the two sidecars
    binaries/        sidecar drop zone — EMPTY in git, filled by release CI
```

## Sidecars (not vendored)

`tauri.conf.json > bundle.externalBin` declares two sidecars:

- `binaries/arxa-studio` — the studio engine/server (packaged
  `bin/arxa-studio.mjs`, compiled or wrapped to a single executable)
- `binaries/arxa` — the compiled Dart CLI (`dart compile exe`)

Binaries are **not** committed. The release pipeline must, before
`tauri build`, place per-platform binaries next to the config using
target-triple suffixes, e.g.:

```
src-tauri/binaries/arxa-aarch64-apple-darwin
src-tauri/binaries/arxa-x86_64-apple-darwin
src-tauri/binaries/arxa-studio-aarch64-apple-darwin
...
```

(Tauri resolves `binaries/arxa` + current target triple at bundle time; a
missing binary fails the bundle, not `cargo check`.)

### `arxa-studio` sidecar: real single executable (self-extracting)

The `arxa-studio-aarch64-apple-darwin` sidecar is a **real Mach-O arm64 single
executable** (~141 MB), built by `arxa-studio/scripts/pack-sidecar.mjs`:

```sh
cd ../arxa-studio && node scripts/pack-sidecar.mjs   # writes desktop/src-tauri/binaries/arxa-studio-<triple>
```

How it works: naive `bun build --compile` of `bin/arxa-studio.mjs` cannot work
— the launcher spawns a second Node process on `@deepseek-ai/dsh/lib/bin.js`
(with the loopback `--import` patch), and dsh loads its plugin tree by name at
runtime through the cordis plugin loader, invisible to any bundler (the
earlier attempt bundled exactly 1 module and broke; node SEA and deno compile
hit the same wall, plus `process.execPath` inside a compiled binary is the
binary itself, so the child spawn would recurse). The pack script therefore
builds a small bun-compiled **self-extracting** entry that embeds a tar.gz
payload — the arxa-studio runtime tree (bin + node_modules + plugins +
profile + pi), the sibling `arxa/harness/pi/arxa-gate.ts`, and a pinned real
Node binary (v24.19.0). On first run it extracts once to
`$ARXA_HOME/engine/<payload-sha12>/` (atomic tmp+rename), then execs the
extracted node on the extracted launcher; later runs skip extraction. The
launcher detects `bin/packed.json` (written only by the pack script) and
copies plugins into the profile instead of requiring pnpm — end-user machines
need **no node, pnpm, nvm, or checkout**.

Verified empirically: binary run from `/tmp` with a fresh `ARXA_HOME` boots
the dsh server and serves HTTP 200 (`--port 7912 --no-open`, app HTML ~20 KB),
and exits cleanly leaving no listener. Old `engine/<sha>` dirs are not
auto-pruned (an older running app may still use one) — safe to delete by hand.

Gotcha: bun 1.3.4's `--outfile` silently writes a 0-byte file when the target
is on a different filesystem than its temp dir; the pack script compiles to
the workdir and copies to the destination.

Release CI needs only: checkout both repos, `npm install` in arxa-studio, run
the pack script per target, drop the binary in `binaries/` (still gitignored).

## Develop / verify

`tauri-build` verifies sidecar paths at **compile** time, so create local stub
binaries first (gitignored; real ones come from the release pipeline):

```sh
desktop/scripts/dev-stub-sidecars.sh
cd desktop/src-tauri
cargo check          # compile-verifies the shell (no bundling needed)
cargo tauri dev      # run the shell (requires tauri-cli; expects studio server or shows wait screen)
```

## Code signing & notarization (macOS)

Identity (in this machine's keychain):
`Developer ID Application: EVAN F PIERRE LOUIS (43GNRCGQXQ)`.

Sign a built `.app` (or `.dmg`) after the fact:

```sh
desktop/scripts/sign-and-notarize.sh "/path/to/Arxa Studio.app"   # sign + notarize + staple
desktop/scripts/sign-and-notarize.sh --sign-only "/path/to/Arxa Studio.app"
```

What it does: signs every Mach-O sidecar in `Contents/MacOS` with the hardened
runtime and `desktop/entitlements.plist` (`allow-jit` +
`allow-unsigned-executable-memory` — the production subset of Node's own
`tools/osx-entitlements.plist`; needed by node/bun sidecars, harmless for the
Dart AOT `arxa`), gives script sidecars a plain signature (codesign treats
anything in `Contents/MacOS` as nested code), signs the bundle, verifies with
`codesign --verify --deep --strict`, then submits via `notarytool --wait`,
staples, and checks `spctl -a -vv`. Idempotent (`--force` re-signs).

Env overrides: `SIGN_IDENTITY`, `ENTITLEMENTS`, `NOTARY_PROFILE`
(default `arxa-notary`), or `APPLE_ID`/`APPLE_PASSWORD`/`APPLE_TEAM_ID`.

**Notarization credentials are NOT yet configured** — one-time setup:

```sh
xcrun notarytool store-credentials arxa-notary \
  --apple-id <your-apple-id-email> --team-id 43GNRCGQXQ \
  --password <app-specific-password>   # create at https://support.apple.com/en-ca/HT204397
```

To make `tauri build` sign directly (per v2.tauri.app distribute/sign/macos):
export `APPLE_SIGNING_IDENTITY="Developer ID Application: EVAN F PIERRE LOUIS (43GNRCGQXQ)"`
plus the `APPLE_ID`/`APPLE_PASSWORD`/`APPLE_TEAM_ID` trio before building — no
config change needed for the identity. For Tauri to apply the sidecar
entitlements at bundle time, `tauri.conf.json` sets (applied):

```json
"bundle": { "macOS": { "entitlements": "../entitlements.plist" } }
```

## Auto-update (tauri-plugin-updater, D21)

The shell checks for updates on launch: non-blocking, silent on failure — an
unreachable endpoint never stops the app from starting. A found update is
downloaded, signature-verified, and staged; it applies on the next launch.

- Channels (D21): `stable` (default) and `beta`. Override at runtime with
  `ARXA_UPDATE_CHANNEL=beta` — no rebuild needed.
- Endpoint layout (static JSON, channel-aware):
  `{BASE}/desktop/{channel}/{target}/{arch}/latest.json`
  with bundle archives under `{BASE}/desktop/{channel}/artifacts/{version}/`.
- Beta endpoints are **derived, not hardcoded**: `check_for_updates` in
  `src-tauri/src/lib.rs` swaps the `/stable/` segment in the endpoints
  CONFIGURED in `tauri.conf.json`, preserving their order — D6 endpoint
  failover (R2 primary + raw GitHub fallback once R2 is live; failover only
  on non-2xx, first 200+valid wins).

### Update signing (minisign-style, separate from Apple codesigning above)

`bundle.createUpdaterArtifacts: true` makes `tauri build` emit an update
archive + `.sig` per bundle. Updates are only accepted if signed by the
keypair whose **public key** is committed in
`tauri.conf.json > plugins.updater.pubkey`.

- Private key (never commit it): `~/.arxa/updater/arxa-updater.key`
  (mode 600, generated with `tauri signer generate`, empty password).
- To sign a build: `TAURI_SIGNING_PRIVATE_KEY=~/.arxa/updater/arxa-updater.key tauri build`
  (the var is `TAURI_SIGNING_PRIVATE_KEY`, NOT `..._PATH` — it takes either the
  key itself or a path to it. Verified against @tauri-apps/cli 2.11.4 on
  2026-09-03: the `_PATH` spelling is ignored and the build fails at the very
  end with "A public key has been found, but no private key", AFTER both
  bundles are already written, so it looks like a success until the last line.)
- Losing the private key means shipped apps can never be updated again —
  release CI must vault it.

### Publishing a release manifest

```sh
node desktop/scripts/make-update-manifest.mjs \
  --bundle "target/release/bundle/macos/Arxa Studio.app.tar.gz" \
  --channel stable                    # writes + self-validates latest.json
node desktop/scripts/make-update-manifest.mjs --check latest.json
```

Upload `latest.json` to `{BASE}/desktop/{channel}/{target}/{arch}/latest.json`
and the archive to the `url` the manifest points at.

## Local release builds

Use `scripts/build-release.sh` instead of calling `npx tauri build` directly —
it exports `TAURI_SIGNING_PRIVATE_KEY` from `~/.arxa/updater/arxa-updater.key`
(passwordless; override path via `TAURI_SIGNING_PRIVATE_KEY_FILE`) so the
updater `.app.tar.gz` gets its `.sig`. Without it, `createUpdaterArtifacts`
warns "A public key has been found, but no private key" and skips signing.

## Release CI

`.github/workflows/desktop-release.yml` runs on `studio-v*` (stable) and
`studio-beta-v*` (beta) tag pushes — the D21 channel ladder (self-hosted
macOS ARM64 runner, aarch64-apple-darwin only for now — Windows/x64 would
slot in as a build-matrix entry). It builds both sidecars, runs `tauri build`
with `createUpdaterArtifacts`, and publishes to the **public**
[`unfazed-dev/arxa-releases`](https://github.com/unfazed-dev/arxa-releases) repo:

- bundle assets (`.app.tar.gz` + `.sig`, `.dmg`) as GitHub Release assets **on
  the triggering tag** (`studio-v<version>` / `studio-beta-v<version>`)
- `desktop/{channel}/{target}/{arch}/latest.json` committed to `main`, served via
  `https://raw.githubusercontent.com/unfazed-dev/arxa-releases/main` — the
  updater endpoint configured in `src-tauri/tauri.conf.json`. The manifest's
  bundle `url` points at the Release asset (passed with `--url`);
  `ARXA_UPDATE_BASE_URL` overrides the manifest base for other hosting.

Signing/notarization happen inside `tauri build`: Tauri codesigns when
`APPLE_SIGNING_IDENTITY` is set and notarizes (notarytool) when the
`APPLE_ID`/`APPLE_PASSWORD`/`APPLE_TEAM_ID` trio is set. Absent notary secrets
⇒ signed-but-unnotarized build (warning, not failure); absent cert ⇒ ad-hoc
signature. `scripts/sign-and-notarize.sh` remains the local/manual path.

The job declares `environment: release` (D10 key custody): the two
`TAURI_SIGNING_*` secrets live in that **protected GitHub environment**
(tag-policy-restricted to `studio-v*` / `studio-beta-v*`), not as bare repo
secrets readable by every run. The local `~/.arxa/updater/arxa-updater.key`
is the offline backup, not a release build input.

**Optional R2 publish (D6):** when repo secret `CLOUDFLARE_API_TOKEN` exists
(R2-edit token — the bucket is NOT created yet), the workflow mirrors
`latest.json` to the R2 feed bucket via `desktop/scripts/publish-feed.mjs`
(`Cache-Control: public, max-age=300`; bucket name from variable
`R2_FEED_BUCKET`, default `arxa-releases`). Once the bucket is live, the R2
URL becomes the FIRST updater endpoint with raw.githubusercontent.com kept as
fallback. Absent secret ⇒ the step warns and skips.

Runbook (channel ladder, rollback, kill switch, key rotation, R2 flip
checklist): **`docs/ci/release-ops.md`**.

### Required secrets (arxa repo)

`TAURI_SIGNING_*` live in the protected `release` environment (D10); the rest
are repo-level.

| Secret | Contents / how to create |
|---|---|
| `TAURI_SIGNING_PRIVATE_KEY` | **Required.** Contents of `~/.arxa/updater/arxa-updater.key` (paste the file's text). Never commit the key file. |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | Password for that key (empty/omit if none was set). |
| `GH_RELEASES_TOKEN` | **Required.** PAT (classic `repo` scope, or fine-grained with Contents read/write on `arxa-releases`) used to create Releases and push manifests cross-repo. |
| `ARXA_STUDIO_CHECKOUT_TOKEN` | PAT with read access to the private `unfazed-dev/arxa-studio` repo (engine sidecar source). |
| `APPLE_CERTIFICATE_P12` | Base64 of the Developer ID Application cert+key: `base64 -i cert.p12 \| pbcopy` (export from Keychain Access with a password). Optional — absent ⇒ ad-hoc signing. |
| `APPLE_CERTIFICATE_PASSWORD` | Password chosen when exporting the `.p12`. |
| `APPLE_SIGNING_IDENTITY` | e.g. `Developer ID Application: <name> (<team id>)` — must match the imported cert. |
| `APPLE_ID` | Apple ID email for notarization. Optional — absent ⇒ notarization skipped. |
| `APPLE_APP_PASSWORD` | App-specific password for that Apple ID (appleid.apple.com → App-Specific Passwords). |
| `APPLE_TEAM_ID` | Developer team id (e.g. `43GNRCGQXQ`). |

## Remaining work (tracked in arxa-studio docs/plans/desktop-shell-scaffold.md)

- real icon assets (`icons/icon.png` is a solid-color placeholder; `.icns`/`.ico` set still needed)
- shell should optionally auto-spawn the `arxa-studio` sidecar on launch
- notarization credentials (see "Release CI" secrets) — signing itself is done


## Push sidecar (M7 — cairn-pushd supervision)

The shell supervises the push daemon beside the engine (decision M7, cairn
plan track B3): probe a healthy daemon at boot, spawn one if none is running
(probe-before-spawn — an externally owned pushd always wins), kill only the
child we spawned on exit. No binary found means no push this session — the
studio keeps working; nothing about the daemon is load-bearing for the UI.

### The credentials keystore (track B4: operator-owned, never the repo)

`<app-local-data-dir>/pushd.env` — KEY=VALUE lines. The shell owns exactly
three keys (`CAIRN_PUSHD_BIND`, `CAIRN_PUSHD_DB`, `CAIRN_PUSHD_API_KEYS`,
created on first run, file mode 0600) and preserves every other line
verbatim. Rail credentials are the operator's to place:

    cairn push init --fcm --fcm-credentials-json <service-account.json> \
        --env-file "<app-local-data-dir>/pushd.env"

(or `--apns --apns-key-p8 ... --apns-key-id ... --apns-team-id ...
--apns-bundle-id ...`; `cairn push check` validates the same file). The
file is local-only: credentials never enter the repo, the engine, or any
Arxa Digital Solutions database (M6 ownership rule). Free users get the
identical path — the daemon runs on their Mac beside the engine.

### Token registration

Phones register their OS push token over the iroh tunnel at QR-pair time
(`PUSH <session-token> <platform> <token>\n` on its own stream, ACKed with
`OK\n`). Durable record: `pairing.json` (the daemon's SQLite registry is
disposable; the supervisor re-registers every stored token whenever the
daemon (re)starts). The mobile frontend hands the token to the shell via the
`set_push_token` invoke — the OS push plugin (FCM/APNs) is the remaining
mobile-side seam, documented in `mobile/README.md`.
