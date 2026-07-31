//! probe-runner — drop-in debug-probe module for Dioxus desktop apps.
//!
//! Provides:
//! - `install()` — call once at startup (e.g. in your root component
//!   via `use_effect`). Installs a JS console-relay shim that pipes
//!   every `console.log/warn/error` call to host stderr as a single
//!   line `[probe-runner-console] {...}`.
//! - `probe_dom(selector)` — returns `{x,y,w,h,childCount,tag}` for
//!   the first match. Output also lands on host stderr as
//!   `[probe-runner-dom] {...}` so the `dom.py` script can read it
//!   without an in-process channel.
//! - `dom_snapshot(selector, max_depth)` — light-weight DOM tree
//!   rooted at `selector`.
//! - `tail_console(max_lines)` — returns the last N captured console
//!   lines from the in-webview ring buffer.
//!
//! Wire-up:
//!
//! 1. Copy this file to `src/presentation/debug_probe.rs`
//!    (or any `src/` path).
//! 2. Add to `Cargo.toml`:
//!
//!    ```toml
//!    [features]
//!    debug-probe = []
//!    ```
//!
//! 3. In `lib.rs` or `main.rs`:
//!
//!    ```rust
//!    #[cfg(feature = "debug-probe")]
//!    pub mod debug_probe;
//!    ```
//!
//! 4. In your root component:
//!
//!    ```rust
//!    #[cfg(feature = "debug-probe")]
//!    use_effect(move || { crate::debug_probe::install(); });
//!    ```
//!
//! 5. Run with: `cargo run --features debug-probe …`

#![cfg(feature = "debug-probe")]

use dioxus::prelude::*;
use serde_json::Value;

/// JS shim installed once. Captures console.* into a global ring buffer
/// and emits each event to host stderr (via stdout-of-eval bounce) tagged
/// with `[probe-runner-console]` so the skill can grep for it in `log
/// stream`.
const SHIM: &str = r#"
(() => {
    if (window.__probe_runner_console_buffer) return "already";
    const ring = [];
    const MAX = 1000;
    window.__probe_runner_console_buffer = ring;
    const wrap = (level, original) => function(...args) {
        try {
            const msg = args.map(a => {
                if (typeof a === 'string') return a;
                try { return JSON.stringify(a); } catch (_) { return String(a); }
            }).join(' ');
            const ev = { level, msg, ts: Date.now() };
            ring.push(ev);
            while (ring.length > MAX) ring.shift();
            // Send to host via a synthetic console.info that wry forwards
            // as os_log; if the Rust side wires `with_log_handler` we
            // also get this verbatim.
            (original || console.log).apply(console, args);
            try { window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.probeRunner && window.webkit.messageHandlers.probeRunner.postMessage(JSON.stringify(ev)); } catch (_) {}
        } catch (e) { /* swallow */ }
    };
    console.log = wrap('info', console.log.bind(console));
    console.info = wrap('info', console.info.bind(console));
    console.warn = wrap('warn', console.warn.bind(console));
    console.error = wrap('error', console.error.bind(console));
    return "installed";
})()
"#;

/// Install the JS shim. Safe to call multiple times.
pub fn install() {
    let _ = document::eval(SHIM);
}

/// Return rect + childCount + tag for the first element matching `selector`.
/// Also emits a `[probe-runner-dom]` stderr line so `dom.py` can capture
/// it without an in-process channel.
pub async fn probe_dom(selector: &str) -> Value {
    let js = format!(
        r#"
(() => {{
    const el = document.querySelector({selector});
    if (!el) return {{ selector: {selector}, found: false }};
    const r = el.getBoundingClientRect();
    const out = {{
        selector: {selector},
        found: true,
        tag: el.tagName,
        id: el.id || null,
        cls: el.className || null,
        x: r.x, y: r.y, w: r.width, h: r.height,
        childCount: el.childElementCount,
    }};
    try {{ console.info('[probe-runner-dom]', JSON.stringify(out)); }} catch(_) {{}}
    return out;
}})()
"#,
        selector = serde_json::to_string(selector).unwrap()
    );
    match document::eval(&js).await {
        Ok(v) => v,
        Err(e) => Value::String(format!("eval error: {e}")),
    }
}

/// Light-weight DOM tree dump rooted at `selector`, up to `max_depth`.
pub async fn dom_snapshot(selector: &str, max_depth: usize) -> Value {
    let js = format!(
        r#"
(() => {{
    function walk(el, depth) {{
        if (depth > {max_depth} || !el) return null;
        const out = {{ tag: el.tagName, id: el.id || null, cls: el.className || null }};
        if (depth < {max_depth} && el.children && el.children.length) {{
            out.children = Array.from(el.children).map(c => walk(c, depth+1));
        }}
        return out;
    }}
    const root = document.querySelector({selector});
    const tree = walk(root, 0);
    try {{ console.info('[probe-runner-dom]', JSON.stringify({{ selector: {selector}, tree }})); }} catch(_) {{}}
    return tree;
}})()
"#,
        selector = serde_json::to_string(selector).unwrap(),
        max_depth = max_depth,
    );
    match document::eval(&js).await {
        Ok(v) => v,
        Err(e) => Value::String(format!("eval error: {e}")),
    }
}

/// Return the last `max_lines` console events from the in-webview ring.
pub async fn tail_console(max_lines: usize) -> Vec<Value> {
    let js = format!(
        r#"
(() => {{
    const ring = window.__probe_runner_console_buffer || [];
    return ring.slice(-{max_lines});
}})()
"#,
        max_lines = max_lines
    );
    match document::eval(&js).await {
        Ok(Value::Array(a)) => a,
        Ok(other) => vec![other],
        Err(e) => vec![Value::String(format!("eval error: {e}"))],
    }
}
