(() => {
  /* Icon gate — the fourth gate.
   *
   * Why it exists: a Lucide sprite reference with a typo'd name renders an
   * EMPTY <use>. No error, no console warning, zero-size box, nothing drawn.
   * A screenshot cannot show you a missing icon, because nothing appears where
   * nothing was. The contrast gate won't see it (no foreground to sample) and
   * the geometry gate won't see it (it doesn't know the slot should be filled).
   * This is the only gate that can catch it.
   *
   * Asserts, per style:
   *   1. the sprite is present and has symbols (else every icon is vacuous)
   *   2. at least one icon renders (catches "migration never happened")
   *   3. every <use href="#i-name"> resolves to a symbol that exists
   *   4. every icon has a non-zero rendered box
   *   5. no leftover legacy glyphs remain in icon slots
   *   6. stroke is currentColor, so icons theme with their container
   */
  const fails = [];
  let checked = 0;
  const ok = (cond, label) => { checked++; if (!cond) fails.push(label); };

  const style = new URLSearchParams(location.search).get("style") || "liquid-glass";

  /* overlay-load guard: same law as the other gates — a gate that runs against
     the base skin when it thinks it is testing an overlay is worse than no gate */
  if (style !== "custom") {
    const link = [...document.querySelectorAll('link[rel="stylesheet"]')]
      .find((l) => (l.href || "").includes(style));
    const n = (() => { try { return link && link.sheet ? link.sheet.cssRules.length : 0; } catch (e) { return 0; } })();
    if (n < 50) throw new Error(`overlay for "${style}" not loaded (${n} rules) — gate would be vacuous`);
  }

  /* 1. sprite present */
  const symbols = [...document.querySelectorAll("svg symbol[id]")];
  const ids = new Set(symbols.map((s) => s.id));
  ok(symbols.length > 0, `no <symbol> found — icon sprite missing entirely`);

  /* 2. icons actually used */
  const icons = [...document.querySelectorAll("svg.ic")];
  ok(icons.length > 0, `no svg.ic elements — glyph migration has not happened`);

  /* 3+4+6. every icon resolves, has a box, and inherits colour */
  const seen = new Set();
  icons.forEach((svg, i) => {
    const use = svg.querySelector("use");
    const href = use ? (use.getAttribute("href") || use.getAttribute("xlink:href") || "") : "";
    const id = href.replace(/^#/, "");
    const where = svg.parentElement
      ? `${svg.parentElement.tagName.toLowerCase()}.${(svg.parentElement.className || "").toString().split(" ")[0]}`
      : "?";

    checked++;
    if (!use) { fails.push(`icon[${i}] in ${where}: svg.ic has no <use>`); return; }
    if (!id) { fails.push(`icon[${i}] in ${where}: <use> has no href`); return; }
    if (!ids.has(id)) { fails.push(`icon[${i}] in ${where}: href "#${id}" resolves to NO symbol — renders invisible`); return; }
    seen.add(id);

    /* An icon a style deliberately hides is not a broken icon: .seg-check only
       shows under m3. Skip the size assertion when it (or an ancestor) is
       display:none — this does NOT weaken typo detection, because an unresolved
       <use> still has a normal box and is caught by the symbol check above. */
    /* NOT `offsetParent === null` — SVGElement does not implement offsetParent,
       so that test is `undefined` and never true. An empty client-rect list is
       the real "display:none somewhere up the tree" signal. */
    const hidden = svg.getClientRects().length === 0;
    if (!hidden) {
      const r = svg.getBoundingClientRect();
      checked++;
      if (r.width < 4 || r.height < 4)
        fails.push(`icon[${i}] "#${id}" in ${where}: rendered ${r.width.toFixed(1)}x${r.height.toFixed(1)} — too small to see`);
    }

    const cs = getComputedStyle(svg);
    checked++;
    if (cs.stroke !== "none" && !/rgb|currentcolor/i.test(cs.stroke))
      fails.push(`icon[${i}] "#${id}": stroke "${cs.stroke}" is not a resolved colour — will not theme`);
  });

  /* 5. no legacy glyphs left in icon slots. These are the characters the
        gallery used before the sprite; any survivor is a missed slot. ⌘ is
        deliberately excluded — it is a keyboard shortcut string ("⌘X"), text
        rather than an icon. */
  const LEGACY = "✓›‹☰⌄◉▤◷✎♥↗✕＋☷≡▾▦✉⋯";
  /* Scan the WHOLE rendered document, not a slot list. Two holes killed the
     slot-list version: `.nb i` matched nothing (the nav puts <svg class="ic">
     straight into .nb, no <i> wrapper) — a selector matching zero elements
     passes silently — and the scan only read DIRECT text children, so a glyph
     one level deeper (inside .nb-l) was invisible. The real invariant is
     simpler and unfoolable: no legacy icon glyph anywhere in the page's text. */
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const leftovers = [];
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (n.parentElement && n.parentElement.closest("svg")) continue;   // sprite internals
    for (const ch of n.textContent) {
      if (!LEGACY.includes(ch)) continue;
      const el = n.parentElement;
      leftovers.push(`${el ? el.tagName.toLowerCase() + "." + (el.className || "").toString().split(" ")[0] : "?"}:"${ch}"`);
    }
  }

  /* 7. legacy glyphs generated by CSS. A DOM text scan cannot see
        `content: "\2713"` on a ::before — that is exactly how M3's segmented
        button kept a unicode checkmark through the whole sprite migration.
        Walk every element's pseudo-element content too. */
  const pseudoLeft = [];
  [...document.querySelectorAll("*")].forEach((el) => {
    for (const pe of ["::before", "::after"]) {
      let c;
      try { c = getComputedStyle(el, pe).content; } catch (e) { continue; }
      if (!c || c === "none" || c === "normal") continue;
      for (const ch of c) if (LEGACY.includes(ch))
        pseudoLeft.push(`${el.tagName.toLowerCase()}.${(el.className || "").toString().split(" ")[0]}${pe}:"${ch}"`);
    }
  });
  ok(leftovers.length === 0, `legacy glyphs still in page text: ${leftovers.join(", ")}`);
  ok(pseudoLeft.length === 0, `legacy glyphs generated in CSS content: ${pseudoLeft.join(", ")}`);

  return {
    style,
    checked,
    spriteSymbols: symbols.length,
    iconsRendered: icons.length,
    distinctUsed: seen.size,
    pass: fails.length === 0,
    fails,
  };
})()
