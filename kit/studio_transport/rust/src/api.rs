//! flutter_rust_bridge surface — the only module the codegen scans
//! (`rust_input: crate::api`).
//!
//! Design: sync fns backed by a crate-owned static tokio runtime. FRB runs
//! sync fns on worker threads, so nothing here blocks the platform/UI thread;
//! long-lived work (dial loop, proxy) is spawned onto the owned runtime —
//! the same shape the Tauri original used via `tauri::async_runtime`.

use std::sync::{Arc, OnceLock};

use flutter_rust_bridge::frb;

use crate::frb_generated::StreamSink;
use crate::transport::{self, Pairing, SharedHandle};

fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("arxa-transport: tokio runtime")
    })
}

/// Session lifecycle as observed from Dart. Mirrors
/// `transport::LinkState` (kept separate so the core stays FRB-free).
pub enum TransportState {
    Connecting,
    Connected,
    Reconnecting,
    /// Desktop refused the token (or revoked it mid-session). Terminal —
    /// the user must scan a fresh QR code.
    Revoked,
    /// Dial budget exhausted or `close()` called. `resume()` can redial.
    Disconnected,
}

impl From<transport::LinkState> for TransportState {
    fn from(s: transport::LinkState) -> Self {
        match s {
            transport::LinkState::Connecting => TransportState::Connecting,
            transport::LinkState::Connected => TransportState::Connected,
            transport::LinkState::Reconnecting => TransportState::Reconnecting,
            transport::LinkState::Revoked => TransportState::Revoked,
            transport::LinkState::Disconnected => TransportState::Disconnected,
        }
    }
}

/// Handle to one pairing session. Opaque to Dart; the Dart-side
/// `StudioSession` wraps it.
#[frb(opaque)]
pub struct TransportSession {
    shared: SharedHandle,
}

/// Parse the QR payload and start dialing. Returns immediately with a live
/// handle; progress arrives on [`TransportSession::status_stream`].
///
/// * `qr_payload` — `arxa-pair:<base32(json)>` exactly as scanned.
/// * `device_name` — shown in the desktop's paired-devices list; defaults to
///   the device hostname / iPhone model.
#[frb(sync)]
pub fn connect(qr_payload: String, device_name: Option<String>) -> Result<TransportSession, String> {
    let pairing = transport::parse_ticket(&qr_payload)?;
    let shared = transport::new_shared();
    let epoch = transport::begin_epoch(
        &shared,
        pairing.clone(),
        device_name,
        transport::LinkState::Connecting,
    );
    spawn_session(&shared, epoch, pairing, transport::FRESH_DIAL_ATTEMPTS, false);
    Ok(TransportSession { shared })
}

fn spawn_session(
    shared: &SharedHandle,
    epoch: u64,
    pairing: Pairing,
    max_dial_attempts: u32,
    reconnecting: bool,
) {
    let shared = Arc::clone(shared);
    runtime().spawn(async move {
        transport::run_session(shared, epoch, pairing, max_dial_attempts, reconnecting).await;
    });
}

impl TransportSession {
    /// Loopback proxy port while Connected (`http://127.0.0.1:<port>/`),
    /// otherwise None. May change across reconnects — re-read it on every
    /// transition to Connected.
    #[frb(sync, getter)]
    pub fn proxy_port(&self) -> Option<u16> {
        transport::current_proxy_port(&self.shared)
    }

    /// Current state, for polling; prefer [`status_stream`].
    #[frb(sync, getter)]
    pub fn state(&self) -> TransportState {
        transport::current_state(&self.shared).into()
    }

    /// Subscribe to lifecycle updates. Emits the current state immediately,
    /// then every transition. Multiple subscribers are fine.
    pub fn status_stream(&self, sink: StreamSink<TransportState>) {
        let (current, mut rx) = transport::subscribe(&self.shared);
        runtime().spawn(async move {
            if sink.add(current.into()).is_err() {
                return;
            }
            loop {
                match rx.recv().await {
                    Ok(state) => {
                        if sink.add(state.into()).is_err() {
                            break;
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                }
            }
        });
    }

    /// Register the OS push token (platform: `apns` | `fcm`). Stored for the
    /// session and re-sent over the tunnel after every (re)connect; if the
    /// tunnel is up now, it is sent immediately.
    #[frb(sync)]
    pub fn register_push_token(&self, platform: String, token: String) {
        if let Some((conn, pairing)) =
            transport::set_push_token(&self.shared, platform.clone(), token.clone())
        {
            runtime().spawn(async move {
                transport::register_push_over_tunnel(&conn, &pairing.token, &platform, &token)
                    .await;
            });
        }
    }

    /// Redial after the app returns to the foreground. iOS suspends QUIC
    /// sockets in the background, so the old connection is usually dead on
    /// resume — this supersedes it and dials on the reconnect budget (5
    /// attempts, 3s backoff). No-op if the pairing was revoked or the
    /// session already closed without a stored pairing.
    #[frb(sync)]
    pub fn resume(&self) {
        if matches!(
            transport::current_state(&self.shared),
            transport::LinkState::Revoked
        ) {
            return;
        }
        let Some(pairing) = transport::current_pairing(&self.shared) else {
            return;
        };
        let epoch = transport::begin_epoch(
            &self.shared,
            pairing.clone(),
            None,
            transport::LinkState::Reconnecting,
        );
        spawn_session(
            &self.shared,
            epoch,
            pairing,
            transport::RECONNECT_DIAL_ATTEMPTS,
            true,
        );
    }

    /// Tear the session down: closes the QUIC connection, aborts the
    /// loopback proxy, releases the endpoint. Terminal for this handle
    /// (state becomes Disconnected; `resume()` on a closed handle redials
    /// only if a pairing is still held).
    #[frb(sync)]
    pub fn close(&self) {
        let shared = Arc::clone(&self.shared);
        let _guard = runtime().enter(); // transport::close spawns endpoint shutdown
        transport::close(&shared);
    }
}
