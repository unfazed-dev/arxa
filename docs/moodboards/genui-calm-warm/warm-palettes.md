# Moodboard — Warm palettes (light cream/paper + warm-dark ember)

Slice: color direction for **appbox**'s calm/warm GenUI redesign — a warm-LIGHT scheme (cream/paper/terracotta/amber) and a warm-DARK scheme (ember/warm-charcoal), with real hex values to steal.

Captured 2026-07-28 with the appbox lens (own-tab CDP, 1440×900 @2x, full-page). Freshness: **🔥** current craft bar · **🌡️** canonical, steal selectively · **❄️** dated.

---

## 1. Flexoki — https://stephango.com/flexoki · 🔥

![Flexoki palette](shots/warm-palettes/flexoki__palette.png)

The single best warm-palette reference that exists: an "inky, analog paper" scheme with a complete published ramp, both modes, and **role mappings** (bg / bg-2 / ui / tx-3-2-1 + 8 accent families, each 50–950). MIT-licensed — hex values are directly stealable.

- **Steal:**
  - **Light mode**: bg `#FFFCF0` (paper), bg-2 `#F2F0E5`, ui borders `#E6E4D9`, tx `#100F0F`, tx-2 `#6F6E69`, tx-3 `#B7B5AC`.
  - **Dark mode**: bg `#100F0F` (warm black, not blue-black), bg-2 `#1C1B1A`, ui `#282726`, tx `#CECDC3`, tx-2 `#878580`, tx-3 `#575653`.
  - **Accents**: orange `#BC5215` (light) / `#DA702C` (dark) — the terracotta; yellow `#AD8301` / `#D0A215` — the amber; red `#AF3029` / `#D14D41` for failed gates.
  - **The design rule, verbatim**: "light themes use 600 for text accents, dark themes use 400" — a ready-made cross-mode accent policy.
  - **Pigment model**: accent intensity ramps exponentially toward the extremes so dark-mode accents stay warm, not pastel. Avoids the washed-out look of naive opacity scaling.
- **Why it fits:** appbox needs *one* warm neutral family that works in both modes; Flexoki's base ramp is exactly that, and its role naming maps 1:1 onto design tokens (surface/border/text/semantic).

## 2. Rosé Pine — https://rosepinetheme.com/palette/ · 🌡️

![Rosé Pine palette](shots/warm-palettes/rosepine__palette.png)

Three coordinated variants (main dark `#191724`, moon, and **Dawn** — a warm cream light `#FAF4ED`). The palette page itself is a role→hex→HSL→RGB table — the cleanest token-documentation format to copy.

- **Steal:**
  - **Token role names**: `base / surface / overlay / muted / subtle / text` + `love / gold / rose / pine / foam / iris` — six semantic accent names warmer than "primary/secondary".
  - **Dawn as warm-light**: base `#FAF4ED`, surface `#FFFAF3`, overlay `#F2E9E1`, text `#575279`, gold `#EA9D34`.
  - **Main as (mauve-leaning) dark**: base `#191724`, surface `#1F1D2E`, overlay `#26233A`, gold `#F6C177`, rose `#EBCBCA`-family pinks for warmth.
  - The **three-variant ladder** (light / dim-dark / deep-dark) as a product concept: appbox could offer paper / ember / charcoal instead of a binary toggle.
- **Why it fits:** proves a warm palette can be a *system* (3 variants, 15 roles) rather than 5 loose swatches; Dawn is the closest shipping thing to "cream paper" in a real dev-tool ecosystem.

## 3. Realtime Colors — warm-cream palette applied to a live page · 🔥

![Warm cream palette on a real UI](shots/warm-palettes/realtimecolors__warm-cream-demo.png)

A palette visualizer that applies your five hexes to a full dummy site (hero, cards, buttons, footer) in real time. Shot shows a candidate appbox light palette **in situ**, not as swatches: text `#2B2118` (warm charcoal), bg `#FAF3E8` (cream), primary `#C96F4A` (terracotta), secondary `#E9DCC3` (sand), accent `#D9A441` (amber) — in Lexend, no less.

- **Steal:**
  - **Judge palettes on a page, never on swatches.** A terracotta that looks loud as a swatch reads calm as a button on cream.
  - The **5-role budget**: text / background / primary / secondary / accent — nothing else gets a color. This restraint *is* the calm.
  - 60-30-10 distribution is visible in the shot: cream dominates, sand sections divide, terracotta/amber only on actions.
- **Why it fits:** this is the evaluation method appbox's designer should apply to any candidate palette before adopting it. _(Note: `/palettes` listing 404s; the visualizer with URL-encoded colors is the usable surface.)_

## 4. Coolors — https://coolors.co/palettes/trending · 🔥

![Coolors trending palettes](shots/warm-palettes/coolors__trending.png)

The industry-standard palette browser: infinite grid of 5-swatch strips, each with copy-hex on hover. Trending skews warm/earth in 2026 — terracottas, ochres, sage-cream pairs.

- **Steal:**
  - The **5-swatch horizontal strip** as the atomic palette card — instantly scannable, one row per idea.
  - Warm families recur as: cream + rust + ochre + olive + espresso. Good raw material for alternates beyond the primary scheme.
- **Why it fits:** breadth reference — when the primary palette needs a sibling (e.g. a distinct "ship gate" family), this is the hunting ground.

## 5. Color Hunt — https://colorhunt.co/palettes/warm · 🌡️

![Color Hunt warm collection](shots/warm-palettes/colorhunt__warm.png)

A curated "warm" tag collection: dozens of 4-swatch cards heavy on amber/apricot/rust/cream. Simpler than Coolors (4 colors, no tools) — closer to how a client actually talks about color.

- **Steal:**
  - The **4-color discipline** (bg / surface / accent / text) — even fewer roles than 5; forces every element to earn its color.
  - Recurring warm-dark anchors: deep espresso `#2B2118`-family and warm charcoal rather than pure black.
- **Why it fits:** vocabulary check — "warm" to a client means exactly these apricot/terracotta/cream combinations; appbox's scheme must read as a member of this family.

---

## Patterns this slice must have

1. **Warm paper light mode**: bg `#FFFCF0`–`#FAF4ED` family, never pure white; text warm charcoal `#100F0F`–`#2B2118`, never pure black. (Flexoki, Dawn)
2. **Warm dark mode**: charcoal-with-brown bg `#100F0F`–`#1C1B1A`, not blue-grey dark. (Flexoki dark)
3. **One terracotta primary** (`#BC5215` light / `#DA702C` dark) + **one amber accent** (`#AD8301` / `#D0A215`); nothing else saturated except semantic red/green. (Flexoki, realtimecolors)
4. **A documented role system** — bg/bg-2/ui/tx × light/dark, published as a table like Rosé Pine's — not loose hexes scattered in code. (Rosé Pine, Flexoki)
5. **Cross-mode accent rule**: light themes use the 600 step, dark the 400 step, so warmth survives the toggle. (Flexoki)
6. **5-color budget per surface** (text/bg/primary/secondary/accent), 60-30-10 distribution — cream dominates, accents only on actions. (Realtime Colors)
7. **Palette evaluated on a real page mock** before adoption. (Realtime Colors)
8. Optional **three-variant ladder** (paper / ember-dim / charcoal) instead of binary light/dark. (Rosé Pine)
9. Semantic accents named by warmth (`gold`, `rose`) rather than cold system names — reinforces the brand feel in tokens. (Rosé Pine)
10. Red reserved for failure (`#AF3029`/`#D14D41`), so a red gate is the loudest thing in a calm UI. (Flexoki)
