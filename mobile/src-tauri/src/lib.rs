mod connection;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            connection::connection_status,
            connection::begin_pairing,
        ])
        .run(tauri::generate_context!())
        .expect("error while running arxa studio mobile");
}
