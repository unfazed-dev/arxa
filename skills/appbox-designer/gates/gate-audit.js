// gallery contrast gate (R9): every probed pairing x light+dark, >= 4.5:1 composited.
// Run via gates/sweep.sh (any artifact). Keys on the family class contract.ab-tools/gallery-audit.js)" 1280 3400 --out=/Volumes/developer_ssd/Developer/totem_labs/ez-lab/sweep/gallery-gate-STYLE.json
(() => {
  /* guard: a named style MUST load its overlay sheet — a 404 here once made the gate
     "pass" by silently testing the base custom skin four times (short-name URL bug). */
  const stName = new URLSearchParams(location.search).get("style") || "liquid-glass";
  if (stName !== "custom") {
    /* the overlay link is matched by STYLE NAME: the lab serves styles/<name>.css,
       artifacts serve /ui/styles/common/overlay-<name>.css — a generic "styles/"
       match grabs an artifact's 9-line barrel and false-fails. */
    const link = [...document.querySelectorAll('link[rel="stylesheet"]')].find((l) => decodeURIComponent(l.href).includes(stName));
    const n = (() => { try { return link && link.sheet ? link.sheet.cssRules.length : 0; } catch (e) { return 0; } })();
    if (!n || n < 50) throw new Error("style overlay NOT loaded for style=" + stName + " (rules=" + n + ") — gate would be vacuous");
  }
  const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4); };
    return 0.2126*f(c[0]) + 0.7152*f(c[1]) + 0.0722*f(c[2]); };
  const parse = (s) => { s = (s||"").trim();
    if (s[0] === "#") { let h = s.slice(1); if (h.length === 3) h = h.split("").map(c=>c+c).join("");
      return [parseInt(h.slice(0,2),16), parseInt(h.slice(2,4),16), parseInt(h.slice(4,6),16), 1]; }
    if (s.startsWith("color-mix")) { const m = s.match(/color-mix\(in srgb,\s*(#[0-9a-fA-F]{6})\s*([0-9.]+)%/);
      if (m) { const c = parse(m[1]); c[3] = Number(m[2]) / 100; return c; } return null; }
    const m = s.match(/rgba?\(([^)]*)\)/); if (!m) return null;
    const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number);
    return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; };
  const over = (fg, bg) => { const a = fg[3] + bg[3]*(1-fg[3]);
    return [...[0,1,2].map(i => (fg[i]*fg[3] + bg[i]*bg[3]*(1-fg[3]))/a), a]; };
  const ratio = (fgC, bgC) => (Math.max(lum(fgC), lum(bgC)) + 0.05) / (Math.min(lum(fgC), lum(bgC)) + 0.05);
  const backdropOf = (el) => { const layers = []; let node = el.parentElement;
    while (node) { const b = parse(getComputedStyle(node).backgroundColor); if (b && b[3] > 0) layers.push(b); node = node.parentElement; }
    let acc = layers.pop() || [255, 255, 255, 1];
    while (layers.length) acc = over(layers.pop(), acc);
    return acc; };
  const PROBES = [
    ["btn-primary", ".btn:not(.btn--ghost):not(.btn--text):not(.btn--danger)"],
    ["btn-ghost", ".btn--ghost"], ["btn-danger", ".btn--danger"], ["btn-text", ".btn--text"],
    ["ibtn-on", ".ibtn.on"], ["fab", ".fab"],
    ["seg-on", ".seg button.on"], ["seg-off", ".seg button:not(.on)"],
    ["tabset-on", ".tabset a.on"], ["tabset-off", ".tabset a:not(.on)"],
    ["toggle-on", ".toggle.on"], ["toggle-off", ".toggle:not(.on)"],
    ["check-label", ".check"], ["cb-on-mark", ".cb.on"], ["radio-label", ".radio"], ["switch-label", ".switch"],
    ["select", ".select"], ["menu-item", "#menus .menu .mi"], ["menu-sel", ".menu .mi.sel"],
    ["menu-danger", ".menu .mi.danger"], ["menubar-on", ".menubar span.on"],
    ["pop-text", ".pop b"], ["tip", ".tip"], ["hcard-body", ".hcard-body"],
    ["cal-day", ".day:not(.out):not(.today):not(.sel):not(.range):not(.sel-end)"],
    ["day-sel", ".day.sel"], ["day-today", ".day.today"], ["day-range", ".day.range"],
    ["datepick", ".datepick"], ["tp-on", ".tp-f.on"], ["tp-dial-n", ".tp-n"],
    ["dlg-title", ".dlg h3"], ["dlg-body", ".dlg p"], ["sheet-sel", ".sheet .mi.sel"], ["drawer-title", ".drawer h3"],
    ["toast", ".toast"], ["toast-action", ".toast--act a"],
    ["banner", ".banner:not(.banner--warn):not(.banner--bad)"], ["banner-warn", ".banner--warn"], ["banner-bad", ".banner--bad"],
    ["crumbs-link", ".crumbs a"], ["crumbs-current", ".crumbs b"], ["pg-on", ".pg.on"],
    ["tbl-head", ".tbl th"], ["tbl-cell", ".tbl td"], ["tbl-sel", ".tbl tr.sel td"],
    ["acc-head", ".acc-head"], ["acc-body", ".acc-body"],
    ["card-media", ".g-media"], ["avatar", ".avatar"], ["badge", ".badge"],
    ["empty-body", ".empty p"], ["hint", ".hint"], ["error", ".emsg"],
    ["caption", ".g-cap"], ["sub", ".type-scale .sub"], ["kbd", ".kbd"],
    ["appbar-title", ".appbar b"],
    ["nb-on", ".nb.on"], ["nb-off", ".nb:not(.on)"],
    ["nr-on", ".nr.on"], ["nr-off", ".nr:not(.on)"],
    ["sb-on", ".sb-i.on"], ["sb-off", ".sb-i:not(.on)"], ["sb-head", ".sb-head"],
  ];
  const out = {}; let fails = 0;
  const prior = document.documentElement.dataset.theme;
  /* theme flips must measure the static truth, not a mid-flight blend: any transitioned color
     (e.g. a 150ms wash swap) reads as the FROM theme right after dataset.theme flips. */
  const noFx = document.createElement("style");
  noFx.textContent = "*{transition:none!important;animation:none!important}";
  document.head.appendChild(noFx);
  for (const theme of ["light", "dark"]) {
    document.documentElement.dataset.theme = theme;
    for (const [label, sel] of PROBES) {
      const el = document.querySelector(sel);
      if (!el) { out[theme + "/" + label] = "MISSING " + sel; fails++; continue; }
      let bgC = parse(getComputedStyle(el).backgroundColor) || [0,0,0,0];
      let fgC = parse(getComputedStyle(el).color);
      if (!fgC) { out[theme + "/" + label] = "NOFG"; fails++; continue; }
      const flat = over(bgC, backdropOf(el));
      const r = ratio(fgC, flat);
      if (r < 4.5) fails++;
      out[theme + "/" + label] = r.toFixed(2) + (r >= 4.5 ? "" : " FAIL");
    }
  }
  document.documentElement.dataset.theme = prior || "light";
  noFx.remove();
  const bad = Object.entries(out).filter(([k,v]) => String(v).includes("FAIL") || String(v).includes("MISSING") || String(v).includes("NOFG"));
  /* report HOW MANY probes ran, not just how many failed. "fails: 0" from a gate
     that never executed is indistinguishable from a real pass — that is exactly
     how a dropped comma in PROBES hid behind four green readings. A reader that
     sees checked===0 must treat it as failure, not success. */
  return {
    style: new URLSearchParams(location.search).get("style") || "liquid-glass",
    checked: Object.keys(out).length,          // probes × themes actually measured
    probes: PROBES.length,
    fails,
    bad: bad.length ? bad : "none",
  };
})()