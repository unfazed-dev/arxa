//! Headless conformance test for the desktop <-> mobile pairing wire contract
//! (`docs/plans/mobile-pairing-transport.md`).
//!
//! Both sides of the contract run in this one process, using the shipped code:
//! `arxa_desktop_lib::pairing` mints the ticket and hosts the iroh accept loop,
//! `arxa_mobile_lib::connection` parses the ticket, dials, authenticates and
//! serves the loopback proxy. Nothing here re-implements the protocol — a
//! change to either module that breaks the other fails this file.
//!
//! Hermetic: every iroh endpoint binds to `127.0.0.1:0` with
//! `RelayMode::Disabled` and the `Minimal` preset (no relays, no DNS/pkarr
//! address lookup), and the ticket advertises only the loopback socket. No
//! network, no n0 infrastructure. The endpoint is injected through the core
//! functions; the bytes on the wire are exactly what the app produces.
//!
//! What is proven, in order:
//! 1. `desktop_ticket_parses_on_the_mobile_side` — base32 flavour, JSON field
//!    names, EndpointTicket string form, prefix, TTL.
//! 2. `live_handshake_bridges_http_through_to_the_engine` — real iroh dial,
//!    `AUTH <token>\n` -> `OK\n`, and an HTTP GET through the mobile loopback
//!    proxy reaching the stand-in engine (Host header rewritten en route).
//! 3. `session_token_outlives_the_single_use_ticket` — single-use means one
//!    pairing, not one stream.
//! 4. `revoking_closes_the_next_stream_without_ok` + 5.
//!    `a_rejected_token_returns_the_mobile_session_to_not_paired` — revocation
//!    is signalled by closing with no reply, and the mobile session loop reads
//!    that as auth-reject: back to NotPaired, stored pairing cleared.
//! 6. `a_paired_session_reports_connected_with_a_loopback_studio_url` — the
//!    whole shipped mobile session loop, from ticket to `studio_url`.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use arxa_desktop_lib::pairing::{Pairing as DesktopPairing, ALPN};
use arxa_mobile_lib::connection::{
    establish, parse_ticket, run_session, start_proxy, ConnectionManager, ConnectionState,
    Pairing as MobilePairing, PairingStore, SessionError,
};
use data_encoding::BASE32_NOPAD;
use iroh::endpoint::presets;
use iroh::{Endpoint, EndpointAddr, RelayMode, SecretKey, TransportAddr};
use iroh_tickets::endpoint::EndpointTicket;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::timeout;

/// Every awaited phase is bounded: the mobile side's own AUTH timeout is 15s,
/// so an unbounded await would stall the suite instead of failing it.
const STEP: Duration = Duration::from_secs(20);

/// Bound one phase of a test. Panics with a clear message instead of hanging.
async fn step<F: std::future::Future>(f: F) -> F::Output {
    timeout(STEP, f).await.expect("pairing step timed out")
}

// ---------------------------------------------------------------------------
// Hermetic iroh endpoints
// ---------------------------------------------------------------------------

/// An endpoint that can only ever talk over loopback: no relays, no address
/// lookup services, bound to `127.0.0.1:0`.
async fn hermetic_endpoint(secret: Option<SecretKey>) -> Endpoint {
    let mut builder = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .alpns(vec![ALPN.to_vec()])
        .bind_addr("127.0.0.1:0")
        .expect("loopback bind addr");
    if let Some(secret) = secret {
        builder = builder.secret_key(secret);
    }
    builder.bind().await.expect("iroh endpoint bind")
}

/// The endpoint's address, narrowed to its loopback socket. `pairing_begin`
/// passes `endpoint.addr()` here; pinning loopback keeps the dial off the LAN
/// without changing a byte of the encoded ticket.
fn loopback_addr(ep: &Endpoint) -> EndpointAddr {
    let port = ep
        .bound_sockets()
        .into_iter()
        .find(|s| s.is_ipv4())
        .expect("an IPv4 socket")
        .port();
    let sock: SocketAddr = (std::net::Ipv4Addr::LOCALHOST, port).into();
    EndpointAddr::from_parts(ep.id(), [TransportAddr::Ip(sock)])
}

// ---------------------------------------------------------------------------
// Stand-in engine: the local HTTP server the desktop bridges authed streams to
// ---------------------------------------------------------------------------

/// Serves a fixed response and echoes back the request path and the `Host`
/// header it actually received, so the desktop's Host rewrite is observable.
async fn spawn_dummy_engine() -> (String, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.expect("engine bind");
    let host_port = listener.local_addr().expect("engine addr").to_string();
    let handle = tokio::spawn(async move {
        while let Ok((sock, _)) = listener.accept().await {
            tokio::spawn(serve_one(sock));
        }
    });
    (host_port, handle)
}

async fn serve_one(sock: TcpStream) {
    let (rd, mut wr) = sock.into_split();
    let mut rd = BufReader::new(rd);

    // The desktop opens a fresh TCP connection per authed stream — including
    // the handshake stream, which never sends an HTTP byte. EOF here is normal.
    let mut request_line = String::new();
    if rd.read_line(&mut request_line).await.unwrap_or(0) == 0 {
        return;
    }
    let path = request_line
        .split_whitespace()
        .nth(1)
        .unwrap_or("<none>")
        .to_string();

    let mut host = String::from("<none>");
    loop {
        let mut line = String::new();
        if rd.read_line(&mut line).await.unwrap_or(0) == 0 {
            break;
        }
        if line == "\r\n" || line == "\n" {
            break;
        }
        let lower = line.to_ascii_lowercase();
        if let Some(value) = lower.strip_prefix("host:") {
            host = value.trim().to_string();
        }
    }

    let body = format!("arxa-dummy-engine path={path} host={host}");
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let _ = wr.write_all(response.as_bytes()).await;
    let _ = wr.shutdown().await;
}

// ---------------------------------------------------------------------------
// Test client: speaks HTTP at the mobile side's loopback proxy
// ---------------------------------------------------------------------------

/// `Host: phone.local` is deliberately wrong for the engine — the desktop is
/// contractually required to rewrite it, and the engine echoes what it saw.
async fn http_get_raw(proxy_port: u16, path: &str) -> std::io::Result<String> {
    let mut sock = TcpStream::connect(("127.0.0.1", proxy_port)).await?;
    let request =
        format!("GET {path} HTTP/1.1\r\nHost: phone.local\r\nConnection: close\r\n\r\n");
    sock.write_all(request.as_bytes()).await?;
    // Half-close so the mobile proxy's uplink copy finishes and the desktop
    // sees a complete request.
    let _ = sock.shutdown().await;
    let mut body = String::new();
    sock.read_to_string(&mut body).await?;
    Ok(body)
}

async fn http_get(proxy_port: u16, path: &str) -> String {
    http_get_raw(proxy_port, path)
        .await
        .expect("proxied HTTP request")
}

// ---------------------------------------------------------------------------
// Harness: a desktop pairing host, live, with an engine behind it
// ---------------------------------------------------------------------------

static SEQ: AtomicU64 = AtomicU64::new(0);

fn unique_store_dir() -> PathBuf {
    let seq = SEQ.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!(
        "arxa-pairing-conformance-{}-{seq}",
        std::process::id()
    ));
    std::fs::create_dir_all(&dir).expect("temp store dir");
    dir
}

struct Harness {
    desktop: DesktopPairing,
    desktop_ep: Endpoint,
    engine_hp: String,
    store_dir: PathBuf,
    engine: tokio::task::JoinHandle<()>,
    serve: tokio::task::JoinHandle<()>,
}

impl Harness {
    async fn start() -> Self {
        let (engine_hp, engine) = spawn_dummy_engine().await;
        let store_dir = unique_store_dir();
        // Exactly the sequence `pairing::init` runs, minus the AppHandle.
        let (desktop, secret, secret_hex) =
            DesktopPairing::load(store_dir.join("pairing.json"), engine_hp.clone());
        let desktop_ep = hermetic_endpoint(Some(secret)).await;
        let serve = tokio::spawn({
            let desktop = desktop.clone();
            let endpoint = desktop_ep.clone();
            async move { desktop.serve(endpoint, secret_hex).await }
        });
        Harness {
            desktop,
            desktop_ep,
            engine_hp,
            store_dir,
            engine,
            serve,
        }
    }

    /// Mint a ticket the mobile side can dial over loopback, and pre-chew the
    /// two forms every live test needs.
    fn mint_local(&self) -> (MobilePairing, EndpointTicket) {
        let (ticket, _expires) = self.desktop.mint_ticket_for(loopback_addr(&self.desktop_ep));
        let pairing = parse_ticket(&ticket).expect("mobile parses a desktop ticket");
        let endpoint_ticket = pairing.node.parse().expect("EndpointTicket string");
        (pairing, endpoint_ticket)
    }
}

impl Drop for Harness {
    fn drop(&mut self) {
        self.serve.abort();
        self.engine.abort();
        let _ = std::fs::remove_dir_all(&self.store_dir);
    }
}

/// Stands in for the Tauri app data dir so the auth-reject branch's effect on
/// stored state is observable headlessly.
#[derive(Default)]
struct RecordingStore {
    stored: AtomicU32,
    forgotten: AtomicBool,
}

impl PairingStore for RecordingStore {
    fn store(&self, _pairing: &MobilePairing) -> Result<(), String> {
        self.stored.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
    fn forget(&self) {
        self.forgotten.store(true, Ordering::SeqCst);
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_millis() as u64
}

// ---------------------------------------------------------------------------
// 1. Ticket round-trip
// ---------------------------------------------------------------------------

#[tokio::test(flavor = "multi_thread")]
async fn desktop_ticket_parses_on_the_mobile_side() {
    let harness = Harness::start().await;

    // Mint against the endpoint's own advertised address — byte for byte what
    // `pairing_begin` produces in the shipped app.
    let advertised = harness.desktop_ep.addr();
    let issued_at = now_ms();
    let (ticket, expires_at_ms) = harness.desktop.mint_ticket_for(advertised.clone());

    let payload = ticket
        .strip_prefix("arxa-pair:")
        .expect("TICKET_PREFIX must be `arxa-pair:`");
    assert!(!payload.is_empty());
    assert!(!payload.contains('='), "BASE32_NOPAD must not pad");
    assert!(
        payload
            .bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit()),
        "payload must use the RFC 4648 uppercase base32 alphabet"
    );

    // The JSON field names are contract, not an implementation detail.
    let json = BASE32_NOPAD
        .decode(payload.as_bytes())
        .expect("payload decodes as RFC 4648 base32, no padding");
    let value: serde_json::Value = serde_json::from_slice(&json).expect("payload is JSON");
    let object = value.as_object().expect("payload is a JSON object");
    assert_eq!(object.len(), 2, "exactly `node` and `token`: {object:?}");
    assert!(object.contains_key("node"), "missing `node`: {object:?}");
    assert!(object.contains_key("token"), "missing `token`: {object:?}");

    // The real mobile parser accepts it, and recovers the desktop's address.
    let parsed = parse_ticket(&ticket).expect("mobile parse_ticket");
    assert_eq!(parsed.token.len(), 64, "32-byte token, hex encoded");
    assert!(parsed.token.bytes().all(|b| b.is_ascii_hexdigit()));
    let endpoint_ticket: EndpointTicket = parsed.node.parse().expect("EndpointTicket string form");
    assert_eq!(endpoint_ticket.endpoint_addr().id, advertised.id);
    assert_eq!(endpoint_ticket.endpoint_addr().addrs, advertised.addrs);

    // A QR scanner may hand the code back lowercased, or with stray whitespace.
    parse_ticket(&ticket.to_ascii_lowercase()).expect("case-insensitive base32");
    parse_ticket(&format!("  {ticket}\n")).expect("surrounding whitespace tolerated");

    // 10-minute TTL (plan contract).
    assert!(
        expires_at_ms >= issued_at + 599_000 && expires_at_ms <= now_ms() + 600_000,
        "ticket TTL should be ~600s, got {}ms",
        expires_at_ms.saturating_sub(issued_at)
    );

    // Junk must not parse as a pairing code.
    assert!(parse_ticket("https://example.com").is_err());
    assert!(parse_ticket(&format!("arxa-pair:{}", "!!!!")).is_err());
}

// ---------------------------------------------------------------------------
// 2. Live handshake + HTTP bridge
// ---------------------------------------------------------------------------

#[tokio::test(flavor = "multi_thread")]
async fn live_handshake_bridges_http_through_to_the_engine() {
    let harness = Harness::start().await;
    let (pairing, endpoint_ticket) = harness.mint_local();
    let mobile_ep = hermetic_endpoint(None).await;

    let conn = step(establish(&mobile_ep, &endpoint_ticket, &pairing.token))
        .await
        .expect("AUTH <token> must be answered with OK on the handshake stream");

    // The QR token has been promoted to a session token bound to this device.
    assert_eq!(
        harness.desktop.paired_ids(),
        vec![mobile_ep.id().to_string()]
    );

    let (proxy_port, proxy) = start_proxy(conn, pairing.token.clone())
        .await
        .expect("loopback proxy bind");
    let response = step(http_get(proxy_port, "/studio/index.html")).await;

    assert!(
        response.starts_with("HTTP/1.1 200 OK"),
        "response: {response}"
    );
    assert!(
        response.contains("arxa-dummy-engine"),
        "engine body must arrive intact: {response}"
    );
    assert!(
        response.contains("path=/studio/index.html"),
        "request path must survive the bridge: {response}"
    );
    assert!(
        response.contains(&format!("host={}", harness.engine_hp)),
        "desktop must rewrite Host to the engine host:port (phones never learn it): {response}"
    );

    proxy.abort();
}

// ---------------------------------------------------------------------------
// 3. Session persistence across streams
// ---------------------------------------------------------------------------

#[tokio::test(flavor = "multi_thread")]
async fn session_token_outlives_the_single_use_ticket() {
    let harness = Harness::start().await;
    let (pairing, endpoint_ticket) = harness.mint_local();
    let mobile_ep = hermetic_endpoint(None).await;

    // Stream 1 consumes the single-use QR ticket and promotes it.
    let conn = step(establish(&mobile_ep, &endpoint_ticket, &pairing.token))
        .await
        .expect("first AUTH");

    // Streams 2 and 3 send the same token. Single-use has to mean one pairing,
    // not one stream, or the loopback proxy could never open a second request.
    let (proxy_port, proxy) = start_proxy(conn, pairing.token.clone())
        .await
        .expect("loopback proxy bind");
    for path in ["/one", "/two"] {
        let response = step(http_get(proxy_port, path)).await;
        assert!(
            response.starts_with("HTTP/1.1 200 OK"),
            "{path} must also be answered OK: {response}"
        );
        assert!(response.contains(&format!("path={path}")), "{response}");
    }

    // A whole new connection authenticates too, with the ticket long consumed.
    let reconnect = step(establish(&mobile_ep, &endpoint_ticket, &pairing.token))
        .await
        .expect("reconnect with the promoted session token");
    let (reconnect_port, reconnect_proxy) = start_proxy(reconnect, pairing.token.clone())
        .await
        .expect("loopback proxy bind");
    let response = step(http_get(reconnect_port, "/three")).await;
    assert!(
        response.starts_with("HTTP/1.1 200 OK"),
        "reconnected stream: {response}"
    );

    // Still one paired device, not one per stream or per connection.
    assert_eq!(harness.desktop.paired_ids().len(), 1);

    proxy.abort();
    reconnect_proxy.abort();
}

// ---------------------------------------------------------------------------
// 4. Revocation
// ---------------------------------------------------------------------------

#[tokio::test(flavor = "multi_thread")]
async fn revoking_closes_the_next_stream_without_ok() {
    let harness = Harness::start().await;
    let (pairing, endpoint_ticket) = harness.mint_local();
    let mobile_ep = hermetic_endpoint(None).await;

    let conn = step(establish(&mobile_ep, &endpoint_ticket, &pairing.token))
        .await
        .expect("first AUTH");
    let (proxy_port, proxy) = start_proxy(conn, pairing.token.clone())
        .await
        .expect("loopback proxy bind");
    assert!(step(http_get(proxy_port, "/before"))
        .await
        .starts_with("HTTP/1.1 200 OK"));

    harness
        .desktop
        .revoke(&mobile_ep.id().to_string())
        .expect("revoke");
    assert!(harness.desktop.paired_ids().is_empty());

    // Same live connection: the next stream is closed with no `OK\n`, so the
    // mobile bridge tears down the proxied TCP connection without a reply.
    let response = step(http_get_raw(proxy_port, "/after"))
        .await
        .unwrap_or_default();
    assert!(
        response.is_empty(),
        "a revoked stream must get no reply at all, got: {response}"
    );

    // And a fresh dial is classified as auth-reject rather than unreachable —
    // that is the branch that clears the phone's stored pairing.
    let error = step(establish(&mobile_ep, &endpoint_ticket, &pairing.token))
        .await
        .expect_err("a revoked token must be rejected");
    assert!(
        matches!(error, SessionError::AuthRejected(_)),
        "expected AuthRejected, got {error:?}"
    );

    proxy.abort();
}

// ---------------------------------------------------------------------------
// 5. The mobile session loop's reaction to rejection
// ---------------------------------------------------------------------------

#[tokio::test(flavor = "multi_thread")]
async fn a_rejected_token_returns_the_mobile_session_to_not_paired() {
    let harness = Harness::start().await;
    let (mut pairing, _endpoint_ticket) = harness.mint_local();
    // A token the desktop never issued: the same rejection a revoked device
    // meets on its next dial.
    pairing.token = "0".repeat(64);

    let manager = ConnectionManager::default();
    let shared = manager.shared();
    let epoch = manager.begin_epoch();
    assert_eq!(manager.status().state, ConnectionState::Connecting);

    let store = Arc::new(RecordingStore::default());
    let mobile_ep = hermetic_endpoint(None).await;
    step(run_session(store.clone(), shared, epoch, pairing, 2, mobile_ep)).await;

    let status = manager.status();
    assert_eq!(status.state, ConnectionState::NotPaired);
    assert!(status.studio_url.is_none());
    assert!(
        store.forgotten.load(Ordering::SeqCst),
        "auth rejection must clear the stored pairing"
    );
    assert_eq!(
        store.stored.load(Ordering::SeqCst),
        0,
        "a rejected pairing must never be persisted"
    );
}

// ---------------------------------------------------------------------------
// 6. The whole shipped mobile session loop, ticket to studio_url
// ---------------------------------------------------------------------------

#[tokio::test(flavor = "multi_thread")]
async fn a_paired_session_reports_connected_with_a_loopback_studio_url() {
    let harness = Harness::start().await;
    let (pairing, _endpoint_ticket) = harness.mint_local();

    let manager = ConnectionManager::default();
    let shared = manager.shared();
    let epoch = manager.begin_epoch();
    let store = Arc::new(RecordingStore::default());
    let mobile_ep = hermetic_endpoint(None).await;

    let session = tokio::spawn(run_session(
        store.clone(),
        shared,
        epoch,
        pairing,
        2,
        mobile_ep,
    ));

    let studio_url = step(async {
        loop {
            let status = manager.status();
            if status.state == ConnectionState::Connected {
                return status.studio_url.expect("Connected implies a studio_url");
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
    })
    .await;

    assert!(
        studio_url.starts_with("http://127.0.0.1:"),
        "studio_url: {studio_url}"
    );
    let proxy_port: u16 = studio_url
        .trim_start_matches("http://127.0.0.1:")
        .trim_end_matches('/')
        .parse()
        .expect("port in studio_url");

    let response = step(http_get(proxy_port, "/live")).await;
    assert!(
        response.starts_with("HTTP/1.1 200 OK"),
        "the URL the frontend navigates to must serve the engine: {response}"
    );
    assert_eq!(
        store.stored.load(Ordering::SeqCst),
        1,
        "a successful pairing is persisted exactly once"
    );

    session.abort();
}
