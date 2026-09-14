//! cairn-pushd sidecar supervision (decision M7, plan track B3/B4).
//!
//! The engine's push service: one binary, SQLite token registry, no Postgres.
//! Users never install or manage it — this module probes for a healthy
//! daemon at boot, spawns one if none is running, and kills only the child
//! it spawned on app exit (same rider as the engine sidecar: an externally
//! owned pushd always wins).
//!
//! ## The credentials keystore (B4: operator-owned, never the repo)
//!
//! `<app-local-data-dir>/pushd.env` — KEY=VALUE lines. THIS module owns
//! exactly three keys (`CAIRN_PUSHD_BIND`, `CAIRN_PUSHD_DB`,
//! `CAIRN_PUSHD_API_KEYS`) and preserves every other line verbatim: the
//! operator (or `cairn push init --env-file <path>`) writes the rail
//! credentials there — `CAIRN_FCM_CREDENTIALS_JSON`, `CAIRN_APNS_KEY_P8`,
//! `CAIRN_APNS_KEY_ID`, `CAIRN_APNS_TEAM_ID`, `CAIRN_APNS_BUNDLE_ID`,
//! `CAIRN_WEBPUSH_VAPID_PRIVATE_KEY`, ... — and they never enter the repo,
//! the engine, or any Arxa Digital Solutions database (M6 ownership rule).
//! Free users get the same path: pushd runs beside the engine on their Mac.
//!
//! ## Send path
//!
//! Anything on this machine (the engine's tools, a future notifications
//! surface) reaches pushd at the loopback bind with the bearer tenant key
//! from the env file: `POST /v1/send`, `POST /v1/tokens` (ADR-0038 REST).
//! Device push tokens arrive at QR-pair time over the iroh tunnel (see
//! pairing.rs's PUSH stream) and are re-registered here whenever pushd
//! (re)starts — its registry is disposable SQLite; pairing.json is the
//! durable source of truth.

use std::path::{Path, PathBuf};
use std::process::Command;

use data_encoding::HEXLOWER;
use tauri::{AppHandle, Manager};

/// Env file name inside the app local data dir (beside pairing.json).
const PUSHD_ENV_FILE: &str = "pushd.env";
/// Default loopback bind (cairn-pushd's own default).
const DEFAULT_BIND: &str = "127.0.0.1:8090";

/// Reachability for a live (spawned or external) pushd: loopback bind +
/// the bearer tenant key. Cloned into pairing state so PUSH-stream
/// registrations can forward into the daemon's registry.
#[derive(Clone)]
pub struct PushdHandle {
    pub bind: String,
    pub key: String,
}

/// Managed state: how to reach pushd + the child we own (to kill on exit).
pub struct PushdState {
    pub bind: String,
    pub api_key: String,
    /// Present only when THIS app instance spawned the daemon.
    pub child: std::sync::Mutex<Option<std::process::Child>>,
}

/// Load (or create) the keystore, probe for a live daemon, spawn one if
/// none, and hand the reachability contract to the app. Called from setup.
///
/// Never fatal: no pushd and no rails means no push, and the studio keeps
/// working (M7's degradation contract — the daemon is a sidecar, not a leg).
pub fn init(app: &AppHandle) {
    let data_dir = match app.path().app_local_data_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("[arxa-desktop] pushd disabled: no local data dir: {e}");
            return;
        }
    };
    let env_path = data_dir.join(PUSHD_ENV_FILE);
    let env = ensure_env_file(&env_path);
    let bind = env_value(&env, "CAIRN_PUSHD_BIND").unwrap_or_else(|| DEFAULT_BIND.to_string());
    // The BEARER the daemon expects is the SECRET only —
    // CAIRN_PUSHD_API_KEYS is `tenant:secret[:role]` and the daemon hashes
    // the presented string against the stored secret digest (verified
    // live against cairn-pushd: whole-string bearer -> 401, secret -> 200).
    let api_key = env_value(&env, "CAIRN_PUSHD_API_KEYS")
        .and_then(|raw| raw.split(',').next().map(str::to_string))
        .and_then(|first| first.split(':').nth(1).map(str::to_string))
        .unwrap_or_default();

    let state = PushdState {
        bind: bind.clone(),
        api_key: api_key.clone(),
        child: std::sync::Mutex::new(None),
    };
    app.manage(state);

    // Probe-then-spawn (the engine sidecar's rider 1): an externally owned
    // pushd always wins; we only self-heal a cold port. The probe needs the
    // key from the env FILE (the process env never carries it).
    if healthy(&bind, &api_key).is_some() {
        eprintln!("[arxa-desktop] pushd: reusing external daemon at {bind}");
        attach_and_resync(app, &bind, &api_key);
        return;
    }
    let bin = pushd_binary();
    let Some(bin) = bin else {
        eprintln!(
            "[arxa-desktop] pushd: no cairn-pushd binary found (looked at              CAIRN_PUSHD_BIN, PATH) — push disabled this session; install              cairn (cargo install --path crates/cairn-push) to enable"
        );
        return;
    };
    let child = Command::new(&bin)
        .env("CAIRN_PUSHD_BIND", &bind)
        .env("CAIRN_PUSHD_DB", data_dir.join("cairn-pushd.db"))
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .spawn();
    match child {
        Ok(c) => {
            if let Ok(mut guard) = app.state::<PushdState>().child.lock() {
                guard.replace(c);
            }
            eprintln!("[arxa-desktop] pushd: spawned {} at {bind}", bin.display());
            attach_and_resync(app, &bind, &api_key);
        }
        Err(e) => {
            eprintln!("[arxa-desktop] pushd: spawn failed ({e}) — push disabled this session");
        }
    }
}

/// Publish the handle to pairing state and re-register every stored device
/// token (the daemon's SQLite registry is disposable; pairing.json is the
/// durable source of truth). Runs on a thread: a just-spawned daemon needs
/// a moment to bind, so the status probe retries briefly.
fn attach_and_resync(app: &AppHandle, bind: &str, key: &str) {
    if let Some(pairing) = app.try_state::<crate::pairing::Pairing>() {
        pairing.attach_pushd(PushdHandle {
            bind: bind.to_string(),
            key: key.to_string(),
        });
        let tokens = pairing.device_push_tokens();
        if tokens.is_empty() {
            return;
        }
        let bind = bind.to_string();
        let key = key.to_string();
        std::thread::spawn(move || {
            // Brief liveness wait: up to ~5s for the daemon to accept.
            for _ in 0..25 {
                if healthy(&bind, &key).is_some() {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(200));
            }
            for (node, platform, token) in tokens {
                if let Err(e) = register_token_blocking(&bind, &key, &platform, &token, &node) {
                    eprintln!("[arxa-desktop] pushd resync {node}: {e}");
                }
            }
        });
    }
}

/// Kill the child we spawned (called from the app's exit path, beside
/// kill_spawned). An externally owned daemon is never touched.
pub fn kill_spawned(app: &AppHandle) {
    if let Ok(mut guard) = app.state::<PushdState>().child.lock() {
        if let Some(mut child) = guard.take() {
            // cairn-pushd drains gracefully on SIGTERM (axum
            // with_graceful_shutdown); SIGKILL only if it ignores that.
            use std::process::Command as C;
            let _ = C::new("kill")
                .arg("-TERM")
                .arg(child.id().to_string())
                .status();
            let _ = child.wait();
        }
    }
}

/// Where the cairn-pushd binary can be found: explicit env override first,
/// then PATH. Bundling as a Tauri sidecar is the release shape (M7 note in
/// desktop README); the PATH lookup covers dev machines with a cargo
/// install of the cairn workspace.
fn pushd_binary() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("CAIRN_PUSHD_BIN") {
        let p = PathBuf::from(p);
        if p.is_file() {
            return Some(p);
        }
    }
    let candidates = [
        "cairn-pushd".to_string(),
        dirs_home()
            .map(|h| format!("{h}/.cargo/bin/cairn-pushd"))
            .unwrap_or_default(),
    ];
    // Absolute candidate first; bare name resolves via PATH.
    if let Some(abs) = candidates.iter().find(|c| Path::new(c).is_file()) {
        return Some(PathBuf::from(abs));
    }
    if let Ok(out) = Command::new("which").arg("cairn-pushd").output() {
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
/// Operator-written lines are preserved byte-for-byte on every later run —
/// this module rewrites ONLY its own three keys.
fn ensure_env_file(path: &Path) -> Vec<(String, String)> {
    let existing = std::fs::read_to_string(path).unwrap_or_default();
    let mut pairs = parse_env(&existing);
    let owned = [
        ("CAIRN_PUSHD_BIND", Some(DEFAULT_BIND.to_string())),
        (
            "CAIRN_PUSHD_DB",
            Some(
                path.parent()
                    .map(|d| d.join("cairn-pushd.db").to_string_lossy().into_owned())
                    .unwrap_or_else(|| "cairn-pushd.db".to_string()),
            ),
        ),
        (
            "CAIRN_PUSHD_API_KEYS",
            Some(format!("arxa:{}:rail", new_secret())),
        ),
    ];
    for (key, value) in owned {
        match (pairs.iter().position(|(k, _)| k == key), &value) {
            (Some(_), Some(_)) => {} // operator/env already pinned it — keep
            (Some(idx), None) => {
                pairs.remove(idx);
            }
            (None, Some(v)) => pairs.push((key.to_string(), v.clone())),
            (None, None) => {}
        }
    }
    let body = render_env(&pairs);
    // Best-effort 0600: the file can carry rail credentials.
    let _ = std::fs::write(path, &body);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    }
    pairs
}

/// 32 random bytes hex — a freshly generated iroh SecretKey is a CSPRNG
/// draw (same trick pairing.rs uses for its tickets).
pub(crate) fn new_secret() -> String {
    HEXLOWER.encode(&iroh::SecretKey::generate().to_bytes())
}

/// Parse KEY=VALUE lines; blank lines and # comments skipped.
pub fn parse_env(body: &str) -> Vec<(String, String)> {
    body.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .filter_map(|l| {
            l.split_once('=')
                .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
        })
        .collect()
}

/// Render back to KEY=VALUE lines (order preserved).
pub fn render_env(pairs: &[(String, String)]) -> String {
    pairs
        .iter()
        .map(|(k, v)| format!("{k}={v}"))
        .collect::<Vec<_>>()
        .join("\n")
        + "\n"
}

fn env_value(pairs: &[(String, String)], key: &str) -> Option<String> {
    pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone())
}

/// GET /v1/status over loopback TCP (bearer-authed — pushd has no
/// unauthenticated healthz). Returns the status line on success.
fn healthy(bind: &str, key: &str) -> Option<String> {
    let mut stream = std::net::TcpStream::connect(bind).ok()?;
    use std::io::{Read, Write};
    let req = format!(
        "GET /v1/status HTTP/1.1\r\nHost: {bind}\r\nAuthorization: Bearer {key}\r\nConnection: close\r\n\r\n"
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

/// Register a device push token with the daemon (POST /v1/tokens,
/// bearer-authed). Called from pairing.rs when a phone registers over the
/// tunnel, and at pushd boot for every stored paired device.
pub async fn register_token(
    bind: &str,
    key: &str,
    platform: &str,
    token: &str,
    tag: &str,
) -> Result<(), String> {
    let body = serde_json::json!({
        "token": token,
        "platform": platform,
        "account_tag": tag,
    })
    .to_string();
    let mut stream = tokio::net::TcpStream::connect(bind)
        .await
        .map_err(|e| format!("pushd connect {bind}: {e}"))?;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let req = format!(
        "POST /v1/tokens HTTP/1.1\r\nHost: {bind}\r\nAuthorization: Bearer {key}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    stream
        .write_all(req.as_bytes())
        .await
        .map_err(|e| format!("pushd write: {e}"))?;
    let mut resp = String::new();
    stream
        .read_to_string(&mut resp)
        .await
        .map_err(|e| format!("pushd read: {e}"))?;
    let status = resp.lines().next().unwrap_or_default().to_string();
    // 201 = registered; 409 = cross-tenant re-register (same token under
    // another tag) — treat as success-adjacent: the token IS known to pushd.
    if status.contains("201") || status.contains("409") {
        Ok(())
    } else {
        Err(format!("pushd /v1/tokens -> {status}"))
    }
}

/// Best-effort synchronous wrapper for contexts without an async runtime
/// handle (the pairing stream handler calls this through tauri's runtime).
pub fn register_token_blocking(
    bind: &str,
    key: &str,
    platform: &str,
    token: &str,
    tag: &str,
) -> Result<(), String> {
    let body = serde_json::json!({
        "token": token,
        "platform": platform,
        "account_tag": tag,
    })
    .to_string();
    let mut stream =
        std::net::TcpStream::connect(bind).map_err(|e| format!("pushd connect: {e}"))?;
    use std::io::{Read, Write};
    let req = format!(
        "POST /v1/tokens HTTP/1.1\r\nHost: {bind}\r\nAuthorization: Bearer {key}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    stream
        .write_all(req.as_bytes())
        .map_err(|e| format!("pushd write: {e}"))?;
    let mut resp = String::new();
    stream
        .read_to_string(&mut resp)
        .map_err(|e| format!("pushd read: {e}"))?;
    let status = resp.lines().next().unwrap_or_default().to_string();
    if status.contains("201") || status.contains("409") {
        Ok(())
    } else {
        Err(format!("pushd /v1/tokens -> {status}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_env_roundtrip_preserves_operator_lines() {
        let body = "# operator credentials (cairn push init writes these)\nCAIRN_FCM_CREDENTIALS_JSON={\"project\":1}\n\nCAIRN_APNS_KEY_P8=/secure/apns.p8\n";
        let pairs = parse_env(body);
        assert_eq!(pairs.len(), 2);
        assert_eq!(
            env_value(&pairs, "CAIRN_FCM_CREDENTIALS_JSON").unwrap(),
            "{\"project\":1}"
        );
        let rendered = render_env(&pairs);
        assert!(rendered.contains("CAIRN_APNS_KEY_P8=/secure/apns.p8\n"));
    }

    #[test]
    fn ensure_env_file_creates_owned_keys_once() {
        let dir = std::env::temp_dir().join(format!("arxa-pushd-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("pushd.env");
        let _ = std::fs::remove_file(&path);
        let pairs = ensure_env_file(&path);
        assert_eq!(
            env_value(&pairs, "CAIRN_PUSHD_BIND").as_deref(),
            Some(DEFAULT_BIND)
        );
        let key = env_value(&pairs, "CAIRN_PUSHD_API_KEYS").unwrap();
        assert!(key.starts_with("arxa:") && key.ends_with(":rail"), "{key}");
        // A second run with an operator-added line preserves it and keeps
        // the SAME generated key (the file exists now).
        std::fs::write(
            &path,
            format!(
                "CAIRN_FCM_CREDENTIALS_JSON=x\n{}",
                std::fs::read_to_string(&path).unwrap()
            ),
        )
        .unwrap();
        let again = ensure_env_file(&path);
        assert_eq!(env_value(&again, "CAIRN_PUSHD_API_KEYS"), Some(key));
        assert!(env_value(&again, "CAIRN_FCM_CREDENTIALS_JSON").is_some());
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_dir(&dir);
    }
}
