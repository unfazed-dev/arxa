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
//!   ARXA_PAIRHOST_RELAY=1 opts into the n0 relays: minted tickets then carry
//!   a Relay transport so a phone OFF the LAN (cellular) can dial. Default is
//!   relay-less — sim and host are adjacent, and a LAN IP is unroutable
//!   off-network (2026-08-29 D68 cellular loop: every dial timed out against
//!   a relay-less ticket).
//!
//! Prints `TICKET <arxa-pair:...>` on boot and again for every stdin line
//! (tickets are single-use; repeat pairings mint fresh ones). Runs until
//! stdin closes or the process is killed.

use std::path::PathBuf;

use arxa_desktop_lib::pairing::{Pairing, ALPN};
use arxa_desktop_lib::pushd::PushdHandle;
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

/// Parse CAIRN_PUSHD_BIND + the first CAIRN_PUSHD_API_KEYS secret from a
/// pushd.env-style KEY=VALUE file. Absent file or missing keys → None
/// (push stays unwired, as before).
fn read_pushd_env(path: std::path::PathBuf) -> Option<(String, String)> {
    let text = std::fs::read_to_string(path).ok()?;
    let mut bind = None;
    let mut key = None;
    for line in text.lines() {
        let t = line.trim();
        if let Some(v) = t.strip_prefix("CAIRN_PUSHD_BIND=") {
            bind = Some(v.trim().to_string());
        } else if let Some(v) = t.strip_prefix("CAIRN_PUSHD_API_KEYS=") {
            let first = v.split(',').next().unwrap_or("").trim();
            if let Some((_, secret)) = first.split_once(':') {
                key = Some(secret.trim_end_matches(":rail").to_string());
            }
        }
    }
    Some((bind?, key?))
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

    // D68 phone leg: wire the PUSH-forward exactly as the Tauri shell does
    // (pairing.rs skips the forward when no pushd handle is attached — a
    // token that lands in pairing.json but never in the daemon's registry
    // sends 404 at /v1/send). pushd.env beside the store is the operator's
    // credential file: bind + the first tenant:secret key, same pick as the
    // engine's doorbell (push-doorbell/lib/index.js apiKeyFromEnv).
    if let Some((bind, key)) = read_pushd_env(store_dir.join("pushd.env")) {
        pairing.attach_pushd(PushdHandle { bind: bind.clone(), key });
        eprintln!("[pairhost] pushd forward wired: {bind}");
    }

    // Bind every interface (the sim dials the advertised LAN IP). Relays off
    // by default — sim and host are adjacent, no n0 infrastructure needed;
    // ARXA_PAIRHOST_RELAY=1 turns them on for the off-network (cellular) leg.
    let with_relay = std::env::var("ARXA_PAIRHOST_RELAY").as_deref() == Ok("1");
    let builder = if with_relay {
        Endpoint::builder(presets::N0)
    } else {
        Endpoint::builder(presets::Minimal).relay_mode(RelayMode::Disabled)
    };
    let endpoint = builder
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
    let mut addrs = vec![TransportAddr::Ip(sock)];
    if with_relay {
        // Wait for the n0 relay handshake so the ticket truly carries a
        // reachable path; without it a cellular phone has no route at all.
        match tokio::time::timeout(std::time::Duration::from_secs(30), endpoint.online()).await {
            Ok(()) => {
                if let Some(relay) = endpoint.addr().relay_urls().next() {
                    eprintln!("[pairhost] relay path advertised: {relay}");
                    addrs.push(TransportAddr::Relay(relay.clone()));
                }
            }
            Err(_) => {
                eprintln!(
                    "[pairhost] WARNING: relay handshake timed out; ticket is LAN-only                      (off-network reconnects will fail)"
                );
            }
        }
    }
    let addr = EndpointAddr::from_parts(endpoint.id(), addrs);

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
