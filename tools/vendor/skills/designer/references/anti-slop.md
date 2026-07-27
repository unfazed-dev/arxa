# Anti-AI-slop + positive structural defaults

> Distilled from huashu-design §6 + Anthropic frontend-design. The blacklist lives **inline in
> SKILL.md** (load every time); this file is the full table with the *why*, plus the positive
> defaults that replace slop with taste.

## What is AI slop, and why fight it
AI slop = the **visual greatest-common-denominator of training data**. Purple gradients, emoji
icons, rounded-card-with-left-border, SVG-drawn faces — these are slop *not because they're ugly*,
but because they're **the AI default that carries zero brand information**.

Logic chain:
1. The user hired you to make *their brand* recognizable.
2. AI default output = training-data average = all brands blended = **no brand recognized**.
3. So AI default output = diluting the user's brand into "yet another AI page".
4. Anti-slop isn't aesthetic fastidiousness — it's **protecting brand recognizability for the user**.

This is why `core-asset-protocol.md` is the hardest constraint: obeying the spec is the *positive*
form of anti-slop (doing the right thing); the blacklist is the *negative* form (not doing the
wrong thing).

## The full blacklist (with the why, and the one legal exception)
| Element | Why it's slop | When it's legal |
|---|---|---|
| Aggressive purple gradient | the "tech" formula in every SaaS/AI/web3 landing | the brand *itself* uses it (Linear sometimes); or the task is to satirize/showcase slop |
| Emoji as icons | "not pro enough, pad with emoji" disease; every bullet gets one | the brand uses them (Notion); or child/casual audience |
| Rounded card + left color-border accent | 2020-24 Material/Tailwind cliché, now visual noise | user explicitly asks; or it's preserved in the brand spec |
| SVG-drawn imagery (faces/scenes/objects) | AI-drawn SVG people are always anatomically wrong, proportions eerie | **almost never** — use real photos (Wikimedia/Unsplash/AI-gen), or honest placeholder |
| **CSS silhouette / hand-drawn SVG for a real product** | produces "generic tech" — black bg + orange accent; every hardware product looks identical; recognizability = 0 (DJI Pocket 4 case) | **almost never** — run `core-asset-protocol.md` for a real render; AI-gen on official reference; honest placeholder as last resort |
| Inter/Roboto/Arial/system as display | too common; reader can't tell "designed product" from "demo page" | brand spec explicitly uses them (Stripe uses Sohne/Inter variants, but tuned) |
| Cyber-neon / `#0D1117` dark | GitHub-dark cliché copy | dev-tool product whose brand genuinely goes this way |

**Boundary:** "the brand itself uses it" is the *only* legal exception. If the spec says purple
gradient, use it — then it's a signature, not slop.

## The positive defaults (what to do instead)
- ✅ `text-wrap: pretty` + CSS Grid + advanced CSS — typesetting detail is the "taste tax" AI can't
  tell apart; an agent that uses these reads as a real designer.
- ✅ Use `oklch()` or colors already in the spec — **never invent new colors on the fly**. Every
  ad-hoc color dilutes recognizability.
- ✅ Illustrations prefer AI-generation (over SVG hand-drawing); HTML "screenshots" only for precise
  data tables.
- ✅ One detail to 120%, everything else to 80% — taste =精致 in the *right* place, not even polish.
- ✅ Asymmetry, band rhythm, color-block-over-shadow — structural moves that read as authored.

## Anthropic's 3-lever prompting (for generation / refinement)
1. **Address each dimension separately.** One prompt per axis (layout, color, typography, motion).
   Bundling produces mush.
2. **Cite concrete inspirations.** "Kenya Hara's whitespace + terracotta-orange #C04A1A", never just
   "minimalist". Concrete references pull the model off its default.
3. **Explicitly forbid the defaults.** Name the slop: "no purple gradient, no emoji icons, no
   rounded-card-with-left-border". Forbidding is as load-bearing as requesting.

## Structural taste anchors (when there's no design system)
| Dimension | Prefer | Avoid |
|---|---|---|
| Typeface | a serif display (Newsreader / Source Serif / EB Garamond) + `-apple-system` body | all-SF-Pro or all-Inter (reads as system default) |
| Color | one warm/cool ground + **single** accent carried throughout (rust/ink-green/deep-red) | multi-color clusters (unless ≥3 real data categories) |
| Density (default: restrained) | one fewer container, one fewer border, one fewer **decorative** icon — leave air | every card with a meaningless icon + tag + status-dot |
| Density (exception: high) | when the product's core value is intelligence/data/context-awareness (AI tools, dashboards, trackers), every screen needs **≥3 visible product-differentiating signals** — non-decorative data, reasoning fragments, inferred state | one button + one clock — the "smartness" is invisible, indistinguishable from a normal app |
| Signature detail | one "screenshot-worthy" texture: ultra-faint oil-paint grain / serif italic pull-quote / full-screen black waveform | even effort everywhere = bland everywhere |

**Two principles, both active:**
1. Taste = one detail at 120%, the rest at 80% —精致 in the right place, not everywhere.
2. Subtraction is the *fallback*, not a universal law. When the product's core value needs density
   (AI / data / context-aware), addition beats restraint — but the density is **content-bearing**,
   not decorative icons.

## Slop-isolation (for demo/educational content)
When the task *itself* is to show anti-design (e.g. "demo what AI slop is", or a comparison review),
**don't fill the page with slop** — isolate it in an honest bad-sample container: dashed border +
"counter-example · don't do this" badge, so the counter-example serves the narrative instead of
polluting the page's tone. Principle, not a template: a counter-example must *read* as one.
