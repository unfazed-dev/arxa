# Design directions — the vague-brief fallback

> Distilled from huashu-design's "Design Direction Consultant" mode. Use **only** when the brief is
> genuinely vague ("make something nice", "help me design", no reference, no stated style). If the
> user gave a concrete reference/style, skip this and go straight to the Junior-Designer pass.

## When to trigger / when to skip
**Trigger:** vague need ("做个好看的"/"design something nice"), explicit "recommend a style / give
me directions", zero design context, or the user says "I don't know what style I want".
**Skip:** a clear reference is given (Figma/screenshot/spec); the need is specific ("an Apple-Silicon
launch animation"); it's a small fix or a tool call.

When unsure, use the lightest version: **list 3 differentiated directions, let the user pick — don't
expand, don't generate yet.** Respect the user's pace.

## The flow
1. **Understand** (≤3 questions): audience / core message / emotional tone / output format. Skip if clear.
2. **Consultant restate** (100-200 words): your understanding of need, audience, scene, tone. End with
   "based on this, I prepared 3 directions".
3. **Recommend 3 design philosophies** (must be differentiated — see the school table below).
4. **Generate 3 visual demos** (use the user's real content, not lorem ipsum); screenshot each; show
   all 3 together. If the agent supports parallel subagents, run 3 in parallel; else serial.
5. **User picks** one to deepen / mix ("A's color + C's layout") / tweak / restart → back to step 3.
6. **Produce an AI prompt** for the chosen direction: `[philosophy constraint] + [content] + [tech
   params]` — concrete features not style names ("Kenya Hara whitespace + terracotta #C04A1A", not
   "minimalist"); include HEX, ratios, spacing, output spec; avoid the slop blacklist.
7. **Direction confirmed → return to the main Junior-Designer pass** with real context now.

## The 5 schools × 4 philosophies (pick 3 from 3 *different* schools)
The differentiation rule is load-bearing: 3 directions must come from **3 different schools** or the
user can't tell them apart.

| School (ids) | Visual mood | Good as |
|---|---|---|
| Information Architecture (01-04) | rational, data-driven, restrained | the safe/pro choice |
| Kinetic Poetics (05-08) | dynamic, immersive, technical beauty | the bold/avant choice |
| Minimalism (09-12) | order, whitespace, refinement | the safe/premium choice |
| Experimental Avant-garde (13-16) |先锋, generative-art, visual impact | the bold/innovative choice |
| Eastern Philosophy (17-20) | warm, poetic, contemplative | the differentiating/unique choice |

Representative philosophies (name a designer/studio, never just an "-ism"):
- **Pentagram** (info-architecture) — rigorous grid, typographic hierarchy, editorial discipline.
- **Field.io** (kinetic-poetics) — motion poetics, generative choreography, physics-driven beauty.
- **Kenya Hara / Hara Design Institute** (eastern) — existential minimalism, white as a concept,
  texture/material over decoration, MEBIUS/SENSEWARE.
- **Sagmeister & Walsh** (experimental) — hand-crafted type, rule-breaking composition, conceptual wit.
- **Dieter Rams** (minimalism) — "less but better", honest, unobtrusive, functional purity.
- **Massimo Vignelli** (info-architecture) — canonical grids, Helvetica discipline, "design is one".

Each direction card needs: designer/studio name · 50-100 words "why this fits you" · 3-4 signature
visual features · 3-5 mood keywords · an optional representative work. **Never recommend 2+ from the
same school.**

## The AI-prompt DNA (for a chosen direction)
Template: `[philosophy constraint] + [content description] + [technical params]`
- ✅ concrete features over style names; include color HEX, proportions, spacing, output spec.
- ❌ avoid the slop blacklist (purple gradient, emoji icons, SVG imagery, etc.).

## Real-material-first principle
When the design touches the user themselves or their product: ask for real assets — **never
fabricate** real personal data. Don't store real personal data inside the skill (leakage on
distribution).
