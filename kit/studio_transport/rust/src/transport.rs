//! Phone <-> Mac connection layer — iroh transport.
//!
//! Ported from arxa/mobile/src-tauri/src/connection.rs (the Tauri scaffold),
//! minus the Tauri plumbing. Wire contract pinned in
//! docs/plans/mobile-flutter-migration-spec.md:
//!
//! * QR payload: `arxa-pair:<base32(json)>` (RFC 4648 BASE32_NOPAD, uppercase),
//!   JSON `{ "node": <iroh endpoint ticket>, "token": <32-byte hex> }`.
//! * iroh bidi streams, ALPN `arxa/studio/0`.
//! * Every stream opens with `AUTH <token> <device-name>\n` → `OK\n`.
//! * After AUTH, raw HTTP/1.1 is bridged via a loopback proxy
//!   (phone listens on 127.0.0.1:<port>).
//! * Push relay frame: `PUSH <session_token> <platform> <token>\n` → `OK\n`.
//! * Revocation = the desktop closing the AUTH stream / refusing AUTH.
//! * No heartbeat frame — liveness is stream-level (conn.closed()).

use std::sync::{Arc, Mutex};
use std::time::Duration;

use iroh::endpoint::{presets, Connection, Endpoint};
use iroh_tickets::endpoint::EndpointTicket;
use serde::{Deserialize, Serialize};
use tokio::{
    io::AsyncWriteExt,
    net::{TcpListener, TcpStream},
    time::timeout,
};

pub const ALPN: &[u8] = b"arxa/studio/0";
pub const TICKET_PREFIX: &str = "arxa-pair:";
pub const AUTH_TIMEOUT: Duration = Duration::from_secs(15);
pub const RECONNECT_BACKOFF: Duration = Duration::from_secs(3);
pub const FRESH_DIAL_ATTEMPTS: u32 = 2;
pub const RECONNECT_DIAL_ATTEMPTS: u32 = 5;

type DynErr = Box<dyn std::error::Error + Send + Sync>;

/// Session lifecycle as observed from Dart.
///
/// `Revoked` is terminal: the desktop refused the token (or the pairing was
/// revoked mid-session and the redial was refused). `Disconnected` means dial
/// attempts were exhausted — `resume()` may bring it back.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum LinkState {
    Connecting,
    Connected,
    Reconnecting,
    Revoked,
    Disconnected,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct Pairing {
    /// iroh endpoint ticket (`EndpointTicket` string form).
    pub node: String,
    /// Session auth token (32-byte hex minted by the desktop).
    pub token: String,
}

/// Parse the QR payload: `arxa-pair:<base32(json)>`.
pub fn parse_ticket(raw: &str) -> Result<Pairing, String> {
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

/// The first frame on every bidi stream. Desktop replies `OK\n` or closes.
pub fn auth_frame(token: &str, device_name: &str) -> String {
    format!("AUTH {token} {device_name}\n")
}

/// Push-token registration frame (one dedicated stream). Reply: `OK\n`.
pub fn push_frame(session_token: &str, platform: &str, token: &str) -> String {
    format!("PUSH {session_token} {platform} {token}\n")
}

/// The desktop's 3-byte accept reply.
pub fn is_ok_reply(buf: &[u8; 3]) -> bool {
    buf == b"OK\n"
}

#[derive(Debug)]
pub enum SessionError {
    AuthRejected(String),
    Unreachable(String),
}

// ---------------------------------------------------------------------------
// Shared session state
// ---------------------------------------------------------------------------

pub struct Shared {
    state: LinkState,
    proxy_port: Option<u16>,
    epoch: u64,
    pairing: Option<Pairing>,
    device_name: Option<String>,
    push_token: Option<(String, String)>,
    /// Live QUIC connection while Connected — lets `register_push_token` and
    /// `close()` act immediately.
    conn: Option<Connection>,
    endpoint: Option<Endpoint>,
    proxy: Option<tokio::task::JoinHandle<()>>,
    events: tokio::sync::broadcast::Sender<LinkState>,
}

impl Default for Shared {
    fn default() -> Self {
        let (events, _) = tokio::sync::broadcast::channel(32);
        Self {
            state: LinkState::Disconnected,
            proxy_port: None,
            epoch: 0,
            pairing: None,
            device_name: None,
            push_token: None,
            conn: None,
            endpoint: None,
            proxy: None,
            events,
        }
    }
}

pub type SharedHandle = Arc<Mutex<Shared>>;

pub fn new_shared() -> SharedHandle {
    Arc::new(Mutex::new(Shared::default()))
}

pub fn current_state(shared: &SharedHandle) -> LinkState {
    shared.lock().expect("transport state poisoned").state
}

pub fn current_proxy_port(shared: &SharedHandle) -> Option<u16> {
    shared.lock().expect("transport state poisoned").proxy_port
}

pub fn current_pairing(shared: &SharedHandle) -> Option<Pairing> {
    shared.lock().expect("transport state poisoned").pairing.clone()
}

pub fn subscribe(shared: &SharedHandle) -> (LinkState, tokio::sync::broadcast::Receiver<LinkState>) {
    let s = shared.lock().expect("transport state poisoned");
    (s.state, s.events.subscribe())
}

pub fn set_push_token(shared: &SharedHandle, platform: String, token: String) -> Option<(Connection, Pairing)> {
    let mut s = shared.lock().expect("transport state poisoned");
    s.push_token = Some((platform, token));
    // If already connected, caller should register over the live tunnel now.
    match (&s.conn, &s.pairing) {
        (Some(c), Some(p)) if s.state == LinkState::Connected => Some((c.clone(), p.clone())),
        _ => None,
    }
}

/// Supersede any running session: bump the epoch, stash the pairing, mark the
/// new phase. Returns the new epoch.
pub fn begin_epoch(
    shared: &SharedHandle,
    pairing: Pairing,
    device_name: Option<String>,
    phase: LinkState,
) -> u64 {
    let mut s = shared.lock().expect("transport state poisoned");
    s.epoch += 1;
    s.state = phase;
    s.proxy_port = None;
    s.pairing = Some(pairing);
    if device_name.is_some() {
        s.device_name = device_name;
    }
    // Tear down the superseded session's resources so its loop unblocks.
    if let Some(conn) = s.conn.take() {
        conn.close(0u32.into(), b"superseded");
    }
    if let Some(proxy) = s.proxy.take() {
        proxy.abort();
    }
    let _ = s.events.send(s.state);
    s.epoch
}

/// Terminal close from the Dart side.
pub fn close(shared: &SharedHandle) {
    let mut s = shared.lock().expect("transport state poisoned");
    s.epoch += 1; // supersede the running loop
    s.state = LinkState::Disconnected;
    s.proxy_port = None;
    if let Some(conn) = s.conn.take() {
        conn.close(0u32.into(), b"closed");
    }
    if let Some(proxy) = s.proxy.take() {
        proxy.abort();
    }
    let endpoint = s.endpoint.take();
    let _ = s.events.send(s.state);
    drop(s);
    if let Some(ep) = endpoint {
        // Fire-and-forget: releases sockets without blocking the caller.
        tokio::spawn(async move { ep.close().await });
    }
}

fn set_state(
    shared: &SharedHandle,
    epoch: u64,
    state: LinkState,
    proxy_port: Option<u16>,
) -> bool {
    let mut s = shared.lock().expect("transport state poisoned");
    if s.epoch != epoch {
        return false;
    }
    s.state = state;
    s.proxy_port = proxy_port;
    let _ = s.events.send(state);
    true
}

fn stash_conn(shared: &SharedHandle, epoch: u64, conn: Connection, proxy: tokio::task::JoinHandle<()>) -> bool {
    let mut s = shared.lock().expect("transport state poisoned");
    if s.epoch != epoch {
        proxy.abort();
        return false;
    }
    s.conn = Some(conn);
    s.proxy = Some(proxy);
    true
}

fn clear_conn(shared: &SharedHandle, epoch: u64) {
    let mut s = shared.lock().expect("transport state poisoned");
    if s.epoch == epoch {
        s.conn = None;
        if let Some(p) = s.proxy.take() {
            p.abort();
        }
    }
}

fn stash_endpoint(shared: &SharedHandle, epoch: u64, endpoint: Endpoint) -> bool {
    let mut s = shared.lock().expect("transport state poisoned");
    if s.epoch != epoch {
        return false;
    }
    s.endpoint = Some(endpoint);
    true
}

fn push_token_of(shared: &SharedHandle) -> Option<(String, String)> {
    shared.lock().expect("transport state poisoned").push_token.clone()
}

fn device_name_of(shared: &SharedHandle) -> String {
    shared
        .lock()
        .expect("transport state poisoned")
        .device_name
        .clone()
        .unwrap_or_else(|| device_label().to_string())
}

fn revoke_pairing(shared: &SharedHandle, epoch: u64) {
    let mut s = shared.lock().expect("transport state poisoned");
    if s.epoch == epoch {
        s.pairing = None;
    }
}

// ---------------------------------------------------------------------------
// Session loop (ported from run_session)
// ---------------------------------------------------------------------------

/// Dial → AUTH → proxy → wait for close → redial. `initial_reconnecting`
/// distinguishes a fresh pairing (Connecting) from a resume (Reconnecting).
pub async fn run_session(
    shared: SharedHandle,
    epoch: u64,
    pairing: Pairing,
    mut max_dial_attempts: u32,
    initial_reconnecting: bool,
) {
    let endpoint = match Endpoint::bind(presets::N0).await {
        Ok(ep) => ep,
        Err(e) => {
            eprintln!("arxa-transport: iroh endpoint bind failed: {e}");
            set_state(&shared, epoch, LinkState::Disconnected, None);
            return;
        }
    };
    if !stash_endpoint(&shared, epoch, endpoint.clone()) {
        endpoint.close().await;
        return;
    }
    let ticket: EndpointTicket = match pairing.node.parse() {
        Ok(t) => t,
        Err(_) => {
            set_state(&shared, epoch, LinkState::Disconnected, None);
            endpoint.close().await;
            return;
        }
    };

    let mut attempts = 0u32;
    let mut was_connected = initial_reconnecting;
    loop {
        let phase = if was_connected {
            LinkState::Reconnecting
        } else {
            LinkState::Connecting
        };
        if !set_state(&shared, epoch, phase, None) {
            break; // superseded by a newer pairing / resume / close
        }
        let device_name = device_name_of(&shared);
        match establish(&endpoint, &ticket, &pairing.token, &device_name).await {
            Ok(conn) => {
                attempts = 0;
                // A session that has connected once redials on the more
                // patient reconnect budget from here on.
                max_dial_attempts = RECONNECT_DIAL_ATTEMPTS;
                was_connected = true;
                let (port, proxy) =
                    match start_proxy(conn.clone(), pairing.token.clone(), device_name.clone()).await {
                        Ok(v) => v,
                        Err(e) => {
                            eprintln!("arxa-transport: loopback proxy bind failed: {e}");
                            set_state(&shared, epoch, LinkState::Disconnected, None);
                            break;
                        }
                    };
                if !stash_conn(&shared, epoch, conn.clone(), proxy) {
                    break;
                }
                if let Some((platform, token)) = push_token_of(&shared) {
                    register_push_over_tunnel(&conn, &pairing.token, &platform, &token).await;
                }
                if !set_state(&shared, epoch, LinkState::Connected, Some(port)) {
                    clear_conn(&shared, epoch);
                    break;
                }
                let reason = conn.closed().await;
                eprintln!("arxa-transport: link to desktop closed: {reason}");
                clear_conn(&shared, epoch);
            }
            Err(SessionError::AuthRejected(msg)) => {
                eprintln!("arxa-transport: desktop rejected pairing token: {msg}");
                revoke_pairing(&shared, epoch);
                set_state(&shared, epoch, LinkState::Revoked, None);
                break;
            }
            Err(SessionError::Unreachable(msg)) => {
                attempts += 1;
                eprintln!("arxa-transport: dial failed ({attempts}/{max_dial_attempts}): {msg}");
                if attempts >= max_dial_attempts {
                    set_state(&shared, epoch, LinkState::Disconnected, None);
                    break;
                }
                tokio::time::sleep(RECONNECT_BACKOFF).await;
            }
        }
    }
    endpoint.close().await;
}

pub async fn register_push_over_tunnel(
    conn: &Connection,
    session_token: &str,
    platform: &str,
    token: &str,
) {
    match timeout(AUTH_TIMEOUT, async {
        let (mut send, mut recv) = conn.open_bi().await?;
        send.write_all(push_frame(session_token, platform, token).as_bytes())
            .await?;
        let _ = send.finish();
        let mut ok = [0u8; 3];
        recv.read_exact(&mut ok).await?;
        if is_ok_reply(&ok) {
            Ok::<(), DynErr>(())
        } else {
            Err(format!("unexpected PUSH reply: {ok:?}").into())
        }
    })
    .await
    {
        Ok(Ok(())) => {}
        Ok(Err(e)) => eprintln!("arxa-transport: push registration not accepted: {e}"),
        Err(_) => eprintln!("arxa-transport: push registration timed out"),
    }
}

pub async fn establish(
    endpoint: &Endpoint,
    ticket: &EndpointTicket,
    token: &str,
    device_name: &str,
) -> Result<Connection, SessionError> {
    let addr = ticket.endpoint_addr().clone();
    let conn = endpoint
        .connect(addr, ALPN)
        .await
        .map_err(|e| SessionError::Unreachable(e.to_string()))?;
    match timeout(AUTH_TIMEOUT, auth_stream(&conn, token, device_name)).await {
        Ok(Ok(())) => Ok(conn),
        Ok(Err(e)) => Err(SessionError::AuthRejected(e.to_string())),
        Err(_) => Err(SessionError::Unreachable("auth handshake timed out".into())),
    }
}

async fn auth_stream(conn: &Connection, token: &str, device_name: &str) -> Result<(), DynErr> {
    let (mut send, mut recv) = conn.open_bi().await?;
    send.write_all(auth_frame(token, device_name).as_bytes())
        .await?;
    let mut ok = [0u8; 3];
    recv.read_exact(&mut ok).await?;
    if !is_ok_reply(&ok) {
        return Err(format!("unexpected handshake reply: {ok:?}").into());
    }
    let _ = send.finish();
    Ok(())
}

// ---------------------------------------------------------------------------
// Loopback HTTP proxy (ported verbatim)
// ---------------------------------------------------------------------------

pub async fn start_proxy(
    conn: Connection,
    token: String,
    device_name: String,
) -> std::io::Result<(u16, tokio::task::JoinHandle<()>)> {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await?;
    let port = listener.local_addr()?.port();
    let handle = tokio::spawn(async move {
        loop {
            match listener.accept().await {
                Ok((tcp, _peer)) => {
                    let conn = conn.clone();
                    let token = token.clone();
                    let device_name = device_name.clone();
                    tokio::spawn(async move {
                        if let Err(e) = bridge(conn, token, device_name, tcp).await {
                            eprintln!("arxa-transport: proxied stream ended: {e}");
                        }
                    });
                }
                Err(e) => {
                    eprintln!("arxa-transport: loopback accept failed: {e}");
                    break;
                }
            }
        }
    });
    Ok((port, handle))
}

async fn bridge(
    conn: Connection,
    token: String,
    device_name: String,
    mut tcp: TcpStream,
) -> Result<(), DynErr> {
    let (mut send, mut recv) = conn.open_bi().await?;
    send.write_all(auth_frame(&token, &device_name).as_bytes())
        .await?;
    let mut ok = [0u8; 3];
    recv.read_exact(&mut ok).await?;
    if !is_ok_reply(&ok) {
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
// Device name (ported verbatim)
// ---------------------------------------------------------------------------

pub fn device_label() -> &'static str {
    static LABEL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    LABEL.get_or_init(|| {
        let fallback = if cfg!(target_os = "ios") {
            "iPhone"
        } else if cfg!(target_os = "android") {
            "Android device"
        } else {
            "Mobile device"
        };
        let mut buf = [0u8; 256];
        let hostname = unsafe {
            if libc::gethostname(buf.as_mut_ptr() as *mut libc::c_char, buf.len()) == 0 {
                std::ffi::CStr::from_bytes_until_nul(&buf)
                    .ok()
                    .and_then(|c| c.to_str().ok())
                    .map(|s| s.trim_end_matches(".local").trim().to_string())
            } else {
                None
            }
        };
        match hostname {
            Some(h)
                if !h.is_empty()
                    && !h.eq_ignore_ascii_case("localhost")
                    && !h.eq_ignore_ascii_case("iphone") =>
            {
                h.chars().filter(|c| !c.is_control()).take(64).collect()
            }
            _ => ios_model_name().unwrap_or_else(|| fallback.to_string()),
        }
    })
}

#[cfg(target_os = "ios")]
fn ios_model_name() -> Option<String> {
    let key = std::ffi::CString::new("hw.machine").ok()?;
    let ident = unsafe {
        let mut len: libc::size_t = 0;
        if libc::sysctlbyname(
            key.as_ptr(),
            std::ptr::null_mut(),
            &mut len,
            std::ptr::null_mut(),
            0,
        ) != 0
            || len == 0
        {
            return None;
        }
        let mut buf = vec![0u8; len];
        if libc::sysctlbyname(
            key.as_ptr(),
            buf.as_mut_ptr() as *mut libc::c_void,
            &mut len,
            std::ptr::null_mut(),
            0,
        ) != 0
        {
            return None;
        }
        std::ffi::CStr::from_bytes_until_nul(&buf)
            .ok()?
            .to_str()
            .ok()?
            .to_string()
    };
    let name = match ident.as_str() {
        "iPhone14,2" => "iPhone 13 Pro",
        "iPhone14,3" => "iPhone 13 Pro Max",
        "iPhone14,4" => "iPhone 13 mini",
        "iPhone14,5" => "iPhone 13",
        "iPhone14,6" => "iPhone SE (3rd gen)",
        "iPhone14,7" => "iPhone 14",
        "iPhone14,8" => "iPhone 14 Plus",
        "iPhone15,2" => "iPhone 14 Pro",
        "iPhone15,3" => "iPhone 14 Pro Max",
        "iPhone15,4" => "iPhone 15",
        "iPhone15,5" => "iPhone 15 Plus",
        "iPhone16,1" => "iPhone 15 Pro",
        "iPhone16,2" => "iPhone 15 Pro Max",
        "iPhone17,1" => "iPhone 16 Pro",
        "iPhone17,2" => "iPhone 16 Pro Max",
        "iPhone17,3" => "iPhone 16",
        "iPhone17,4" => "iPhone 16 Plus",
        "iPhone17,5" => "iPhone 16e",
        other if other.starts_with("iPhone") || other.starts_with("iPad") => other,
        _ => return None, // simulator/host arch — not a device identifier
    };
    Some(name.to_string())
}

#[cfg(not(target_os = "ios"))]
fn ios_model_name() -> Option<String> {
    None
}

// ---------------------------------------------------------------------------
// Unit tests — QR parsing + AUTH/PUSH framing, no network.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Build a syntactically valid pairing code around a real (offline)
    /// endpoint ticket.
    fn make_code(token: &str) -> (String, String) {
        let secret = iroh::SecretKey::generate();
        let addr = iroh::EndpointAddr::from(secret.public());
        let ticket = EndpointTicket::from(addr);
        let json = serde_json::json!({ "node": ticket.to_string(), "token": token });
        let payload = data_encoding::BASE32_NOPAD.encode(json.to_string().as_bytes());
        (format!("{TICKET_PREFIX}{payload}"), ticket.to_string())
    }

    #[test]
    fn parse_ticket_roundtrip() {
        let token = "a".repeat(64);
        let (code, node) = make_code(&token);
        let pairing = parse_ticket(&code).expect("valid code parses");
        assert_eq!(pairing.node, node);
        assert_eq!(pairing.token, token);
    }

    #[test]
    fn parse_ticket_accepts_lowercase_base32_and_whitespace() {
        let (code, _) = make_code("deadbeef");
        let sloppy = format!("  {}  ", code.to_ascii_lowercase());
        // prefix is lowercase already; payload case-folds up
        assert!(parse_ticket(&sloppy).is_ok());
    }

    #[test]
    fn parse_ticket_rejects_wrong_prefix() {
        let err = parse_ticket("otherapp:ABC").unwrap_err();
        assert!(err.contains("not an arxa pairing code"), "{err}");
    }

    #[test]
    fn parse_ticket_rejects_bad_base32() {
        let err = parse_ticket("arxa-pair:!!!not-base32!!!").unwrap_err();
        assert!(err.contains("base32"), "{err}");
    }

    #[test]
    fn parse_ticket_rejects_malformed_json() {
        let payload = data_encoding::BASE32_NOPAD.encode(b"{not json");
        let err = parse_ticket(&format!("{TICKET_PREFIX}{payload}")).unwrap_err();
        assert!(err.contains("JSON is malformed"), "{err}");
    }

    #[test]
    fn parse_ticket_rejects_invalid_node_ticket() {
        let json = serde_json::json!({ "node": "not-a-ticket", "token": "abc" });
        let payload = data_encoding::BASE32_NOPAD.encode(json.to_string().as_bytes());
        let err = parse_ticket(&format!("{TICKET_PREFIX}{payload}")).unwrap_err();
        assert!(err.contains("invalid iroh endpoint ticket"), "{err}");
    }

    #[test]
    fn parse_ticket_rejects_empty_token() {
        let secret = iroh::SecretKey::generate();
        let addr = iroh::EndpointAddr::from(secret.public());
        let ticket = EndpointTicket::from(addr);
        let json = serde_json::json!({ "node": ticket.to_string(), "token": "" });
        let payload = data_encoding::BASE32_NOPAD.encode(json.to_string().as_bytes());
        let err = parse_ticket(&format!("{TICKET_PREFIX}{payload}")).unwrap_err();
        assert!(err.contains("missing the auth token"), "{err}");
    }

    #[test]
    fn auth_frame_shape() {
        assert_eq!(auth_frame("tok123", "iPhone 15 Pro"), "AUTH tok123 iPhone 15 Pro\n");
        // exactly one trailing newline, no interior newlines from us
        let f = auth_frame("t", "n");
        assert!(f.ends_with('\n') && f.matches('\n').count() == 1);
    }

    #[test]
    fn push_frame_shape() {
        assert_eq!(
            push_frame("sess", "apns", "devicetoken"),
            "PUSH sess apns devicetoken\n"
        );
        let f = push_frame("s", "fcm", "t");
        assert!(f.starts_with("PUSH ") && f.ends_with('\n'));
    }

    #[test]
    fn ok_reply_detection() {
        assert!(is_ok_reply(b"OK\n"));
        assert!(!is_ok_reply(b"NO\n"));
        assert!(!is_ok_reply(b"OK "));
    }

    #[test]
    fn pinned_constants() {
        // The spec pins these; a drift here is a protocol break, not a tune-up.
        assert_eq!(AUTH_TIMEOUT, Duration::from_secs(15));
        assert_eq!(RECONNECT_BACKOFF, Duration::from_secs(3));
        assert_eq!(FRESH_DIAL_ATTEMPTS, 2);
        assert_eq!(RECONNECT_DIAL_ATTEMPTS, 5);
        assert_eq!(ALPN, b"arxa/studio/0");
        assert_eq!(TICKET_PREFIX, "arxa-pair:");
    }
}
