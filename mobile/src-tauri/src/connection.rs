//! Phone <-> Mac connection layer — placeholder.
//!
//! ponytail: the iroh P2P transport (decision M1) lands in this module. The seam is
//! the public command surface below (`connection_status`, `begin_pairing`); replace
//! the stub bodies with an embedded iroh endpoint + pairing-ticket exchange while the
//! frontend contract (invoke names + JSON shapes) stays fixed.
//!
//! ponytail: push tokens (cairn-pushd via cairn_tauri, decision M7) and the
//! online-only session policy (M8) also hang off this module once the transport exists.

use serde::Serialize;

// ponytail: Connecting/Connected are unconstructed until the iroh transport lands —
// they document the fixed frontend contract, hence the allow.
#[allow(dead_code)]
#[derive(Serialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionState {
    NotPaired,
    Connecting,
    Connected,
}

#[derive(Serialize)]
pub struct ConnectionStatus {
    pub state: ConnectionState,
    /// Set once connected: the engine-served studio UI URL (decision M4). The
    /// frontend navigates the webview to it, mirroring desktop's studio_url flow.
    pub studio_url: Option<String>,
}

/// ponytail: replace with real transport state once iroh lands (M1).
#[tauri::command]
pub fn connection_status() -> ConnectionStatus {
    ConnectionStatus {
        state: ConnectionState::NotPaired,
        studio_url: None,
    }
}

/// Invoked when the user taps "Scan QR". ponytail: will open the camera, decode the
/// desktop-minted pairing QR (decision M2), and hand the ticket to the iroh layer.
#[tauri::command]
pub fn begin_pairing() -> Result<(), String> {
    Err("pairing not implemented yet — iroh transport pending (M1/M2)".into())
}
