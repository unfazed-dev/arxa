//! Arxa desktop shell (decision D30): a thin Tauri window over the locally
//! served arxa studio web UI. The dsh + PI engine (`bin/arxa-studio.mjs`) and
//! the compiled `arxa` Dart CLI ship as sidecars — this shell never
//! reimplements engine or entitlement logic.
//!
//! Sidecar auto-spawn (locked decision, option B with riders):
//! 1. Probe the studio port first — if something already serves it (launchd on
//!    a dev machine, a hand-launched server), spawn NOTHING and never touch
//!    that process. launchd stays the owner wherever it is installed.
//! 2. Only a child THIS process spawned is killed on exit (SIGTERM, short
//!    grace, then SIGKILL). We never kill a server we didn't start.
//! 3. Single-instance guard: a second app launch focuses the first window
//!    instead of racing it for the port.

use std::net::{TcpStream, ToSocketAddrs};
use std::sync::Mutex;
use std::time::Duration;

use tauri::Manager;
use tauri_plugin_shell::process::CommandChild;
use tauri_plugin_shell::ShellExt;

/// Default address of the locally served studio UI (D30). The canonical
/// origin everywhere arxa is used (README/grill-decisions): `*.localhost`
/// resolves to loopback at the OS getaddrinfo layer (verified), so the TCP
/// probe, the webview, and the browser all agree on one origin — mixing in
/// `127.0.0.1` would split sessionStorage/presence state across origins.
const DEFAULT_STUDIO_URL: &str = "http://arxa.studio.localhost:7891";

/// The child server process, present only when THIS app instance spawned it.
/// `None` means an external owner (launchd / dev server) is serving the port
/// and we must not manage — let alone kill — anything.
struct SpawnedServer(Mutex<Option<CommandChild>>);

/// Resolve the studio server URL. Overridable via `ARXA_STUDIO_URL` so
/// non-standard setups and future config files can point the shell
/// elsewhere without a rebuild.
#[tauri::command]
fn studio_url() -> String {
    std::env::var("ARXA_STUDIO_URL")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_STUDIO_URL.to_string())
}

/// Extract `host:port` from the studio URL (scheme/path stripped, default
/// port 80). Kept dependency-free — good enough for http(s) loopback URLs.
fn studio_host_port(url: &str) -> String {
    let no_scheme = url.split("://").nth(1).unwrap_or(url);
    let authority = no_scheme.split('/').next().unwrap_or(no_scheme);
    if authority.contains(':') {
        authority.to_string()
    } else {
        format!("{authority}:80")
    }
}

/// True when something already accepts TCP connections on the studio port.
fn server_reachable(url: &str) -> bool {
    let hp = studio_host_port(url);
    let Ok(addrs) = hp.to_socket_addrs() else {
        return false;
    };
    for addr in addrs {
        if TcpStream::connect_timeout(&addr, Duration::from_millis(400)).is_ok() {
            return true;
        }
    }
    false
}

/// All live descendant PIDs of `pid` (children, grandchildren, …) via
/// `pgrep -P`, breadth-first. Needed because the sidecar is a launcher: the
/// wrapper node process spawns the real dsh server as a grandchild, and
/// killing only the direct child would orphan the server on the port.
#[cfg(unix)]
fn descendants(pid: u32) -> Vec<u32> {
    let mut all = Vec::new();
    let mut queue = vec![pid];
    while let Some(p) = queue.pop() {
        if let Ok(out) = std::process::Command::new("pgrep")
            .args(["-P", &p.to_string()])
            .output()
        {
            for line in String::from_utf8_lossy(&out.stdout).lines() {
                if let Ok(c) = line.trim().parse::<u32>() {
                    all.push(c);
                    queue.push(c);
                }
            }
        }
    }
    all
}

/// Rider 2: graceful shutdown of OUR child only — including its whole process
/// tree. SIGTERM first so the engine can flush, short grace, then SIGKILL for
/// stragglers. Errors are ignored — processes may have exited on their own.
fn kill_spawned(app: &tauri::AppHandle) {
    let Some(state) = app.try_state::<SpawnedServer>() else {
        return;
    };
    let Some(child) = state.0.lock().ok().and_then(|mut g| g.take()) else {
        return;
    };
    #[cfg(unix)]
    {
        let pid = child.pid();
        // Snapshot the tree BEFORE terminating the parent, otherwise the
        // grandchildren are reparented to PID 1 and become unfindable.
        let tree = descendants(pid);
        let term = |p: u32, sig: &str| {
            let _ = std::process::Command::new("kill")
                .args([sig, &p.to_string()])
                .status();
        };
        term(pid, "-TERM");
        for p in &tree {
            term(*p, "-TERM");
        }
        std::thread::sleep(Duration::from_millis(1200));
        for p in &tree {
            term(*p, "-KILL");
        }
    }
    let _ = child.kill();
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Rider 3: second launch focuses the existing window; it never gets a
        // chance to probe-and-spawn a duplicate server.
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(win) = app.get_webview_window("main") {
                let _ = win.set_focus();
            }
        }))
        .plugin(tauri_plugin_shell::init())
        .manage(SpawnedServer(Mutex::new(None)))
        .invoke_handler(tauri::generate_handler![studio_url])
        .setup(|app| {
            let url = studio_url();
            // Rider 1: probe before spawn. An externally owned server (launchd
            // on the dev machine) always wins; we only self-heal a closed port
            // for public installs that have no service manager.
            if !server_reachable(&url) {
                match app
                    .shell()
                    .sidecar("arxa-studio")
                    .map(|c| c.args(["--no-open"]))
                    .and_then(|c| c.spawn())
                {
                    Ok((_rx, child)) => {
                        if let Ok(mut guard) = app.state::<SpawnedServer>().0.lock() {
                            guard.replace(child);
                        }
                    }
                    Err(e) => {
                        // Non-fatal: the waiting screen keeps polling, and a
                        // manually started server still gets picked up.
                        eprintln!("[arxa-desktop] sidecar spawn failed: {e}");
                    }
                }
            }
            // Watchdog: if the server dies while the shell is showing its UI,
            // send the window back to the bundled waiting page (brand logo +
            // "Waiting for main app to start…"), which polls and returns to
            // the UI once the server is back. `home` is captured now, while
            // the window still shows the bundled page.
            let home = app
                .get_webview_window("main")
                .and_then(|w| w.url().ok());
            if let Some(home) = home {
                let handle = app.handle().clone();
                let watch_url = url.clone();
                std::thread::spawn(move || {
                    let mut was_up = false;
                    loop {
                        std::thread::sleep(Duration::from_secs(2));
                        let up = server_reachable(&watch_url);
                        if was_up && !up {
                            eprintln!("[arxa-desktop] server lost - showing waiting page");
                            if let Some(mut win) = handle.get_webview_window("main") {
                                let _ = win.navigate(home.clone());
                            }
                        }
                        was_up = up;
                    }
                });
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building arxa desktop shell")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                kill_spawned(app);
            }
        });
}
