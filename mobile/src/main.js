// arxa studio mobile shell — pairing screen wired to the iroh transport.
// Flow (docs/plans/mobile-pairing-transport.md): scan the desktop-minted QR
// (M2) or paste the `arxa-pair:...` code manually -> begin_pairing(ticket) ->
// poll connection_status every 2s -> on connected, navigate the webview to the
// engine-served studio_url (M4), mirroring desktop's studio_url flow.

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

function showError(message) {
  const el = document.getElementById("pairing-error");
  el.textContent = message;
  el.hidden = false;
}

function clearError() {
  const el = document.getElementById("pairing-error");
  el.textContent = "";
  el.hidden = true;
}

let navigated = false;

async function refresh() {
  if (!invoke) {
    // Plain-browser preview: no Tauri runtime.
    show("not_paired");
    return;
  }
  try {
    const status = await invoke("connection_status");
    if (status.state === "connected" && status.studio_url) {
      if (!navigated) {
        navigated = true;
        window.location.replace(status.studio_url);
      }
      return;
    }
    show(status.state === "connecting" ? "connecting" : "not_paired");
  } catch {
    show("not_paired");
  }
}

async function pairWith(ticket) {
  if (!invoke) {
    showError("Tauri runtime unavailable (browser preview).");
    return;
  }
  clearError();
  try {
    await invoke("begin_pairing", { ticket });
    await refresh();
  } catch (e) {
    showError(String(e));
  }
}

// Returns the scanned QR content, throwing when no scanner is available
// (host/dev builds — the plugin only exists on iOS/Android).
async function scanTicket() {
  const scanner = window.__TAURI__?.barcodeScanner;
  if (scanner) {
    await scanner.requestPermissions();
    const scanned = await scanner.scan({ windowed: false, formats: ["QR_CODE"] });
    return scanned.content;
  }
  // Fallback: raw plugin invokes in case the global API script is not injected.
  await invoke("plugin:barcode-scanner|request_permissions");
  const scanned = await invoke("plugin:barcode-scanner|scan", {
    windowed: false,
    formats: ["QR_CODE"],
  });
  return scanned.content;
}

document.getElementById("scan-btn").addEventListener("click", async () => {
  clearError();
  if (!invoke) {
    showError("Tauri runtime unavailable (browser preview).");
    return;
  }
  try {
    const ticket = await scanTicket();
    if (ticket) await pairWith(ticket);
  } catch (e) {
    // No camera/scanner (e.g. host dev build): fall back to manual entry.
    document.getElementById("manual-form").hidden = false;
    showError(`Scanner unavailable — paste the pairing code instead. (${String(e)})`);
  }
});

document.getElementById("manual-link").addEventListener("click", () => {
  const form = document.getElementById("manual-form");
  form.hidden = !form.hidden;
  if (!form.hidden) document.getElementById("ticket-input").focus();
});

document.getElementById("manual-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const ticket = document.getElementById("ticket-input").value.trim();
  if (ticket) await pairWith(ticket);
});

refresh();
setInterval(refresh, 2000);

// ── OS push token (M7 seam) ──────────────────────────────────────────────
// Mint the APNs/FCM device token via tauri-plugin-mobile-push and hand it
// to Rust (`set_push_token`); the connection layer then sends the PUSH
// frame over the pairing tunnel at (re)connect time. Token values follow
// cairn-push's Platform vocabulary: "apns" (iOS) / "fcm" (Android).
// Desktop/dev-browser: no OS rail exists — skipped by design.

function pushPlatform() {
  const ua = navigator.userAgent;
  if (/iPhone|iPad|iPod/.test(ua)) return "apns";
  if (/Android/.test(ua)) return "fcm";
  return null;
}

async function registerOsPush() {
  const platform = pushPlatform();
  const core = window.__TAURI__?.core;
  if (!platform || !core?.invoke) return;
  try {
    const { granted } = await core.invoke("plugin:mobile-push|request_permission");
    if (!granted) return;
    const { token } = await core.invoke("plugin:mobile-push|get_token");
    if (token) await core.invoke("set_push_token", { platform, token });
    // APNs refresh / FCM rotation: stash the new token; it rides the next
    // (re)connect's PUSH frame (mid-session re-send is deliberately not
    // wired — rotation is rare and every app launch re-registers).
    if (core.addPluginListener) {
      core.addPluginListener("mobile-push", "token-received", (event) => {
        const t = event?.payload?.token;
        if (t) core.invoke("set_push_token", { platform, token: t });
      });
    }
  } catch (e) {
    // Expected until the operator drops in google-services.json (Android)
    // or a provisioning profile with Push Notifications (iOS) — push stays
    // off, sync is unaffected. Never escalate to the pairing UI.
    console.warn("arxa-mobile: push token minting skipped:", e);
  }
}

registerOsPush();
