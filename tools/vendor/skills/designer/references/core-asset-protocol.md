# Core Asset Protocol — the brand-recognizability life-line

> Distilled from huashu-design §1.a (v1.1, the "asset > spec" upgrade). This is the **single
> biggest quality lever**: walking it correctly is the difference between a 40 and a 90. Skip no step.

**Trigger:** the task involves a concrete brand — a product/company/client is named (Stripe, Linear,
DJI, your own company…), whether or not the user supplied brand material.

## Step 0 — fact-verify (principle #0, precedes everything)
Before hunting assets, confirm the product **exists** and its **current state** is known:
`WebSearch "<product> 2026 latest | launch | release | specs"`. Read 1-3 authoritative results.
Write facts to `design-system.md`. If you catch yourself thinking "I think it hasn't launched" or
"probably vN" — **stop and search**. (Real case: assumed DJI Pocket 4 unreleased; it had shipped 4
days prior. 2h rework.)

## The core idea — asset > spec
A brand is recognized by what's *most identifiable*, in priority order:

| Asset | Identifiability | Required? |
|---|---|---|
| **Logo** | highest — logo = instant recognition | **every brand, mandatory** |
| **Product render** | very high — the hero of a hardware product | **hardware/packaging/consumer goods: mandatory** |
| **UI screenshot** | very high — the hero of a digital product | **app/website/SaaS: mandatory** |
| Color values | medium — often collides without the above | auxiliary |
| Typeface | low — needs the above to register | auxiliary |

**Execution rules (violating any = protocol breach):**
- Extracting only colors + fonts, skipping logo/product/UI → **breach**.
- CSS silhouette / hand-drawn SVG in place of a real product render → **breach** (produces "generic
  tech" output — black bg + orange accent — recognizable as *no* brand).
- Can't find an asset and silently faking it → **breach**. Stop and ask.

## Step 1 — ask (one complete asset checklist)
Don't ask "do you have brand guidelines?" (too vague). Ask by priority:
```
For <brand/product>, which do you have? (priority order)
1. Logo (SVG / hi-res PNG)             — mandatory
2. Product render / official shot      — mandatory if hardware
3. UI screenshots / interface assets   — mandatory if digital
4. Color list (HEX/RGB)
5. Typeface list (display / body)
6. Brand guidelines PDF / Figma / brand site URL
Send what you have; I'll search/scrape/generate the rest.
```

## Step 2 — search official channels (by asset type)
| Asset | Where |
|---|---|
| Logo | `<brand>.com/brand` · `/press` · `/press-kit` · `brand.<brand>.com` · inline SVG in the site header |
| Product render | `<brand>.com/<product>` hero + gallery · official YouTube launch-film frames · press-release images |
| UI screenshot | App Store / Google Play product pages · site screenshots section · official demo-video frames |
| Color | inline CSS / Tailwind config / brand-guidelines PDF |
| Typeface | `<link rel=stylesheet>` refs · Google Fonts · brand guidelines |

`WebSearch` fallbacks: `<brand> logo download SVG` · `<brand> <product> official renders` ·
`<brand> app screenshots`.

## Step 3 — download (three fallback paths per asset type)
**Logo (mandatory):** (1) standalone SVG/PNG; (2) scrape the homepage HTML for inline `<svg>`;
(3) official social avatar (GitHub/Twitter/LinkedIn, 400-800px transparent PNG).

**Product render (hardware):** (1) official product-page hero (2000px+); (2) press kit;
(3) launch-video frames via `yt-dlp` + `ffmpeg`; (4) Wikimedia Commons; (5) AI-gen on a real
reference base — **never CSS/SVG hand-drawn**.

**UI screenshot (digital):** store/Play screenshots (beware mockups — compare), site screenshots
section, demo-video frames, the brand's own X launch shots, or ask the user to screenshot their own
logged-in view.

## The 5-10-2-8 quality gate (iron law, for non-logo assets)
> Logo: if it exists, use it (no 5-10-2-8 — recognition root, not a choice problem).
> Other assets (product/UI/reference/illustration): obey the gate.

- **5 search rounds** across channels (site / press / social / YouTube frames / Wikimedia / user
  screenshots), not "grab the first 2".
- **10 candidates** before filtering.
- **Pick 2** good ones from the 10.
- **Each ≥ 8/10** — below 8, prefer an honest placeholder (grey block + label) over filler.

**8/10 scoring dimensions:** resolution (≥2000px, ≥3000px for print/large-screen) · license clarity
(official > public domain > free stock > suspected-stolen = 0) · brand-mood fit · light/composition
consistency between the 2 picks · standalone narrative power (not decoration).

## Step 4 — verify + extract (not just grep colors)
| Asset | Verify |
|---|---|
| Logo | file exists + opens + ≥2 versions (light/dark bg) + transparent |
| Product render | ≥1 at 2000px+ + clean/masked bg + multiple angles |
| UI screenshot | real resolution (1x/2x) + current version + no user-data leakage |
| Color | `grep -hoE '#[0-9A-Fa-f]{6}' assets/<brand>-brand/*.{svg,html,css} \| sort \| uniq -c \| sort -rn \| head -20`, filter black/white/grey |

**Watch for demo-brand contamination:** product screenshots often contain *another* brand's color
(e.g. a tool demoing Heytea-red). Two strong colors together → distinguish. **Brand facets:** a
brand's marketing-site color and product-UI color often differ (Lovart: warm-cream+orange on
marketing, charcoal+lime in product). Both are real — pick the facet for the delivery context.

## Step 5 — freeze into `design-system.md`
Record logo paths, product/UI asset paths, color palette (with source), typefaces, signature
details, forbidden moves, and 3-5 mood keywords. **Then enforce structurally:**
- All HTML/shards **reference** the asset file paths — never CSS silhouettes or redrawn SVG.
- Logo/product renders are `<img>` refs to real files.
- CSS vars injected from the spec: `:root { --brand-primary: …; }`; HTML uses only `var(--brand-*)`.

This turns brand consistency from "discipline" into "structure" — to add a color you must edit the spec.

## Fallback when the protocol fails
| Missing | Action |
|---|---|
| Logo entirely | **stop and ask** — logo is the recognition root |
| Product render (hardware) | AI-gen on official reference → ask user → honest placeholder ("product render TODO") |
| UI screenshot (digital) | ask user for their own screenshot → demo-video frames; never a mockup generator |
| Colors entirely | run the design-directions fallback, recommend 3 directions, mark as assumptions |

**Never** silently fill with CSS silhouette / generic gradient — the protocol's biggest anti-pattern.
**Better to stop and ask than to fake.**

## Free commercial-use image sources (where to get real imagery)
A real `<img>`/data-URL photo beats a redrawn SVG silhouette every time (anti-slop rule). These are
the "holy trinity" — free for commercial use, no attribution required (verify per-image; terms shift):

| Source | Best for | License |
|---|---|---|
| **[Unsplash](https://unsplash.com)** | lifestyle / product / workspace photos, hi-res | free commercial, no attribution |
| **[Pexels](https://www.pexels.com)** | photos + video, filter by color/orientation (great for UI theming) | free commercial, no attribution |
| **[Pixabay](https://pixabay.com)** | 6.2M+ photos, vectors, illustrations, video | free commercial, no attribution |
| **[Picsum](https://picsum.photos)** | quick placeholder images for wireframes/mockups | free, deterministic by seed |
| **[PicJumbo](https://picjumbo.com)** | lifestyle & product photography | free commercial |

**For product context** search keywords like "minimal workspace", "phone mockup", or the product
category. **For placeholders during layout** use Picsum (`https://picsum.photos/seed/<id>/400/400`).
**Always verify** each image's license page before shipping, even on "free" platforms — contributor
terms can change. Reference the file path (or base64 data-URL for `file://`-openable designs) in
`design-system.md` Step 5, never a CSS silhouette.

## Real-case scars (don't repeat)
- **Kimi:** guessed "orange" from memory; Kimi is `#1783FF` blue. Full rework.
- **Lovart:** mistook Heytea-red (in a demo screenshot) for Lovart's own color. Near-miss.
- **DJI Pocket 4 (2026-04-20, triggered this protocol's v1.1):** ran the old colors-only protocol —
  no DJI logo, no Pocket 4 render, CSS silhouette instead. Output: "generic black+orange tech". The
  upgrade lesson: *"otherwise, what are we even expressing?"*
