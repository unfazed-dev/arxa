# Moodboard — Restrained data viz (whitespace + warm accents)

Slice: chart language for **arxa**'s generative cards — build-duration trends, gate pass/fail history, coverage deltas — rendered with editorial restraint, not dashboard density.

Captured 2026-07-28 with the arxa lens. Freshness: **🔥** current · **🌡️** canonical.

---

## 1. Observable Plot — https://observablehq.com/plot/ · 🔥

![Observable Plot](shots/data-viz/observable-plot__examples.png)

The exploratory-viz library's site leads with a honeycomb wall of chart thumbnails — and the individual charts are the restraint benchmark: hairline axes, no chartjunk, muted grids, one or two hues per chart, whitespace doing the layout work.

- **Steal:**
  - **Grammar-of-graphics defaults**: thin grey axis lines, no box around the plot area, ticks outside, direct labels instead of legends where possible.
  - **One hue per chart** (+ a neutral); a second hue only to mark the *thing that matters* (today's bar, the failed run).
  - Small-multiples thinking: many tiny charts each answering one question beat one dense mega-chart.
- **Why it fits:** arxa's inline cards will hold small charts (duration trend, gate history); Plot's defaults are exactly "generous whitespace, warm accent possible".

## 2. Linear Insights — https://linear.app/insights · 🔥

![Linear Insights](shots/data-viz/linear__insights.png)

Linear's analytics surface: burnup/velocity charts with muted gridlines, soft area fills, a single accent per series, and — crucially — **each chart is presented as an answer with a plain-language title**, not a tile in a grid.

- **Steal:**
  - **Chart-as-answer framing**: title states the finding ("Cycle velocity"), the chart merely evidences it — matches GenUI's "render the answer, not the dashboard".
  - Muted gridlines + soft area under the line + one accent; axes carry minimal ticks.
  - **Progress bars with gentle rounded caps** as the dominant quantitative glyph — cheap, calm, glanceable.
- **Why it fits:** Insights proves dev-tool analytics can feel serene; its burnup chart is a direct template for arxa's pipeline-progress card.

## 3. GitHub contribution graph — https://github.com/sindresorhus (public profile) · 🔥

![GitHub profile + contribution graph](shots/data-viz/github__contribution-graph.png)

The most-viewed data viz in dev tools: a calendar heatmap with a **5-step single-hue ramp**, zero axes, zero labels except months/days — plus the profile's activity-overview radial and language bars, all in the same restrained register.

- **Steal:**
  - **Single-hue stepped ramp** (empty → full) — recolor with arxa amber/terracotta for a "build activity" heatmap; warmth comes free.
  - **Quantitative display with no chrome**: if the data needs no axis, draw no axis.
  - Language/proportion bars: thin stacked horizontal bars with 4-6 segments and tiny dot+label legends — perfect for per-surface gate status distribution.
- **Why it fits:** every arxa user already reads this vocabulary fluently; borrowing it makes the build monitor instantly legible.

## 4. Stripe — https://stripe.com · 🔥

![Stripe product UI](shots/data-viz/stripe__dashboard.png)

Stripe's marketing pages show its dashboard/product UI: metric cards with large quiet numerals, small sparkline-adjacent charts, enormous padding, and typography-first hierarchy — numbers as the visual, not decoration.

- **Steal:**
  - **Metric card anatomy**: small caps label, big numeral, one delta line ("+12% vs last week"), optional tiny trend — nothing else.
  - **Padding as a feature**: cards breathe with 24-32px internal space; density is the enemy of calm.
  - Hierarchy by weight/size, not by color: the number shouts, everything else whispers.
- **Why it fits:** arxa's headline metrics (builds green this week, gate latency, time-to-ship) deserve exactly this treatment inside chat cards.

---

## Patterns this slice must have

1. **One hue per chart**; a second only to spotlight the datum that matters. (Plot, Insights)
2. **Hairline muted grids, no plot box, minimal ticks**; direct labels over legends. (Plot)
3. **Chart titles state the answer** in plain language; the chart is evidence. (Insights)
4. **Single-hue stepped ramps** for heatmaps/calendars, recolored warm (amber/terracotta). (GitHub)
5. **Metric cards = label + numeral + delta**, 24-32px padding, whitespace as layout. (Stripe)
6. **Small multiples over mega-charts** inside chat cards. (Plot)
7. **Rounded progress bars** as the default quantitative glyph for gate/pipeline progress. (Insights)
8. **No chrome where data needs none** — no axes on ramp/heat visualizations. (GitHub)
9. Hierarchy by **weight and size, not color**; color is reserved for status. (Stripe)
10. Red appears *only* for failure states — in a calm warm UI it carries maximum signal. (all)
