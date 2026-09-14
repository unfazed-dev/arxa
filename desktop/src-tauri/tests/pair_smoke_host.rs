//! Headless pairing host for the lens E2E smoke (evidence harness, not CI).
//!
//! Runs the real desktop pairing stack — `Pairing::load` + iroh accept loop —
//! but points the engine hostport at the live studio dev server on
//! `127.0.0.1:7891`, so an authed mobile session proxies the actual studio UI.
//! Prints the minted `arxa-pair:` ticket to stdout and to
//! `$ARXA_SMOKE_TICKET_OUT` (if set), then serves until the process is killed
//! or `HOLD_SECS` (default 900) elapses.
//!
//! Run: `ARXA_SMOKE_ENGINE_HP=127.0.0.1:7891 cargo test --test pair_smoke_host -- --ignored --nocapture`

use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;

use arxa_desktop_lib::pairing::{Pairing as DesktopPairing, ALPN};
use iroh::endpoint::presets;
use iroh::{Endpoint, EndpointAddr, RelayMode, SecretKey, TransportAddr};

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

#[tokio::test(flavor = "multi_thread")]
#[ignore = "long-running evidence harness, run explicitly with --ignored"]
async fn host_pairing_for_smoke() {
    let engine_hp =
        std::env::var("ARXA_SMOKE_ENGINE_HP").unwrap_or_else(|_| "127.0.0.1:7891".to_string());
    let hold_secs: u64 = std::env::var("HOLD_SECS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(900);

    let store_dir = std::env::temp_dir().join(format!("arxa-pair-smoke-{}", std::process::id()));
    std::fs::create_dir_all(&store_dir).expect("temp store dir");
    let store: PathBuf = store_dir.join("pairing.json");

    let (desktop, secret, secret_hex) = DesktopPairing::load(store, engine_hp.clone());
    let desktop_ep = hermetic_endpoint(Some(secret)).await;
    let serve = tokio::spawn({
        let desktop = desktop.clone();
        let endpoint = desktop_ep.clone();
        async move { desktop.serve(endpoint, secret_hex).await }
    });

    let (ticket, expires) = desktop.mint_ticket_for(loopback_addr(&desktop_ep));
    println!("SMOKE_TICKET={ticket}");
    println!("SMOKE_TICKET_EXPIRES={expires}");
    println!("SMOKE_ENGINE_HP={engine_hp}");
    if let Ok(out) = std::env::var("ARXA_SMOKE_TICKET_OUT") {
        std::fs::write(&out, &ticket).expect("write ticket file");
        println!("SMOKE_TICKET_FILE={out}");
    }

    // Report pairing state every 15s so the log shows when AUTH lands.
    let mut elapsed = 0u64;
    while elapsed < hold_secs {
        tokio::time::sleep(Duration::from_secs(15)).await;
        elapsed += 15;
        let ids = desktop.paired_ids();
        println!("SMOKE_T+{elapsed}s paired_ids={ids:?}");
    }

    serve.abort();
    let _ = std::fs::remove_dir_all(&store_dir);
}
