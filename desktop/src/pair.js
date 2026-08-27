// Pair-mobile-device window: mints a single-use pairing ticket, shows the
// locally rendered QR (SVG from Rust — no network service), counts down its
// 10-minute expiry, and lists paired devices with revoke.

const invoke = (cmd, args) => window.__TAURI__.core.invoke(cmd, args);

const statusEl = document.getElementById("pair-status");
const qrEl = document.getElementById("qr");
const countdownEl = document.getElementById("countdown");
const regenBtn = document.getElementById("regen");
const listEl = document.getElementById("device-list");

let expiresAtMs = null;

async function mint() {
  regenBtn.hidden = true;
  countdownEl.textContent = "";
  qrEl.innerHTML = "";
  statusEl.textContent = "Preparing pairing code…";
  try {
    const res = await invoke("pairing_begin");
    expiresAtMs = res.expires_at_ms;
    qrEl.innerHTML = res.qr_svg; // SVG string rendered locally by the shell
    statusEl.textContent = "Scan this code with the Arxa mobile app.";
  } catch (e) {
    expiresAtMs = null;
    statusEl.textContent = String(e);
    regenBtn.hidden = false;
    regenBtn.textContent = "Retry";
  }
}

function renderCountdown() {
  if (expiresAtMs === null) return;
  const left = Math.max(0, expiresAtMs - Date.now());
  if (left === 0) {
    qrEl.innerHTML = "";
    statusEl.textContent = "Code expired.";
    countdownEl.textContent = "";
    regenBtn.hidden = false;
    regenBtn.textContent = "Generate new code";
    expiresAtMs = null;
    return;
  }
  const m = Math.floor(left / 60000);
  const s = Math.floor((left % 60000) / 1000);
  countdownEl.textContent = `Code expires in ${m}:${String(s).padStart(2, "0")}`;
}

function renderDevices(peers) {
  listEl.innerHTML = "";
  if (!peers.length) {
    const li = document.createElement("li");
    li.className = "hint";
    li.textContent = "None yet.";
    listEl.appendChild(li);
    return;
  }
  for (const p of peers) {
    const li = document.createElement("li");
    const name = document.createElement("span");
    name.textContent = p.label;
    name.title = p.node_id;
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = "Revoke";
    btn.addEventListener("click", async () => {
      btn.disabled = true;
      try {
        await invoke("pairing_revoke", { nodeId: p.node_id });
      } catch (e) {
        statusEl.textContent = String(e);
      }
      await refresh();
    });
    li.append(name, btn);
    listEl.appendChild(li);
  }
}

async function refresh() {
  try {
    const st = await invoke("pairing_status");
    renderDevices(st.peers);
    // A successful first pairing consumes the ticket server-side.
    if (expiresAtMs !== null && st.ticket_expires_at_ms === null) {
      expiresAtMs = null;
      qrEl.innerHTML = "";
      countdownEl.textContent = "";
      statusEl.textContent = "Device paired.";
      regenBtn.hidden = false;
      regenBtn.textContent = "Pair another device";
    }
  } catch {
    // IPC unavailable (page opened outside Tauri) — leave the UI as-is.
  }
}

regenBtn.addEventListener("click", mint);
setInterval(renderCountdown, 500);
setInterval(refresh, 1500);
mint().then(refresh);
