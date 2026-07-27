# Workflow — the Junior-Designer pass sequence

> Distilled from huashu's "Junior Designer" mode. The load-bearing idea: **understanding wrong,
> caught early, is 100× cheaper than caught late.** Show assumptions and placeholders before you
> build; show progress mid-build; never vanish into a long silent "big move".

## Track with a task list
Use TodoWrite/TaskCreate to track the pass. The sequence below is the standard; small fixes skip steps.

## The pass
1. **Understand the need.**
   - 🔍 **#0 Fact-verify** (if a concrete product/tech/version is involved) — `WebSearch` FIRST,
     before questions. Write facts to `design-system.md`.
   - New/vague task → ask clarifying questions (template below), one focused round, batched.
   - 🛑 **Checkpoint 1:** send the whole question list at once; proceed only after the user answers.
     Don't ask-and-build interleaved.
2. **Explore resources + extract core assets.** Read the design system / linked files / screenshots /
   code. **If a brand is named, run `core-asset-protocol.md` end-to-end** (ask → search → download
   logo/product/UI → verify → freeze into `design-system.md`).
   - 🛑 **Checkpoint 2 (asset self-check):** real product render (not CSS silhouette) + logo + UI
     shots + colors from real HTML/SVG. Missing → stop and fill, don't fake.
   - If no context and no assets surface → run `design-directions.md` (3 directions), then return here.
3. **Answer the four position-questions, THEN plan the system.** The first half matters more than any
   CSS rule:
   - **Narrative role** — hero / transition / data / quote / closing? (each screen differs)
   - **Viewing distance** — 10cm phone / 1m laptop / 10m projector? (sets type size + density)
   - **Visual temperature** — calm / excited / cold / authoritative / warm / somber? (sets color + rhythm)
   - **Capacity estimate** — sketch 3 five-second thumbnails; does the content fit? (prevents overflow/cramping)
   - 🛑 **Checkpoint 3:** position answers + the system (color/type/layout rhythm/components) spoken
     aloud; wait for a nod before coding.
4. **Build the folder structure** — `design/` per `jsx-prototype-patterns.md` (shell + shards +
   data.jsx + icons + styles).
5. **Junior pass** — write assumptions + placeholders + reasoning comments into the shards first.
   - 🛑 **Checkpoint 3 (early show):** show the user (even grey blocks + labels); wait for feedback
     before filling components.
6. **Full pass** — fill placeholders, build variations (Tweaks if useful), show again mid-way (don't
   wait for "fully done").
7. **Verify** — Playwright screenshot + console-error check + the conformance freeze gate
   (`verification.md`).
   - 🛑 **Checkpoint 4:** open the browser yourself and look. Screenshots hide interaction bugs.
8. **Summarize** — minimal; caveats + next steps only.

## The clarifying-question template (batch, one round)
```
1. Do you have a design system / UI kit / codebase / Figma / screenshots? (if not, I'll search)
2. How many variations, and across which dimensions (visual / interaction / color / layout / motion)?
3. Care most about flow, copy, or visuals?
4. Anything you want me to Tweaks-tune live (accent hue / type / density)?
```
Adapt to the task; keep it to one focused round. Small fixes skip entirely.

## Exception handling (pre-defined fallbacks)
| Situation | Action |
|---|---|
| Need too vague to start | list 3 possible directions (landing/dashboard/detail), let the user pick — don't ask 10 questions |
| User says "stop asking, just build" | respect the pace; build 1 main + 1 clearly-different variant; **mark assumptions explicitly** so the user can localize what to change |
| Design context contradicts itself (ref vs. spec) | stop; point to the specific conflict ("screenshot is serif, spec says sans"); let the user pick |
| Starter asset fails to load (console 404) | check the pinned versions in `verification.md`; if still broken, degrade to plain HTML+CSS (no React) so output still works |
| Time-boxed ("need it in 30 min") | skip the Junior pass, go Full pass, 1 variant; **mark "unvalidated early-show"** — quality may suffer |
| Restraint vs. density conflict | if the product's core value is AI/data/context-aware, go high-density (≥3 differentiating signals/screen); else restrained |

**Principle:** on any exception, **tell the user what happened in one sentence first**, then act.
Never decide silently.

## Output discipline
- Descriptive file names: `Landing Page.html`, `iOS Onboarding v2.html`.
- On major revision, copy the old version: `My Design.html` → `My Design v2.html`.
- Avoid >1000-line files — split into shards (`jsx-prototype-patterns.md`).
- Keep everything in the project `design/` dir, not scattered to `~/Downloads`.
- Final output opened in a browser or Playwright-screenshotted before handoff.

## Iteration pass — "improve" / "v2" / "restyle" (the non-destructive contract)
When the verb is **improve / restyle / iterate / v2**, the prior design is the **source of truth**.
You **copy it verbatim and only ADD** — you never re-author, re-type, re-order, or rewrite v1's
content. This is the rule that prevents "an upgrade that's actually a downgrade" (the atlet-v2
failure: re-typed `Sunrise 5k` from distance→time, invented a `secs` step schema that broke the
ported Detail, rewrote SignInView dropping the Google/Apple glyphs).

**The pass:**
1. **Copy, don't rewrite.** `cp -r design/ design-v2/`. v1's `data.jsx`, `auth.jsx`, `icons.jsx`,
   `detail.jsx`, `styles.css`, and the shell structure are now v2's starting point, byte-for-byte.
2. **Only append.** Add new commerce/shop/support shards below v1's. Append new `SEED_*` arrays to
   `data.jsx` (never edit v1's `SEED_WORKOUTS`). Add new icons to the icon set. Append CSS, don't
   edit v1's rules. Wire the new surfaces into the shell.
3. **Verify drift BEFORE the gate.** `python3 scripts/design.py --diff design/ design-v2/` — a clean
   iteration shows ONLY `FILES ADDED` + `SEED_* (new — appended, OK)` + `BRAND MARKS (geometry
   preserved)`. Any `DRIFTED` / `DROPPED` / `GEOMETRY CHANGED` is a bug — fix it before freezing.
4. **The gate enforces it.** `designer_gate` runs `check_iteration_fidelity` (v1's `SEED_*` arrays
   must be a verbatim prefix of v2's — a single re-typed field fails it) + `check_brand_integrity`
   (the mark geometry must carry over) + `check_color_coherence` (no off-palette hardcoded colors —
   the "one dark screen doesn't match" glitch). Fail any → re-copy, don't hand-patch.

**Forbidden on an iteration:** rebranding the logo (that's `restyle`/`rebrand`, a from-scratch
asset pass), changing seed data, downgrading a feature (porting a thinner version), or re-ordering
screens. If you genuinely want to change v1's identity or content, the verb is **rebrand** or
**redesign**, not improve — and that resets the asset protocol.

**TweaksPanel is mandatory** for every design (new or iteration) — it's part of the deliverable,
not a debug tool. Ship the 4-axis controller (color/theme, typography, radius+spacing, motion) that
live-mutates the token CSS vars. `check_tweak_panel` fails any design with a committed `tokens.json`
that omits it.
