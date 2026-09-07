// Welcome screen (desktop shell): poll the local arxa studio server and
// navigate to it once it answers. This page is the shell's own launch view —
// "Launching…" — and is also where the watchdog returns when the server goes
// away ("Reconnecting…"). The "Waiting for main app…" copy belongs ONLY to
// the secondary browser instance, which is served by the studio
// waiting-page plugin, not this file.
//
// The URL comes from the Rust side (ARXA_STUDIO_URL override or the
// canonical default http://arxa.studio.localhost:7891).

// 200ms, not 1000: on the 2026-09-07 boot the studio was ready at +2.1s and
// this page still sat on the splash for most of a second waiting for its
// next tick. Two polls (port, then ready) each paid that. Attempt counts
// below are scaled so the status copy flips at the same wall-clock moments.
const POLL_INTERVAL_MS = 200;

async function resolveStudioUrl() {
  try {
    return await window.__TAURI__.core.invoke("studio_url");
  } catch {
    // Fallback if IPC is unavailable (e.g. page opened outside Tauri).
    return "http://arxa.studio.localhost:7891";
  }
}

async function isReachable(url) {
  try {
    // no-cors: we only care that the server answers, not what it says.
    await fetch(url, { mode: "no-cors", cache: "no-store" });
    return true;
  } catch {
    return false;
  }
}

// The port answering is not the app being ready: the studio opens its port
// BEFORE its plugins finish applying, so navigating then shows the user the
// app loading (2026-09-07). /__arxa/ready answers 200 once the studio's org
// shell is loaded, 503 while it is still booting. An older studio has no such
// route: a 404 or a CORS failure reads as "unknown", and the port poll stands.
const READY_CAP = 150; // 30s at 200ms
let readyNote = "";
async function isReady(url) {
  try {
    const res = await fetch(url.replace(/\/?(\?.*)?$/, "") + "/__arxa/ready", { cache: "no-store" });
    readyNote = "status" + res.status;
    if (res.status === 503) return false;
    return true; // 200, or a studio without the route
  } catch (e) {
    readyNote = "err:" + String(e && e.message || e).slice(0, 40);
    return true; // no CORS on the answer = older studio; the port poll decided
  }
}
// Boot trace (2026-09-07): the shell has no log of its own, so the tick that
// opens the studio posts its timeline to the engine's trace route. text/plain
// keeps it a simple request — it reaches the engine even though this page's
// origin cannot read the answer.
const T0 = performance.now();
const marks = [];
const mark = (n) => marks.push(n + "=" + Math.round(performance.now() - T0));
function postShellTrace(url) {
  try {
    fetch(url.replace(/\/?(\?.*)?$/, "") + "/__arxa/artifacts/trace", {
      method: "POST", mode: "no-cors", keepalive: true, headers: { "content-type": "text/plain" },
      body: JSON.stringify({ relPath: "shell", outcome: "open", totalMs: Math.round(performance.now() - T0), bundleWarm: true, marks: marks.join(" ") }),
    }).catch(() => {});
  } catch { /* trace only */ }
}

(async () => {
  const url = await resolveStudioUrl();
  const status = document.getElementById("status");

  let attempts = 0;
  let readyPolls = 0;
  const tick = async () => {
    // Reachable but not ready: keep the splash up to READY_CAP more ticks, then
    // open anyway rather than hang on a studio that never flips its flag.
    const reachable = await isReachable(url);
    if (reachable && marks.length === 0) mark("reachable");
    if (reachable && (readyPolls++ >= READY_CAP || await isReady(url))) {
      mark("ready(" + readyNote + ")");
      mark("invoke");
      postShellTrace(url);
      // The navigation MUST be app-initiated: WKWebView drops the
      // BrowserAuth exchange cookie when the 303 answers a cross-site JS
      // navigation from this bundled page (tauri.localhost → studio
      // origin), which parks the window on the 401 hint forever — the
      // 2026-09-05 lockout, pinned by desktop/e2e's auth gate. The Rust
      // side recomputes the tokenized studio URL itself. The location
      // fallback only fires outside Tauri (plain browser), where a typed
      // or clicked navigation is first-party anyway.
      try {
        await window.__TAURI__.core.invoke("open_studio");
      } catch {
        window.location.replace(url);
      }
      return;
    }
    attempts += 1;
    // First moments: launch copy. If the server still isn't up after a few
    // seconds (or died mid-session and the watchdog sent us back here),
    // switch to honest reconnect copy rather than pretending to launch.
    if (attempts === 25) {
      status.textContent = "Getting things ready…";
    } else if (attempts === 75) {
      status.textContent = "Reconnecting…";
    }
    setTimeout(tick, POLL_INTERVAL_MS);
  };
  tick();
})();
