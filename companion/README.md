# app_box companion

The iOS companion (plan 12). Remote control of the desktop, with the prototype as
a mode inside the app (architecture §15). Owns the prototype view; **the FAB
carries channel state** — live / reconnecting / dead — from the paired channel's
heartbeat, never from whether the WebView painted.

## What is built (this run)

The provable core, with no device and no signing:

- **The paired-channel heartbeat** (`lib/channel/prototype_channel_service.dart`)
  — HTTP-heartbeats the prototype URL and emits `ChannelState` (live /
  reconnecting / dead). This is the liveness signal the FAB reads, and it closes
  plan-09 done-when #5. Proven against a **real `HttpServer`**, not a mock.
- **The FAB** (`lib/widgets/channel_fab.dart`) — floating, draggable,
  edge-docking, with a home-indicator keepout and gesture capture scoped to the
  FAB only. Stop-server + back controls expand on tap; double-tap minimises.
- **The prototype surface** (`lib/ui/prototype_view.dart`) — fullscreen
  `WebViewWidget` with the FAB riding above it; safe-area insets are read
  explicitly from `MediaQuery` (a WebView is a platform view and does not inherit
  `SafeArea`).
- **The render/channel split** (`lib/prototype/`) — `LastRenderStore` holds what
  the WebView shows; `PrototypeSession` receives the P09 ready-line payload,
  serves the render and starts the heartbeat. The render is decoupled from the
  channel on purpose: a dead server leaves the last render on screen, and the
  FAB reads the channel, not the render.
- **iOS local-network ceremony** (`ios/Runner/Info.plist`) —
  `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_appbox._tcp`),
  `NSCameraUsageDescription`.
- **Config** (`assets/config/companion.config.json`) — heartbeat cadence, dead
  threshold, Bonjour service type, FAB insets. No magic numbers in code (R3).

## The property this app exists to guarantee

> Killing the desktop server flips the FAB to **dead** within one heartbeat,
> while the WebView still shows the last render.

Proven in `test/fab_dead_while_render_persists_test.dart`: a real `HttpServer`
stands in for the desktop; a `PrototypeSession` receives the ready-line payload;
the heartbeat reaches LIVE and the WebView gets a render; the server is killed;
the FAB reads DEAD while `LastRenderStore.lastUrl` is unchanged. The "stale render
on a dead channel" combination — exactly the lie the FAB exists to expose — is
asserted directly.

## Run

```
cd companion
flutter pub get
flutter analyze        # No issues found
flutter test           # 18 tests, all green
```

## Env-blocked (need a signed iOS build on real hardware)

The desktop-command + pairing stack is not faked; these land with a device:

- 12.1 scaffold from the plan-14 design (plan 14 not done — this run hand-built
  the minimal surface; the scaffold-from-design step stays open).
- 12.3 / 12.4 QR pairing + QR-relay defense (camera, TLS-fingerprint pin,
  single-use nonce, rotation).
- 12.5 honoured by design — no cloud relay introduced; the LAN-local property is
  a security stance, not yet wired to a real pairing surface.
- 12.6 remote pipeline control + the three gate halts.
- 12.12 push notification on a gate going red.

Done-when #1 (real-LAN pairing), #2 (relayed-QR fails the pin), #4 (fullscreen
interaction), #5 (agent halts at gates), #6 (device revocation) are env-blocked.
Done-when #3 (FAB dead while render persists) **passes**.

## Does not belong here

Pipeline orchestration stays server-side in `pipeline/`. The companion commands
the desktop and renders; it does not run the pipeline.
