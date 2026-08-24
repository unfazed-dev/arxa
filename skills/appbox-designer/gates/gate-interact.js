/* gallery interaction smoke (R9): drive every wired family, assert state lands.
   Run via gates/sweep.sh (any artifact). Keys on the family class contract. */
(async () => {
  /* guard: a named style MUST load its overlay sheet — a 404 here once made the gate
     "pass" by silently testing the base custom skin four times (short-name URL bug). */
  const stName = new URLSearchParams(location.search).get("style") || "liquid-glass";
  if (stName !== "custom") {
    const link = [...document.querySelectorAll('link[rel="stylesheet"]')].find((l) => l.href.includes("styles/"));
    const n = (() => { try { return link && link.sheet ? link.sheet.cssRules.length : 0; } catch (e) { return 0; } })();
    if (!n || n < 50) throw new Error("style overlay NOT loaded for style=" + stName + " (rules=" + n + ") — gate would be vacuous");
  }
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const fails = [];
  /* count every assertion, not just the failing ones: a gate that returns
     pass:true having checked nothing is the false-green this suite has already
     been bitten by twice. read-gate.js fails on checked===0. */
  let checked = 0;
  const ok = (cond, label) => { checked++; if (!cond) fails.push(label); };
  const q = (s) => document.querySelector(s);
  const qa = (s) => [...document.querySelectorAll(s)];
  const hidden = (el) => getComputedStyle(el).visibility === "hidden" || parseFloat(getComputedStyle(el).opacity) < 0.05;

  /* 1. seg: click Month -> .on moves; thumb (when live) lands on it */
  const seg = q("#seg-tabs .seg"), segItems = [...seg.querySelectorAll("button")];
  segItems[2].click(); await wait(900);
  ok(segItems[2].classList.contains("on"), "seg on-month");
  const thumb = seg.querySelector(".thumb");
  if (thumb) ok(Math.abs(parseFloat(thumb.style.left) - segItems[2].offsetLeft) < 2.5, "seg thumb lands");
  const tabset = q("#seg-tabs .tabset"), tabs = [...tabset.querySelectorAll("a")];
  tabs[1].click(); await wait(900);
  ok(tabs[1].classList.contains("on"), "tabset on-second");
  const ink = tabset.querySelector(".thumb, .inkbar");
  if (ink) { const il = parseFloat(ink.style.left); ok(il >= tabs[1].offsetLeft - 1 && il <= tabs[1].offsetLeft + 14, "tab indicator moved"); }

  /* 2. selection: switch off/on, checkbox flip, radio single-select.
     Normalize first: the ?demo=interact hook toggles shared controls, so assert
     transitions from a KNOWN state, never absolute state (timing-independent). */
  const sw = q(".switch .sw"), swHost = sw.closest(".switch");
  if (!sw.classList.contains("on")) { swHost.click(); await wait(700); }
  swHost.click(); await wait(700);
  ok(!sw.classList.contains("on"), "switch off");
  /* the class flipping is NOT the switch working — assert the thumb physically
     moved. A class-only assertion passed 17/17 while travel was 0 in all four
     styles (interact.js clobbered the CSS transform before measuring). */
  const swTh = sw.querySelector(".th");
  const thumbX = () => swTh.getBoundingClientRect().left - sw.getBoundingClientRect().left;
  const swXoff = thumbX();
  swHost.click(); await wait(700);
  ok(sw.classList.contains("on"), "switch on");
  const swXon = thumbX();
  ok(swXon - swXoff >= 8,
     `switch thumb travel (off=${swXoff.toFixed(1)} on=${swXon.toFixed(1)} delta=${(swXon - swXoff).toFixed(1)}, need >=8)`);
  const cb = q(".check .cb"); cb.closest(".check").click();
  ok(!cb.classList.contains("on") && cb.textContent === "", "checkbox flip");
  const radios = qa(".radio"); radios[1].click();
  ok(radios[1].querySelector(".rd").classList.contains("on") && !radios[0].querySelector(".rd").classList.contains("on"), "radio single");

  /* 3. calendar: single pick, then range */
  const day = (n) => [...q(".cal").querySelectorAll(".day:not(.out)")].find((d) => d.textContent === String(n));
  day(10).click();
  ok(day(10).classList.contains("sel") && day(10).classList.contains("solo"), "cal solo pick");
  day(14).click();
  ok(day(14).classList.contains("sel-end") && qa(".cal .day.range").length >= 3, "cal range");
  const titleBefore = q(".cal .cal-head b").textContent;
  const arrows = q(".cal .cal-head").querySelectorAll(".ibtn");
  arrows[1].click();
  ok(q(".cal .cal-head b").textContent !== titleBefore, "cal month pages");
  arrows[0].click();

  /* 4. dialog: scrim dismiss + re-present */
  const stage = q("#dialogs .stage"), dlg = stage.querySelector(".dlg"), scrim = stage.querySelector(".scrim");
  scrim.click(); await wait(900);
  ok(getComputedStyle(dlg).visibility === "hidden", "dlg dismisses");
  stage.parentElement.querySelector(".stage-re").click(); await wait(900);
  ok(getComputedStyle(dlg).visibility === "visible", "dlg re-presents");

  /* 5. select: close, reopen, pick */
  const wrap = q(".select-wrap"), smenu = wrap.querySelector(".menu");
  wrap.querySelector(".select").click(); await wait(1100);
  ok(hidden(smenu), "select closes");
  wrap.querySelector(".select").click(); await wait(1100);
  ok(getComputedStyle(smenu).visibility === "visible" && parseFloat(getComputedStyle(smenu).opacity) > 0.95, "select reopens");
  wrap.querySelectorAll(".mi")[1].click(); await wait(500);
  ok(wrap.querySelector(".sel-label").textContent === "Villa Belle Rive", "select picks");

  /* 5b. dropdown anatomy (R9n), pinned after Evan's report. Three defects
     this fences, all measured red before the fix:
     (a) a stray always-visible duplicate check svg lived on the initially
         selected item — after ANY pick, two checks showed at once;
     (b) .menu .mi used space-between, so revealing the check made the
         selected label jump ~67px to the menu's right edge — the check
         clusters LEFT with its label (shadcn/HIG menus), only kbd hints
         belong at the right edge;
     (c) the menu was in-flow: closing it left a 169px void under a 40px
         field forever. A listbox that presents/dismisses FLOATS (the
         datepop in the same page is the working pattern). */
  const ddItems = [...wrap.querySelectorAll(".mi")];
  ok(ddItems.every((mi) => ![...mi.querySelectorAll("svg.ic")].some((s) => !s.classList.contains("mi-check"))),
     "select items carry no stray always-on icons");
  const labelBox = (mi) => {
    const svgs = [...mi.querySelectorAll("svg")];
    const r = document.createRange(); r.selectNodeContents(mi);
    const rects = [...r.getClientRects()].filter((x) => x.width > 2 && !svgs.some((s) => {
      const b = s.getBoundingClientRect();
      return Math.abs(b.left - x.left) < 1 && Math.abs(b.width - x.width) < 1;
    }));
    return rects.length ? rects[0] : null;
  };
  const selMi = ddItems.find((mi) => mi.classList.contains("sel"));
  const unselMi = ddItems.find((mi) => !mi.classList.contains("sel"));
  /* cluster law, adjacency form (R9o revision): the R9n right-gap form
     assumed a 200px menu with free right space — menus now fit content, so
     the widest row legitimately ends near the right edge. The defect
     space-between caused was a ~67px gap BETWEEN check and label; assert
     that adjacency directly (they are neighboring flex items). */
  const checkGap = (mi) => {
    const chk = mi.querySelector(".mi-check");
    const lb = labelBox(mi);
    return chk && lb ? lb.left - chk.getBoundingClientRect().right : null;
  };
  if (selMi && checkGap(selMi) !== null) {
    ok(checkGap(selMi) < 16, "check hugs its selected label (no fling gap)");
  }
  if (unselMi && checkGap(unselMi) !== null) {
    ok(checkGap(unselMi) < 16, "unselected label hugs the reserved slot");
  }
  const selBtn = wrap.querySelector(".select");
  ok(Math.abs(wrap.getBoundingClientRect().height - selBtn.getBoundingClientRect().height) < 3,
     "closed select leaves no layout void (menu floats)");
  ok(getComputedStyle(wrap.querySelector(".menu")).position === "absolute",
     "select menu is a floating popover");

  /* 5c. dropdown size stability (R9o), pinned after Evan's report: "the
     dropdown is changing size; a 2-line option must be addressed properly".
     Laws, each measured red before the fix:
     (i)   menu items are single-line — M2 menus: "Each menu item is limited
           to a single line of text"; content that needs two lines belongs
           in a dialog, not a menu;
     (ii)  the state-check slot is RESERVED on every row (shadcn SelectItem:
           the check indicator is absolutely positioned inside a padded slot
           that exists on every row) — so a label's x never moves when
           selection moves, and the check adds no row height;
     (iii) the open menu's box does not depend on WHICH item is selected:
           width floors at the trigger width, height is uniform rows. */
  const menuBox = () => ({ w: smenu.offsetWidth, h: smenu.offsetHeight });
  const measureOpen = async () => {
    if (hidden(smenu)) { selBtn.click(); await wait(1100); }
    const hs = ddItems.map((mi) => mi.getBoundingClientRect().height);
    const sorted = hs.slice().sort((a, b) => a - b);
    const median = sorted[Math.floor(sorted.length / 2)];
    const trig = selBtn.getBoundingClientRect();
    const carR = selBtn.querySelector(".car").getBoundingClientRect();
    return {
      box: menuBox(), hs, median,
      selL: labelBox(ddItems.find((mi) => mi.classList.contains("sel"))),
      unselL: labelBox(ddItems.find((mi) => !mi.classList.contains("sel"))),
      trigW: Math.round(trig.width), trigH: Math.round(trig.height),
      carX: Math.round(carR.left * 10) / 10,
      carRightGap: Math.round((trig.right - carR.right) * 10) / 10
    };
  };
  /* state here: menu dismissed, "Villa Belle Rive" (longest) selected */
  const dd1 = await measureOpen();            /* longest label selected  */
  ddItems[0].click(); await wait(1300);       /* pick -> selects + closes */
  const dd2 = await measureOpen();
  ddItems[2].click(); await wait(1300);
  const dd3 = await measureOpen();            /* shortest label selected */
  if (hidden(smenu) === false) { selBtn.click(); await wait(100); }
  ok(Math.abs(dd1.box.w - dd2.box.w) <= 1 && Math.abs(dd2.box.w - dd3.box.w) <= 1,
     "menu width stable across selections");
  ok(Math.abs(dd1.box.h - dd2.box.h) <= 1 && Math.abs(dd2.box.h - dd3.box.h) <= 1,
     "menu height stable across selections");
  ok(dd1.hs.every((h) => Math.abs(h - dd1.median) < 2) &&
     dd3.hs.every((h) => Math.abs(h - dd3.median) < 2),
     "menu items are single-line (no wrapped rows)");
  if (dd1.selL && dd1.unselL) {
    ok(Math.abs(dd1.selL.left - dd1.unselL.left) < 2,
       "label x is check-independent (state slot reserved on every row)");
  }
  ok(Math.abs(dd1.trigH - dd3.trigH) <= 1, "trigger height fixed across picks");
  ok(dd1.box.w >= dd1.trigW - 1 && dd3.box.w >= dd3.trigW - 1,
     "menu never narrower than its trigger");
  /* (R9p) a field's trailing affordance is PINNED to the field's right edge:
     the chevron floated after the label (right-gap 39.2px with one value,
     68.2px with another). shadcn's SelectTrigger ends in its SelectIcon at
     the padding — the gap is a constant, never a function of the value. */
  ok(Math.abs(dd1.carRightGap - dd3.carRightGap) <= 1,
     "chevron gap constant across picks (pinned, not value-following)");
  ok(dd1.carRightGap <= 24 && dd3.carRightGap <= 24,
     "chevron hugs the field's right edge");
  /* combo rows obey the same single-line law while unfiltered. Judged
     WITHIN the combo, never against select rows: the select's reserved
     check slot makes its rows legitimately taller in idioms with big icons
     (m3: 24px icon > text line) — a cross-component threshold false-flags. */
  const comboHs = [...q(".combo").querySelectorAll(".mi")].map((m) => m.getBoundingClientRect().height);
  const cMin = Math.min(...comboHs), cMax = Math.max(...comboHs);
  ok(comboHs.length > 0 && cMax - cMin < 2 && cMax < cMin * 1.5, "combo rows single-line too");

  /* 6. combo filter */
  const combo = q(".combo"), cinput = combo.querySelector("input");
  cinput.value = "marina"; cinput.dispatchEvent(new Event("input", { bubbles: true }));
  const visible = [...combo.querySelectorAll(".mi")].filter((m) => m.style.display !== "none");
  ok(visible.length === 1 && visible[0].textContent.includes("Marina"), "combo filters");
  cinput.value = ""; cinput.dispatchEvent(new Event("input", { bubbles: true }));

  /* 7. accordion — normalize to known states first (demo hook shares item 1) */
  const items = qa(".acc-item");
  if (items[1].classList.contains("open")) { items[1].querySelector(".acc-head").click(); await wait(700); }
  items[1].querySelector(".acc-head").click(); await wait(700);
  ok(items[1].classList.contains("open"), "accordion opens");
  /* chevron law (R9i): glass = outline disclosure (right -> 90deg to down);
     other styles keep chevron-down rotating 180 (their platform idiom) */
  {
    const rotDeg = (el) => { const m = getComputedStyle(el).transform.match(/matrix\(([^)]+)\)/);
      if (!m) return 0; const v = m[1].split(",").map(Number); return Math.round(Math.atan2(v[1], v[0]) * 180 / Math.PI); };
    const car1 = items[1].querySelector(".car");
    ok(car1.querySelector("use").getAttribute("href") === (stName === "liquid-glass" ? "#i-chevron-right" : "#i-chevron-down"),
       "accordion glyph per idiom (glass: right/outline, others: down)");
    ok(rotDeg(car1) === (stName === "liquid-glass" ? 90 : 180), "chevron rotated on open (" + rotDeg(car1) + "deg)");
    if (stName === "liquid-glass") {
      const h = items[2].querySelector(".acc-head");
      h.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
      ok(h.classList.contains("hl"), "row press highlights (cell fill, not scale)");
      h.dispatchEvent(new PointerEvent("pointerup", { bubbles: true }));
      ok(!h.classList.contains("hl"), "row highlight clears on release");
    }
  }
  if (!items[0].classList.contains("open")) { items[0].querySelector(".acc-head").click(); await wait(700); }
  items[0].querySelector(".acc-head").click(); await wait(700);
  ok(!items[0].classList.contains("open"), "accordion closes");
  {
    const m2 = getComputedStyle(items[0].querySelector(".car")).transform.match(/matrix\(([^)]+)\)/);
    const v2 = m2 ? m2[1].split(",").map(Number) : [1, 0];
    ok(Math.round(Math.atan2(v2[1], v2[0]) * 180 / Math.PI) === 0, "chevron returned to 0deg on close");
  }

  /* 8. pagination + table + timepick + otp */
  const pgs = qa(".pages .pg"); pgs[2].click();
  ok(pgs[2].classList.contains("on") && !pgs[0].classList.contains("on"), "pagination moves");
  const rows = qa(".tbl tr").filter((r) => r.querySelector("td"));
  rows[1].click();
  ok(rows[1].classList.contains("sel") && !rows[0].classList.contains("sel"), "table selects");
  const tps = qa(".tpick .tp-f");
  if (tps.length) {
    tps[1].click();
    ok(tps[1].classList.contains("on"), "timepick field switches");
    /* the dial is the control, not decoration: picking a number must move the
       hand. shadcn has no dial (no such component in its registry), so this
       whole block is style-conditional rather than a hard requirement. */
    /* `q(".tp-dial")` is truthy even where the style hides it — display:none
       elements stay in the DOM. Test for actually rendered, or shadcn (which
       has no dial by design) fails an assertion about a control it never shows. */
    const dial = q(".tp-dial");
    if (dial && dial.getClientRects().length) {
      const hand = dial.querySelector(".tp-hand");
      const before = getComputedStyle(hand).transform;
      const nums = [...dial.querySelectorAll(".tp-n")];
      const target = nums.find((n) => !n.classList.contains("on"));
      target.click(); await wait(400);
      ok(target.classList.contains("on"), "dial number selects");
      ok(getComputedStyle(hand).transform !== before, "dial hand follows the pick");
    }
  }
  const otpCells = qa(".otp span"); otpCells[3].click();
  ok(otpCells[3].classList.contains("on"), "otp focuses");

  /* 9. datepick popover */
  const dp = q(".datepick"); dp.click(); await wait(800);
  const pop = q(".datepop");
  ok(pop && getComputedStyle(pop).visibility === "visible", "datepop presents");
  const cd = [...pop.querySelectorAll(".day:not(.out)")].find((d) => d.textContent === "12");
  cd.click(); await wait(1100);
  ok(dp.textContent.includes("12"), "datepick fills");
  ok(hidden(pop), "datepop closes");

  /* 10. toast fire */
  document.getElementById("toast-fire").click(); await wait(600);
  ok(qa("#toast-rack .toast").length === 1, "toast fires");

  /* 11. sheet dismiss + re-present */
  const st2 = qa("#sheets .stage")[0], sheet = st2.querySelector(".sheet");
  st2.querySelector(".scrim").click(); await wait(900);
  ok(getComputedStyle(sheet).visibility === "hidden", "sheet dismisses");
  st2.parentElement.querySelector(".stage-re").click(); await wait(900);
  ok(getComputedStyle(sheet).visibility === "visible", "sheet re-presents");

  /* 12. text fields: ONE field indicator at a time (R9m). The bug this pins:
     .input:focus painted the accent outline unconditionally, so an error field
     showed two rings at once — accent outline outside + red ring inside
     (glass: inset shadow; other styles: red border). Platform precedent: iOS
     never shows two field boundary indicators; error outranks focus.
     Focus itself stays idiom-authentic: outline ring in glass/shadcn/custom,
     M3's 2px bottom active indicator in m3-expressive. */
  /* parse without regex: this file travels through shell + JSON string
     layers where escaped parens have already been mangled once (NaN parses
     made every color "not red" — a silent false-red). Handles rgb()/rgba()
     (0-255 channels) and color(srgb r g b[/a]) (0-1 channels). */
  const redDominant = (col) => {
    const s = col || "";
    const o = s.indexOf("("), c = s.lastIndexOf(")");
    if (o < 0 || c <= o) return false;
    const parts = s.slice(o + 1, c).replace("/", ",").split(",").map(Number);
    if (parts.length < 3 || parts.slice(0, 3).some(Number.isNaN)) return false;
    const [r, g, b] = parts[0] <= 1 && parts[1] <= 1
      ? parts.map((v) => v * 255)
      : parts;
    return r > g + 40 && r > b + 40;
  };
  const hasRedBoundary = (cs) =>
    cs.boxShadow.includes("inset") ||
    [cs.borderTopColor, cs.borderRightColor, cs.borderBottomColor, cs.borderLeftColor].some(redDominant);
  const plainIn = q(".fieldwrap:not(.err) .input"), errIn = q(".fieldwrap.err .input");
  plainIn.focus(); await wait(140);
  const pcs = getComputedStyle(plainIn);
  if (stName === "m3-expressive") {
    ok(parseFloat(pcs.borderBottomWidth) >= 2, "plain input M3 focus indicator shows");
  } else {
    ok(pcs.outlineStyle !== "none" && parseFloat(pcs.outlineWidth) >= 1.5,
       "plain input focus ring shows");
  }
  errIn.focus(); await wait(140);
  const ecs = getComputedStyle(errIn);
  ok(ecs.outlineStyle === "none" || parseFloat(ecs.outlineWidth) === 0,
     "err input focus shows NO accent outline");
  ok(hasRedBoundary(ecs), "err input keeps its red boundary while focused");
  errIn.blur(); plainIn.blur();

  return { style: new URLSearchParams(location.search).get("style") || "liquid-glass", checked, pass: fails.length === 0, fails };
})()