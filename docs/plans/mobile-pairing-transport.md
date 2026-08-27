# Mobile pairing + iroh transport (seams M1, M2, M4)

Wire the three stubbed seams in the Tauri v2 mobile scaffold (commit `ca2eff33`)
so a phone can pair with the desktop and use the engine-served studio UI.

## Fixed contracts (do not change)

- **Mobile invoke surface** (`mobile/src-tauri/src/connection.rs`):
  `connection_status() -> { state: "not_paired"|"connecting"|"connected", studio_url: string|null }`
  and `begin_pairing(ticket) -> Result<(), String>`. Invoke names + JSON shapes fixed.
- **Frontend polling**: mobile UI polls `connection_status` every 2s; on
  `connected` it navigates the webview to `studio_url` (decision M4).

## Shared protocol contract (pinned here so both sides build in parallel)

- **Ticket**: QR encodes a single string `arxa-pair:<base32(json)>` where json =
  `{ "node": <iroh NodeAddr ticket>, "token": <32-byte hex auth token> }`.
  Token is single-use, minted per QR display, expires after 10 min.
- **Transport**: iroh bidirectional streams, ALPN `arxa/studio/0`.
  First frame from phone: `AUTH <token>\n`; desktop replies `OK\n` or closes.
- **M4 delivery**: after auth, streams carry raw HTTP/1.1. Desktop bridges each
  authed stream to the local engine HTTP server. Phone runs a loopback TCP
  proxy (random port) that forwards to iroh streams; `studio_url` =
  `http://127.0.0.1:<proxy-port>/`.
- **Persistence**: after first successful pairing, both sides store the peer
  NodeId + a long-lived session token locally (Tauri app data dir on phone,
  engine data dir on desktop). Reconnect skips QR. Local-only storage — no
  Arxa Digital Solutions database involvement (ownership boundary rule).

## Fan-out (2 agents, parallel)

### Agent: mobile-transport
`mobile/` only. Add `iroh` to `mobile/src-tauri/Cargo.toml`; replace
`connection.rs` stub bodies (state machine NotPaired→Connecting→Connected,
ticket redeem, loopback proxy, reconnect from stored peer). Wire QR scanning
(M2) via `tauri-plugin-barcode-scanner` (mobile-only cfg), fall back to manual
ticket paste in dev. Frontend: scan → `begin_pairing(ticket)` → poll → navigate
webview to `studio_url`. Must pass `cargo check` gated via
`#[cfg_attr(mobile, tauri::mobile_entry_point)]` layout as scaffolded.

### Agent: desktop-pairing
`desktop/src-tauri/` (+ minimal `desktop/src` UI). Add iroh endpoint on the
desktop shell; "Pair mobile device" surface that mints a ticket, renders QR
(local QR crate — no network service), accepts authed streams, bridges to the
engine HTTP server. Token bookkeeping (single-use, expiry, revoke on unpair).
Must not break existing desktop build (`cargo check`).

## Later (out of scope here)

- M7/M8: cairn-pushd push tokens, online-only session policy.
- OTA self-update plugin; mobile CI jobs; TestFlight/APK distribution.

## Consult-mode note

Advisor consult attempted before fan-out; skipped — `status:"error"`, no API
key in `ANTHROPIC_API_KEY` / `~/.config/consult-mode/api-key.json`. Proceeding
on primary sources (scaffold ponytail comments + README seams).
