//! systemd supervision of the engine (Linux) — the sibling of `engine_agent`
//! (launchd, macOS), with the same four entry points so `lib.rs` does not care
//! which one it is talking to.
//!
//! `~/.config/systemd/user/arxa-engine.service` runs the bundled
//! `arxa-studio --no-open` with `Restart=always`, so a crashed engine comes
//! back without the shell relaunching. `ConditionPathExists` on the sidecar is
//! the counterpart of launchd's `KeepAlive.PathState`: a deleted app ends the
//! restart loop instead of looping on a missing program (systemd re-evaluates
//! conditions on every start job, restarts included).
//!
//! A **user** unit, deliberately: no sudo, no polkit prompt out of a GUI app,
//! and the engine dies with the session like the LaunchAgent does. Reboot
//! survival is `loginctl enable-linger`, which the caller can add later — the
//! app relaunching is the normal path back.
//!
//! Everything shells out to `systemctl --user`. Where that is missing or has no
//! user instance to talk to (a container, an SSH session with no user bus), the
//! calls fail and `lib.rs` falls back to the detached spawn — exactly what it
//! does on a mac with no launchctl.
use std::path::{Path, PathBuf};
use std::process::Command;

pub const UNIT: &str = "arxa-engine.service";

pub fn unit_path() -> Option<PathBuf> {
    let base = match std::env::var("XDG_CONFIG_HOME") {
        Ok(v) if !v.trim().is_empty() => PathBuf::from(v),
        _ => PathBuf::from(std::env::var("HOME").ok().filter(|h| !h.is_empty())?).join(".config"),
    };
    Some(base.join("systemd").join("user").join(UNIT))
}

/// systemd reads `Environment=` values as shell-ish words: quote them and
/// escape what would end the quote.
fn env_line(key: &str, value: &str) -> String {
    let v = value.replace('\\', "\\\\").replace('"', "\\\"");
    format!("Environment=\"{key}={v}\"\n")
}

/// The unit body. The shell's own PATH and ARXA_* overrides are copied in so
/// the supervised engine sees exactly the environment a shell-spawned one did.
pub fn render(sidecar: &Path, log: &Path) -> String {
    let mut env = env_line("PATH", &std::env::var("PATH").unwrap_or_default());
    for k in ["ARXA_PORT", "ARXA_DSH_HOME", "ARXA_HOME", "ARXA_STUDIO_URL"] {
        if let Ok(v) = std::env::var(k) {
            if !v.trim().is_empty() {
                env.push_str(&env_line(k, &v));
            }
        }
    }
    let s = sidecar.to_string_lossy();
    let l = log.to_string_lossy();
    format!(
        "[Unit]\n\
         Description=arxa studio engine\n\
         ConditionPathExists={s}\n\
         After=network.target\n\
         \n\
         [Service]\n\
         Type=simple\n\
         ExecStart={s} --no-open\n\
         Restart=always\n\
         RestartSec=5\n\
         KillMode=process\n\
         TimeoutStopSec=20\n\
         StandardOutput=append:{l}\n\
         StandardError=append:{l}\n\
         {env}\n\
         [Install]\n\
         WantedBy=default.target\n"
    )
}

fn systemctl(args: &[&str]) -> Result<String, String> {
    let out = Command::new("systemctl")
        .arg("--user")
        .args(args)
        .output()
        .map_err(|e| format!("systemctl --user {}: {e}", args.join(" ")))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    } else {
        let err = String::from_utf8_lossy(&out.stderr);
        let msg = if err.trim().is_empty() {
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        } else {
            err.trim().to_string()
        };
        Err(format!("systemctl --user {}: {msg}", args.join(" ")))
    }
}

/// True when the unit is installed AND systemd knows it. `is-enabled` answers
/// both: an unknown unit is an error, a written-but-not-reloaded one is
/// "not-found".
pub fn loaded() -> bool {
    unit_path().map(|p| p.exists()).unwrap_or(false) && systemctl(&["is-enabled", UNIT]).is_ok()
}

/// Stop-and-start the engine under systemd (Engine → Restart Engine, and the
/// app-updated path).
pub fn kickstart() -> Result<(), String> {
    systemctl(&["restart", UNIT]).map(|_| ())
}

/// Install or refresh the unit. `restart_wanted` forces a restart when the unit
/// is already current (the sidecar binary changed underneath systemd).
/// `port_free` is polled between stop and start so the fresh engine never races
/// the old one for the port. Returns true when this call (re)started the engine.
pub fn ensure(
    sidecar: &Path,
    log: &Path,
    restart_wanted: bool,
    port_free: &dyn Fn() -> bool,
) -> Result<bool, String> {
    let path = unit_path().ok_or("no HOME")?;
    for dir in [path.parent(), log.parent()].into_iter().flatten() {
        let _ = std::fs::create_dir_all(dir);
    }
    let desired = render(sidecar, log);
    let current = std::fs::read_to_string(&path).unwrap_or_default();
    let was_loaded = loaded();
    if current != desired || !was_loaded {
        if was_loaded {
            let _ = systemctl(&["stop", UNIT]);
            for _ in 0..20 {
                if port_free() {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(250));
            }
        }
        std::fs::write(&path, desired).map_err(|e| e.to_string())?;
        // daemon-reload is what makes a rewritten unit visible; without it
        // systemd keeps running the old ExecStart after an app update.
        systemctl(&["daemon-reload"])?;
        systemctl(&["enable", "--now", UNIT])?;
        return Ok(true);
    }
    if restart_wanted {
        kickstart()?;
        return Ok(true);
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn unit_runs_the_sidecar_and_survives_a_crash() {
        let unit = render(
            &PathBuf::from("/opt/arxa/arxa-studio"),
            &PathBuf::from("/home/e/.arxa/dsh/engine-stdio.log"),
        );
        assert!(unit.contains("ExecStart=/opt/arxa/arxa-studio --no-open"));
        assert!(unit.contains("Restart=always"));
        // The launchd KeepAlive.PathState counterpart: no binary, no restart loop.
        assert!(unit.contains("ConditionPathExists=/opt/arxa/arxa-studio"));
        assert!(unit.contains("WantedBy=default.target"));
        assert!(unit.contains("StandardOutput=append:/home/e/.arxa/dsh/engine-stdio.log"));
        // A user unit must never reach for root.
        assert!(!unit.contains("sudo"));
        assert!(!unit.contains("multi-user.target"));
    }

    #[test]
    fn environment_values_are_quoted_and_escaped() {
        let line = env_line("ARXA_HOME", "/home/e/my \"odd\" dir\\x");
        assert_eq!(line, "Environment=\"ARXA_HOME=/home/e/my \\\"odd\\\" dir\\\\x\"\n");
    }

    #[test]
    fn unit_path_prefers_xdg_config_home() {
        // Serialised implicitly: these two vars are only read here.
        std::env::set_var("XDG_CONFIG_HOME", "/tmp/xdg");
        assert_eq!(unit_path().unwrap(), PathBuf::from("/tmp/xdg/systemd/user/arxa-engine.service"));
        std::env::remove_var("XDG_CONFIG_HOME");
        std::env::set_var("HOME", "/home/e");
        assert_eq!(unit_path().unwrap(), PathBuf::from("/home/e/.config/systemd/user/arxa-engine.service"));
    }
}
