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

(async () => {
  const url = await resolveStudioUrl();
  const status = document.getElementById("status");

  let attempts = 0;
  const tick = async () => {
    if (await isReachable(url)) {
      window.location.replace(url);
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
