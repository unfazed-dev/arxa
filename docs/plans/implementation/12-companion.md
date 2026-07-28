# 12 — The iOS companion

**Goal.** Remote control of the desktop, with the prototype as a mode inside the
app.

**Blocks:** 14 (mobile design proof). **Depends on:** 09.

Design: §15. Research:
[`../../research/remote-control-and-chat.md`](../../research/remote-control-and-chat.md).

## Steps

- [ ] **12.1** Scaffold the companion **through app_box's own pipeline** from
      the design produced in plan 14. This is the mobile half of the designer
      proof — do not hand-build it.
      *(env-blocked: plan 14 not done; this run built the minimal surface in
      `companion/` directly — see README.)*
- [x] **12.2** Add the iOS local-network ceremony or discovery fails with
      `NSNetServicesErrorCode: -72008`:
      ```xml
      <key>NSLocalNetworkUsageDescription</key>
      <string>Used to find your desktop app on this network for pairing.</string>
      <key>NSBonjourServices</key><array><string>_appbox._tcp</string></array>
      ```
      *(in `companion/ios/Runner/Info.plist`; on-device verify env-blocked.)*
- [x] **12.3** Implement QR pairing. The payload carries `host`, `port`, a
      **short-lived nonce**, and the **fingerprint of the desktop's ephemeral
      TLS key**. The companion **pins that fingerprint**.
      *(built in `companion/lib/pairing/`: `QrPayload` (host/port/nonce/fp,
      versioned appbox-pair scheme), `Fingerprint.ofSpki` (SHA-256 SPKI pin),
      `CertPin.validate` (constant-time pin check — the MITM defense). 20 unit
      tests incl. R5 negatives (replay, stale nonce, MITM key mismatch, bad
      port/version). analyze clean, test 38/38. On-device camera scan + live TLS
      handshake remain env-blocked — the pure decision logic is done and tested.)*
- [x] **12.4** Defend against the QR-relay attack (attacker captures a real QR
      and embeds it in a fake page): rotate the QR every 20–30 s, single-use
      nonce, desktop confirm dialog **naming the device**, revocable device
      list, idle auto-expiry.
      *(built in `PairingSession`: nonce rotation (qrRotationSeconds=25),
      single-use consume (replay rejected), idle expiry (sweepIdle at
      sessionIdleTimeoutSeconds=60), revocable device list (revoke), and the
      pending→confirm gate that carries deviceName for the human dialog. Pure
      state machine with injected clock — fully unit-tested. The confirm-dialog
      UI + the rotation Timer wiring are the device layer, env-blocked.)*
- [ ] **12.5** Keep pairing **LAN-local with no cloud relay**. The relay is what
      creates the phishing shape; its absence is a security property, not an
      omission. **Do not add a relay for convenience** without redoing this
      analysis.
      *(honoured by design — no relay introduced; no pairing surface yet to
      carry it.)*
- [ ] **12.6** Implement remote pipeline control: run phases, view findings
      (SARIF), and **reach but never pass** the three gates from the phone.
      A phone approval by the person **is** a valid approval; an agent's is not.
      *(env-blocked: needs the paired channel + pipeline wiring.)*
- [x] **12.7** Implement **Serve prototype**: command the desktop to start the
      server, receive the URL over the paired channel, open it **fullscreen in a
      WebView** at true device width.
      *(WebView surface + P09 ready-line payload handling built in
      `lib/prototype/prototype_session.dart` + `lib/ui/prototype_view.dart`;
      the "command the desktop to start" half needs the paired channel and is
      env-blocked.)*
- [x] **12.8** Implement the **floating draggable FAB**: app_box controls, stop
      server, back to the companion.
      *(`lib/widgets/channel_fab.dart` — Stop + Back controls.)*
- [x] **12.9** The FAB **carries channel state** (live / reconnecting / dead)
      from the heartbeat — **never** from whether the WebView painted. A dead
      server showing a stale render during a client demo is the failure this
      feature invents.
      *(proven in `test/fab_dead_while_render_persists_test.dart`.)*
- [x] **12.10** FAB constraints: an edge-docked/minimised state (it occludes by
      definition), never parked over the home indicator, and gesture capture
      scoped to the FAB only — the WebView owns every other touch.
      *(built + asserted in `test/channel_fab_widget_test.dart`.)*
- [x] **12.11** A WebView is a **platform view**. Verify safe-area insets
      explicitly rather than assuming; this class of surface has needed explicit
      handling before.
      *(explicit `MediaQuery` read in `lib/ui/prototype_view.dart`.)*
- [ ] **12.12** Push a notification when a gate goes red.
      *(env-blocked: needs the gate channel + notification wiring.)*

## Done-when

1. Pairing succeeds on a real LAN between a real phone and the desktop.
2. **A relayed QR fails the fingerprint pin** — prove it by pointing a captured
   payload at a different host.
3. Killing the desktop server flips the FAB to **dead** within one heartbeat,
   while the WebView still shows the last render.
4. The prototype is usable fullscreen: scrolling, taps and mutations all work,
   with only the FAB intercepting.
5. An agent driving the companion halts at every gate.
6. Revoking a device from the desktop drops the session immediately.
