// Waiting screen: poll the local arxa studio server and navigate to it once
// it answers. The URL comes from the Rust side (ARXA_STUDIO_URL override or
// the default http://localhost:7891).

const POLL_INTERVAL_MS = 1000;

async function resolveStudioUrl() {
  try {
    return await window.__TAURI__.core.invoke("studio_url");
  } catch {
    // Fallback if IPC is unavailable (e.g. page opened outside Tauri).
    return "http://localhost:7891";
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
  document.getElementById("hint").textContent = `Looking for ${url}`;

  const tick = async () => {
    if (await isReachable(url)) {
      window.location.replace(url);
      return;
    }
    setTimeout(tick, POLL_INTERVAL_MS);
  };
  tick();
})();
