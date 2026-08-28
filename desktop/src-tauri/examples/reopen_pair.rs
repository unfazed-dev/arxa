// Diagnostic repro for "Could not open pairing" on re-pair.
// Replicates open_pairing_window's exact logic (get→focus else build label
// "pair"), then: open → close (like the native close button) → reopen after
// 2s → report. Run: cargo run --example reopen_pair
use tauri::Manager;

fn open_pair(app: &tauri::AppHandle) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("pair") {
        return win
            .set_focus()
            .map_err(|e| format!("FOCUS-ERR: {e}"));
    }
    tauri::WebviewWindowBuilder::new(
        app,
        "pair",
        tauri::WebviewUrl::App("pair.html".into()),
    )
    .title("Pair Mobile Device")
    .inner_size(420.0, 620.0)
    .resizable(false)
    .build()
    .map(|_| ())
    .map_err(|e| format!("BUILD-ERR: {e}"))
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let h = app.handle().clone();
            std::thread::spawn(move || {
                let step = |label: &str, r: Result<(), String>| {
                    println!("REPRO {label}: {:?}", r);
                };
                step("open#1", open_pair(&h));
                std::thread::sleep(std::time::Duration::from_millis(1500));
                // Simulate the user clicking the native close button.
                match h.get_webview_window("pair") {
                    Some(w) => println!("REPRO close#1: {:?}", w.close()),
                    None => println!("REPRO close#1: window missing"),
                }
                // Immediate re-open (races the async destroy on purpose).
                std::thread::sleep(std::time::Duration::from_millis(150));
                step("open#2-after-150ms", open_pair(&h));
                // Human-scale re-open.
                std::thread::sleep(std::time::Duration::from_millis(2000));
                step("open#3-after-2s", open_pair(&h));
                std::thread::sleep(std::time::Duration::from_millis(1000));
                println!(
                    "REPRO final: pair-window-present={}",
                    h.get_webview_window("pair").is_some()
                );
                std::process::exit(0);
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("run failed");
}
