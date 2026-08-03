# Moodboard — Scaffold stage (kit gate + scaffolding progress)

Slice: the blocking "kit gate" screen (~24 toggleable kit cards with a
per-kit circular/percentage loader) and the scaffolding-process/progress
screen that follows it, both hosted inside the existing appbox-studio panel
shell (header / composer / activity / mini / footer panels —
`designs/appbox-studio/ui/views/main_shell/shared/widgets/`).

## Raycast Store — https://www.raycast.com/store
![store grid](shots/scaffold-stage/raycast__store-grid.png)
- Steal: the hero's rounded-square icon tiles (colorful glyph on dark card,
  consistent corner radius, subtle depth/shadow) as the kit card's icon
  treatment — reads instantly at a glance across ~24 cards without needing
  color-coding by category.
- Grade: 🔥 (official site, matches Raycast's own extension icon system used
  store-wide)

## VS Code Marketplace — https://marketplace.visualstudio.com/vscode
![extension grid](shots/scaffold-stage/vscode-marketplace__grid.png)
- Steal: the exact card anatomy — icon (top-left), title, publisher line,
  a right-aligned metric (download count here; would be the kit's category
  or dependency count), star rating row, and a badge pinned bottom-right
  (FREE here; would be the toggle). Also steal the tiered sections —
  "Featured" / "Most Popular" / "Recently Added" — as a model for grouping
  kits (Core / Integrations / Platform) instead of one flat 24-card wall.
- Grade: 🔥 (official Microsoft marketplace, current)

## Unleash — https://www.getunleash.io/
![feature flag rollout card](shots/scaffold-stage/unleash__home-flags.png)
- Steal: the toggle-plus-percentage fusion — each row pairs an on/off switch
  directly against a rollout percentage and a thin gradient progress bar
  underneath the row. This is the most direct precedent for "toggle + %
  progress" living in the *same* control rather than as two separate widgets.
- Grade: 🔥 (official product page, screenshot is the actual product UI)

## PostHog Feature Flags — https://posthog.com/feature-flags
![variant rollout table](shots/scaffold-stage/posthog__feature-flags.png)
- Steal: per-row rollout percentage combined with status chips (Experiment /
  Operational / Stale, Release / Kill switch) — maps to a kit card's
  supporting metadata (e.g. "beta", "requires payments kit"). The toggle
  lives at the top of the whole panel (global on/off) with per-variant rows
  beneath it, worth considering for a "select all / clear all" affordance
  above the 24-card grid.
- Grade: 🔥 (official product page, live product screenshot)

## JetBrains Toolbox App — https://www.jetbrains.com/toolbox-app/
![installed vs available tools list](shots/scaffold-stage/jetbrains-toolbox__home.png)
- Steal: the closest real-world analog to the kit gate's *purpose* — a
  desktop app that lists installable dev tooling. The "Installed" section
  (icon, version, overflow menu) sits above "Available tools" (icon,
  one-line description, Install button) — directly maps to grouping enabled
  kits above disabled ones, or defaulting essential kits as pre-enabled at
  the top.
- Grade: 🔥 (official product page, actual app screenshot embedded)

## Railway — https://railway.com/
![dark pipeline hero + new-project tile](shots/scaffold-stage/railway__pipeline-home.png)
- Steal: the dark, terminal-adjacent studio aesthetic (deep navy/black,
  single accent purple, minimal chrome) for the scaffolding-progress screen,
  plus the "New Project" empty-state tile as a model for the gate-to-run
  transition — the kit gate should collapse into a single confirmation
  tile/card before the pipeline view takes over.
- Grade: 🌡️ (marketing page; full pipeline dashboard itself is behind login,
  captured the public hero/tile only)

## GitHub Actions — visualization graph — https://docs.github.com/en/actions/how-tos/monitor-workflows/use-the-visualization-graph
![job list with per-item status icon](shots/scaffold-stage/github-actions__visualization-graph.png)
- Steal: the left-column job/workflow list — one row per item, a status
  icon on the left, plain-text name, nothing else — as the model for the
  scaffolding-progress screen's step list (one row per kit being scaffolded,
  icon flips from spinner to check/fail as it completes). This is a strong
  fit for the existing **activity panel**'s carousel-of-views pattern
  (`activity_panel.html`) or the **footer panel**'s timeline
  (`footer_panel.html`) rather than a new surface.
- Grade: 🌡️ (docs page shows the surrounding navigation chrome via
  screenshots; the live real-time graph itself is not captured — it renders
  only inside an authenticated repo)

## Vercel Docs — https://vercel.com/docs/deployments
![three-pane dark docs shell](shots/scaffold-stage/vercel__deployments-docs.png)
- Steal: not a kit-gate pattern — a chrome-parity reference. The three-pane
  dark shell (left nav / center content / right "On this page" TOC) is
  structurally close to appbox-studio's existing activity-panel-on-the-side
  layout, confirming the panel-based shell constraint is compatible with a
  CI/pipeline-flavored dark theme without inventing new chrome.
- Grade: 🔥 (official docs, current)

## Patterns this slice must have
1. Kit card = icon (Raycast tile treatment) + label + publisher/category line
   + a single combined toggle-and-percentage control (Unleash), not two
   separate widgets.
2. Percentage renders as a ring around/beside the toggle while scaffolding
   is running, and collapses to a plain on/off once idle — no reference here
   ships a literal circular ring gauge; the ring itself is appbox's own
   invention, informed by the toggle+bar fusion in Unleash/PostHog.
3. ~24 cards are grouped into 3–4 tiers (VS Code's Featured/Most Popular/
   Recently Added, JetBrains' Installed/Available) rather than one flat grid
   — likely Core / Integrations / Platform / Advanced for appbox's kit set.
4. A "select all essentials" or default-enabled-on-top affordance (JetBrains
   Installed-section-first) so the 24-card wall isn't uniformly blank on
   first load.
5. The gate's confirm action collapses into a single tile before the
   scaffolding-progress screen takes over (Railway's New Project tile as the
   transition object) — the composer panel's existing pinned-context chips
   (`composer_panel.html`) are a plausible carrier for "which kits are
   enabled" once the gate closes.
6. Scaffolding-progress screen is a per-kit row list, one status icon per
   row flipping from spinner to check/fail (GitHub Actions job list) — hosted
   in the existing activity panel's carousel view or the footer panel's
   timeline, not a new panel.
7. Dark, low-chrome, single-accent-color palette (Railway, Vercel docs, GitHub
   dark) for the progress screen specifically — the kit gate itself can stay
   on the studio's existing light/neutral surface since it's closer to a
   settings/marketplace moment than a build-log moment.
