//! Arxa desktop shell (decision D30): a thin Tauri window over the locally
//! served arxa studio web UI. The dsh + PI engine (`bin/arxa-studio.mjs`) and
//! the compiled `arxa` Dart CLI ship as sidecars — this shell never
//! reimplements engine or entitlement logic.

/// Default address of the locally served studio UI (D30).
const DEFAULT_STUDIO_URL: &str = "http://localhost:7891";

/// Resolve the studio server URL. Overridable via `ARXA_STUDIO_URL` so dev
/// setups (e.g. `arxa.studio.localhost:7891`) and future config files can
/// point the shell elsewhere without a rebuild.
#[tauri::command]
fn studio_url() -> String {
    std::env::var("ARXA_STUDIO_URL")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_STUDIO_URL.to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![studio_url])
        .run(tauri::generate_context!())
        .expect("error while running arxa desktop shell");
}
