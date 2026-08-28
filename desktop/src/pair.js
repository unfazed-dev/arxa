// Pair-mobile-device window: mints a single-use pairing ticket, shows the
// locally rendered QR (SVG from Rust — no network service), counts down its
// 10-minute expiry (auto-minting a fresh code just before it lapses, so the
// window never sits on a dead/blank code), and lists paired devices with
// revoke.

const invoke = (cmd, args) => window.__TAURI__.core.invoke(cmd, args);

// Live theme: the studio webview reports accent + dark to the shell
// (report_theme); we read the cache on boot and follow the broadcast, so this
// window tracks the studio's swatch/dark toggle instantly instead of only the
// OS setting. Falls back to system dark + moss accent until the first report.
function applyTheme(t) {
  if (!t) return;
  const root = document.documentElement;
  if (t.accent) root.style.setProperty("--acc", t.accent);
  root.dataset.theme = t.dark ? "dark" : "light";
}
invoke("get_theme").then(applyTheme).catch(() => {});
try {
  window.__TAURI__.event.listen("arxa://theme", (e) => applyTheme(e.payload));
} catch {
  // Event API absent (page opened outside Tauri) — theme stays on defaults.
}

const statusEl = document.getElementById("pair-status");
const qrEl = document.getElementById("qr");
const qrWrapEl = document.getElementById("qr-wrap");
const countdownEl = document.getElementById("countdown");
const codeRowEl = document.getElementById("code-row");
const codeTextEl = document.getElementById("code-text");
const copyBtn = document.getElementById("copy-code");
const regenBtn = document.getElementById("regen");
const listEl = document.getElementById("device-list");

let expiresAtMs = null;

async function mint() {
  regenBtn.hidden = true;
  countdownEl.textContent = "";
  qrEl.innerHTML = "";
  codeRowEl.hidden = true;
  codeTextEl.textContent = "";
  statusEl.textContent = "Preparing pairing code…";
  try {
    const res = await invoke("pairing_begin");
    expiresAtMs = res.expires_at_ms;
    qrEl.innerHTML = res.qr_svg; // SVG minted by the shell, brand logo already excavated in
    codeTextEl.textContent = res.ticket;
    codeRowEl.hidden = false;
    statusEl.textContent = "Scan this code with the Arxa mobile app.";
  } catch (e) {
    expiresAtMs = null;
    statusEl.textContent = String(e);
    regenBtn.hidden = false;
    regenBtn.textContent = "Retry";
  }
}

copyBtn.addEventListener("click", async () => {
  const ticket = codeTextEl.textContent;
  if (!ticket) return;
  try {
    await navigator.clipboard.writeText(ticket);
    copyBtn.textContent = "Copied!";
  } catch {
    // Clipboard API unavailable — select the text for manual copy.
    const range = document.createRange();
    range.selectNodeContents(codeTextEl);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    copyBtn.textContent = "Press ⌘C";
  }
  setTimeout(() => (copyBtn.textContent = "Copy code"), 2000);
});

function renderCountdown() {
  if (expiresAtMs === null) return;
  const left = Math.max(0, expiresAtMs - Date.now());
  // Re-mint just BEFORE expiry so a scannable, valid code is always on
  // screen — the window never shows a blank "expired" state. Nulling
  // expiresAtMs first stops this interval re-entering while mint runs.
  if (left <= 1500) {
    expiresAtMs = null;
    mint();
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
    const left = document.createElement("span");
    left.className = "grow";
    const name = document.createElement("span");
    name.className = "device-name";
    name.textContent = p.label;
    // The device's arxa identity (iroh EndpointId), shortened; full id on
    // hover for support/debugging.
    const id = document.createElement("code");
    id.className = "device-id";
    id.textContent = p.node_id.slice(0, 8);
    id.title = p.node_id;
    left.append(name, id);
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
    li.append(left, btn);
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
      codeRowEl.hidden = true;
      codeTextEl.textContent = "";
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
