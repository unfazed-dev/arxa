//! M7 push-token registration over the pairing tunnel (plan track B3): the
//! wire contract the mobile side's register_push_over_tunnel sends and the
//! desktop's PUSH branch answers. Self-contained on purpose (integration
//! tests are separate crates): the same hermetic-recipe endpoints and
//! stand-in engine as pairing_conformance.rs, both sides running the
//! shipped code.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::AtomicU32;
use std::sync::Arc;
use std::time::Duration;

use arxa_desktop_lib::pairing::{Pairing as DesktopPairing, ALPN};
use arxa_mobile_lib::connection::{establish, parse_ticket, Pairing as MobilePairing};
use iroh::endpoint::presets;
use iroh::{Endpoint, EndpointAddr, RelayMode, TransportAddr};
use tokio::time::timeout;

const STEP: Duration = Duration::from_secs(20);

async fn step<F: std::future::Future>(f: F) -> F::Output {
    timeout(STEP, f).await.expect("push step timed out")
}

async fn hermetic_endpoint(secret: Option<iroh::SecretKey>) -> Endpoint {
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

struct Rig {
    desktop: DesktopPairing,
    desktop_ep: Endpoint,
    store_dir: PathBuf,
    serve: tokio::task::JoinHandle<()>,
    engine: tokio::task::JoinHandle<()>,
    _counter: Arc<AtomicU32>,
}

impl Rig {
    async fn start() -> Self {
        let engine_listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .expect("engine bind");
        let engine_hp = engine_listener
            .local_addr()
            .expect("engine addr")
            .to_string();
        let engine = tokio::spawn(async move {
            while let Ok((_sock, _)) = engine_listener.accept().await {
                // One accept is enough for the auth stream's TCP side; the
                // bridge may open a connection per stream and drop it.
            }
        });
        let store_dir = std::env::temp_dir().join(format!(
            "arxa-push-conf-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&store_dir).unwrap();
        let (desktop, secret, secret_hex) =
            DesktopPairing::load(store_dir.join("pairing.json"), engine_hp.clone());
        let desktop_ep = hermetic_endpoint(Some(secret)).await;
        let serve = tokio::spawn({
            let desktop = desktop.clone();
            let endpoint = desktop_ep.clone();
            async move { desktop.serve(endpoint, secret_hex).await }
        });
        Rig {
            desktop,
            desktop_ep,
            store_dir,
            serve,
            engine,
            _counter: Arc::new(AtomicU32::new(0)),
        }
    }

    fn mint_local(&self) -> (MobilePairing, iroh_tickets::endpoint::EndpointTicket) {
        let (ticket, _expires) = self
            .desktop
            .mint_ticket_for(loopback_addr(&self.desktop_ep));
        let pairing = parse_ticket(&ticket).expect("mobile parses a desktop ticket");
        let endpoint_ticket = pairing.node.parse().expect("EndpointTicket string");
        (pairing, endpoint_ticket)
    }
}

impl Drop for Rig {
    fn drop(&mut self) {
        self.serve.abort();
        self.engine.abort();
        let _ = std::fs::remove_dir_all(&self.store_dir);
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn push_stream_registers_token_and_persists() {
    let rig = Rig::start().await;
    let (pairing, ticket) = rig.mint_local();
    let mobile_ep = hermetic_endpoint(None).await;

    let conn = step(establish(&mobile_ep, &ticket, &pairing.token))
        .await
        .expect("auth (promotes the ticket)");
    drop(conn);

    let conn2 = step(establish(&mobile_ep, &ticket, &pairing.token))
        .await
        .expect("reauth for the push stream");
    let (mut send, mut recv) = step(conn2.open_bi()).await.expect("open push stream");
    send.write_all(format!("PUSH {} fcm test-fcm-token-123\n", pairing.token).as_bytes())
        .await
        .expect("write PUSH");
    let _ = send.finish();
    let mut ok = [0u8; 3];
    step(recv.read_exact(&mut ok)).await.expect("read OK");
    assert_eq!(&ok, b"OK\n", "desktop must ACK a valid PUSH frame");

    let tokens = rig.desktop.device_push_tokens();
    assert_eq!(tokens.len(), 1, "exactly one device token stored");
    assert_eq!(tokens[0].1, "fcm");
    assert_eq!(tokens[0].2, "test-fcm-token-123");
    drop(conn2);
    mobile_ep.close().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn push_stream_with_wrong_session_token_gets_no_ok() {
    let rig = Rig::start().await;
    let (pairing, ticket) = rig.mint_local();
    let mobile_ep = hermetic_endpoint(None).await;

    let conn = step(establish(&mobile_ep, &ticket, &pairing.token))
        .await
        .expect("auth");
    let (mut send, mut recv) = step(conn.open_bi()).await.expect("open push stream");
    send.write_all(b"PUSH wrong-session-token apns deadbeef\n")
        .await
        .expect("write PUSH");
    let _ = send.finish();
    let mut buf = [0u8; 3];
    let n = match step(recv.read_exact(&mut buf)).await {
        Ok(()) => buf.len(),
        Err(iroh::endpoint::ReadExactError::FinishedEarly(n)) => n,
        Err(e) => panic!("read error: {e}"),
    };
    assert_eq!(n, 0, "a PUSH with a wrong session token closes silently");
    let tokens = rig.desktop.device_push_tokens();
    assert!(tokens.is_empty(), "nothing persists from a rejected PUSH");
    drop(conn);
    mobile_ep.close().await;
}
