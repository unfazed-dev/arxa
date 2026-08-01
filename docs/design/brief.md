# appbox — design brief

Elicited via appbox-story-mapper; the full story map lives alongside
this brief (`story-map.json`, `story_map.html`). Priorities are MoSCoW,
grouped into release swimlanes. Every registry surface must trace to
the surface inventory table below (gates/intake, plan 10.7).

## Product

appbox

## Releases

- **R1 Dogfood** — appbox designs, builds and ships itself; Michelle's 20-minute evaluation
- **R2 Anywhere** — visual review depth; richer remote and notification surface
- **R3 Delight** — polish and moat-widening

## The things the app must do

### App Shell & Accounts

#### Splash

- [should/R1 Dogfood] Splash holds while the daemon handshake resolves — brand mark and live status, never a dead-end spinner

#### Access

- [must/R1 Dogfood] Splash screen while the daemon connects, then sign-in (email + Sign in with Apple + Google, seeded accounts) landing on the dashboard; sign-up, sign-out and session-expired states seeded

#### Dashboard

- [must/R1 Dogfood] 'Needs you' strip listing pending gates and failed runs across all projects
- [must/R1 Dogfood] Project cards grid: name, targets, stage, last activity, thumbnail
- [must/R1 Dogfood] Pair-a-device entry point on the dashboard opens the safely generated QR pairing modal (short-lived, single-use)
- [should/R2 Anywhere] Analytics trio: runs/week, stage durations, gate latency

#### Projects

- [must/R1 Dogfood] Project creation is a GenUI wizard generated inline in the chat thread (name + platform targets: iOS/Android/macOS/web)
- [should/R2 Anywhere] Repo connect (GitHub default, other hosts) deferred to first gate approval; also available in settings
- [must/R1 Dogfood] Auto-save of every chat action with a saved/saving indicator
- [must/R1 Dogfood] Header panel shows project name + current stage chip, with click-through to the dashboard/project switcher

#### Pairing

- [must/R1 Dogfood] One-scan QR pairing: single-use short-lived tailnet pre-auth key + host/nonce/key fingerprint; relayed QR fails the pin
- [must/R1 Dogfood] Device list with last-seen + revoke; revoke drops the session immediately
- [must/R1 Dogfood] No third-party cloud relay — self-hosted tailnet only; an agent can never mint an approval
- [must/R1 Dogfood] Phone/tablet auth view is the pairing flow (scan QR or enter code) — no sign-in forms on touch devices; account sign-in lives on desktop

#### Notifications

- [must/R1 Dogfood] Push when a gate goes red (deduped per transition), deep-link into the gate card
- [should/R1 Dogfood] Actionable notification: approve/reject without opening the app

#### Remote

- [must/R1 Dogfood] Self-host tailnet (compose file) or hosted Tailscale from day one; daemon and apps are tailnet nodes in-process; approvals bind to WireGuard node identity
- [should/R2 Anywhere] Private mesh CA gives trusted HTTPS origins over the mesh (arxa ADR-0036 pattern)

### Intake & Story Mapping

#### Interview

- [must/R1 Dogfood] Intake is a typeform journey of eight surfaced steps — interview, personas, surfaces, flows, story map, direction, brief, moodboard — each walking one item at a time in the main panel, the chat rail always in step context, the journey timeline in the footer
- [must/R1 Dogfood] Mode pick is the journey's first move (selectable cards, not chat buttons): simple auto-answers and auto-accepts prefills on the fast path (interview → brief); normal (default) shows every step prefilled for confirmation; advanced (expert) shows every step raw with no auto-accept
- [must/R1 Dogfood] Every prefill carries a provenance chip (client / founder / inferred) — inferred items ask to be confirmed or corrected, never trusted silently; confirmed items re-open from the item strip
- [must/R1 Dogfood] Each journey step is its own surfaced screen with confirm, a structured correction form, skip, and accept-all — progress lives in the footer timeline, the chat rail answers in step context
- [must/R1 Dogfood] All-at-once generation when the questionnaire completes: brief + story map appear as main panel artifacts; the moodboard follows as a suggested next step
- [must/R1 Dogfood] Layout template picking is an intake step: app category first (closed list), then one of six archetype galleries (feed, list-detail, supporting-pane, dashboard, hero-scroll, detail-column) shown as plain colored boxes of named containers at full size in the main panel — recorded in the brief, consumed by the designer without rewriting

#### Personas

- [must/R1 Dogfood] Personas are a confirmable step: drafted from the interview with provenance chips (goals / frustrations / contexts / proficiency / accessibility), corrected via structured edits, re-opened from the item strip

#### Surfaces

- [must/R1 Dogfood] The surface inventory is a confirmable step grouped by shell — every surface lists the states it must cover (empty / loading / error / populated), feeding the designer and the coverage gate

#### Flows

- [must/R1 Dogfood] Flows are drafted over the screen registry as persona-bound edge sets {from, to, trigger} — one edge set, three projections (prototype / flows / screens), confirmed path by path

#### Direction

- [must/R1 Dogfood] Design direction is a confirmable step: adjectives to chase, hard avoids, and moodboard references — handed to the designer alongside the brief

#### Mapping

- [must/R1 Dogfood] Evan turns a client brief into an Epic-Feature-Story map in one sitting
- [must/R1 Dogfood] Surface count + kit-coverage estimate within an hour of signing, to quote honestly
- [should/R1 Dogfood] A non-technical client can read and correct the story map (HTML)
- [could/R3 Delight] Stories carry EARS-style acceptance criteria gates can check
- [must/R1 Dogfood] Stage gating: the Design shell stays locked until the story map is approved (human-gate pattern); locked shells explain why and the chat nudges
- [should/R2 Anywhere] Post-approval edits produce a new story-map version requiring re-approval; downstream stages get a 'map changed' badge

#### Live Map

- [must/R1 Dogfood] Live story map artifact: epics as horizontally scrolling columns, release swimlanes, story cards with live status dots (pending/in-progress/done/blocked) fed by pipeline state
- [should/R1 Dogfood] Progress rollups per epic and per release on the live story map
- [should/R2 Anywhere] Tapping a story opens a detail card center-stage

#### Brief

- [must/R1 Dogfood] brief.md surface table feeds the designer; every registry surface traces to a story
- [must/R1 Dogfood] Registry seeded from the brief without rewriting

#### Moodboard

- [must/R1 Dogfood] Given the story map, the moodboard orchestrator fans out per-epic reference-gathering prompts and curates real apps to steal from
- [must/R1 Dogfood] Each reference's key screens are captured (appbox lens) and saved with semantic filenames (ref__screen.png)
- [must/R1 Dogfood] The moodboard assembles as a browsable doc linking references and shots to the epics they inform; every embedded shot verified on disk
- [should/R1 Dogfood] The design stage receives the moodboard alongside the brief and consults it before authoring

### Design & Freeze

#### Prototype

- [must/R1 Dogfood] Brief to clickable htmx prototype in under 10 minutes, carrying structure not pixels
- [must/R1 Dogfood] Every surface designed at 390/744/1280 from targets alone (literal parity)
- [must/R1 Dogfood] Target selection labels buildability on this machine (requires macOS)
- [must/R1 Dogfood] The daemon drafts all screens from the approved story map in one pass; refining happens exclusively in the centered chat
- [must/R1 Dogfood] Component-library components are Auto Layout by default (flow, gap, padding, alignment; child hug/fill/fixed emitted as flexbox data-attributes); off by default at artboard level, per-frame opt-out

#### Chat

- [must/R1 Dogfood] Pin multiple screens as chat context (removable chips); in-context screens render side-by-side (rungs layout) at real device sizes with a colored outline + 'in context' tag; non-context screens stay off-canvas
- [must/R1 Dogfood] Each pinned screen is a removable context chip carrying its surfaceId's spec, never the whole app
- [must/R1 Dogfood] Tool-gating scopes to the in-context set: only the pinned screens' tools exposed (edit-layout, restyle, adjust-states, regenerate)
- [should/R1 Dogfood] Text/token tweaks apply instantly, no model round-trip
- [must/R1 Dogfood] Each message checkpoints the in-context screens only; one-tap revert, rendered before/after
- [should/R1 Dogfood] Stale-selection guard: prototype changed since the in-context screens were pinned triggers re-sync or warn
- [could/R2 Anywhere] Shared token/nav edit offers 'affects N screens, apply to all?' (nobody ships this)
- [must/R1 Dogfood] The floating vertical filmstrip inside the design artifact is the context picker: clicking toggles a screen's in-context state
- [must/R1 Dogfood] Design elements carry inspect metadata (data-inspect-role/-style/-motion/-fn): role, style, motion and function facts read straight from the markup by the inspect pass

#### Freeze

- [must/R1 Dogfood] Hash-locked freeze; approval bound to the design hash; post-approval change goes stale loudly
- [must/R1 Dogfood] Drift report + brief-to-surface-to-code traceability
- [must/R1 Dogfood] Freeze approval of the frozen manifest is the human gate that unlocks the Build stage
- [must/R1 Dogfood] Designer declares kit usage per surface (the registry `kits` field); the declaration is validated against the kit registry and flows through structure.json to the scaffold

### Chat-Centric Layout

#### Chat Stage

- [must/R1 Dogfood] Chat is the centerpiece in every stage, living in the composer panel — permanent, single-state, always on the right; the retired two-state chat (centered, sliding into a floating rail) is gone
- [must/R1 Dogfood] Single input path: no text inputs outside the chat — gate notes are chat replies carrying a context chip

#### Panels

- [must/R1 Dogfood] Activity panel (left): navigation and inventory — files, surfaces, runs / artifacts / commits views
- [must/R1 Dogfood] Main panel: the single render destination, an automatic multi-mode viewer — render:code/doc/image/svg/pdf/video for files, art/map/board for stage content
- [must/R1 Dogfood] Main panel mode selection is fully automatic: the active shell plus the content type select the mode and panel composition — no user toggles, no tabs, no panel picking
- [must/R1 Dogfood] Composer panel (right): permanent and single-state in every shell
- [must/R1 Dogfood] Panel bar: on compact and medium rungs a segmented switcher picks the one visible content panel (activity / main / composer); the tabbar (compact) and railbar (medium) switch shells
- [must/R1 Dogfood] Adaptive chrome defaults: expanded = header panel + activity/main/composer panels + footer panel; compact = header panel + tabbar + panel bar; medium = header panel + railbar + panel bar — overridable per project in the design brief
- [should/R2 Anywhere] Panels resize via a hover handle on the inner edge only, min = current width, max = 1.5×

#### Footer Panel

- [must/R1 Dogfood] Footer panel: read-only stage timeline with proper labels (not clickable; animation kept), project + run state, daemon status + pending-gate dots; in the design shell it also shows the design sub-steps (artboards → inspect · fine-tune → approval → freeze); the old top stage strip is removed

#### Main Chrome

- [must/R1 Dogfood] The main chrome (tab bar, shell switcher, daemon status) is one shared frame across every shell — intake, design, build, surfaces, settings

### Build & Gates

#### Loop

- [must/R1 Dogfood] Start a build, walk away; stops on red, ESC_LIMIT=3
- [must/R1 Dogfood] Per-surface evidence report (screen to tests to code), not one giant diff
- [must/R1 Dogfood] SARIF findings pinned to file/line with reproduce command
- [must/R1 Dogfood] The run thread is the build shell's chat: stage, evidence, chart and gate cards stream in as chat messages; evidence and charts open in the main panel (the composer panel stays put — see Chat-Centric Layout)

#### Gates

- [must/R1 Dogfood] Three gates an agent can reach but never pass; approval = human + any authenticated shell, provenance-bound (shell, device/node identity, confirm method, timestamp, hash)
- [must/R1 Dogfood] Approve/reject from phone push with biometric confirm
- [should/R1 Dogfood] Pre-submission checklist gate (crashes/permissions, where generated apps die)
- [must/R1 Dogfood] Gate approve/reject buttons live inline on gate chat cards; a reject note is a chat reply with a gate-context chip
- [must/R1 Dogfood] Build acceptance approval unlocks the deploy stage

#### Visual

- [must/R1 Dogfood] appbox lens design-vs-built gates: pixel (SSIM), skeleton, colour (deltaE) against the frozen golden
- [must/R1 Dogfood] Smoke per target: app boots, first screen renders, no crash

### Source Control & Files

#### Git

- [must/R1 Dogfood] The pipeline auto-commits at each gate/stage with shell-scoped conventional messages (e.g. chore(intake): ...)
- [should/R2 Anywhere] Commits view in the activity panel: git history with per-commit diff and CI status dots
- [could/R2 Anywhere] Open-in-editor button (VS Code default, configurable editor) launches the project externally
- [should/R2 Anywhere] appbox scaffolds each project's git setup: repo init, .gitignore, host connect

#### Files

- [should/R2 Anywhere] Files view in the activity panel: read-only generated-project tree with per-file status badges (new/changed/frozen); clicking a file opens its content in the main panel

### Flows Canvas

#### Canvas

- [must/R2 Anywhere] appbox auto-captures screenshots of design + built app per surface (appbox lens)
- [must/R2 Anywhere] Flows on a canvas: living captures, connections truth-derived from real navigation
- [should/R2 Anywhere] Replayable named flows for gate reviews; zoom-semantic canvas keyed to story-map sections

### Ship & Deploy

#### Deploy

- [must/R1 Dogfood] Per-platform builds from one codebase; unbuildable targets hard-block as a named precondition, never a red gate
- [must/R1 Dogfood] Payment gate at first deploy: licence required to ship; everything before it free
- [must/R1 Dogfood] Export-always: ordinary Stacked MVVM in my own repo, no export tier
- [should/R2 Anywhere] Guided store submission (most-cited unmet gap in every builder)

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
- [should/R1 Dogfood] Appearance prefs per device: warm light/dark theme + brand accent picker (cyan/violet/blue/ember from the logo)
- [must/R1 Dogfood] Language level plain/balanced/technical — every user-facing string written three ways; visual metrics render as X/100 match scores (ΔE 2.0 = 95/100 pass bar), technical level keeps raw values

#### Credentials

- [must/R1 Dogfood] One credentials surface manages every credential the generated app needs — payments, auth, maps, deploy and AI providers grouped in sections; each row shows the key name, a secret/publishable badge, a password-style input, a where-to-get link and a set/not-set chip
- [must/R1 Dogfood] User adds a Stripe test key for their design app from the credentials surface; the value goes to the OS vault via the daemon, never logged, and test keys work on simulators
- [must/R1 Dogfood] User sees which required keys are missing before build — the credentials surface and `appbox credentials check` report missing required keys per module
- [must/R1 Dogfood] Design surfaces the required credentials by key name from the catalog for the kits a surface declares — a maps screen lists its maps keys before build
- [must/R1 Dogfood] One config surface unifies the app's knobs — build targets and default locale (the appbox.config.json mirror), a credentials summary per module with missing-required badges, and shell prefs (theme, accent, jargon) — so the user reviews everything a generated app ships with in one place

#### Config

- [must/R1 Dogfood] A unified config view manages every kit credential and provider setting in one place — the same catalog the designer, scaffolder, and builder consume

### Website

#### Site

- [must/R2 Anywhere] A visitor gets appbox in 30 seconds: gated pipeline, own-your-code export, pay-at-deploy
- [should/R2 Anywhere] The three human gates are the headline, shown not told (recorded gate flow)
- [must/R2 Anywhere] Pricing page: flat licence, never per-seat, BYO key, pay at first deploy (the anti-credit-rage page)

#### Docs

- [must/R1 Dogfood] Docs portal publishes the knowledge base (architecture, plans, research, skills) with search
- [must/R1 Dogfood] Getting-started mirrors Michelle's 20 minutes: install, showcase, first prototype
- [should/R2 Anywhere] Public honesty page: what is wired, what throws, what is roadmap

#### Showcase

- [should/R2 Anywhere] Recorded walkthroughs and design-vs-built comparisons (appbox lens captures) prove quality before install
- [should/R2 Anywhere] Demo videos per persona journey (Evan's modes, Michelle's 20 minutes)

#### Download

- [must/R2 Anywhere] Download per platform: macOS dmg, daemon CLI for Windows/Linux, mobile apps, with the honest build matrix
- [must/R2 Anywhere] Licence purchase and activation, pay-at-deploy explained before checkout
- [should/R2 Anywhere] Changelog and release notes per version

## Surface inventory

| id | label | priority | release |
|----|-------|----------|---------|
| `app.splash` | Splash | should | R1 Dogfood |
| `app.access` | Access | must | R1 Dogfood |
| `app.dashboard` | Dashboard | must | R1 Dogfood |
| `app.projects` | Projects | must | R1 Dogfood |
| `app.pairing` | Pairing | must | R1 Dogfood |
| `app.notifications` | Notifications | must | R1 Dogfood |
| `app.remote` | Remote | must | R1 Dogfood |
| `intake.interview` | Interview | must | R1 Dogfood |
| `intake.personas` | Personas | must | R1 Dogfood |
| `intake.surfaces` | Surfaces | must | R1 Dogfood |
| `intake.flows` | Flows | must | R1 Dogfood |
| `intake.direction` | Direction | must | R1 Dogfood |
| `intake.mapping` | Mapping | must | R1 Dogfood |
| `intake.live` | Live Map | must | R1 Dogfood |
| `intake.brief` | Brief | must | R1 Dogfood |
| `intake.moodboard` | Moodboard | must | R1 Dogfood |
| `design.prototype` | Prototype | must | R1 Dogfood |
| `design.chat` | Chat | must | R1 Dogfood |
| `design.freeze` | Freeze | must | R1 Dogfood |
| `chat.chat2` | Chat Stage | must | R1 Dogfood |
| `shell.composer` | Panels | must | R1 Dogfood |
| `shell.footer` | Footer Panel | must | R1 Dogfood |
| `main.chrome` | Main Chrome | must | R1 Dogfood |
| `build.loop` | Loop | must | R1 Dogfood |
| `build.gates` | Gates | must | R1 Dogfood |
| `build.visual` | Visual | must | R1 Dogfood |
| `source.git` | Git | must | R1 Dogfood |
| `source.files` | Files | should | R2 Anywhere |
| `flows.canvas` | Canvas | must | R2 Anywhere |
| `ship.deploy` | Deploy | must | R1 Dogfood |
| `first.showcase` | Showcase | must | R1 Dogfood |
| `first.honesty` | Honesty | must | R1 Dogfood |
| `workspace.projects2` | Projects | must | R1 Dogfood |
| `workspace.settings` | Settings | must | R1 Dogfood |
| `workspace.credentials` | Credentials | must | R1 Dogfood |
| `workspace.config` | Config | must | R1 Dogfood |
| `website.site` | Site | must | R2 Anywhere |
| `website.docs` | Docs | must | R1 Dogfood |
| `website.showcase2` | Showcase | should | R2 Anywhere |
| `website.download` | Download | must | R2 Anywhere |
