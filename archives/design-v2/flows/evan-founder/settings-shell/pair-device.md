# Pair device — QR pairing, LAN-local with pinned fingerprint

Actor: Evan (founder, setup mode) · Shell: settings-shell · Surfaces:
`settings.pair` (null surface — QR pair · fingerprint · device name),
`settings.devices` → `stage_shell_settings_devices_view` (paired · revoke) —
NEW — not yet scaffolded · Decision refs: architecture.md §15 (companion — QR
pairing LAN-local, TLS fingerprint pinned from payload; the FAB carries channel
state), research: remote-control-and-chat.md

## Trigger

Evan opens settings → pair device — to drive the desktop from the iOS companion
(Serve prototype, approve gates, get a push when a gate goes red).

## Entry / exit

- Entry criteria: desktop running on the LAN; companion installed on iOS; the
  ios target's platform-conditional files present (`NSLocalNetworkUsageDescription`
  + `NSBonjourServices`), or mDNS discovery fails with
  `NSNetServicesErrorCode: -72008` (research: remote-control-and-chat.md). No 💳
  — pairing is setup, not a licensed build action.
- Exit states: **paired** — companion connected; device appears in
  `settings.devices`; companion can Serve prototype and drive the pipeline ·
  **revoked** — Evan revokes from `settings.devices`; the channel drops
  immediately · **refused** — fingerprint mismatch on the TLS handshake; pairing
  aborted, nothing linked.

## Happy path

1. `settings.pair` renders the QR. The payload encodes `host`, `port`, a
   **short-lived nonce**, and the **fingerprint of the desktop's ephemeral TLS
   key** (research: remote-control-and-chat.md). QR rotates every ~20–30 s;
   each nonce is single-use.
2. Evan scans with the companion. iOS raises the local-network permission prompt
   (first scan only). Denied → the companion cannot see the desktop over mDNS;
   route to iOS Settings, not a red gate.
3. Companion opens a TLS connection to `host:port` and **pins the fingerprint
   from the QR payload** — handshake matches the pin (proceed) or does not
   (→ refuse, Decision points).
4. Desktop shows a confirm dialog naming the device (model + companion-supplied
   name) before the link completes — the human sees *what* is being linked.
5. Device appears in `settings.devices` → `stage_shell_settings_devices_view` as
   **paired**. The channel's heartbeat drives the FAB state (live) on the
   companion — not whether the WebView last painted (architecture.md §15).
6. Companion can now **Serve prototype** (desktop starts the htmx producer's
   `server.js`, returns the URL over the paired channel) and drive the pipeline.

## Decision points

- **Pair vs revoke:** pair completes through the confirm dialog (step 4); revoke
  is a per-device action in `settings.devices` — drops the channel, removes the
  entry, single human action, no confirm-replay loop.
- **Fingerprint mismatch:** the TLS handshake's certificate fingerprint ≠ the
  pin from the QR payload → **refuse pairing**. This defeats the QR-relay attack
  — a relayed QR points at the attacker's host, whose key the pin does not match
  (research: remote-control-and-chat.md).
- **Numeric pairing-code fallback:** treated as high risk and not offered. The
  LAN-local pin is the only path; a cloud relay reintroduces the relay attack
  the LAN constraint removes.

## Edge cases

- **QR-relay attack (the design case):** attacker lifts the QR and embeds it in a
  fake page; the victim's companion connects to the attacker's host; the pin
  fails → refuse. The pin, not the QR's visual authenticity, is the control.
- **LAN disconnect mid-session:** the heartbeat stops; the FAB transitions live →
  **reconnecting** → **dead** (after bounded retry). The WebView may keep showing
  the last render — that stale page is exactly why the FAB carries channel state
  itself, never infers liveness from paint (architecture.md §15).
- **Desktop restart while paired:** the ephemeral TLS key is regenerated; the
  stored pin no longer matches. Re-pair required — the device entry shows
  **stale** with a re-pair action, not a silent reconnect.
- **Multiple devices:** each companion pairs independently (separate nonce, TLS
  key, confirm). `settings.devices` lists each; each is revocable on its own.
- **Idle companion:** long idle → the channel auto-expires (mirrors WhatsApp's
  inactivity logout). The entry shows the expiry; re-pair to resume.
- **iOS local-network permission denied:** the step-2 prompt — a platform
  ceremony, not a red gate. The companion names the missing permission and
  routes to iOS Settings.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `settings.pair` (null surface) — rotating QR, fingerprint, device name |
| 2 | iOS local-network permission prompt (system, not an app surface) |
| 4 | Desktop confirm dialog — device name + model before link completes |
| 5 | `stage_shell_settings_devices_view` — paired device, revoke action |
| 6 | Companion FAB (live) — not a desktop surface; channel state per §15 |

## Notes

- **No state inferred from paint.** The FAB carries channel state (live /
  reconnecting / dead) from the heartbeat; a stale WebView page that looks live
  is the failure mode this feature exists to prevent (architecture.md §15).
- Pairing is **LAN-local with no cloud relay** — that *is* the security property.
  Adding a cloud relay reintroduces the QR-relay attack the LAN constraint
  removes; redo the analysis before ever doing so (research:
  remote-control-and-chat.md).
- The ios target's `NSLocalNetworkUsageDescription` + `NSBonjourServices`
  ceremony is a platform-conditional file, turned on by `--targets ios` — the
  same derivation model as the Keychain entitlements (architecture.md §11).
- Sibling flows: [`configure-credentials.md`](configure-credentials.md) — the
  OS-vault credential tier; [`../chat-shell/drive-pipeline.md`](../chat-shell/drive-pipeline.md)
  — the companion driving the pipeline over the paired channel (◆ NEW — not yet
  scaffolded).
