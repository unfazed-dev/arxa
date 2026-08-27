//! Phone <-> Mac connection layer — iroh transport (decisions M1/M2/M4).
//!
//! Wire contract (pinned in `docs/plans/mobile-pairing-transport.md`):
//! - **Ticket**: `arxa-pair:<base32(json)>` where json =
//!   `{ "node": <iroh endpoint ticket string>, "token": <32-byte hex auth token> }`.
//!   base32 is RFC 4648 (uppercase alphabet, no padding); decoding here is
//!   case-insensitive. With iroh 1.x the "NodeAddr ticket" of the plan is an
//!   `iroh_tickets::endpoint::EndpointTicket` (NodeAddr was renamed EndpointAddr).
//! - **Transport**: iroh bidirectional streams, ALPN `arxa/studio/0`. The first
//!   frame from the phone on EVERY stream is `AUTH <token>\n`; the desktop
//!   replies `OK\n` or closes the stream.
//! - **M4 delivery**: after auth a stream carries raw HTTP/1.1. A loopback TCP
//!   proxy on `127.0.0.1:<random port>` opens one fresh iroh stream per accepted
//!   TCP connection; `studio_url` = `http://127.0.0.1:<port>/`.
//! - **Persistence**: peer ticket + session token stored as JSON in the Tauri
//!   app data dir; startup attempts a silent reconnect before falling back to
//!   NotPaired. Local-only storage — no Arxa Digital Solutions database
//!   involvement (ownership boundary rule).
//!
//! The public command surface (`connection_status`, `begin_pairing`) and its
//! JSON shapes are the fixed frontend contract — do not rename or reshape.
//!
//! ponytail: push tokens (cairn-pushd via cairn_tauri, decision M7) and the
//! online-only session policy (M8) hang off this module once needed.

use std::{
    fs,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration,
};

use iroh::endpoint::{presets, Connection, Endpoint};
use iroh_tickets::endpoint::EndpointTicket;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};
use tokio::{
    io::AsyncWriteExt,
    net::{TcpListener, TcpStream},
    time::timeout,
};

const ALPN: &[u8] = b"arxa/studio/0";
const TICKET_PREFIX: &str = "arxa-pair:";
const AUTH_TIMEOUT: Duration = Duration::from_secs(15);
const RECONNECT_BACKOFF: Duration = Duration::from_secs(3);
/// Interactive pairing fails fast; the silent startup reconnect gets more patience.
const FRESH_DIAL_ATTEMPTS: u32 = 2;
const RECONNECT_DIAL_ATTEMPTS: u32 = 5;

type DynErr = Box<dyn std::error::Error + Send + Sync>;

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

/// Ticket payload — also the on-disk persistence shape (`pairing.json`).
#[derive(Serialize, Deserialize, Clone)]
struct Pairing {
    /// iroh endpoint ticket string for the desktop peer.
    node: String,
    /// Auth token, sent as `AUTH <token>\n` on every stream. Kept as the
    /// long-lived session token after the first successful pairing.
    token: String,
}

struct Shared {
    state: ConnectionState,
    studio_url: Option<String>,
    /// Bumped on every (re)pairing so stale session tasks stop writing state.
    epoch: u64,
}

impl Default for Shared {
    fn default() -> Self {
        Self {
            state: ConnectionState::NotPaired,
            studio_url: None,
            epoch: 0,
        }
    }
}

type SharedHandle = Arc<Mutex<Shared>>;

#[derive(Default)]
pub struct ConnectionManager {
    inner: SharedHandle,
}

/// Writes state iff `epoch` is still current; returns false when superseded.
fn set_state(
    shared: &SharedHandle,
    epoch: u64,
    state: ConnectionState,
    studio_url: Option<String>,
) -> bool {
    let mut s = shared.lock().expect("connection state poisoned");
    if s.epoch != epoch {
        return false;
    }
    s.state = state;
    s.studio_url = studio_url;
    true
}

fn begin_epoch(shared: &SharedHandle) -> u64 {
    let mut s = shared.lock().expect("connection state poisoned");
    s.epoch += 1;
    s.state = ConnectionState::Connecting;
    s.studio_url = None;
    s.epoch
}

#[tauri::command]
pub fn connection_status(mgr: State<'_, ConnectionManager>) -> ConnectionStatus {
    let s = mgr.inner.lock().expect("connection state poisoned");
    ConnectionStatus {
        state: s.state,
        studio_url: s.studio_url.clone(),
    }
}

/// Invoked with the scanned/pasted pairing code (decision M2). Validates the
/// ticket, flips to Connecting, and drives the iroh session in the background;
/// progress is observed via `connection_status` polling.
#[tauri::command]
pub fn begin_pairing(
    app: AppHandle,
    mgr: State<'_, ConnectionManager>,
    ticket: String,
) -> Result<(), String> {
    let pairing = parse_ticket(&ticket)?;
    let shared = mgr.inner.clone();
    let epoch = begin_epoch(&shared);
    spawn_session(app, shared, epoch, pairing, FRESH_DIAL_ATTEMPTS);
    Ok(())
}

/// Startup path: silently reconnect from stored pairing, if any (Connecting
/// until it succeeds or gives up back to NotPaired).
pub fn attempt_reconnect(app: &AppHandle) {
    let Some(pairing) = load_pairing(app) else {
        return;
    };
    let mgr = app.state::<ConnectionManager>();
    let shared = mgr.inner.clone();
    let epoch = begin_epoch(&shared);
    spawn_session(app.clone(), shared, epoch, pairing, RECONNECT_DIAL_ATTEMPTS);
}

// ---------------------------------------------------------------------------
// Ticket parsing
// ---------------------------------------------------------------------------

fn parse_ticket(raw: &str) -> Result<Pairing, String> {
    let payload = raw
        .trim()
        .strip_prefix(TICKET_PREFIX)
        .ok_or_else(|| format!("not an arxa pairing code (expected `{TICKET_PREFIX}...`)"))?;
    let bytes = data_encoding::BASE32_NOPAD
        .decode(payload.trim().to_ascii_uppercase().as_bytes())
        .map_err(|e| format!("pairing code payload is not valid base32: {e}"))?;
    let pairing: Pairing = serde_json::from_slice(&bytes)
        .map_err(|e| format!("pairing code JSON is malformed: {e}"))?;
    pairing
        .node
        .parse::<EndpointTicket>()
        .map_err(|e| format!("pairing code holds an invalid iroh endpoint ticket: {e}"))?;
    if pairing.token.is_empty() {
        return Err("pairing code is missing the auth token".into());
    }
    Ok(pairing)
}

// ---------------------------------------------------------------------------
// Session driving
// ---------------------------------------------------------------------------

enum SessionError {
    /// Reached the desktop but it refused the token — stored pairing is dead.
    AuthRejected(String),
    /// Could not reach the desktop (network / relay / timeout) — retryable.
    Unreachable(String),
}

fn spawn_session(
    app: AppHandle,
    shared: SharedHandle,
    epoch: u64,
    pairing: Pairing,
    max_dial_attempts: u32,
) {
    tauri::async_runtime::spawn(async move {
        run_session(app, shared, epoch, pairing, max_dial_attempts).await;
    });
}

async fn run_session(
    app: AppHandle,
    shared: SharedHandle,
    epoch: u64,
    pairing: Pairing,
    max_dial_attempts: u32,
) {
    // Already validated in parse_ticket / stored form; bail defensively.
    let ticket: EndpointTicket = match pairing.node.parse() {
        Ok(t) => t,
        Err(_) => {
            set_state(&shared, epoch, ConnectionState::NotPaired, None);
            return;
        }
    };
    let endpoint = match Endpoint::bind(presets::N0).await {
        Ok(ep) => ep,
        Err(e) => {
            eprintln!("arxa-mobile: iroh endpoint bind failed: {e}");
            set_state(&shared, epoch, ConnectionState::NotPaired, None);
            return;
        }
    };

    let mut attempts = 0u32;
    loop {
        if !set_state(&shared, epoch, ConnectionState::Connecting, None) {
            break; // superseded by a newer pairing
        }
        match establish(&endpoint, &ticket, &pairing.token).await {
            Ok(conn) => {
                attempts = 0;
                if let Err(e) = store_pairing(&app, &pairing) {
                    eprintln!("arxa-mobile: could not persist pairing: {e}");
                }
                let (port, proxy) = match start_proxy(conn.clone(), pairing.token.clone()).await {
                    Ok(v) => v,
                    Err(e) => {
                        eprintln!("arxa-mobile: loopback proxy bind failed: {e}");
                        set_state(&shared, epoch, ConnectionState::NotPaired, None);
                        break;
                    }
                };
                let url = format!("http://127.0.0.1:{port}/");
                if !set_state(&shared, epoch, ConnectionState::Connected, Some(url)) {
                    proxy.abort();
                    break;
                }
                let reason = conn.closed().await;
                eprintln!("arxa-mobile: link to desktop closed: {reason}");
                proxy.abort();
                // Fall through: redial with the stored session token.
            }
            Err(SessionError::AuthRejected(msg)) => {
                eprintln!("arxa-mobile: desktop rejected pairing token: {msg}");
                forget_pairing(&app);
                set_state(&shared, epoch, ConnectionState::NotPaired, None);
                break;
            }
            Err(SessionError::Unreachable(msg)) => {
                attempts += 1;
                eprintln!("arxa-mobile: dial failed ({attempts}/{max_dial_attempts}): {msg}");
                if attempts >= max_dial_attempts {
                    set_state(&shared, epoch, ConnectionState::NotPaired, None);
                    break;
                }
                tokio::time::sleep(RECONNECT_BACKOFF).await;
            }
        }
    }
    endpoint.close().await;
}

/// Dial the desktop and prove the token on a handshake stream.
async fn establish(
    endpoint: &Endpoint,
    ticket: &EndpointTicket,
    token: &str,
) -> Result<Connection, SessionError> {
    let addr = ticket.endpoint_addr().clone();
    let conn = endpoint
        .connect(addr, ALPN)
        .await
        .map_err(|e| SessionError::Unreachable(e.to_string()))?;
    match timeout(AUTH_TIMEOUT, auth_stream(&conn, token)).await {
        Ok(Ok(())) => Ok(conn),
        Ok(Err(e)) => Err(SessionError::AuthRejected(e.to_string())),
        Err(_) => Err(SessionError::Unreachable("auth handshake timed out".into())),
    }
}

/// Opens a stream and performs the `AUTH <token>\n` -> `OK\n` exchange.
async fn auth_stream(conn: &Connection, token: &str) -> Result<(), DynErr> {
    let (mut send, mut recv) = conn.open_bi().await?;
    send.write_all(format!("AUTH {token}\n").as_bytes()).await?;
    let mut ok = [0u8; 3];
    recv.read_exact(&mut ok).await?;
    if &ok != b"OK\n" {
        return Err(format!("unexpected handshake reply: {ok:?}").into());
    }
    let _ = send.finish();
    Ok(())
}

// ---------------------------------------------------------------------------
// Loopback proxy (M4): TCP on 127.0.0.1 <-> one iroh stream per connection
// ---------------------------------------------------------------------------

async fn start_proxy(
    conn: Connection,
    token: String,
) -> std::io::Result<(u16, tauri::async_runtime::JoinHandle<()>)> {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await?;
    let port = listener.local_addr()?.port();
    let handle = tauri::async_runtime::spawn(async move {
        loop {
            match listener.accept().await {
                Ok((tcp, _peer)) => {
                    let conn = conn.clone();
                    let token = token.clone();
                    tauri::async_runtime::spawn(async move {
                        if let Err(e) = bridge(conn, token, tcp).await {
                            eprintln!("arxa-mobile: proxied stream ended: {e}");
                        }
                    });
                }
                Err(e) => {
                    eprintln!("arxa-mobile: loopback accept failed: {e}");
                    break;
                }
            }
        }
    });
    Ok((port, handle))
}

async fn bridge(conn: Connection, token: String, mut tcp: TcpStream) -> Result<(), DynErr> {
    let (mut send, mut recv) = conn.open_bi().await?;
    // AUTH is the first frame on every stream (plan contract); consume the
    // desktop's OK before piping raw HTTP/1.1 bytes.
    send.write_all(format!("AUTH {token}\n").as_bytes()).await?;
    let mut ok = [0u8; 3];
    recv.read_exact(&mut ok).await?;
    if &ok != b"OK\n" {
        return Err("desktop refused stream auth".into());
    }
    let (mut tcp_read, mut tcp_write) = tcp.split();
    let uplink = async {
        tokio::io::copy(&mut tcp_read, &mut send).await?;
        let _ = send.finish();
        Ok::<(), DynErr>(())
    };
    let downlink = async {
        tokio::io::copy(&mut recv, &mut tcp_write).await?;
        let _ = tcp_write.shutdown().await;
        Ok::<(), DynErr>(())
    };
    tokio::try_join!(uplink, downlink)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Local persistence (Tauri app data dir — local-only by design)
// ---------------------------------------------------------------------------

fn pairing_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    Ok(dir.join("pairing.json"))
}

fn load_pairing(app: &AppHandle) -> Option<Pairing> {
    let bytes = fs::read(pairing_path(app).ok()?).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn store_pairing(app: &AppHandle, pairing: &Pairing) -> Result<(), String> {
    let path = pairing_path(app)?;
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_vec(pairing).map_err(|e| e.to_string())?;
    fs::write(&path, json).map_err(|e| e.to_string())
}

fn forget_pairing(app: &AppHandle) {
    if let Ok(path) = pairing_path(app) {
        let _ = fs::remove_file(path);
    }
}
