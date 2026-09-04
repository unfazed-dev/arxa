# desktop/e2e — the WKWebView boot gate

The D3 tiered gate's desktop rung (update-strategy amendment 2026-09-05):
proof that the shell boots and renders in the **real WKWebView** — macOS has
no standalone WKWebView WebDriver, so this rides `@wdio/tauri-service`'s
embedded WebDriver provider, compiled into the app behind the `wdio` cargo
feature (release builds never set it; see `src-tauri/src/lib.rs` and
`src-tauri/Cargo.toml`).

CI runs it via `.github/workflows/desktop-gate.yml` on every `desktop/**` PR.
Locally:

```sh
bash ../scripts/dev-stub-sidecars.sh
cp capabilities/wdio.json ../src-tauri/capabilities/wdio-e2e.json   # gitignored there
(cd ../src-tauri && cargo build --features wdio)
npm install
npm run gate   # = ARXA_STUDIO_URL=http://arxa-gate.localhost:1 wdio run wdio.conf.js
```

The `ARXA_STUDIO_URL` override keeps the gate HERMETIC: pointed at a dead
port, the shell stays on its bundled waiting page instead of Rider-1
connecting to a real engine (on the self-hosted runner the operator's live
engine may own :7891). Gate builds also disable the single-instance rider
(`#[cfg(not(feature = "wdio"))]` in lib.rs) so the gate never surrenders to
a running production instance.

Scope, deliberately: with stub sidecars the engine never comes up — the
SHELL is the unit under test (title, waiting page, brand logo). The engine's
own boot is proven by arxa-studio's `npm run smoke` (engine-boot-smoke).
The two capability/feature switches cannot drift silently: a build without
the feature fails on the `wdio:*` capability file, and the feature without
the capability file simply has nothing to permit.
