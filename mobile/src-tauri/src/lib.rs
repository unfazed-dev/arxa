pub mod connection;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default()
        .manage(connection::ConnectionManager::default())
        .invoke_handler(tauri::generate_handler![
            connection::connection_status,
            connection::begin_pairing,
            connection::set_push_token,
        ])
        .setup(|app| {
            // Silent reconnect from stored pairing (Connecting until it
            // succeeds or falls back to NotPaired).
            connection::attempt_reconnect(app.handle());
            Ok(())
        });

    // QR pairing (M2): camera scanner only exists on the mobile targets.
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let builder = builder.plugin(tauri_plugin_barcode_scanner::init());

    // M7 seam: OS push token source (APNs device token / FCM registration
    // token). Foreground presentation is silent — when the app is open the
    // studio UI is already live, so a banner would be pure interruption;
    // backgrounded/locked delivery bypasses this and shows natively.
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let builder = builder.plugin(
        tauri_plugin_mobile_push::Builder::new()
            .ios_foreground_presentation(
                tauri_plugin_mobile_push::ForegroundPresentationOptions::silent(),
            )
            .build(),
    );

    builder
        .run(tauri::generate_context!())
        .expect("error while running arxa studio mobile");
}
