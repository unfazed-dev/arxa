// arxa studio mobile shell — pairing/connecting placeholder screen.
// ponytail: this screen is the entire app until the iroh transport (M1) and QR
// pairing (M2) land. Once connected, the webview navigates to the engine-served
// studio UI (M4), mirroring desktop's studio_url flow.

const invoke = window.__TAURI__?.core?.invoke;

const sections = {
  not_paired: document.getElementById("state-not-paired"),
  connecting: document.getElementById("state-connecting"),
};

function show(state) {
  for (const [name, el] of Object.entries(sections)) {
    el.hidden = name !== state;
  }
}

async function refresh() {
  if (!invoke) {
    // Plain-browser preview: no Tauri runtime.
    show("not_paired");
    return;
  }
  try {
    const status = await invoke("connection_status");
    if (status.state === "connected" && status.studio_url) {
      // ponytail: stubbed studio_url navigation path — same pattern as desktop.
      window.location.replace(status.studio_url);
      return;
    }
    show(status.state === "connecting" ? "connecting" : "not_paired");
  } catch {
    show("not_paired");
  }
}

document.getElementById("scan-btn").addEventListener("click", async () => {
  const errEl = document.getElementById("pairing-error");
  errEl.hidden = true;
  if (!invoke) return;
  try {
    await invoke("begin_pairing");
  } catch (e) {
    errEl.textContent = String(e);
    errEl.hidden = false;
  }
});

refresh();
setInterval(refresh, 2000);
