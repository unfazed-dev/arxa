// Run via gates/sweep.sh (any artifact: BASE_URL + SPECIMEN). This copy is the durable
//        "$(cat /Volumes/developer_ssd/Developer/totem_labs/ez-lab-tools/gallery-geometry.js)" \
//        1280 3400 --out=/Volumes/developer_ssd/Developer/totem_labs/ez-lab/sweep/geom-gate-STYLE.json
//
// The third gate (R9a). Contrast gate = colour. Interaction smoke = behaviour.
// NEITHER can see shape — which is how a 5px-wrong glass switch and a 38px
// calendar cell stayed green all day. This one asserts geometry.
//
// m3 / shadcn / custom  -> absolute px, sourced in docs/technique-layer/component-specs.md
// liquid-glass          -> RELATIONSHIPS only. Apple publishes no per-component
//                          pixel specs (10 HIG pages read; the sole number is tvOS).
//                          Asserting invented px here would fabricate a spec.
(() => {
  const alias = { glass: "liquid-glass", expressive: "m3-expressive", m3: "m3-expressive" };
  const raw = new URLSearchParams(location.search).get("style") || "liquid-glass";
  const style = alias[raw] || raw;

  // guard: a named style MUST have loaded its overlay. A 404 here once made the
  // contrast gate "pass" by testing the base skin four times.
  if (style !== "custom") {
    /* overlay link matched by STYLE NAME: lab styles/<name>.css, artifact
       overlay-<name>.css — a generic "styles/" match grabs an artifact's
       9-line barrel and false-fails. */
    const link = [...document.querySelectorAll('link[rel="stylesheet"]')].find((l) => decodeURIComponent(l.href).includes(style));
    let n = 0; try { n = link && link.sheet ? link.sheet.cssRules.length : 0; } catch (e) { n = 0; }
    if (!n || n < 50) throw new Error("style overlay NOT loaded for " + style + " (rules=" + n + ") - gate would be vacuous");
  }

  // transitions blend mid-flight and corrupt a geometry read (same trap the
  // contrast gate hit with theme swaps).
  const kill = document.createElement("style");
  kill.textContent = "*,*::before,*::after{transition:none!important;animation:none!important}";
  document.head.appendChild(kill);

  const TOL = 1.0;
  const get = (sel) => {
    const e = document.querySelector(sel);
    if (!e) return null;
    const r = e.getBoundingClientRect(), c = getComputedStyle(e);
    return { w: +r.width.toFixed(1), h: +r.height.toFixed(1), r: parseFloat(c.borderTopLeftRadius) || 0 };
  };

  const fails = [], missing = [], notes = [];
  let checked = 0;

  const near = (a, b) => Math.abs(a - b) <= TOL;
  const check = (name, sel, expect) => {
    const g = get(sel);
    if (!g) { missing.push(name + " (" + sel + ")"); return; }
    checked++;
    for (const [k, want] of Object.entries(expect)) {
      if (k === "capsule") {
        const need = Math.min(g.w, g.h) / 2 - 0.5;
        if (!(g.r >= need)) fails.push(`${name}: radius ${g.r} is not a capsule (needs >= ${need.toFixed(1)} for ${g.w}x${g.h})`);
      } else if (k === "rFrac") {
        /* corner radius as a fraction of height — the glass fixed-shape law.
           The HIG text-fields hero measures radius ~= h/4..h/5 (two vision
           reads, R9m); capsules are for controls and search fields only
           (WWDC25-356 three-shape system). */
        const got = g.r / g.h;
        if (Math.abs(got - want) > 0.02) fails.push(`${name}: r/h ${got.toFixed(3)} != ${want} (${g.r}/${g.h})`);
      } else if (k === "ratio") {
        const got = g.w / g.h;
        if (Math.abs(got - want) > 0.12) fails.push(`${name}: w/h ratio ${got.toFixed(2)} != ${want} (${g.w}x${g.h})`);
      } else if (!near(g[k], want)) {
        fails.push(`${name}: ${k}=${g[k]} expected ${want}`);
      }
    }
  };

  const SPEC = {
    // ---- absolutes: material-web tokens v0.192 ----
    "m3-expressive": {
      /* M3 time picker — material-web md-comp-time-picker tokens + Flutter
         time_picker.dart constants (see component-specs.md R9a). */
      /* r28 = container-shape corner-extra-large. The published 310x468 is
         Flutter's FULL portrait dialog including title and action rows in an
         arrangement this specimen does not replicate, so asserting that total
         would pin a number our layout never claimed. The PARTS are sourced. */
      "time picker container": [".tpick",     { r: 28 }],
      "time field":            [".tp-f",      { w: 96, h: 80, r: 8 }],
      "AM/PM selector":        [".tp-ap",     { w: 52, h: 80, r: 8 }],
      "dial":                  [".tp-dial",   { w: 256, h: 256 }],
      "dial handle":           [".tp-n.on",   { w: 48, h: 48 }],
      "switch track":        [".sw",                  { w: 52, h: 32 }],
      "switch thumb (on)":   [".sw.on .th",   { w: 24, h: 24 }],
      "switch thumb (off)":  [".sw:not(.on) .th", { w: 16, h: 16 }],
      "checkbox":            [".cb",                  { w: 18, h: 18, r: 2 }],
      "radio":               [".rd",                  { w: 20, h: 20 }],
      "filled field":        [".fieldwrap .input",    { h: 56, r: 4 }],
      "floated label":       [".fieldwrap > label",   { h: 12 }],
      "calendar day":        [".cal .day",            { w: 40, h: 40 }],
      /* container-width 360, container-shape corner-large 16, sub-header 52.
         The 456 height and the 64 "Select date" headline are the MODAL picker;
         this specimen renders the docked grid + month nav, so those two are
         not asserted — pinning them would claim a layout we do not draw. */
      "calendar container":  [".cal",                 { w: 360, r: 16 }],
      "calendar sub-header": [".cal-head",            { h: 52 }],
      "list row":            [".row",                 { h: 56 }],
      "tab bar":             [".tabset",              { h: 48 }],
      "nav rail":            [".navrail",             { w: 80 }],
      "nav bar":             [".navbar",              { h: 80 }],
      "nav drawer":          [".sidebar",             { w: 360 }],
      "drawer collapsed":    [".sidebar.icon",        { w: 88 }],
      "top app bar":         [".appbar",              { h: 64 }],
    },
    // ---- absolutes: shadcn registry new-york-v4 ----
    "shadcn": {
      "switch track":        [".sw",                  { w: 32, h: 18.4 }],
      "switch thumb":        [".sw .th",              { w: 16, h: 16 }],
      "checkbox":            [".cb",                  { w: 16, h: 16, r: 4 }],
      "radio":               [".rd",                  { w: 16, h: 16 }],
      "input":               [".input",               { h: 36, r: 6 }],
      "tabs list":           [".tabset",              { h: 36, r: 8 }],
      "calendar day":        [".cal .day",            { w: 32, h: 32 }],
      "calendar nav row":    [".cal-head",            { h: 32 }],
      "pagination":          [".pages .pg",           { w: 36, h: 36 }],
      "sidebar":             [".sidebar",             { w: 256 }],
      "sidebar collapsed":   [".sidebar.icon",        { w: 48 }],
    },
    // ---- relationships only: HIG publishes no per-component px ----
    "liquid-glass": {
      "segmented track":     [".seg",                 { capsule: true }],
      "segmented thumb":     [".seg .thumb",          { capsule: true }],
      /* REAL size 52x32pt: the native SwiftUI Liquid Glass control default
         (liquid_glass_native LiquidGlassSwitch width 52 height 32; UIKit
         lineage 51x31). The HIG docs figure is stretched (2.29) — shape only. */
      "switch track":        [".sw",                  { capsule: true, ratio: 52 / 32 }],
      /* row height from the REAL control default: UIKit rowHeight /
         SwiftUI defaultMinListRowHeight = 44 (same doctrine as the 52x32 switch) */
      "accordion row":       [".acc-head",            { h: 44 }],
      "search field":        [".search",              { capsule: true }],
      /* text field = FIXED shape, deliberately NOT a capsule: content-layer
         fields are standard-material rounded rects (HIG Materials: "Don't use
         Liquid Glass in the content layer"), hero radius ~= h/4, flat fill,
         no border. Capsule is the search-field + control idiom. */
      "text field":          [".fieldwrap .input",    { rFrac: 0.25 }],
      "button":              [".btn",                 { capsule: true }],
      "app bar":             [".appbar",              { h: 50 }],
      "nav bar":             [".navbar",              { h: 56 }],
      /* "nav rail": [".navrail", { w: 76 }] — DELETED for the same reason as
         the capsule indicator. Apple has no navigation rail: 0 hits for
         "navigation rail" across the HIG; the iPad equivalent is a top tab bar
         or a sidebar/split view. 76 was an invented width. Asserting it while
         the caption says "no Apple equivalent" would have the gate defending
         geometry the research overturned. The specimen still renders (deleting
         it changes what the gallery claims — Evan's call), but nothing pins a
         glass rail width any more. */
      "sidebar":             [".sidebar",             { w: 260 }],
      /* "nav indicator": [".nb.on .ind", { capsule: true }] — DELETED.
         That assertion encoded Material 3's "active indicator". I wrote it
         before researching the HIG, building the nav from M3 geometry.
         Negative test across 9 HIG pages: "capsule" 0 hits, "active indicator"
         0 hits, "pill" 2 hits (both *pillarboxed*, in layout). Apple's tab-bar
         anatomy figure lists exactly two parts — icon and label — and states
         selection as colour ON THE SYMBOL: "Symbols and text that appear on
         Liquid Glass can have color, like in a selected tab bar item"
         (color#Liquid-Glass-color). The only filled selected-tab treatment
         Apple documents is tvOS.
         Replaced by the navTint check below, which asserts the ABSENCE of a
         filled indicator and the PRESENCE of a tint difference. Changed
         because the spec changed — never to turn a red gate green. */
    },
    // ---- our house style: chosen, then pinned so it stays stable ----
    "custom": {
      "switch track":        [".sw",                  { w: 44, h: 26 }],
      "checkbox":            [".cb",                  { w: 20, h: 20, r: 6 }],
      "radio":               [".rd",                  { w: 20, h: 20 }],
      "input":               [".input",               { h: 42, r: 8 }],
      "calendar day":        [".cal .day",            { w: 38, h: 38 }],
      "app bar":             [".appbar",              { h: 52 }],
      "nav bar":             [".navbar",              { h: 60 }],
      "nav rail":            [".navrail",             { w: 72 }],
      "sidebar":             [".sidebar",             { w: 240 }],
      "sidebar collapsed":   [".sidebar.icon",        { w: 56 }],
    },
  };

  const table = SPEC[style];
  if (!table) throw new Error("no geometry spec for style=" + style);
  for (const [name, [sel, expect]] of Object.entries(table)) check(name, sel, expect);

  if (style === "m3-expressive") {
    // tails: a floated label must clear its control's text, in EVERY fieldwrap -
    // not just the first one. The first pass floated the label over the textarea
    // and the OTP digits and the gate did not see it.
    document.querySelectorAll(".fieldwrap").forEach((fw, i) => {
      const lab = fw.querySelector(":scope > label");
      const ctl = fw.querySelector(":scope > .input, :scope > .textarea, :scope > .otp");
      if (!lab || !ctl) return;
      checked++;
      const lr = lab.getBoundingClientRect(), cr = ctl.getBoundingClientRect();
      const inside = lr.top >= cr.top - 0.5 && lr.bottom <= cr.bottom + 0.5;
      if (!inside) return;                       // label sits outside the control - fine
      const padTop = parseFloat(getComputedStyle(ctl).paddingTop) || 0;
      if (lr.bottom > cr.top + padTop + 0.5)
        fails.push(`fieldwrap[${i}] (${ctl.className}): floated label overlaps content ` +
                   `(label bottom ${lr.bottom.toFixed(1)} > content top ${(cr.top + padTop).toFixed(1)})`);
    });
  }

  if (style === "liquid-glass") {
    // accordion chevron = the OUTLINE-DISCLOSURE glyph, not the macOS disclosure
    // button. HIG disclosure-controls: "points inward from the leading edge when
    // its content is hidden and down when its content is visible"; UIKit
    // UICellAccessoryOutlineDisclosure: "a rotating chevron ... on the trailing
    // edge" (iOS). So: chevron RIGHT when collapsed, rotated 90deg (to DOWN)
    // when expanded — the 180deg down->up spin is the macOS button idiom.
    {
      const car = document.querySelector(".acc-item.open .acc-head .car");
      const use = car && car.querySelector("use");
      if (!car || !use) missing.push("accordion chevron (.acc-item.open .car)");
      else {
        checked++;
        const href = use.getAttribute("href");
        if (href !== "#i-chevron-right")
          fails.push("accordion chevron glyph " + href + " — must be i-chevron-right (collapsed points inward; 90deg to down when open)");
        checked++;
        const m = getComputedStyle(car).transform.match(/matrix\(([^)]+)\)/);
        const v = m ? m[1].split(",").map(Number) : [1, 0];
        const ang = Math.round(Math.atan2(v[1], v[0]) * 180 / Math.PI);
        if (ang !== 90)
          fails.push("open accordion chevron at " + ang + "deg — expanded is DOWN = 90deg from right (HIG disclosure controls)");
      }
      // separators inset to the text lead (inset-grouped specimen: Settings),
      // never full-width border-top
      const items = document.querySelectorAll(".acc-item");
      if (items.length >= 2) {
        checked++;
        const after = getComputedStyle(items[1], "::after");
        const left = parseFloat(after.left) || 0;
        if (after.content === "none" || after.display === "none" || left < 16)
          fails.push("accordion separator not inset to text lead (::after left=" + left + ", content=" + after.content + ") — inset-grouped separators align with the title, full-width dividers are not the iOS idiom");
      }
    }
    // spinner = the iOS activity indicator: 12 fading blades (conic), never a
    // border ring. HIG progress-indicators: an indeterminate indicator "uses an
    // animated image"; the iOS form is the 12-blade UIActivityIndicator /
    // SwiftUI ProgressView(.circular); medium control = 20pt.
    {
      const sp = document.querySelector('.spin');
      if (!sp) missing.push('spinner (.spin)');
      else {
        const c = getComputedStyle(sp);
        const maskStr = (c.webkitMaskImage || '') + ' ' + (c.maskImage || '');
        checked++;
        if (!c.backgroundImage.includes('conic-gradient'))
          fails.push('glass spinner is not the conic alpha ladder (bg=' + c.backgroundImage.slice(0, 40) + ') — a border-top ring is the legacy idiom');
        checked++;
        // Chrome normalizes 'transparent 16deg 45deg' to split rgba stops —
        // accept either form; the semantic is a 16deg blade on a 45deg pitch.
        const pitch = maskStr.includes('repeating-conic-gradient') &&
          (maskStr.includes('transparent 16deg 45deg') || /rgba\(0, 0, 0, 0\) 16deg, rgba\(0, 0, 0, 0\) 45deg/.test(maskStr));
        if (!pitch)
          fails.push('glass spinner is not 8 blades (needs the 16deg-blade/45deg-pitch repeating-conic mask)');
        checked++;
        if (parseFloat(c.borderTopWidth) !== 0)
          fails.push('glass spinner has a border ring (' + c.borderTopWidth + ') — blades are not a ring');
        checked++;
        if (Math.round(parseFloat(c.width)) !== 20)
          fails.push('glass spinner ' + c.width + ' — medium activity indicator is 20pt');
      }
      // slider thumb wears the SAME invariant knob as the switch (R9k: the
      // overlay comment said "white thumb" but never set background, so the
      // base var(--surface) painted it near-black in dark)
      const sth = document.querySelector('.slider .thumb'), kth = document.querySelector('.sw .th');
      if (sth && kth) {
        checked++;
        const a = getComputedStyle(sth).backgroundColor, b = getComputedStyle(kth).backgroundColor;
        if (a !== b) fails.push('slider thumb ' + a + ' != switch knob ' + b + ' — both must be the invariant --knob (white in both themes)');
      }
    }
    // HIG: checkbox/radio are a macOS idiom, not iOS. Their presence in a glass
    // surface is a design smell, not a hard fail - flag it, don't block.
    if (document.querySelector(".cb") || document.querySelector(".rd"))
      notes.push("glass renders checkbox/radio: HIG says these are macOS-only; iOS uses a switch or a list-row checkmark accessory");
      notes.push("glass shows the compact time field only: Apple publishes no time-picker geometry and iOS uses a wheel, not a dial — inventing px here would fabricate a spec");

      /* navTint — the HIG-grounded replacement for the deleted capsule check.
         Apple's selected-tab treatment is colour on the symbol and label, with
         NO filled background behind it. Two assertions, both directional:
           a) the selected indicator has no fill (that fill is the Material tell)
           b) selected and unselected differ in COLOUR (else nothing marks it) */
      [[".nb", "bottom bar"], [".nr", "rail"], [".sb-i", "sidebar row"]].forEach(([sel, label]) => {
        const on = document.querySelector(`${sel}.on`);
        const off = document.querySelector(`${sel}:not(.on)`);
        if (!on || !off) { missing.push(`${sel} (navTint)`); return; }

        const ind = on.querySelector(".ind") || on;
        const bg = getComputedStyle(ind).backgroundColor;
        const filled = bg && bg !== "transparent" && !/rgba?\([^)]*,\s*0\s*\)/.test(bg);
        checked++;
        if (filled)
          fails.push(`${label}: selected item has a filled indicator (${bg}) — that is Material 3's active indicator; Apple marks selection with colour on the symbol, not a background`);

        checked++;
        if (getComputedStyle(on).color === getComputedStyle(off).color)
          fails.push(`${label}: selected and unselected are the same colour — with no filled indicator, tint is the ONLY thing marking selection`);
      });
  }

  return JSON.stringify({
    style, checked,
    pass: fails.length === 0 && missing.length === 0,
    fails, missing, notes,
  }, null, 1);
})()
