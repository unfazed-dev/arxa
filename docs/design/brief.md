# app-box — design brief

Elicited via app-box-story-mapper; the full story map lives alongside
this brief (`story-map.json`, `story_map.html`). Priorities are MoSCoW,
grouped into release swimlanes. Every registry surface must trace to
the surface inventory table below (gates/intake, plan 10.7).

## Product

app-box

## Releases

- **R1 Dogfood** — app-box designs, builds and ships itself; Michelle's 20-minute evaluation
- **R2 Anywhere** — reach the daemon from anywhere (self-host tailnet); visual review depth
- **R3 Delight** — polish and moat-widening

## The things the app must do

### Intake & Story Mapping

#### Mapping

- [must/R1 Dogfood] Evan turns a client brief into an Epic-Feature-Story map in one sitting
- [must/R1 Dogfood] Surface count + kit-coverage estimate within an hour of signing, to quote honestly
- [should/R1 Dogfood] A non-technical client can read and correct the story map (HTML)
- [could/R3 Delight] Stories carry EARS-style acceptance criteria gates can check

#### Brief

- [must/R1 Dogfood] brief.md surface table feeds the designer; every registry surface traces to a story
- [must/R1 Dogfood] Registry seeded from the brief without rewriting

#### Moodboard

- [must/R1 Dogfood] Given the story map, the moodboard orchestrator fans out per-epic reference-gathering prompts and curates real apps to steal from
- [must/R1 Dogfood] Each reference's key screens are captured (probe-runner) and saved with semantic filenames (ref__screen.png)
- [must/R1 Dogfood] The moodboard assembles as a browsable doc linking references and shots to the epics they inform; every embedded shot verified on disk
- [should/R1 Dogfood] The design stage receives the moodboard alongside the brief and consults it before authoring

### Design & Freeze

#### Prototype

- [must/R1 Dogfood] Brief to clickable htmx prototype in under 10 minutes, carrying structure not pixels
- [must/R1 Dogfood] Every surface designed at 390/744/1280 from targets alone (literal parity)
- [must/R1 Dogfood] Target selection labels buildability on this machine (requires macOS)

#### Chat

- [must/R1 Dogfood] Select a screen, chat exclusively in its context; all other screens dim
- [must/R1 Dogfood] Selection is a removable context chip: this surfaceId's spec, never the whole app
- [must/R1 Dogfood] Hard tool-gating: only this screen's tools exposed (edit-layout, restyle, adjust-states, regenerate)
- [should/R1 Dogfood] Text/token tweaks apply instantly, no model round-trip
- [must/R1 Dogfood] Each message checkpoints this screen only; one-tap revert, rendered before/after
- [should/R1 Dogfood] Stale-selection guard: prototype changed since selection triggers re-sync or warn
- [could/R2 Anywhere] Shared token/nav edit offers 'affects N screens, apply to all?' (nobody ships this)

#### Freeze

- [must/R1 Dogfood] Hash-locked freeze; approval bound to the design hash; post-approval change goes stale loudly
- [must/R1 Dogfood] Drift report + brief-to-surface-to-code traceability

### Build & Gates

#### Loop

- [must/R1 Dogfood] Start a build, walk away; stops on red, ESC_LIMIT=3
- [must/R1 Dogfood] Per-surface evidence report (screen to tests to code), not one giant diff
- [must/R1 Dogfood] SARIF findings pinned to file/line with reproduce command

#### Gates

- [must/R1 Dogfood] Three gates an agent can reach but never pass; approval = human + any authenticated shell, provenance-bound (shell, device/node identity, confirm method, timestamp, hash)
- [must/R1 Dogfood] Approve/reject from phone push with biometric confirm
- [should/R1 Dogfood] Pre-submission checklist gate (crashes/permissions, where generated apps die)

#### Visual

- [must/R1 Dogfood] probe-runner design-vs-built gates: pixel (SSIM), skeleton, colour (deltaE) against the frozen golden
- [must/R1 Dogfood] Smoke per target: app boots, first screen renders, no crash

### Flows Canvas

#### Canvas

- [must/R2 Anywhere] app-box auto-captures screenshots of design + built app per surface (probe-runner)
- [must/R2 Anywhere] Flows on a canvas: living captures, connections truth-derived from real navigation
- [should/R2 Anywhere] Replayable named flows for gate reviews; zoom-semantic canvas keyed to story-map sections

### Ship & Deploy

#### Deploy

- [must/R1 Dogfood] Per-platform builds from one codebase; unbuildable targets hard-block as a named precondition, never a red gate
- [must/R1 Dogfood] Payment gate at first deploy: licence required to ship; everything before it free
- [must/R1 Dogfood] Export-always: ordinary Stacked MVVM in my own repo, no export tier
- [should/R2 Anywhere] Guided store submission (most-cited unmet gap in every builder)

### Access & Devices

#### Pairing

- [must/R1 Dogfood] One-scan QR pairing (host/port/nonce/key fingerprint); relayed QR fails the pin
- [must/R1 Dogfood] Device list with last-seen + revoke; revoke drops the session immediately
- [must/R1 Dogfood] LAN-only by default, no cloud relay; an agent can never mint an approval

#### Notifications

- [must/R1 Dogfood] Push when a gate goes red (deduped per transition), deep-link into the gate card
- [should/R1 Dogfood] Actionable notification: approve/reject without opening the app

#### Remote

- [should/R2 Anywhere] Self-host tailnet (compose file) or hosted Tailscale; pre-auth key in the QR; approvals bind to WireGuard node identity
- [should/R2 Anywhere] Private mesh CA gives trusted HTTPS origins over the mesh (arxa ADR-0036 pattern)

### First Run & Showcase

#### Showcase

- [must/R1 Dogfood] Showcase app launches on install, automatically; quality visible in minute one
- [must/R1 Dogfood] First project to working prototype in 20 minutes or less, no docs (timed; over 20 is a finding)

#### Honesty

- [must/R1 Dogfood] Stubs labelled before you build against them; kit availability honest
- [must/R1 Dogfood] Credential tier stated on screen (stored in the macOS Keychain)
- [should/R1 Dogfood] Empty states carry wording, not blank surfaces

### Workspace

#### Projects

- [must/R1 Dogfood] Multi-project management; registry CRUD; add/delete feature yields byte-identical round-trip

#### Settings

- [must/R1 Dogfood] BYO key in OS vault, never logged; no inference metering, cost is yours and visible
- [must/R1 Dogfood] Flat licence, never per-seat; pay at first deploy
- [should/R1 Dogfood] Kit vendoring from targets + capabilities; dependencyMode config from day one

### Website

#### Site

- [must/R2 Anywhere] A visitor gets app-box in 30 seconds: gated pipeline, own-your-code export, pay-at-deploy
- [should/R2 Anywhere] The three human gates are the headline, shown not told (recorded gate flow)
- [must/R2 Anywhere] Pricing page: flat licence, never per-seat, BYO key, pay at first deploy (the anti-credit-rage page)

#### Docs

- [must/R1 Dogfood] Docs portal publishes the knowledge base (architecture, plans, research, skills) with search
- [must/R1 Dogfood] Getting-started mirrors Michelle's 20 minutes: install, showcase, first prototype
- [should/R2 Anywhere] Public honesty page: what is wired, what throws, what is roadmap

#### Showcase

- [should/R2 Anywhere] Recorded walkthroughs and design-vs-built comparisons (probe-runner captures) prove quality before install
- [should/R2 Anywhere] Demo videos per persona journey (Evan's modes, Michelle's 20 minutes)

#### Download

- [must/R2 Anywhere] Download per platform: macOS dmg, daemon CLI for Windows/Linux, mobile apps, with the honest build matrix
- [must/R2 Anywhere] Licence purchase and activation, pay-at-deploy explained before checkout
- [should/R2 Anywhere] Changelog and release notes per version

## Surface inventory

| id | label | priority | release |
|----|-------|----------|---------|
| `intake.mapping` | Mapping | must | R1 Dogfood |
| `intake.brief` | Brief | must | R1 Dogfood |
| `intake.moodboard` | Moodboard | must | R1 Dogfood |
| `design.prototype` | Prototype | must | R1 Dogfood |
| `design.chat` | Chat | must | R1 Dogfood |
| `design.freeze` | Freeze | must | R1 Dogfood |
| `build.loop` | Loop | must | R1 Dogfood |
| `build.gates` | Gates | must | R1 Dogfood |
| `build.visual` | Visual | must | R1 Dogfood |
| `flows.canvas` | Canvas | must | R2 Anywhere |
| `ship.deploy` | Deploy | must | R1 Dogfood |
| `access.pairing` | Pairing | must | R1 Dogfood |
| `access.notifications` | Notifications | must | R1 Dogfood |
| `access.remote` | Remote | should | R2 Anywhere |
| `first.showcase` | Showcase | must | R1 Dogfood |
| `first.honesty` | Honesty | must | R1 Dogfood |
| `workspace.projects` | Projects | must | R1 Dogfood |
| `workspace.settings` | Settings | must | R1 Dogfood |
| `website.site` | Site | must | R2 Anywhere |
| `website.docs` | Docs | must | R1 Dogfood |
| `website.showcase2` | Showcase | should | R2 Anywhere |
| `website.download` | Download | must | R2 Anywhere |
