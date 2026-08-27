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

### Local dev-grade `arxa-studio` sidecar (current state)

The `arxa-studio-aarch64-apple-darwin` sidecar on this machine is a **dev-grade
wrapper script**, not a true single binary: a `#!/bin/sh` exec of the local
Node (nvm v24.19.0, falling back to `command -v node`) running the absolute
path to this machine's `arxa-studio/bin/arxa-studio.mjs`. It works when
spawned by the installed `.app`, but it depends on the local checkout and
node_modules staying in place.

Why not a single binary yet: `bin/arxa-studio.mjs` is a launcher that spawns a
second Node process on `@deepseek-ai/dsh/lib/bin.js` (with the loopback patch
`--import`), and dsh loads its plugin tree dynamically from node_modules via
the cordis plugin loader — `bun build --compile` bundles only the launcher
(1 module) and produces a broken artifact. **Release CI must replace this
wrapper** with a real packaging step that bundles dsh + plugins (or ships a
pinned node + node_modules payload).

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
entitlements at bundle time, `tauri.conf.json` will additionally need
(not yet applied — conf file owned by another workstream):

```json
"bundle": { "macOS": { "entitlements": "../entitlements.plist" } }
```

## Remaining work (tracked in arxa-studio docs/plans/desktop-shell-scaffold.md)

- real icon assets (`icons/icon.png` is a solid-color placeholder; `.icns`/`.ico` set still needed)
- sidecar injection step in the release pipeline
- shell should optionally auto-spawn the `arxa-studio` sidecar on launch
- auto-update
- notarization credentials (`notarytool store-credentials arxa-notary`, see above) — signing itself is done
