//! E2E smoke probe: redeem a pairing ticket exactly like the mobile client
//! (same parse_ticket/establish code path), from the host. Prints each step.
//! Run: cargo run --example probe [ticket-file]

use arxa_studio_transport::transport::{establish, parse_ticket};
use iroh::endpoint::{presets, Endpoint};
use iroh_tickets::endpoint::EndpointTicket;

#[tokio::main]
async fn main() {
    let path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "/tmp/arxa-smoke-ticket.txt".to_string());
    let raw = std::fs::read_to_string(&path).expect("read ticket file");
    let pairing = parse_ticket(raw.trim()).expect("parse ticket");
    println!("PROBE parse ok; token len={}", pairing.token.len());
    let ticket: EndpointTicket = pairing.node.parse().expect("endpoint ticket");
    println!("PROBE endpoint addr: {:?}", ticket.endpoint_addr());
    let endpoint = Endpoint::bind(presets::N0).await.expect("bind endpoint");
    println!("PROBE endpoint bound, dialing…");
    match establish(&endpoint, &ticket, &pairing.token, "probe-host").await {
        Ok(conn) => {
            println!("PROBE AUTH OK — remote={:?}", conn.remote_id());
            conn.close(0u32.into(), b"probe done");
        }
        Err(e) => {
            println!("PROBE FAILED: {e:?}");
            std::process::exit(1);
        }
    }
    endpoint.close().await;
}
