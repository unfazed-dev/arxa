// WebdriverIO config — the BrowserAuth desktop gate. Same embedded-provider
// shape as wdio.conf.js (the WKWebView boot gate), but a single spec:
// run-auth-gate.mjs supplies a live fake engine and points the shell at it
// via ARXA_STUDIO_URL / ARXA_DSH_HOME.
export const config = {
  runner: 'local',
  specs: ['./specs/auth.spec.js'],
  maxInstances: 1,
  capabilities: [{}],
  services: [
    [
      'tauri',
      {
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
