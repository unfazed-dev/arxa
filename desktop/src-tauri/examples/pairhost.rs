//! pairhost — dev harness: the REAL desktop pairing core, no GUI.
//!
//! Runs arxa_desktop_lib::pairing exactly as the Tauri shell does (same
//! load → bind → serve → mint path), but headless, for the iOS-simulator
//! approvals e2e: the simulator is a separate device, so the ticket
//! advertises the host's LAN IP (default: this machine's en0) instead of
//! the conformance test's loopback pin.
//!
//! Usage:
//!   cargo run --example pairhost -- <engine host:port> [advertise ip] [store dir]
//!
//! Prints `TICKET <arxa-pair:...>` on boot and again for every stdin line
//! (tickets are single-use; repeat pairings mint fresh ones). Runs until
//! stdin closes or the process is killed.

use std::path::PathBuf;

use arxa_desktop_lib::pairing::{Pairing, ALPN};
use iroh::endpoint::presets;
use iroh::{Endpoint, EndpointAddr, RelayMode, TransportAddr};

fn lan_ip() -> Option<std::net::IpAddr> {
    // Best-effort en0/en1 lookup — the sim reaches the host over its LAN
    // address. Callers can pass an explicit IP to skip the guess.
    for iface in ["en0", "en1"] {
        if let Ok(out) = std::process::Command::new("ipconfig")
            .args(["getifaddr", iface])
            .output()
        {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if let Ok(ip) = s.parse() {
                return Some(ip);
            }
        }
    }
    None
}

#[tokio::main]
async fn main() {
    let mut args = std::env::args().skip(1);
    let engine_hp = args
        .next()
        .expect("usage: pairhost <engine host:port> [advertise ip] [store dir]");
    let advertise: std::net::IpAddr = args
        .next()
        .and_then(|s| s.parse().ok())
        .or_else(lan_ip)
        .expect("no advertise ip given and no LAN interface found");
    let store_dir = PathBuf::from(
        args.next()
            .unwrap_or_else(|| std::env::temp_dir().join("arxa-pairhost").to_string_lossy().into_owned()),
    );
    std::fs::create_dir_all(&store_dir).expect("create store dir");

    let (pairing, secret, secret_hex) =
        Pairing::load(store_dir.join("pairing.json"), engine_hp.clone());

    // Bind every interface (the sim dials the advertised LAN IP); no relays —
    // sim and host are adjacent, no n0 infrastructure needed or wanted.
    let endpoint = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .alpns(vec![ALPN.to_vec()])
        .secret_key(secret)
        .bind_addr("0.0.0.0:0")
        .expect("bind addr")
        .bind()
        .await
        .expect("iroh endpoint bind");

    let serve_endpoint = endpoint.clone();
    tokio::spawn({
        let pairing = pairing.clone();
        let secret_hex = secret_hex.clone();
        async move { pairing.serve(serve_endpoint, secret_hex).await }
    });

    let port = endpoint
        .bound_sockets()
        .into_iter()
        .find(|s| s.is_ipv4())
        .expect("an IPv4 socket")
        .port();
    let sock = std::net::SocketAddr::new(advertise, port);
    let addr = EndpointAddr::from_parts(endpoint.id(), [TransportAddr::Ip(sock)]);

    let ticket_path = store_dir.join("ticket.txt");
    let mint = || {
        let (ticket, expiry) = pairing.mint_ticket_for(addr.clone());
        std::fs::write(&ticket_path, &ticket).expect("write ticket file");
        println!("TICKET {ticket}");
        println!("EXPIRY {expiry}");
    };
    mint();
    eprintln!(
        "[pairhost] serving: engine={engine_hp} advertise={sock} store={}",
        store_dir.display()
    );

    // Background harnesses close stdin at once, so tickets re-mint on
    // CONSUMPTION (every new paired peer spent the active ticket) AND on
    // EXPIRY margin: a ticket older than 8 of its 10 TTL minutes is replaced
    // so a long-idle harness never hands out a stale ticket (measured
    // 2026-08-29: a sim dial with an expired ticket is rejected at AUTH and
    // the phone reports not-paired). The 2-minute margin keeps a ticket
    // mid-dial valid — replacement only fires when nobody used it for 8min.
    let ttl_margin = std::time::Duration::from_secs(8 * 60);
    let mut paired = pairing.paired_ids().len();
    let mut minted_at = std::time::Instant::now();
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        let now = pairing.paired_ids().len();
        if now > paired {
            paired = now;
            mint();
            minted_at = std::time::Instant::now();
        } else if minted_at.elapsed() > ttl_margin {
            mint();
            minted_at = std::time::Instant::now();
        }
    }
}
