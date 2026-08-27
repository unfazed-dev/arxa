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
- **`https://updates.arxa.invalid` is a deliberate placeholder.** No hosting
  exists yet; picking real hosting (bucket/CDN/worker) is a release-CI
  decision. Until then the launch check logs "update check skipped" and the
  app runs normally.

### Update signing (minisign-style, separate from Apple codesigning above)

`bundle.createUpdaterArtifacts: true` makes `tauri build` emit an update
archive + `.sig` per bundle. Updates are only accepted if signed by the
keypair whose **public key** is committed in
`tauri.conf.json > plugins.updater.pubkey`.

- Private key (never commit it): `~/.arxa/updater/arxa-updater.key`
  (mode 600, generated with `tauri signer generate`, empty password).
- To sign a build: `TAURI_SIGNING_PRIVATE_KEY_PATH=~/.arxa/updater/arxa-updater.key tauri build`
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

## Remaining work (tracked in arxa-studio docs/plans/desktop-shell-scaffold.md)

- real icon assets (`icons/icon.png` is a solid-color placeholder; `.icns`/`.ico` set still needed)
- sidecar injection step in the release pipeline (build itself is solved: `arxa-studio/scripts/pack-sidecar.mjs`; CI just runs it per target)
- shell should optionally auto-spawn the `arxa-studio` sidecar on launch
- update-endpoint hosting (auto-update is wired; base URL is a placeholder — release-CI decision)
- notarization credentials (`notarytool store-credentials arxa-notary`, see above) — signing itself is done
