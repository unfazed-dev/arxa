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

pub mod cairn_server;
pub mod pairing;
pub mod pushd;

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
/// When THIS shell spawned the engine. `open_studio` refuses a session file
/// older than this: on every measured boot (2026-09-07) the shell navigated
/// with the PREVIOUS engine's token, watched it rotate 250ms later, and
/// navigated again — a full second of double page load on the boot path.
struct EngineSpawnedAt(Mutex<Option<std::time::SystemTime>>);

fn session_file_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("ARXA_DSH_HOME")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var("HOME")
                .ok()
                .map(|h| std::path::PathBuf::from(h).join(".arxa").join("dsh"))
        })?;
    Some(home.join("desktop-session.json"))
}

/// True once the session file was written after `since` (mtime, no parsing).
fn session_file_newer_than(since: std::time::SystemTime) -> bool {
    session_file_path()
        .and_then(|p| std::fs::metadata(p).ok())
        .and_then(|m| m.modified().ok())
        .map(|t| t > since)
        .unwrap_or(false)
}

/// Resolve the studio server URL. Overridable via `ARXA_STUDIO_URL` so
/// non-standard setups and future config files can point the shell
/// elsewhere without a rebuild.
fn raw_studio_url() -> String {
    std::env::var("ARXA_STUDIO_URL")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_STUDIO_URL.to_string())
}

/// The engine's BrowserAuth launch token (dsh 0.1.2-rc.1), published to
/// $DSH_HOME/desktop-session.json by the profile's arxa-desktop-session
/// plugin at every engine boot. The webview has no human to click the
/// printed `dsh web:` URL, so the shell reads the per-boot token here and
/// lets the waiting page navigate tokenized once — the 303 exchange mints
/// the 30-day signed cookie on this authority (the token itself is
/// authority-agnostic; the cookie binds at mint). ARXA_DSH_HOME overrides
/// the home for gates and sandboxes. A missing or unreadable file degrades
/// to the pre-publisher behaviour: navigate clean, see the engine's 401
/// hint — never something worse.
fn session_token() -> Option<String> {
    let home = std::env::var("ARXA_DSH_HOME")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var("HOME")
                .ok()
                .map(|h| std::path::PathBuf::from(h).join(".arxa").join("dsh"))
        })?;
    let body = std::fs::read_to_string(home.join("desktop-session.json")).ok()?;
    serde_json::from_str::<serde_json::Value>(&body)
        .ok()?
        .get("token")?
        .as_str()
        .map(str::to_owned)
}

/// The studio URL as the webview should load it: the launch token attached
/// whenever the engine has published one. Read fresh on every invocation —
/// the waiting page re-invokes after every engine respawn, and a reboot
/// means a new token. An ARXA_STUDIO_URL that already carries `token=`
/// wins as-is (manual override beats the file).
#[tauri::command]
fn studio_url() -> String {
    let base = raw_studio_url();
    if base.contains("token=") {
        return base;
    }
    match session_token() {
        Some(token) => format!("{}/?token={}", base.trim_end_matches('/'), token),
        None => base,
    }
}

/// Dev-only trace for the auth-gate flow (the app's stderr does not reach
/// the gate runner; eprintln vanishes under LaunchServices too).
fn auth_trace(msg: &str) {
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/arxa-open-studio.trace")
    {
        let _ = writeln!(f, "{msg}");
    }
}

/// App-initiated navigation to the (tokenized) studio URL, in two steps.
///
/// Step 1 (exchange): navigate to the tokenized URL — the engine's 303
/// mints the 30-day cookie. Step 2 (land): once the address has settled
/// on the clean root, navigate to it once more, token-free. Step 2 is
/// load-bearing, not cosmetic: WKWebView STORES the exchange cookie but
/// never SENDS it inside the exchange's own navigation chain
/// (SameSite=Strict withholds it while the chain was initiated from this
/// shell — proven by the e2e auth gate, 2026-09-05: the exchange chain
/// lands on the 401 hint with `cookie=no`, then a fresh first-party
/// navigation sends `cookie=yes` and renders the app). Without step 2 the
/// window parks on the 401 text with a valid cookie sitting in the store.
#[tauri::command]
fn open_studio(app: tauri::AppHandle) {
    // Wait (≤3s) for the engine this shell spawned to publish ITS token;
    // an externally owned engine (no spawn) is taken as-is.
    let spawned_at = app
        .try_state::<EngineSpawnedAt>()
        .and_then(|s| s.0.lock().ok().and_then(|g| *g));
    if let Some(since) = spawned_at {
        let mut waited = 0;
        while !session_file_newer_than(since) && waited < 12 {
            std::thread::sleep(Duration::from_millis(250));
            waited += 1;
        }
        auth_trace(&format!("open_studio: fresh-token wait polls={waited}"));
    }
    let tokenized = studio_url();
    let clean = format!("{}/", raw_studio_url().trim_end_matches('/'));
    auth_trace(&format!(
        "open_studio: tokenized={} clean={}",
        tokenized.contains("token="),
        clean
    ));
    let Ok(url) = tauri::Url::parse(&tokenized) else {
        auth_trace("open_studio: tokenized URL did not parse");
        return;
    };
    let Some(win) = app.get_webview_window("main") else {
        auth_trace("open_studio: no main window");
        return;
    };
    let nav = win.navigate(url);
    auth_trace(&format!("open_studio: navigate#1 err={}", nav.is_err()));
    if tokenized == clean {
        return; // no token published — single navigation is all there is
    }
    std::thread::spawn(move || {
        // Condition-based, not a fixed sleep: the exchange chain settles
        // on the clean root only after the 303 round-trip.
        //
        // Token rotation (2026-09-05 blank-screen-on-install): the engine
        // starts LISTENING before its arxa-desktop-session plugin publishes
        // the new boot's token, and the waiting page's no-cors probe counts
        // any answer — even the 401 — as "up". So the first navigation can
        // carry the PREVIOUS boot's token, which the engine rejects, and
        // the window parks on the 401 text. While unsettled, re-read the
        // session file every tick; when the published token differs from
        // the one we navigated with, navigate again with the fresh one.
        let mut navigated_token = tokenized
            .split("token=")
            .nth(1)
            .map(str::to_owned)
            .unwrap_or_default();
        const BUDGET: usize = 120; // 30s — covers a slow first engine boot
        for i in 0..BUDGET {
            std::thread::sleep(Duration::from_millis(250));
            let Ok(current) = win.url() else {
                auth_trace("open_studio: win.url() failed — thread exits");
                return;
            };
            if i == 0 || i == BUDGET - 1 {
                auth_trace(&format!("open_studio: poll[{i}] url={}", current.as_str()));
            }
            if current.as_str() != clean {
                if let Some(fresh) = session_token() {
                    if fresh != navigated_token {
                        let retok = format!("{}?token={}", clean, fresh);
                        match tauri::Url::parse(&retok) {
                            Ok(u) => {
                                let err = win.navigate(u).is_err();
                                auth_trace(&format!(
                                    "open_studio: token rotated at poll[{i}] — renavigate err={err}"
                                ));
                                navigated_token = fresh;
                            }
                            Err(_) => auth_trace("open_studio: rotated URL did not parse"),
                        }
                        continue;
                    }
                }
            }
            if current.as_str() == clean {
                // The 303 exchange already landed the window on the clean
                // root with the cookie minted; re-navigating here reloaded
                // the whole studio a second time on every boot (2026-09-07
                // trace: only the second load ever painted, ~1s later).
                auth_trace(&format!("open_studio: settled on clean root at poll[{i}]"));
                return;
            }
        }
        auth_trace("open_studio: poll budget exhausted without settling on the clean root");
    });
}

/// Live theme as last reported by the studio webview (arxa-pairing's client
/// half watches the accent swatch + dark toggle). Shell-owned windows (pair)
/// render on a different origin than the studio, so they can't read the
/// studio's localStorage/body attributes — this relay is how they stay on the
/// SAME tokens instead of drifting into a hardcoded copy.
#[derive(Clone, serde::Serialize, serde::Deserialize)]
struct Theme {
    accent: Option<String>,
    dark: bool,
}
struct ThemeState(Mutex<Option<Theme>>);

/// Called by the studio page (remote origin — granted in
/// capabilities/remote-studio.json) on load and on every accent/dark change.
/// Caches for late-opening windows and broadcasts to already-open ones.
#[tauri::command]
fn report_theme(
    app: tauri::AppHandle,
    state: tauri::State<ThemeState>,
    accent: Option<String>,
    dark: bool,
) {
    use tauri::Emitter as _;
    // Only a literal #rrggbb reaches CSS — the value crosses a trust boundary
    // (remote page → shell window style attribute).
    let accent = accent.filter(|v| {
        v.len() == 7 && v.starts_with('#') && v[1..].chars().all(|c| c.is_ascii_hexdigit())
    });
    let theme = Theme { accent, dark };
    *state.0.lock().unwrap() = Some(theme.clone());
    let _ = app.emit("arxa://theme", theme);
}

/// Read the cached theme — pair.js calls this on boot so a window opened
/// after a theme change starts correct instead of waiting for the next event.
#[tauri::command]
fn get_theme(state: tauri::State<ThemeState>) -> Option<Theme> {
    state.0.lock().unwrap().clone()
}

/// Open (or focus) the small "Pair mobile device" window served from the
/// bundled frontend (`pair.html`). Invoked from the menu and the launch page.
#[tauri::command]
fn open_pairing_window(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("pair") {
        return win.set_focus().map_err(|e| e.to_string());
    }
    tauri::WebviewWindowBuilder::new(
        &app,
        "pair",
        tauri::WebviewUrl::App("pair.html".into()),
    )
    .title("Pair Mobile Device")
    .inner_size(420.0, 620.0)
    .resizable(false)
    .build()
    .map(|_| ())
    .map_err(|e| e.to_string())
}

/// Append a "Devices → Pair Mobile Device…" entry to the default app menu.
#[cfg(desktop)]
fn install_pairing_menu(app: &tauri::AppHandle) {
    use tauri::menu::{Menu, MenuItem, SubmenuBuilder};
    let build = || -> tauri::Result<()> {
        let pair_item =
            MenuItem::with_id(app, "pair-mobile", "Pair Mobile Device…", true, None::<&str>)?;
        let devices = SubmenuBuilder::new(app, "Devices").item(&pair_item).build()?;
        let menu = Menu::default(app)?;
        menu.append(&devices)?;
        app.set_menu(menu)?;
        app.on_menu_event(|app, event| {
            if event.id() == "pair-mobile" {
                if let Err(e) = open_pairing_window(app.clone()) {
                    eprintln!("[arxa-desktop] pair window: {e}");
                }
            }
        });
        Ok(())
    };
    if let Err(e) = build() {
        eprintln!("[arxa-desktop] pairing menu install failed: {e}");
    }
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

/// Default update channel (D21: stable/beta channels). Overridable via
/// `ARXA_UPDATE_CHANNEL` (e.g. `beta`) without a rebuild; the endpoints
/// configured in tauri.conf.json point at the `stable` channel, and
/// `check_for_updates` swaps the channel segment for anything else.
const DEFAULT_UPDATE_CHANNEL: &str = "stable";

/// Launch-time update check (D21 channels, D6 endpoint failover).
/// Non-blocking (spawned on the async runtime) and silent on failure — the
/// shell must never refuse to start because the update endpoint is
/// unreachable or unhosted. A downloaded update is staged by the updater
/// and applies on next launch; we never force a restart.
#[cfg(desktop)]
fn check_for_updates(app: &tauri::AppHandle) {
    use tauri_plugin_updater::UpdaterExt;

    let handle = app.clone();
    tauri::async_runtime::spawn(async move {
        let channel = std::env::var("ARXA_UPDATE_CHANNEL")
            .ok()
            .filter(|c| !c.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_UPDATE_CHANNEL.to_string());
        let mut builder = handle.updater_builder();
        if channel != DEFAULT_UPDATE_CHANNEL {
            // Non-stable channel (D21): serve it from the SAME endpoints
            // configured in tauri.conf.json (plugins.updater.endpoints) with
            // the /stable/ segment swapped for /{channel}/ — no hardcoded
            // URL. The configured list is ordered failover (D6: R2 primary
            // first, raw.githubusercontent.com fallback — the updater fails
            // over ONLY on non-2xx and the first 200 + valid manifest wins),
            // so the whole list travels through the swap, order intact.
            //
            // tauri::Config.plugins is a newtype map of serde_json values.
            let stable_seg = format!("/{DEFAULT_UPDATE_CHANNEL}/");
            let channel_seg = format!("/{channel}/");
            let swapped: Vec<String> = handle
                .config()
                .plugins
                .0
                .get("updater")
                .and_then(|u| u.get("endpoints"))
                .and_then(|e| e.as_array())
                .map(|endpoints| {
                    endpoints.iter().filter_map(|v| v.as_str()).map(|url| {
                        if url.contains(&stable_seg) {
                            url.replace(&stable_seg, &channel_seg)
                        } else {
                            // Endpoint outside the channel layout — pass it
                            // through unchanged rather than guessing where a
                            // channel segment would sit.
                            eprintln!(
                                "[arxa-desktop] update endpoint {url:?} has no {stable_seg} segment - using it as configured"
                            );
                            url.to_string()
                        }
                    }).collect()
                })
                .unwrap_or_default();
            if swapped.is_empty() {
                eprintln!(
                    "[arxa-desktop] no updater endpoints configured - cannot swap in channel {channel:?}, skipping update check"
                );
                return;
            }
            // Parse inline so the element type is fixed by builder.endpoints()
            // (tauri-plugin-updater's own Url) instead of naming the url crate
            // here. Parsing leaves {{target}}/{{arch}} percent-encoded; the
            // updater substitutes BOTH the encoded and raw placeholder forms
            // at check time (verified against tauri-plugin-updater 2.10.1).
            let urls: Vec<_> = swapped
                .iter()
                .filter_map(|s| match s.parse() {
                    Ok(url) => Some(url),
                    Err(e) => {
                        eprintln!("[arxa-desktop] malformed update endpoint {s:?}: {e}");
                        None
                    }
                })
                .collect();
            match builder.endpoints(urls) {
                Ok(b) => builder = b,
                Err(e) => {
                    eprintln!("[arxa-desktop] update endpoint rejected: {e}");
                    return;
                }
            }
        }
        let updater = match builder.build() {
            Ok(u) => u,
            Err(e) => {
                eprintln!("[arxa-desktop] updater unavailable: {e}");
                return;
            }
        };
        match updater.check().await {
            Ok(Some(update)) => {
                eprintln!(
                    "[arxa-desktop] update {} available on {channel} - downloading",
                    update.version
                );
                match update.download_and_install(|_, _| {}, || {}).await {
                    Ok(()) => eprintln!(
                        "[arxa-desktop] update installed - applies on next launch"
                    ),
                    Err(e) => eprintln!("[arxa-desktop] update install failed: {e}"),
                }
            }
            Ok(None) => {}
            // Unreachable endpoint / no hosting yet: log and move on.
            Err(e) => eprintln!("[arxa-desktop] update check skipped: {e}"),
        }
    });
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();
    // Rider 3 (stable builds): a second launch focuses the existing window;
    // it never gets a chance to probe-and-spawn a duplicate server.
    // DISABLED in gate builds (`wdio` feature): the self-hosted gate runner
    // shares the machine with the operator's real install, and this rider
    // makes a second launch focus the FIRST instance and exit 0 — the
    // gate's own hermetic launch would surrender to the production app
    // before the WebDriver server ever came up.
    #[cfg(not(feature = "wdio"))]
    let builder = builder.plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
        if let Some(win) = app.get_webview_window("main") {
            let _ = win.set_focus();
        }
    }));
    let builder = builder
        .plugin(tauri_plugin_shell::init())
        // Native folder locator for the create-organisation modal: the studio
        // page (remote origin) calls window.__TAURI__.dialog.open through the
        // global API; the remote-studio capability scopes it to dialog:allow-open.
        .plugin(tauri_plugin_dialog::init())
        .manage(SpawnedServer(Mutex::new(None)))
        .manage(EngineSpawnedAt(Mutex::new(None)))
        .manage(ThemeState(Mutex::new(None)))
        .invoke_handler(tauri::generate_handler![
            studio_url,
            open_studio,
            open_pairing_window,
            report_theme,
            get_theme,
            pairing::pairing_begin,
            pairing::pairing_status,
            pairing::pairing_revoke
        ])
        .setup(|app| {
            #[cfg(desktop)]
            {
                app.handle()
                    .plugin(tauri_plugin_updater::Builder::new().build())?;
                check_for_updates(app.handle());
            }
            // Probing, pairing and logs use the RAW url — the token belongs
            // only in the webview-facing command, never in log lines.
            let url = raw_studio_url();
            // Mobile pairing: iroh endpoint + bridge to the engine server.
            pairing::init(app.handle(), studio_host_port(&url));
            #[cfg(desktop)]
            install_pairing_menu(app.handle());
            // M7: the push sidecar (cairn-pushd) beside the engine — probe,
            // spawn, and publish its reachability to the pairing state.
            pushd::init(app.handle());
            // B2 (ADR-0042): the cairn-server mirror sidecar beside pushd -
            // probe, spawn, loopback 8190; the engine mirrors out over /ingest.
            cairn_server::init(app.handle());
            // Rider 1: probe before spawn. An externally owned server (launchd
            // on the dev machine) always wins; we only self-heal a closed port
            // for public installs that have no service manager.
            eprintln!("[arxa-desktop] probe {} reachable={}", url, server_reachable(&url));
            if !server_reachable(&url) {
                eprintln!("[arxa-desktop] spawning engine sidecar");
                match app
                    .shell()
                    .sidecar("arxa-studio")
                    .map(|c| c.args(["--no-open"]))
                    .and_then(|c| c.spawn())
                {
                    Ok((_rx, child)) => {
                        eprintln!("[arxa-desktop] engine sidecar spawned");
                        if let Ok(mut guard) = app.state::<SpawnedServer>().0.lock() {
                            guard.replace(child);
                        }
                        if let Ok(mut guard) = app.state::<EngineSpawnedAt>().0.lock() {
                            guard.replace(std::time::SystemTime::now());
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
                    let mut ever_up = false;
                    let mut down_ticks: u32 = 0;
                    loop {
                        std::thread::sleep(Duration::from_secs(2));
                        let up = server_reachable(&watch_url);
                        if up {
                            ever_up = true;
                            down_ticks = 0;
                        } else {
                            down_ticks += 1;
                        }
                        if was_up && !up {
                            eprintln!("[arxa-desktop] server lost - showing waiting page");
                            if let Some(win) = handle.get_webview_window("main") {
                                let _ = win.navigate(home.clone());
                            }
                        }
                        // Self-heal (Rider 1's stated intent, previously absent):
                        // when THIS app owns the server (SpawnedServer is Some)
                        // and a previously-up engine stays down for ~6s, respawn
                        // the sidecar instead of polling a corpse forever. A slow
                        // FIRST boot never triggers this — ever_up only latches
                        // after one successful reach — so extraction time cannot
                        // double-spawn. An externally owned server (guard None)
                        // is never managed from here.
                        if !up && ever_up && down_ticks >= 3 {
                            let owned = handle
                                .state::<SpawnedServer>()
                                .0
                                .lock()
                                .map(|g| g.is_some())
                                .unwrap_or(false);
                            if owned {
                                match handle
                                    .shell()
                                    .sidecar("arxa-studio")
                                    .map(|c| c.args(["--no-open"]))
                                    .and_then(|c| c.spawn())
                                {
                                    Ok((_rx, child)) => {
                                        eprintln!("[arxa-desktop] engine respawned");
                                        if let Ok(mut guard) =
                                            handle.state::<SpawnedServer>().0.lock()
                                        {
                                            guard.replace(child);
                                        }
                                        down_ticks = 0;
                                    }
                                    Err(e) => {
                                        eprintln!("[arxa-desktop] engine respawn failed: {e}")
                                    }
                                }
                            }
                        }
                        was_up = up;
                    }
                });
            }
            Ok(())
        });

    // WKWebView boot gate (D3 tiered gate, update-strategy amendment
    // 2026-09-05): register the WebdriverIO plugins ONLY in gate builds.
    // The compile switch is this cargo feature (release never sets it); the
    // runtime switch is the wdio capability file desktop/e2e ships, which
    // the gate build copies into capabilities/ (gitignored there) — an
    // unknown-permission capability would fail a build that lacks the
    // plugin, so the two switches cannot drift apart silently.
    #[cfg(feature = "wdio")]
    let builder = builder
        .plugin(tauri_plugin_wdio_webdriver::init())
        .plugin(tauri_plugin_wdio::init());

    builder
        .build(tauri::generate_context!())
        .expect("error while building arxa desktop shell")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                kill_spawned(app);
                pushd::kill_spawned(app);
                cairn_server::kill_spawned(app);
            }
        });
}
