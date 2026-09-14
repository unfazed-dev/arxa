//! cairn-server sidecar supervision (B2 sync-first, ADR-0042; plan
//! b2-sync-first-phase1.md Task 5).
//!
//! The desktop's read-model replica: one cairn-server binary on the loopback
//! bind with CAIRN_REPLICATOR=mirror, so the engine mirrors approvals out
//! over the admin-gated POST /ingest. Same contract as the pushd sidecar
//! (pushd.rs, decision M7): probe-then-spawn (an externally owned server
//! always wins), env keystore <app-local-data-dir>/cairn-server.env (0600),
//! and kill only the child THIS process spawned on exit.
//!
//! Loopback-only posture: CAIRN_SYNC_AUTH=none is safe because the bind
//! never leaves 127.0.0.1 - the phone reaches the server through the
//! engine's tunnel proxy (phase 1b), never directly.
//!
//! Push rail: when pushd.env sits beside this env file (the pushd sidecar's
//! keystore), its bind + bearer secret are forwarded as CAIRN_PUSH_REMOTE_URL
//! / CAIRN_PUSH_REMOTE_KEY so the server's fan-out doorbell (RemoteNotifier)
//! can fire the silent wake for sync-covered events (phase 1b). A plain
//! secret is correct there: doorbell sends target REGISTERED tokens, which a
//! standard (non-:rail) key may send; rail-mode sends (unregistered token +
//! platform field) would need a :rail-suffixed entry daemon-side
//! (docs/push.md security closeout).

use std::path::{Path, PathBuf};
use std::process::Command;

use tauri::{AppHandle, Manager};

use crate::pushd::new_secret;
use crate::pushd::{parse_env, render_env};

/// Env file name inside the app local data dir (beside pushd.env).
const SERVER_ENV_FILE: &str = "cairn-server.env";
/// Default loopback bind - never leaves the machine (module docs).
const DEFAULT_BIND: &str = "127.0.0.1:8190";
/// Explicit binary override for dev machines.
const BIN_ENV: &str = "CAIRN_CAIRN_SERVER_BIN";
/// The pushd sidecar's keystore (sibling file we forward the rail from).
const PUSHD_ENV_FILE: &str = "pushd.env";

/// Managed state: how to reach the server + the child we own (to kill on
/// exit). admin_token is the POST /ingest and PUT /rules bearer.
pub struct CairnServerState {
    pub bind: String,
    pub admin_token: String,
    /// Present only when THIS app instance spawned the server.
    pub child: std::sync::Mutex<Option<std::process::Child>>,
}

/// Load (or create) the keystore, probe for a live server, spawn one if the
/// port is cold. Called from setup, beside pushd::init.
///
/// Never fatal: no cairn-server means no offline mirror and no silent
/// doorbell, and the studio keeps working (the visible approval doorbell
/// does not depend on it - degradation contract mirrors M7).
pub fn init(app: &AppHandle) {
    let data_dir = match app.path().app_local_data_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("[arxa-desktop] cairn-server disabled: no local data dir: {e}");
            return;
        }
    };
    let env_path = data_dir.join(SERVER_ENV_FILE);
    let env = ensure_env_file(&env_path);
    let bind = env_value(&env, "CAIRN_BIND").unwrap_or_else(|| DEFAULT_BIND.to_string());
    let admin_token = env_value(&env, "CAIRN_ADMIN_TOKEN").unwrap_or_default();

    let state = CairnServerState {
        bind: bind.clone(),
        admin_token: admin_token.clone(),
        child: std::sync::Mutex::new(None),
    };
    app.manage(state);

    // Probe-then-spawn (the engine sidecar's rider 1): an externally owned
    // server always wins; we only self-heal a cold port.
    if healthy(&bind).is_some() {
        eprintln!("[arxa-desktop] cairn-server: reusing external server at {bind}");
        return;
    }
    let Some(bin) = cairn_server_binary() else {
        eprintln!(
            "[arxa-desktop] cairn-server: no binary found (looked at BIN_ENV override,              ~/.cargo/bin, PATH) - sync mirror disabled this session; install              cairn (cargo install --path crates/cairn-server) to enable"
        );
        return;
    };
    let mut cmd = Command::new(&bin);
    cmd.env("CAIRN_BIND", &bind)
        .env("CAIRN_SYNC_AUTH", "none")
        .env("CAIRN_REPLICATOR", "mirror")
        .env("CAIRN_ADMIN_TOKEN", &admin_token)
        // Anchor the rules path: the spawned child's CWD is not ours, and a
        // relative CAIRN_RULES_FILE would silently resolve elsewhere
        // (ADR-0031: no file on disk = all-mode, so absence is fine).
        .env("CAIRN_RULES_FILE", data_dir.join("cairn_rules.toml"))
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())));
    // Forward the push rail from the pushd sidecar's keystore when present
    // (phase 1b's silent doorbell rides this).
    if let Some((url, key)) = push_rail(&data_dir) {
        cmd.env("CAIRN_PUSH_REMOTE_URL", url)
            .env("CAIRN_PUSH_REMOTE_KEY", key);
    }
    match cmd.spawn() {
        Ok(c) => {
            if let Ok(mut guard) = app.state::<CairnServerState>().child.lock() {
                guard.replace(c);
            }
            eprintln!(
                "[arxa-desktop] cairn-server: spawned {} at {bind}",
                bin.display()
            );
        }
        Err(e) => {
            eprintln!(
                "[arxa-desktop] cairn-server: spawn failed ({e}) - mirror disabled this session"
            );
        }
    }
}

/// Kill the child we spawned (called from the app's exit path, beside
/// pushd::kill_spawned). An externally owned server is never touched.
pub fn kill_spawned(app: &AppHandle) {
    if let Ok(mut guard) = app.state::<CairnServerState>().child.lock() {
        if let Some(mut child) = guard.take() {
            // cairn-server drains gracefully on SIGTERM; SIGKILL only if it
            // ignores that (same shape as pushd.rs).
            use std::process::Command as C;
            let _ = C::new("kill")
                .arg("-TERM")
                .arg(child.id().to_string())
                .status();
            let _ = child.wait();
        }
    }
}

/// The push rail (bind URL + bearer secret) read from the pushd sidecar's
/// keystore, or None when push was never set up on this machine. The secret
/// is the SECRET only of the first well-formed tenant:secret entry (the
/// daemon stamps the tenant - cairn-push auth.rs).
fn push_rail(data_dir: &Path) -> Option<(String, String)> {
    let body = std::fs::read_to_string(data_dir.join(PUSHD_ENV_FILE)).ok()?;
    let pairs = parse_env(&body);
    let bind =
        env_value(&pairs, "CAIRN_PUSHD_BIND").unwrap_or_else(|| "127.0.0.1:8090".to_string());
    let key = env_value(&pairs, "CAIRN_PUSHD_API_KEYS")
        .and_then(|raw| raw.split(',').next().map(str::to_string))
        .and_then(|first| first.split(':').nth(1).map(str::to_string))
        .filter(|k| !k.is_empty())?;
    Some((format!("http://{bind}"), key))
}

/// Binary discovery order (plan Task 5): explicit override, then
/// ~/.cargo/bin, then PATH. Pure so the order is testable without touching
/// process-global env.
fn discovery_order(override_path: Option<&str>, home: Option<&str>) -> Vec<PathBuf> {
    let mut order = Vec::new();
    if let Some(p) = override_path.map(str::trim).filter(|p| !p.is_empty()) {
        order.push(PathBuf::from(p));
    }
    if let Some(h) = home.map(str::trim).filter(|h| !h.is_empty()) {
        order.push(PathBuf::from(format!("{h}/.cargo/bin/cairn-server")));
    }
    order.push(PathBuf::from("cairn-server")); // bare name resolves via PATH
    order
}

fn cairn_server_binary() -> Option<PathBuf> {
    let override_path = std::env::var(BIN_ENV).ok();
    for candidate in discovery_order(override_path.as_deref(), dirs_home().as_deref()) {
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    if let Ok(out) = Command::new("which").arg("cairn-server").output() {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() {
                return Some(PathBuf::from(s));
            }
        }
    }
    None
}

fn dirs_home() -> Option<String> {
    std::env::var("HOME").ok().filter(|h| !h.is_empty())
}

/// Read the env file, creating it with the shell-owned keys if absent.
/// Operator-written lines are preserved byte-for-byte on every later run -
/// this module rewrites ONLY its own four keys.
fn ensure_env_file(path: &Path) -> Vec<(String, String)> {
    let existing = std::fs::read_to_string(path).unwrap_or_default();
    let mut pairs = parse_env(&existing);
    let owned = [
        ("CAIRN_BIND", Some(DEFAULT_BIND.to_string())),
        // Loopback-only posture (module docs): no token auth on the wire.
        ("CAIRN_SYNC_AUTH", Some("none".to_string())),
        ("CAIRN_REPLICATOR", Some("mirror".to_string())),
        // Gates POST /ingest + PUT /rules (ADR-0042 write door). >= 32 chars
        // is the daemon's own minimum (cairn-server admin_auth.rs).
        ("CAIRN_ADMIN_TOKEN", Some(new_secret())),
    ];
    for (key, value) in owned {
        match (pairs.iter().position(|(k, _)| k == key), &value) {
            (Some(_), Some(_)) => {} // operator/env already pinned it - keep
            (Some(idx), None) => {
                pairs.remove(idx);
            }
            (None, Some(v)) => pairs.push((key.to_string(), v.clone())),
            (None, None) => {}
        }
    }
    let body = render_env(&pairs);
    // Best-effort 0600: the file carries the admin token.
    let _ = std::fs::write(path, &body);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    }
    pairs
}

fn env_value(pairs: &[(String, String)], key: &str) -> Option<String> {
    pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone())
}

/// GET /healthz over loopback TCP (unauthenticated - cairn-server's
/// liveness route). Returns the status line on success.
fn healthy(bind: &str) -> Option<String> {
    let mut stream = std::net::TcpStream::connect(bind).ok()?;
    use std::io::{Read, Write};
    let req = format!(
        "GET /healthz HTTP/1.1
Host: {bind}
Connection: close

"
    );
    stream.write_all(req.as_bytes()).ok()?;
    let mut buf = String::new();
    stream.read_to_string(&mut buf).ok()?;
    let status = buf.lines().next()?.to_string();
    if status.contains("200") {
        Some(status)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ensure_env_file_creates_owned_keys_once() {
        let dir =
            std::env::temp_dir().join(format!("arxa-cairn-server-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("cairn-server.env");
        let _ = std::fs::remove_file(&path);
        let pairs = ensure_env_file(&path);
        assert_eq!(
            env_value(&pairs, "CAIRN_BIND").as_deref(),
            Some(DEFAULT_BIND)
        );
        assert_eq!(
            env_value(&pairs, "CAIRN_SYNC_AUTH").as_deref(),
            Some("none")
        );
        assert_eq!(
            env_value(&pairs, "CAIRN_REPLICATOR").as_deref(),
            Some("mirror")
        );
        let token = env_value(&pairs, "CAIRN_ADMIN_TOKEN").unwrap();
        assert!(
            token.len() >= 32,
            "admin token must clear the daemon minimum: {token}"
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600, "keystore must be 0600");
        }
        // A second run with an operator-added line preserves it and keeps
        // the SAME generated token (the file exists now).
        std::fs::write(
            &path,
            format!(
                "CAIRN_LICENSE_SECRET=op-secret
{}",
                std::fs::read_to_string(&path).unwrap()
            ),
        )
        .unwrap();
        let again = ensure_env_file(&path);
        assert_eq!(env_value(&again, "CAIRN_ADMIN_TOKEN"), Some(token));
        assert_eq!(
            env_value(&again, "CAIRN_LICENSE_SECRET").as_deref(),
            Some("op-secret")
        );
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_dir(&dir);
    }

    #[test]
    fn discovery_order_prefers_override_then_cargo_then_path() {
        let order = discovery_order(Some("/custom/cairn-server"), Some("/Users/dev"));
        assert_eq!(
            order,
            vec![
                PathBuf::from("/custom/cairn-server"),
                PathBuf::from("/Users/dev/.cargo/bin/cairn-server"),
                PathBuf::from("cairn-server"),
            ]
        );
        // No override, no HOME: PATH lookup is the only candidate. Blank
        // strings count as absent (same filter as the env reads).
        assert_eq!(
            discovery_order(Some("  "), Some("")),
            vec![PathBuf::from("cairn-server")]
        );
    }

    #[test]
    fn push_rail_reads_secret_only_from_pushd_env() {
        let dir =
            std::env::temp_dir().join(format!("arxa-cairn-server-rail-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        // Absent keystore means no rail (push never set up).
        assert!(push_rail(&dir).is_none());
        std::fs::write(
            dir.join(PUSHD_ENV_FILE),
            "# operator rail creds
CAIRN_PUSHD_BIND=127.0.0.1:9091
CAIRN_PUSHD_API_KEYS=arxa:sekret:rail,other:x
",
        )
        .unwrap();
        let (url, key) = push_rail(&dir).unwrap();
        assert_eq!(url, "http://127.0.0.1:9091");
        // First entry, secret only, reserved :rail suffix stripped.
        assert_eq!(key, "sekret");
        let _ = std::fs::remove_file(dir.join(PUSHD_ENV_FILE));
        let _ = std::fs::remove_dir(&dir);
    }
}
