//! Synthetic phone: parse an `arxa-pair:` ticket and run the EXACT session
//! loop the mobile app runs (same crate, same code path). Bisect tool for the
//! desktop-QR pairing spinner — if this reaches Connected, the desktop accept
//! path is green and the phone build is the suspect.
//!
//! Usage: cargo run -p arxa_studio_transport --example dial -- <ticket> [name]
//!
//! ponytail: throwaway bisect tool; delete after the pairing bug is fixed.

use arxa_studio_transport::transport;

#[tokio::main(flavor = "multi_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: dial <arxa-pair:...> [device_name]");
        std::process::exit(2);
    }
    let ticket = args[1].clone();
    let device = args.get(2).cloned();

    let pairing = match transport::parse_ticket(&ticket) {
        Ok(p) => {
            eprintln!("[dialer] ticket parsed ok");
            p
        }
        Err(e) => {
            eprintln!("[dialer] PARSE FAILED: {e}");
            std::process::exit(1);
        }
    };

    let shared = transport::new_shared();
    let epoch = transport::begin_epoch(
        &shared,
        pairing.clone(),
        device,
        transport::LinkState::Connecting,
    );
    let (current, mut rx) = transport::subscribe(&shared);
    println!("[dialer] state: {current:?}");

    let sh = shared.clone();
    let pr = pairing.clone();
    tokio::spawn(async move {
        // Mirror the phone exactly: same attempt budget, fresh (not reconnecting).
        transport::run_session(sh, epoch, pr, transport::FRESH_DIAL_ATTEMPTS, false).await;
        eprintln!("[dialer] run_session returned");
    });

    loop {
        match rx.recv().await {
            Ok(s) => {
                println!(
                    "[dialer] state: {s:?} proxy_port={:?}",
                    transport::current_proxy_port(&shared)
                );
                if matches!(
                    s,
                    transport::LinkState::Connected
                        | transport::LinkState::Disconnected
                        | transport::LinkState::Revoked
                ) {
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
            Err(e) => {
                eprintln!("[dialer] rx closed: {e}");
                break;
            }
        }
    }
}
