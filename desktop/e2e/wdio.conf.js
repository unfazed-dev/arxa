// WebdriverIO config — the WKWebView boot gate (D3 tiered gate, update
// strategy amendment 2026-09-05). Drives the REAL WKWebView through
// @wdio/tauri-service's embedded WebDriver provider (macOS has no
// standalone WKWebView driver — the server rides inside the app, compiled
// behind the `wdio` cargo feature; see src-tauri/src/lib.rs).
//
// Prerequisites (desktop/scripts/dev-stub-sidecars.sh + gate capability):
//   bash ../scripts/dev-stub-sidecars.sh
//   cp capabilities/wdio.json ../src-tauri/capabilities/wdio-e2e.json
//   (cd ../src-tauri && cargo build --features wdio)
//   npx wdio run wdio.conf.js
export const config = {
  runner: 'local',
  specs: ['./specs/**/*.js'],
  // auth.spec.js needs the fake engine from run-auth-gate.mjs (wdio.auth.conf.js);
  // specs/real-engine/ needs a live engine (wdio.real.conf.js). Against this
  // suite's dead ARXA_STUDIO_URL they fail by construction, so keep them out.
  exclude: ['./specs/auth.spec.js', './specs/real-engine/**/*.js'],
  maxInstances: 1,
  capabilities: [{}],
  services: [
    [
      'tauri',
      {
        // Debug binary from `cargo build --features wdio` (NOT the .app
        // bundle — the service launches the binary directly).
        appBinaryPath: '../src-tauri/target/debug/arxa-desktop',
        driverProvider: 'embedded',
      },
    ],
  ],
  framework: 'mocha',
  reporters: ['spec'],
  mochaOpts: {
    ui: 'bdd',
    timeout: 120_000,
  },
}
