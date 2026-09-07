//! launchd supervision of the engine (macOS). Closes the gap the detached
//! spawn left: a crashed engine came back only when the shell relaunched.
//!
//! `~/Library/LaunchAgents/solutions.arxadigital.arxa.engine.plist` runs the bundled
//! `arxa-studio --no-open` with `KeepAlive.PathState` on the sidecar binary:
//! launchd restarts the engine whenever it exits, for as long as the binary
//! exists — deleting the app ends the loop instead of spamming launchd with a
//! missing program. The shell owns the plist (rewrites it when the sidecar
//! path or environment changes) but launchd owns the process; the shell
//! never spawns or kills the engine itself while the agent is loaded.
//!
//! Every entry point shells out to `launchctl`; on a platform without it the
//! caller falls back to the detached spawn.
use std::path::{Path, PathBuf};
use std::process::Command;

pub const LABEL: &str = "solutions.arxadigital.arxa.engine";

fn domain() -> Option<String> {
    let out = Command::new("id").arg("-u").output().ok()?;
    let uid = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if uid.is_empty() {
        None
    } else {
        Some(format!("gui/{uid}"))
    }
}

fn service() -> Option<String> {
    domain().map(|d| format!("{d}/{LABEL}"))
}

pub fn plist_path() -> Option<PathBuf> {
    let home = std::env::var("HOME").ok().filter(|h| !h.is_empty())?;
    Some(
        PathBuf::from(home)
            .join("Library")
            .join("LaunchAgents")
            .join(format!("{LABEL}.plist")),
    )
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

/// The plist body. The shell's own PATH and ARXA_* overrides are copied in so
/// the agent's engine sees exactly the environment a shell-spawned one did.
pub fn render(sidecar: &Path, log: &Path) -> String {
    let mut env = vec![("PATH".to_string(), std::env::var("PATH").unwrap_or_default())];
    for k in ["ARXA_PORT", "ARXA_DSH_HOME", "ARXA_HOME", "ARXA_STUDIO_URL"] {
        if let Ok(v) = std::env::var(k) {
            if !v.trim().is_empty() {
                env.push((k.to_string(), v));
            }
        }
    }
    let env_xml: String = env
        .iter()
        .map(|(k, v)| format!("\t\t<key>{}</key>\n\t\t<string>{}</string>\n", esc(k), esc(v)))
        .collect();
    let s = esc(&sidecar.to_string_lossy());
    let l = esc(&log.to_string_lossy());
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>{LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>{s}</string>
		<string>--no-open</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>PathState</key>
		<dict>
			<key>{s}</key>
			<true/>
		</dict>
	</dict>
	<key>ThrottleInterval</key>
	<integer>5</integer>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>StandardOutPath</key>
	<string>{l}</string>
	<key>StandardErrorPath</key>
	<string>{l}</string>
	<key>EnvironmentVariables</key>
	<dict>
{env_xml}	</dict>
</dict>
</plist>
"#
    )
}

fn launchctl(args: &[&str]) -> Result<String, String> {
    let out = Command::new("launchctl")
        .args(args)
        .output()
        .map_err(|e| format!("launchctl {}: {e}", args.join(" ")))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    } else {
        Err(format!(
            "launchctl {}: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        ))
    }
}

/// True when the agent is registered in the user's gui domain.
pub fn loaded() -> bool {
    service().map(|s| launchctl(&["print", &s]).is_ok()).unwrap_or(false)
}

/// Kill-and-restart the engine under launchd (Engine → Restart Engine, and
/// the app-updated path).
pub fn kickstart() -> Result<(), String> {
    let s = service().ok_or("no uid")?;
    launchctl(&["kickstart", "-k", &s]).map(|_| ())
}

/// Install or refresh the agent. `restart_wanted` forces a kickstart when the
/// plist is already current (the sidecar binary changed underneath launchd).
/// `port_free` is polled between bootout and bootstrap so the fresh engine
/// never races the old one for the port. Returns true when this call
/// (re)started the engine.
pub fn ensure(
    sidecar: &Path,
    log: &Path,
    restart_wanted: bool,
    port_free: &dyn Fn() -> bool,
) -> Result<bool, String> {
    let d = domain().ok_or("no uid")?;
    let s = format!("{d}/{LABEL}");
    let path = plist_path().ok_or("no HOME")?;
    for dir in [path.parent(), log.parent()].into_iter().flatten() {
        let _ = std::fs::create_dir_all(dir);
    }
    let desired = render(sidecar, log);
    let current = std::fs::read_to_string(&path).unwrap_or_default();
    let was_loaded = loaded();
    if current != desired || !was_loaded {
        if was_loaded {
            let _ = launchctl(&["bootout", &s]);
            for _ in 0..20 {
                if !loaded() && port_free() {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(250));
            }
        }
        std::fs::write(&path, desired).map_err(|e| e.to_string())?;
        let _ = launchctl(&["enable", &s]);
        launchctl(&["bootstrap", &d, &path.to_string_lossy()])?;
        return Ok(true);
    }
    if restart_wanted {
        kickstart()?;
        return Ok(true);
    }
    Ok(false)
}
