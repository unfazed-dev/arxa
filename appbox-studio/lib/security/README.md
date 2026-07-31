# security/ — the pairing & channel security core

Mined from `companion/` in consolidation wave-2 slice A
(`docs/plans/consolidate-one-app-plus-daemon.md`, decision 12). The value here
is not UI — it is six security properties, each with tests behind it. Any
change that breaks one is a regression regardless of what it makes prettier
(the binding list is in the superseded
`docs/plans/merge-companion-into-one-flutter-project.md` → "What must not be
lost in the move").

Tests live in `test/security/`, mirroring this layout.

## Modules and what they guard

- `pairing/` — pure Dart, no Flutter, no platform calls.
  - `fingerprint.dart` — SHA-256 of the desktop's ephemeral TLS SPKI, plus a
    constant-time comparison. The human compares this fingerprint; it is the
    trust anchor of the whole pairing.
  - `cert_pin.dart` — validates a presented cert's SPKI against the pinned
    fingerprint. A relay/MITM presenting a different key is rejected.
  - `qr_payload.dart` — the `appbox-pair:` QR codec (v1, strict parse, never
    throws on attacker data).
  - `pairing_session.dart` — the nonce lifecycle: rotating single-use nonces,
    human confirm → paired device, revoke, idle sweep.
- `channel/` — the heartbeat channel to the desktop prototype server.
  - `channel_state.dart` — the LIVE / RECONNECTING / DEAD state machine and
    the ready-line parser. DEAD is a first-class, reachable state — the truth
    the FAB shows.
  - `prototype_channel_service.dart` — heartbeats the server (`dart:io`),
    drives the state machine, with transient grace before DEAD.
- `pipeline/` — remote pipeline control over the paired channel.
  - `pipeline_control.dart` — gate approvals are honored **only** for a
    currently-paired device id. Provenance, not transport, is the check: an
    agent has no paired device, so it can neither reach nor approve.
  - `gate_status_feed.dart` — deduped gate-red push (fires on transitions,
    not on every poll).
- `prototype/` — render bookkeeping for the prototype surface.
  - `last_render_store.dart` — keeps the last rendered payload; deliberately
    has **no** death-triggered clear (a stale render may persist — the FAB,
    not the render, carries liveness).
  - `prototype_session.dart` — ties channel state to the render store.
- `config/companion_config.dart` — bundled runtime config
  (`assets/config/companion.config.json`); R3: no project-varying literals in
  code. `loadMap` is the test seam.

## The six properties and the tests that prove them

| # | property | proving test(s) |
|---|---|---|
| 1 | **Fingerprint pin** — a relayed QR must fail | `test/security/pairing/pairing_test.dart` → `CertPin: validate: a different key (MITM/relay) is rejected with both fps`; `Fingerprint: matches: a one-byte difference fails` |
| 2 | **No-relay rule** — absence of any relay is the property | structural, asserted negatively by the same MITM-rejection test above (any relay breaks the pin) and by `QrPayload: tryParse: a foreign scheme is null` (only `appbox-pair:` payloads are even parsed) |
| 3 | **Nonce lifecycle** | `pairing_test.dart` → `consume: a replayed nonce is rejected (single-use)`, `consume: a stale nonce (post-rotation) is rejected`, `isNonceStale: true past the rotation window` |
| 4 | **An agent can never mint an approval** | `test/security/pipeline/pipeline_control_test.dart` → `an unpaired agent cannot reach OR approve`, `a forged deviceName with an unpaired id is still denied` |
| 5 | **Revoking a device drops the session immediately** | `pipeline_control_test.dart` → `a revoked device can no longer approve`; `pairing_test.dart` → `revoke: drops a paired device` |
| 6 | **The FAB reads the channel, never the WebView** | `test/security/fab_dead_while_render_persists_test.dart` (both tests: `FAB goes DEAD while the WebView keeps the last render`, `a stale render on a DEAD channel is the lie the FAB exposes`); `test/security/channel_fab_widget_test.dart` → `DEAD renders the warning and no spinner (the FAB truth)` |

## Interim home: `widgets/`

`widgets/channel_fab.dart`, `widgets/prototype_view.dart`, and
`widgets/companion_home_view.dart` are the companion's hand-built UI. They
live here — **not** under `lib/ui/**` — because the pipeline owns `lib/ui/**`
and the upcoming design may replace these visuals wholesale. What must survive
any redesign is the *behavior* the widget tests pin (property 6 above, plus
the FAB drag/edge-dock constraints in `channel_fab_widget_test.dart`).

Caveat: `prototype_view.dart` imports `webview_flutter`, which has no web
implementation — fine on macOS/iOS/Android, but nothing under `security/`
may be imported by a web build's entry path until the design replaces it.
