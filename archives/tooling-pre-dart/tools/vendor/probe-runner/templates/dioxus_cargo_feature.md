# Wiring `dioxus_debug_probe.rs` into a Dioxus crate

1. Copy `dioxus_debug_probe.rs` from this `templates/` directory to your
   crate, e.g. `src/presentation/debug_probe.rs` or any path you prefer.

2. Add the feature flag to the crate's `Cargo.toml`:

   ```toml
   [features]
   debug-probe = []
   ```

3. Conditionally expose the module from `lib.rs` (or `main.rs`):

   ```rust
   #[cfg(feature = "debug-probe")]
   pub mod debug_probe;          // or `pub mod presentation::debug_probe;`
   ```

4. Install the JS shim once at startup. In your root component:

   ```rust
   #[component]
   fn root() -> Element {
       #[cfg(feature = "debug-probe")]
       use_effect(move || {
           crate::debug_probe::install();
       });

       rsx! { /* … */ }
   }
   ```

5. Trigger probes from any hook, button, keybind, etc.:

   ```rust
   #[cfg(feature = "debug-probe")]
   {
       let _ = crate::debug_probe::probe_dom(".my-canvas svg").await;
       let lines = crate::debug_probe::tail_console(20).await;
   }
   ```

6. Run the binary with the feature enabled:

   ```bash
   cargo run --features debug-probe -- <args>
   # or for an example
   cargo run --features debug-probe --example my_example
   ```

7. From the host, read the probe output:

   ```bash
   python3 .claude/skills/probe-runner/scripts/dom.py <window-owner-name> \
     --selector ".my-canvas svg"
   python3 .claude/skills/probe-runner/scripts/console.py <window-owner-name> --seconds 30
   ```

## Notes

- The module is gated behind `cfg(feature = "debug-probe")` so release
  builds compile without any probe code.
- The JS shim survives navigations only within the same document — call
  `install()` again if your app reloads its webview.
- Output bouncing relies on the macOS unified `log stream`. If your
  binary writes to a regular tty instead, run it via `2>&1 | tee` and
  point the skill at the tee'd file.
