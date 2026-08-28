//! Mobile device pairing over iroh (docs/plans/mobile-pairing-transport.md).
//!
//! Wire contract (pinned in the plan — do not change):
//! - Ticket: QR encodes `arxa-pair:<base32(json)>` (RFC 4648 BASE32, upper,
//!   no padding) where json = `{"node": <iroh EndpointTicket>, "token": <32-byte hex>}`.
//!   Single-use, 10-minute expiry, minted per QR display.
//! - Transport: iroh bidirectional streams, ALPN `arxa/studio/0`.
//! - First frame from phone: `AUTH <token> [device-name]\n` (name optional,
//!   rest-of-line); we reply `OK\n` or close.
//! - After auth the stream carries raw HTTP/1.1, piped to the local engine
//!   HTTP server (same host:port the shell itself probes). The desktop side
//!   rewrites each request's `Host` header to the engine host:port (agreed
//!   with mobile-transport — phones never learn the engine address); response
//!   bytes pass through untouched.
//! - First successful use of a QR token promotes that same token to the
//!   long-lived session token bound to the peer's EndpointId. Reconnects send
//!   the same `AUTH` line; revoking a device deletes the binding.
//! - Persistence is local-only JSON in the app's local data dir. No Arxa
//!   Digital Solutions database involvement (ownership boundary — CLAUDE.md).

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use data_encoding::{BASE32_NOPAD, HEXLOWER};
use iroh::endpoint::presets;
use iroh::{Endpoint, EndpointAddr, SecretKey};
use iroh_tickets::endpoint::EndpointTicket;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};
use tokio::io::AsyncWriteExt;

/// ALPN for the pairing + bridge protocol (plan contract).
pub const ALPN: &[u8] = b"arxa/studio/0";
/// Single-use ticket lifetime (plan contract: 10 minutes).
const TICKET_TTL: Duration = Duration::from_secs(600);
/// Max length of the `AUTH <token>` line we are willing to read.
const MAX_AUTH_LINE: usize = 256;
/// Store file name inside the app local data dir.
const STORE_FILE: &str = "pairing.json";

/// A paired mobile device: EndpointId + promoted session token, local-only.
#[derive(Serialize, Deserialize, Clone)]
pub struct PairedPeer {
    node_id: String,
    session_token: String,
    label: String,
    created_at: u64,
    /// The device's push token (FCM registration token / APNs device
    /// token), registered over the tunnel at pair time (M7). Absent for
    /// devices that never sent one (older mobile builds, push declined).
    #[serde(default)]
    push_platform: Option<String>,
    #[serde(default)]
    push_token: Option<String>,
}

/// On-disk shape: the endpoint's stable secret key plus paired devices.
#[derive(Serialize, Deserialize, Default)]
struct StoreFile {
    secret_key_hex: Option<String>,
    peers: Vec<PairedPeer>,
}

/// The QR ticket currently on display, if any. Single-use: consumed on the
/// first successful `AUTH`, dropped on expiry or when a new one is minted.
struct ActiveTicket {
    token: String,
    minted_at: Instant,
    expires_at_ms: u64,
}

struct Inner {
    /// Set once the iroh endpoint has bound (async, shortly after launch).
    endpoint: Mutex<Option<Endpoint>>,
    active: Mutex<Option<ActiveTicket>>,
    peers: Mutex<Vec<PairedPeer>>,
    store_path: PathBuf,
    /// `host:port` of the local engine HTTP server the bridge forwards to.
    engine_hp: String,
    /// How to reach a supervised cairn-pushd (M7). Attached by
    /// pushd::init after this state exists; `None` = push not wired
    /// (no binary, spawn failed) — registration still persists to
    /// pairing.json and re-registers whenever a pushd appears.
    pushd: Mutex<Option<crate::pushd::PushdHandle>>,
}

/// Managed Tauri state wrapper — and the headless core of this module.
///
/// Every wire-facing operation (load, mint, serve, revoke) is a method here so
/// that the pairing conformance test (`tests/pairing_conformance.rs`) can drive
/// the real code with an injected endpoint instead of a GUI app. The Tauri
/// commands below are thin wrappers over the same methods.
#[derive(Clone)]
pub struct Pairing(Arc<Inner>);

impl Pairing {
    /// Build the pairing core over `store_path`, restoring previously paired
    /// devices, and bridging authed streams to the engine at `engine_hp`.
    ///
    /// Returns the core plus the endpoint secret key to bind with (restored
    /// from the store, or freshly generated and written back) and its hex
    /// encoding, which `serve` needs to re-persist the store after a pairing.
    pub fn load(store_path: PathBuf, engine_hp: String) -> (Self, SecretKey, String) {
        let store = load_store(&store_path);
        // Stable endpoint identity across restarts, otherwise the EndpointAddr a
        // phone stored from its QR would go stale on every desktop relaunch.
        let secret = store
            .secret_key_hex
            .as_deref()
            .and_then(|h| HEXLOWER.decode(h.as_bytes()).ok())
            .and_then(|b| <[u8; 32]>::try_from(b.as_slice()).ok())
            .map(|b| SecretKey::from_bytes(&b))
            .unwrap_or_else(SecretKey::generate);
        let secret_hex = HEXLOWER.encode(&secret.to_bytes());
        let inner = Arc::new(Inner {
            endpoint: Mutex::new(None),
            active: Mutex::new(None),
            peers: Mutex::new(store.peers),
            store_path,
            engine_hp,
            pushd: Mutex::new(None),
        });
        // Write the store back immediately so the secret key survives even if
        // the user never pairs a device this session.
        persist(&inner, &secret_hex);
        (Pairing(inner), secret, secret_hex)
    }

    /// Publish the bound endpoint (so `pairing_begin` can mint against it) and
    /// run the accept loop until the endpoint stops accepting.
    pub async fn serve(&self, endpoint: Endpoint, secret_hex: String) {
        let inner = self.0.clone();
        if let Ok(mut guard) = inner.endpoint.lock() {
            guard.replace(endpoint.clone());
        }
        while let Some(incoming) = endpoint.accept().await {
            let inner = inner.clone();
            let persist_hex = secret_hex.clone();
            // `tokio::spawn` picks up the ambient runtime, which in the app is
            // exactly the `tauri::async_runtime` this loop was spawned onto.
            tokio::spawn(async move {
                let conn = match incoming.await {
                    Ok(c) => c,
                    Err(e) => {
                        eprintln!("[arxa-desktop] pairing conn failed: {e}");
                        return;
                    }
                };
                let remote = conn.remote_id().to_string();
                // Each stream is one authed bridge session; a device opens as
                // many as its loopback proxy needs.
                loop {
                    match conn.accept_bi().await {
                        Ok((send, recv)) => {
                            let inner = inner.clone();
                            let remote = remote.clone();
                            let persist_hex = persist_hex.clone();
                            tokio::spawn(async move {
                                if let Err(e) =
                                    handle_stream(inner, remote, persist_hex, send, recv).await
                                {
                                    eprintln!("[arxa-desktop] pairing stream: {e}");
                                }
                            });
                        }
                        Err(_) => break, // connection closed
                    }
                }
            });
        }
    }

    /// Mint a fresh single-use ticket advertising `addr`, replacing any ticket
    /// currently on display. Returns the `arxa-pair:` string and its expiry.
    ///
    /// The address is a parameter rather than read off the endpoint so tests
    /// can pin a loopback-only address; the encoded bytes are identical either
    /// way.
    pub fn mint_ticket_for(&self, addr: EndpointAddr) -> (String, u64) {
        let inner = &self.0;
        // 32 random bytes; a freshly generated key is a CSPRNG draw.
        let token = HEXLOWER.encode(&SecretKey::generate().to_bytes());
        let expires_at_ms = now_ms() + TICKET_TTL.as_millis() as u64;
        if let Ok(mut guard) = inner.active.lock() {
            guard.replace(ActiveTicket {
                token: token.clone(),
                minted_at: Instant::now(),
                expires_at_ms,
            });
        }
        let node_ticket = EndpointTicket::new(addr).to_string();
        let json = serde_json::json!({ "node": node_ticket, "token": token }).to_string();
        let ticket = format!("arxa-pair:{}", BASE32_NOPAD.encode(json.as_bytes()));
        (ticket, expires_at_ms)
    }

    /// EndpointIds of the devices currently holding a session token.
    pub fn paired_ids(&self) -> Vec<String> {
        self.0
            .peers
            .lock()
            .map(|peers| peers.iter().map(|p| p.node_id.clone()).collect())
            .unwrap_or_default()
    }

    /// Unpair a device: its session token stops working immediately, so the
    /// next stream it opens is closed without an `OK\n`.
    pub fn revoke(&self, node_id: &str) -> Result<(), String> {
        let inner = &self.0;
        {
            let mut peers = inner.peers.lock().map_err(|_| "state poisoned")?;
            peers.retain(|p| p.node_id != node_id);
        }
        let secret_hex = load_store(&inner.store_path)
            .secret_key_hex
            .unwrap_or_default();
        persist(inner, &secret_hex);
        Ok(())
    }

    /// Store a device's push token (the PUSH-stream registration path, M7).
    /// Returns Ok(false) when the (peer, session token) pair is not a
    /// currently-paired binding — the caller closes the stream without
    /// `OK\n`'ing, same contract as a failed AUTH.
    pub fn set_push_token(
        &self,
        remote: &str,
        session_token: &str,
        platform: &str,
        push_token: &str,
    ) -> Result<bool, String> {
        let inner = &self.0;
        let changed = {
            let mut peers = inner.peers.lock().map_err(|_| "state poisoned")?;
            match peers
                .iter_mut()
                .find(|p| p.node_id == remote && p.session_token == session_token)
            {
                Some(p) => {
                    let same = p.push_platform.as_deref() == Some(platform)
                        && p.push_token.as_deref() == Some(push_token);
                    if !same {
                        p.push_platform = Some(platform.to_string());
                        p.push_token = Some(push_token.to_string());
                        true
                    } else {
                        false
                    }
                }
                None => return Ok(false),
            }
        };
        if changed {
            let secret_hex = load_store(&inner.store_path)
                .secret_key_hex
                .unwrap_or_default();
            persist(inner, &secret_hex);
        }
        Ok(true)
    }

    /// Attach the supervised pushd's reachability (bind + bearer key) so
    /// PUSH registrations can forward into its registry (M7). Called by
    /// pushd::init once it knows where the daemon lives.
    pub fn attach_pushd(&self, handle: crate::pushd::PushdHandle) {
        let _ = self
            .0
            .pushd
            .lock()
            .map(|mut guard| guard.replace(handle));
    }

    /// Every stored device push token: (node_id, platform, token). pushd's
    /// SQLite registry is disposable; THIS is the durable source of truth —
    /// the supervisor re-registers the full set whenever pushd (re)starts.
    pub fn device_push_tokens(&self) -> Vec<(String, String, String)> {
        self.0
            .peers
            .lock()
            .map(|peers| {
                peers
                    .iter()
                    .filter_map(|p| {
                        Some((
                            p.node_id.clone(),
                            p.push_platform.clone()?,
                            p.push_token.clone()?,
                        ))
                    })
                    .collect()
            })
            .unwrap_or_default()
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn load_store(path: &PathBuf) -> StoreFile {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn persist(inner: &Inner, secret_key_hex: &str) {
    let peers = inner.peers.lock().map(|p| p.clone()).unwrap_or_default();
    let store = StoreFile {
        secret_key_hex: Some(secret_key_hex.to_string()),
        peers,
    };
    if let Ok(json) = serde_json::to_string_pretty(&store) {
        if let Err(e) = std::fs::write(&inner.store_path, json) {
            eprintln!("[arxa-desktop] pairing store write failed: {e}");
        }
    }
}

/// Set up pairing state and start the iroh endpoint + accept loop.
/// Called once from `setup`. `engine_hp` is `host:port` of the engine server.
pub fn init(app: &AppHandle, engine_hp: String) {
    let data_dir = match app.path().app_local_data_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("[arxa-desktop] pairing disabled: no app data dir: {e}");
            return;
        }
    };
    if let Err(e) = std::fs::create_dir_all(&data_dir) {
        eprintln!("[arxa-desktop] pairing disabled: cannot create data dir: {e}");
        return;
    }
    let store_path = data_dir.join(STORE_FILE);
    let (pairing, secret, secret_hex) = Pairing::load(store_path, engine_hp);
    app.manage(pairing.clone());

    tauri::async_runtime::spawn(async move {
        let endpoint = match Endpoint::builder(presets::N0)
            .secret_key(secret)
            .alpns(vec![ALPN.to_vec()])
            .bind()
            .await
        {
            Ok(ep) => ep,
            Err(e) => {
                eprintln!("[arxa-desktop] pairing endpoint bind failed: {e}");
                return;
            }
        };
        pairing.serve(endpoint, secret_hex).await;
    });
}

/// Strip control chars, cap length, and drop empty/placeholder names so a
/// phone can never inject garbage into the paired-devices list.
fn sanitize_label(raw: &str) -> Option<String> {
    let cleaned: String = raw
        .chars()
        .filter(|c| !c.is_control())
        .take(64)
        .collect::<String>()
        .trim()
        .to_string();
    if cleaned.is_empty() || cleaned.eq_ignore_ascii_case("localhost") {
        None
    } else {
        Some(cleaned)
    }
}

/// Verify the `AUTH` token for `remote`. Returns true when authorized,
/// promoting a live single-use ticket into a stored session token. `label`
/// is the phone's self-reported device name; when present it names the peer
/// on first pairing and refreshes the stored name on reconnect (device
/// renames propagate).
fn authorize(
    inner: &Inner,
    remote: &str,
    token: &str,
    label: Option<&str>,
    persist_hex: &str,
) -> bool {
    // NOTE: closing without `OK\n` is the revocation signal — mobile deletes
    // its stored pairing on it. So this function must only return false for a
    // genuinely wrong/expired token, never for an internal error: poisoned
    // locks are recovered (into_inner) rather than failing verification.

    // 1. Active single-use ticket → consume + promote (first pairing).
    let promoted = {
        let mut guard = inner
            .active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        match guard.as_ref() {
            Some(t) if t.token == token && t.minted_at.elapsed() < TICKET_TTL => {
                guard.take();
                true
            }
            _ => false,
        }
    };
    if promoted {
        {
            let mut peers = inner
                .peers
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            peers.retain(|p| p.node_id != remote);
            let label = label
                .map(str::to_string)
                .unwrap_or_else(|| format!("Mobile device {}", &remote[..remote.len().min(8)]));
            peers.push(PairedPeer {
                node_id: remote.to_string(),
                session_token: token.to_string(),
                label,
                created_at: now_ms(),
                push_platform: None,
                push_token: None,
            });
        }
        persist(inner, persist_hex);
        return true;
    }
    // 2. Stored session token bound to this EndpointId (reconnect). A fresh
    // self-reported name replaces the stored label (persist only on change —
    // this runs on every proxied stream).
    let (authed, label_changed) = {
        let mut peers = inner
            .peers
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        match peers
            .iter_mut()
            .find(|p| p.node_id == remote && p.session_token == token)
        {
            Some(p) => {
                let changed = match label {
                    Some(l) if p.label != l => {
                        p.label = l.to_string();
                        true
                    }
                    _ => false,
                };
                (true, changed)
            }
            None => (false, false),
        }
    };
    if label_changed {
        persist(inner, persist_hex);
    }
    authed
}

/// One authed stream: read `AUTH <token> [device-name]\n`, reply `OK\n`,
/// then pipe raw bytes to/from a fresh TCP connection to the engine HTTP
/// server.
async fn handle_stream(
    inner: Arc<Inner>,
    remote: String,
    persist_hex: String,
    mut send: iroh::endpoint::SendStream,
    mut recv: iroh::endpoint::RecvStream,
) -> Result<(), String> {
    // Read exactly up to the first newline so no HTTP bytes are swallowed.
    let mut line = Vec::with_capacity(80);
    let mut byte = [0u8; 1];
    loop {
        recv.read_exact(&mut byte)
            .await
            .map_err(|e| format!("auth read: {e}"))?;
        if byte[0] == b'\n' {
            break;
        }
        line.push(byte[0]);
        if line.len() > MAX_AUTH_LINE {
            return Err("auth line too long".into());
        }
    }
    let line = String::from_utf8_lossy(&line);
    // M7 push registration (plan track B3): `PUSH <session-token>
    // <platform> <push-token>\n` on its own stream — the phone sends it
    // right after a successful AUTH'd connection, so an OLD desktop (which
    // never sees this frame) is unaffected: it closes the stream as a
    // malformed AUTH, and the phone treats a PUSH-stream close as benign,
    // NEVER as the revocation signal (that is an AUTH-stream-only contract).
    if let Some(rest) = line.strip_prefix("PUSH ") {
        let rest = rest.trim_end_matches('\r').trim();
        let mut parts = rest.split(' ');
        let (Some(session), Some(platform), Some(push_token), None) =
            (parts.next(), parts.next(), parts.next(), parts.next())
        else {
            return Err("malformed PUSH frame".into());
        };
        let pairing = Pairing(inner.clone());
        let accepted = pairing
            .set_push_token(&remote, session, platform, push_token)
            .map_err(|e| format!("push store: {e}"))?;
        if !accepted {
            // Unknown binding — same no-reply close as a failed AUTH.
            return Err(format!("rejected PUSH from {remote}"));
        }
        // Best-effort forward into pushd's registry; the durable record is
        // pairing.json (the supervisor re-registers on every pushd boot),
        // so a down daemon is not an error — just a deferred registration.
        let pushd = inner
            .pushd
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone();
        if let Some(h) = pushd {
            if let Err(e) =
                crate::pushd::register_token_blocking(&h.bind, &h.key, platform, push_token, &remote)
            {
                eprintln!("[arxa-desktop] push token forward to pushd deferred: {e}");
            }
        }
        send.write_all(b"OK\n")
            .await
            .map_err(|e| format!("push ack: {e}"))?;
        let _ = send.finish();
        return Ok(());
    }
    let rest = match line.strip_prefix("AUTH ") {
        Some(t) => t.trim_end_matches('\r').trim(),
        None => return Err("malformed auth frame".into()),
    };
    // `AUTH <token> [device-name]` — the token never contains spaces, so
    // everything after the first space is the phone's self-reported name
    // (optional: older clients send the bare-token form).
    let (token, label) = match rest.split_once(' ') {
        Some((t, l)) => (t, sanitize_label(l)),
        None => (rest, None),
    };
    if !authorize(&inner, &remote, token, label.as_deref(), &persist_hex) {
        // Contract: bad/expired token → close without replying.
        return Err(format!("rejected token from {remote}"));
    }
    send.write_all(b"OK\n")
        .await
        .map_err(|e| format!("auth ack: {e}"))?;

    let tcp = tokio::net::TcpStream::connect(inner.engine_hp.as_str())
        .await
        .map_err(|e| format!("engine connect {}: {e}", inner.engine_hp))?;
    let (mut engine_rd, mut engine_wr) = tcp.into_split();

    // Uplink rewrites the Host header to the engine's host:port (the phone
    // must not know the engine address — agreed with mobile-transport);
    // downlink is untouched. Half-closes propagate so HTTP framing works.
    let engine_hp = inner.engine_hp.clone();
    let up = async {
        let rd = tokio::io::BufReader::new(recv);
        let r = pipe_uplink(rd, &mut engine_wr, &engine_hp).await;
        let _ = engine_wr.shutdown().await;
        r
    };
    let down = async {
        let r = tokio::io::copy(&mut engine_rd, &mut send).await;
        let _ = send.shutdown().await;
        r.map(|_| ())
    };
    let (a, b) = tokio::join!(up, down);
    a.map_err(|e| format!("uplink: {e}"))?;
    b.map_err(|e| format!("downlink: {e}"))?;
    Ok(())
}

/// Forward HTTP/1.1 requests from the phone to the engine, rewriting the
/// `Host` header of each request head to `engine_hp`. Understands just enough
/// framing to find request boundaries on a keep-alive stream:
/// - `Content-Length` bodies are copied byte-exact,
/// - `Transfer-Encoding: chunked` bodies are copied chunk-by-chunk
///   (trailers included),
/// - `Upgrade:` requests (e.g. WebSocket) switch to a raw pipe after the
///   rewritten head — from then on bytes pass through untouched.
async fn pipe_uplink<R, W>(
    mut rd: tokio::io::BufReader<R>,
    mut wr: W,
    engine_hp: &str,
) -> std::io::Result<()>
where
    R: tokio::io::AsyncRead + Unpin,
    W: tokio::io::AsyncWrite + Unpin,
{
    use tokio::io::{AsyncBufReadExt, AsyncReadExt};
    const MAX_HEAD: usize = 64 * 1024;
    'requests: loop {
        // --- request line ---
        let mut line = Vec::new();
        if rd.read_until(b'\n', &mut line).await? == 0 {
            return Ok(()); // clean EOF between requests
        }
        let mut head: Vec<Vec<u8>> = vec![std::mem::take(&mut line)];
        let mut content_length: u64 = 0;
        let mut chunked = false;
        let mut upgrade = false;
        // --- header lines until the blank line ---
        loop {
            if rd.read_until(b'\n', &mut line).await? == 0 {
                break; // truncated head: forward what we have, EOF ends loop
            }
            let l = std::mem::take(&mut line);
            let is_blank = l.as_slice() == b"\r\n" || l.as_slice() == b"\n";
            if !is_blank {
                let lower = String::from_utf8_lossy(&l).to_ascii_lowercase();
                if lower.starts_with("host:") {
                    head.push(format!("Host: {engine_hp}\r\n").into_bytes());
                    continue;
                } else if lower.starts_with("origin:") {
                    // The engine's /api gate requires Origin host == Host header
                    // (dsh isTrustedApiRequest). The phone's page origin is its
                    // local proxy (http://127.0.0.1:<port>), so without this
                    // rewrite every WebSocket downlink 403s and the UI boots
                    // empty. Rewrite Origin to match the rewritten Host.
                    head.push(format!("Origin: http://{engine_hp}\r\n").into_bytes());
                    continue;
                } else if let Some(v) = lower.strip_prefix("content-length:") {
                    content_length = v.trim().parse().unwrap_or(0);
                } else if let Some(v) = lower.strip_prefix("transfer-encoding:") {
                    chunked = chunked || v.contains("chunked");
                } else if lower.starts_with("upgrade:") {
                    upgrade = true;
                }
            }
            head.push(l);
            if is_blank {
                break;
            }
            if head.iter().map(|h| h.len()).sum::<usize>() > MAX_HEAD {
                return Err(std::io::Error::other("request head too large"));
            }
        }
        for h in &head {
            wr.write_all(h).await?;
        }
        // --- body ---
        if upgrade {
            // Protocol switch (WebSocket etc.): raw passthrough from here on,
            // including whatever BufReader still holds.
            tokio::io::copy(&mut rd, &mut wr).await?;
            return Ok(());
        }
        if chunked {
            loop {
                let mut size_line = Vec::new();
                if rd.read_until(b'\n', &mut size_line).await? == 0 {
                    return Ok(());
                }
                wr.write_all(&size_line).await?;
                let hex_owned = String::from_utf8_lossy(&size_line).into_owned();
                let hex = hex_owned.trim().split(';').next().unwrap_or("").trim();
                let size = u64::from_str_radix(hex, 16)
                    .map_err(|_| std::io::Error::other("bad chunk size"))?;
                if size > 0 {
                    // chunk data + trailing CRLF
                    let mut chunk = (&mut rd).take(size + 2);
                    tokio::io::copy(&mut chunk, &mut wr).await?;
                } else {
                    // trailers (if any) up to and including the blank line
                    loop {
                        let mut t = Vec::new();
                        if rd.read_until(b'\n', &mut t).await? == 0 {
                            return Ok(());
                        }
                        wr.write_all(&t).await?;
                        if t.as_slice() == b"\r\n" || t.as_slice() == b"\n" {
                            break;
                        }
                    }
                    continue 'requests;
                }
            }
        }
        if content_length > 0 {
            let mut body = (&mut rd).take(content_length);
            tokio::io::copy(&mut body, &mut wr).await?;
        }
    }
}

#[derive(Serialize)]
pub struct BeginResponse {
    ticket: String,
    qr_svg: String,
    expires_at_ms: u64,
}

/// Mint a fresh single-use ticket and render its QR locally (no network).
#[tauri::command]
pub fn pairing_begin(state: State<'_, Pairing>) -> Result<BeginResponse, String> {
    let inner = &state.0;
    let endpoint = inner
        .endpoint
        .lock()
        .ok()
        .and_then(|g| g.clone())
        .ok_or("pairing endpoint is still starting - try again in a moment")?;

    let (ticket, expires_at_ms) = state.mint_ticket_for(endpoint.addr());

    // EcLevel::Q (25% damage tolerance), not H: the ticket payload is long
    // (iroh node ticket + token), and H would push the QR several versions
    // denser — smaller modules hurt cameras more than the extra tolerance
    // helps the ~5% of modules the logo well excavates.
    let code = qrcode::QrCode::with_error_correction_level(ticket.as_bytes(), qrcode::EcLevel::Q)
        .map_err(|e| format!("qr encode: {e}"))?;
    let qr_svg = render_qr_svg_with_logo(&code);

    Ok(BeginResponse {
        ticket,
        qr_svg,
        expires_at_ms,
    })
}

/// The arxa brand mark, emitted as inline SVG content (1024x1024 viewBox).
const BRAND_MARK_1024: &str = concat!(
    r##"<path d="M391.437 195.736C445.636 104.088 578.25 104.088 632.448 195.736L922.178 685.662C977.368 778.988 910.095 896.926 801.672 896.926H222.214C113.791 896.926 46.518 778.988 101.708 685.662L391.437 195.736Z" fill="url(#qrlogo_grad)"/>"##,
    r##"<path d="M381.907 718.494L314.406 832.413H272.492C208.932 832.413 165.181 775.677 173.312 718.491L381.907 718.494ZM850.647 718.502C858.771 775.684 815.022 832.413 751.466 832.413H439.174L506.675 718.496L850.647 718.502ZM797.076 613.222L569.057 613.218L683.065 420.814L797.076 613.222ZM425.948 277.272C464.679 211.908 559.279 211.907 598.01 277.271L620.681 315.531L444.29 613.215L226.887 613.212L425.948 277.272Z" fill="#0EE4E0"/>"##,
    r##"<defs><linearGradient id="qrlogo_grad" x1="511.943" y1="127" x2="511.943" y2="896.926" gradientUnits="userSpaceOnUse"><stop stop-color="#0EBAE4"/><stop offset="1" stop-color="#08336F"/></linearGradient></defs>"##,
);

/// Module-count width (side) of the excavated center well for a symbol of
/// `w` modules: ~22% of the symbol width, parity-matched to `w` so the well
/// centers exactly on the module grid.
fn well_side(w: i32) -> i32 {
    let mut well = ((w as f64) * 0.24).round() as i32;
    if well % 2 != w % 2 {
        well += 1;
    }
    well
}

/// Render the QR to SVG with the brand logo minted into it, per QR-logo best
/// practice: instead of overlaying artwork on finished modules, a centered,
/// module-grid-aligned square well (~22% of symbol width ≈ 5% of area, well
/// inside EcLevel::Q's 25% tolerance) is excavated from the data area — the
/// finder/timing patterns at the edges are untouched — and the mark is drawn
/// inside that well with a 1-module clear margin. The logo is part of the
/// minted SVG itself, so every re-mint carries it by construction.
fn render_qr_svg_with_logo(code: &qrcode::QrCode) -> String {
    use qrcode::types::Color;

    let w = code.width() as i32;
    let colors = code.to_colors();
    const QUIET: i32 = 4; // ISO 18004 quiet zone, in modules
    let total = w + 2 * QUIET;

    let well = well_side(w);
    let start = (w - well) / 2;
    let end = start + well;

    // One path, one rect per dark module outside the well.
    let mut d = String::with_capacity(colors.len() * 12);
    for y in 0..w {
        for x in 0..w {
            let in_well = x >= start && x < end && y >= start && y < end;
            if !in_well && colors[(y * w + x) as usize] == Color::Dark {
                d.push_str(&format!("M{} {}h1v1h-1z", x + QUIET, y + QUIET));
            }
        }
    }

    // Frame: a thin black rounded-corner border just inside the well edge,
    // leaving a ~half-module white gap to the surrounding data modules so the
    // frame never merges with them optically. Drawn with the same ink as the
    // modules so it reads as part of the code, not a sticker.
    let frame_inset = 0.5f64;
    let frame_stroke = 0.45f64;
    let frame_origin = (start + QUIET) as f64 + frame_inset + frame_stroke / 2.0;
    let frame_size = well as f64 - 2.0 * (frame_inset + frame_stroke / 2.0);
    let frame_radius = 1.2f64;

    // Logo box: inside the frame with a small breathing margin.
    let logo_margin = frame_inset + frame_stroke + 0.55;
    let logo_origin = (start + QUIET) as f64 + logo_margin;
    let logo_size = well as f64 - 2.0 * logo_margin;

    // Upscale so the shell renders it crisply at >= 240 px.
    let scale = (240 + total - 1) / total;
    let dim = total * scale;

    format!(
        concat!(
            r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {t} {t}" width="{dim}" height="{dim}" shape-rendering="crispEdges">"#,
            r##"<rect width="{t}" height="{t}" fill="#fff"/>"##,
            r##"<path d="{d}" fill="#000"/>"##,
            r##"<rect x="{fo}" y="{fo}" width="{fs}" height="{fs}" rx="{fr}" fill="none" stroke="#000" stroke-width="{fw}" shape-rendering="auto"/>"##,
            r#"<svg x="{lo}" y="{lo}" width="{ls}" height="{ls}" viewBox="0 0 1024 1024" shape-rendering="auto">{mark}</svg>"#,
            r#"</svg>"#
        ),
        t = total,
        dim = dim,
        d = d,
        fo = frame_origin,
        fs = frame_size,
        fr = frame_radius,
        fw = frame_stroke,
        lo = logo_origin,
        ls = logo_size,
        mark = BRAND_MARK_1024,
    )
}

#[cfg(test)]
mod qr_logo_tests {
    use super::*;

    /// Worst-case decode check: rasterize the module matrix with the entire
    /// excavated well painted DARK (harsher than the real logo, which sits on
    /// a white well) and require a clean round-trip decode at EcLevel::Q.
    #[test]
    fn excavated_qr_still_decodes() {
        // Representative long payload (~300 bytes, like an iroh ticket + token).
        let payload: String = std::iter::repeat("nodeadbeefcafe0123456789")
            .take(13)
            .collect::<String>();
        let code =
            qrcode::QrCode::with_error_correction_level(payload.as_bytes(), qrcode::EcLevel::Q)
                .expect("encode");
        let w = code.width() as i32;
        let colors = code.to_colors();
        let well = well_side(w);
        let start = (w - well) / 2;
        let end = start + well;

        const S: i32 = 8; // px per module
        const QUIET: i32 = 4;
        let total = (w + 2 * QUIET) * S;
        let img = |px: usize, py: usize| -> u8 {
            let x = (px as i32) / S - QUIET;
            let y = (py as i32) / S - QUIET;
            if x < 0 || y < 0 || x >= w || y >= w {
                return 255; // quiet zone
            }
            let in_well = x >= start && x < end && y >= start && y < end;
            if in_well {
                return 0; // worst case: logo region fully dark
            }
            match colors[(y * w + x) as usize] {
                qrcode::types::Color::Dark => 0,
                qrcode::types::Color::Light => 255,
            }
        };
        let mut prepared = rqrr::PreparedImage::prepare_from_greyscale(
            total as usize,
            total as usize,
            img,
        );
        let grids = prepared.detect_grids();
        assert_eq!(grids.len(), 1, "QR grid not detected");
        let (_meta, content) = grids[0].decode().expect("decode");
        assert_eq!(content, payload, "excavated QR must round-trip its payload");
    }

    #[test]
    fn well_stays_within_q_budget_and_off_finders() {
        for w in [21i32, 45, 77, 89, 105] {
            let well = well_side(w);
            // parity match => exact centering
            assert_eq!(well % 2, w % 2);
            // area excavated stays under half of Q's 25% tolerance
            let frac = (well * well) as f64 / (w * w) as f64;
            assert!(frac < 0.125, "well too large: {frac} at w={w}");
            // A centered well can never reach the corner finder patterns;
            // the binding constraint is the timing pattern at row/col 6.
            let start = (w - well) / 2;
            let end = start + well;
            assert!(start > 6, "well touches timing pattern at w={w}");
            assert!(end < w - 6, "well touches timing pattern at w={w}");
        }
    }
}

#[derive(Serialize)]
pub struct PeerView {
    node_id: String,
    label: String,
    created_at: u64,
}

#[derive(Serialize)]
pub struct StatusResponse {
    endpoint_ready: bool,
    ticket_expires_at_ms: Option<u64>,
    peers: Vec<PeerView>,
}

/// Current pairing state for the UI. Never exposes tokens.
#[tauri::command]
pub fn pairing_status(state: State<'_, Pairing>) -> StatusResponse {
    let inner = &state.0;
    let endpoint_ready = inner
        .endpoint
        .lock()
        .map(|g| g.is_some())
        .unwrap_or(false);
    let ticket_expires_at_ms = inner.active.lock().ok().and_then(|g| {
        g.as_ref()
            .filter(|t| t.minted_at.elapsed() < TICKET_TTL)
            .map(|t| t.expires_at_ms)
    });
    let peers = inner
        .peers
        .lock()
        .map(|peers| {
            peers
                .iter()
                .map(|p| PeerView {
                    node_id: p.node_id.clone(),
                    label: p.label.clone(),
                    created_at: p.created_at,
                })
                .collect()
        })
        .unwrap_or_default();
    StatusResponse {
        endpoint_ready,
        ticket_expires_at_ms,
        peers,
    }
}

/// Unpair a device: its session token stops working immediately.
#[tauri::command]
pub fn pairing_revoke(state: State<'_, Pairing>, node_id: String) -> Result<(), String> {
    state.revoke(&node_id)
}
