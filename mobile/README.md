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

## Seams (deliberately not built)

- **iroh P2P transport (M1)** — `src-tauri/src/connection.rs` is the seam. The
  command surface (`connection_status`, `begin_pairing`) is the fixed contract;
  stub bodies get replaced by an embedded iroh endpoint.
- **QR pairing (M2)** — desktop mints the QR; the mobile "Scan QR to pair" button is
  a stub that returns a not-implemented error.
- **Full studio surface (M4)** — once connected, `main.js` navigates the webview to
  the engine-served `studio_url` (same pattern as desktop). Currently always unset.
- **Push (M7)** — cairn-pushd token registration via `cairn_tauri`, wired into the
  connection layer later.
- **Online-only v1 (M8)** — no offline cache; the app is a thin shell over the
  engine-served UI.
- **OTA web assets** — will use `tauri-plugin-ota-self-update` later; deliberately
  not wired in this scaffold.

## Distribution (M5)

TestFlight for iOS, sideloaded APK for Android. No store automation in the scaffold.
