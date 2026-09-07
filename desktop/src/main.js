// Welcome screen (desktop shell): poll the local arxa studio server and
// navigate to it once it answers. This page is the shell's own launch view —
// "Launching…" — and is also where the watchdog returns when the server goes
// away ("Reconnecting…"). The "Waiting for main app…" copy belongs ONLY to
// the secondary browser instance, which is served by the studio
// waiting-page plugin, not this file.
//
// The URL comes from the Rust side (ARXA_STUDIO_URL override or the
// canonical default http://arxa.studio.localhost:7891).

const POLL_INTERVAL_MS = 1000;

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
const READY_CAP = 30;
async function isReady(url) {
  try {
    const res = await fetch(url.replace(/\/?(\?.*)?$/, "") + "/__arxa/ready", { cache: "no-store" });
    if (res.status === 503) return false;
    return true; // 200, or a studio without the route
  } catch {
    return true; // no CORS on the answer = older studio; the port poll decided
  }
}

(async () => {
  const url = await resolveStudioUrl();
  const status = document.getElementById("status");

  let attempts = 0;
  let readyPolls = 0;
  const tick = async () => {
    // Reachable but not ready: keep the splash up to READY_CAP more ticks, then
    // open anyway rather than hang on a studio that never flips its flag.
    if (await isReachable(url) && (readyPolls++ >= READY_CAP || await isReady(url))) {
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
    if (attempts === 5) {
      status.textContent = "Getting things ready…";
    } else if (attempts === 15) {
      status.textContent = "Reconnecting…";
    }
    setTimeout(tick, POLL_INTERVAL_MS);
  };
  tick();
})();
