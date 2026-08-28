# arxa studio — mobile (iOS + Android)

Tauri v2 mobile shell for arxa studio. Scaffold only: it compiles and shows a branded
pairing/connecting screen. The full studio surface arrives once the phone ↔ Mac
transport lands (see decision log:
`arxa-studio/docs/plans/mobile-grill-decisions.md`).

## Layout

```
mobile/
├── src/                     # static frontend, no bundler (same as desktop/src)
│   ├── index.html           # pairing/connecting screen
│   ├── main.js              # state machine + stubbed studio_url navigation
│   ├── styles.css
│   └── arxa-brand-logo.svg  # copied from desktop/
├── src-tauri/
│   ├── Cargo.toml           # crate: arxa-mobile / lib arxa_mobile_lib
│   ├── tauri.conf.json      # identifier: solutions.arxadigital.arxa.mobile
│   ├── capabilities/default.json
│   ├── icons/               # copied from desktop/src-tauri/icons
│   └── src/
│       ├── main.rs
│       ├── lib.rs           # mobile_entry_point
│       └── connection.rs    # placeholder connection layer (the iroh seam)
└── package.json             # @tauri-apps/cli only
```

## Dev / init

```sh
cd mobile
npm install                # installs @tauri-apps/cli

# One-time platform project generation (requires Xcode / Android Studio toolchains):
npx tauri ios init         # needs Xcode + cocoapods + rustup ios targets
npx tauri android init     # needs Android SDK/NDK, JAVA_HOME=<Android Studio jbr>

# Run on device/simulator:
npx tauri ios dev
npx tauri android dev
```

Host-side sanity check without mobile toolchains: `cargo check` inside `src-tauri/`.

## Seams

Protocol contract: `docs/plans/mobile-pairing-transport.md` (repo root). Ticket
`arxa-pair:<base32(json)>` with `{ "node": <iroh endpoint ticket>, "token": <hex> }`
(RFC 4648 base32, uppercase, no padding); ALPN `arxa/studio/0`; `AUTH <token>\n`
as the first frame on **every** stream, desktop replies `OK\n`; authed streams
carry raw HTTP/1.1.

- **iroh P2P transport (M1) — WIRED.** `src-tauri/src/connection.rs`: parses the
  ticket, dials the desktop over iroh (`iroh` 1.x + `iroh-tickets`), proves the
  token on a handshake stream, then serves `studio_url` through a loopback TCP
  proxy on `127.0.0.1:<random port>` that opens one fresh authed iroh stream per
  TCP connection. Pairing (peer ticket + session token) persists as
  `pairing.json` in the Tauri app data dir — local-only storage — and startup
  silently reconnects before falling back to NotPaired. The command surface
  (`connection_status`, `begin_pairing(ticket)`) stays the fixed contract.
- **QR pairing (M2) — WIRED.** Desktop mints the QR; "Scan QR to pair" uses
  `tauri-plugin-barcode-scanner` (mobile targets only, capability
  `capabilities/mobile.json`) and hands the decoded `arxa-pair:...` string to
  `begin_pairing`. An "enter code manually" paste fallback covers dev/host runs
  where no camera exists.
- **Full studio surface (M4) — WIRED.** `main.js` polls `connection_status`
  every 2s; once `connected` it navigates the webview to the engine-served
  `studio_url` (same pattern as desktop).
- **Push (M7) — WIRED (token minting + registration).** The OS push plugin
  (`tauri-plugin-mobile-push` 0.1.4, mobile targets only, capability
  `capabilities/mobile.json`) mints the APNs device token (iOS) / FCM
  registration token (Android); `main.js` hands it to Rust via
  `set_push_token(platform, token)` with cairn-push's vocabulary
  (`apns`/`fcm`). After every successful connect, the connection layer sends
  `PUSH <session-token> <platform> <token>\n` on its own iroh stream; the
  desktop stores it in `pairing.json` and forwards it into its supervised
  cairn-pushd. Token rotation (`token-received` event) updates the stored
  token and rides the next reconnect's PUSH frame — mid-session re-send is
  deliberately not wired (rotation is rare; every app launch re-registers).
  Foreground presentation is silent: the studio UI is already live when the
  app is open. OPERATOR SEAM: real delivery needs (a) Android —
  `google-services.json` dropped into `gen/android/app/` (the gradle
  google-services plugin activates only when the file exists; without it the
  build stays green and token minting fails soft), and (b) iOS — a
  provisioning profile with Push Notifications on
  (`aps-environment=development` is in the entitlements; flip to
  `production` for TestFlight). cairn-server-side doorbell registration
  (`register_push_token` via cairn_tauri) belongs to cairn-syncing apps,
  not this shell (M8).
- **Online-only v1 (M8)** — no offline cache; the app is a thin shell over the
  engine-served UI.
- **OTA web assets** — will use `tauri-plugin-ota-self-update` later; deliberately
  not wired in this scaffold.

## Distribution (M5)

TestFlight for iOS, sideloaded APK for Android. No store automation in the scaffold.
