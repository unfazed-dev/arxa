// Prevents an extra console window on desktop-target checks; harmless on mobile.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    arxa_mobile_lib::run()
}
