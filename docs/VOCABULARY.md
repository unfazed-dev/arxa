# arxa — VOCABULARY

**This document is sacred.** It is the single source of truth for the words
every human and every agent working on arxa uses. When two documents, two
agents, or a human and an LLM disagree about what a word means, the conflict
resolves **here** — not in the doc that shouted loudest or shipped most
recently.

Each term carries two glosses. They mirror the product's reader levels
(plain / balanced / technical, as implemented in the app's jargon facade):
the **plain gloss** is how you would explain the term to Michelle; the
**technical gloss** is the precise meaning an agent should reason with.
Balanced lives between them and needs no third line.

Every term also names its **owning layer** — Product, Pipeline, Kit, or
Design medium — which is where deeper authority for the term lives.

**Proposing changes.** Anyone may propose a new term, a rename, or a
retirement: open the change against this file and get the founder's sign-off.
A term is not canonical until it lands here. Renames must add the old word to
the term's _Avoid_ line and, once the old word is dead everywhere, to the
legacy table at the bottom.

This is a glossary only: no implementation details, no spec content, no file
paths. Ownership attribution (term → layer) is the only pointer allowed.

---

## Product

Terms for the thing we are selling and the people it serves.

**arxa**:
The product: one app plus its daemon that turns a client conversation into a
shipped mobile/desktop app, with a human approving every irreversible step.
A chat-centric Flutter app driving a deterministic design→build→ship pipeline
over a vendored UI kit, with three human gates an agent can reach but never
pass.
_Avoid_: builder, platform, tool (as the product's name)
_Layer_: Product

**Evan / Michelle**:
The two proto-personas every product decision answers to. Evan is the founder
running client projects; Michelle is the indie developer evaluating a purchase
— her install-to-working-prototype run must fit in 20 minutes.
Proto-personas with jobs-to-be-done: Evan (founder, four modes) is the
operator; Michelle (indie iOS+Android dev) is the buyer whose timed evaluation
is the product's quality bar.
_Avoid_: user, customer (name the persona instead)
_Layer_: Product

**Daemon**:
The always-on helper process on the developer's machine that does the actual
work — drafting screens, running builds, talking to paired devices.
The local background process (arxa) the app talks to; daemon and apps are
tailnet nodes, and approvals bind to its node identity.
_Avoid_: server, backend, cloud
_Layer_: Product

**Story Map**:
The agreed list of everything the app must do, organized so a non-technical
client can read and correct it before any design starts.
An Epic → Feature → Story hierarchy with MoSCoW priorities and release
swimlanes; it seeds the brief, the registry, and the live progress artifact.
_Avoid_: backlog, spec, requirements doc
_Layer_: Product

**Epic / Feature / Story**:
The three zoom levels of the story map: a big area of the app, something it
does inside that area, and one concrete promise small enough to check.
The story map's fixed hierarchy — epics own features, features own stories;
stories carry MoSCoW priority, a release swimlane, and optionally EARS-style
acceptance criteria.
_Avoid_: task, ticket, requirement (as hierarchy names)
_Layer_: Product

**MoSCoW**:
The priority labels on every story: must, should, could — and by omission,
won't (this time).
The priority vocabulary (must / should / could) assigned per story; gates and
release planning read it, "won't" is expressed by absence.
_Avoid_: P0/P1/P2, high/medium/low
_Layer_: Product

**Release Swimlane**:
Which release a story lands in: R1 Dogfood, R2 Anywhere, or R3 Delight.
The story map's horizontal grouping per release — R1 Dogfood (arxa ships
itself; Michelle's 20-minute evaluation), R2 Anywhere (remote/review depth),
R3 Delight (polish).
_Avoid_: milestone, sprint, phase (as release names)
_Layer_: Product

**Brief**:
The document the interview and story map produce, which the design stage
consumes without rewriting.
The gate-compatible design brief whose surface inventory table is the
traceability source: every registry surface traces to it, and the registry is
seeded from it.
_Avoid_: spec, PRD
_Layer_: Product

**Moodboard**:
A browsable collection of real apps worth stealing from, gathered per epic,
with captured screenshots, consulted before any screen is authored.
The per-epic reference artifact assembled by fan-out gathering: each
reference's key screens captured by the arxa lens under semantic filenames and
verified on disk.
_Avoid_: inspiration board, references (bare)
_Layer_: Product

**Stage**:
One step of a project's journey from idea to shipped app — intake, design,
freeze, build, ship — shown to the user as a timeline.
A user-facing phase of the pipeline; stages lock behind human gates (a locked
stage explains why) and the footer panel renders them as a read-only timeline.
_Avoid_: step, tab (a stage is a phase, never a navigation element)
_Layer_: Product

**Main Panel**:
The big middle area of the app: everything arxa shows you — a file, a
design, the story map, a video — appears there, automatically in the right
form.
The center chrome region between the activity and composer panels; the single
render destination for all content, in both the design prototype and the
shipped app. Fully automatic: the active shell plus the content type select
the mode and the panel composition — the user has no mode toggles, no tabs,
no panel picking. Every file made available in arxa (code, text, image,
svg, pdf, video) renders here, read-only, as does all stage content.
_Avoid_: mainboard (proposed, renamed before landing), center panel,
workspace, canvas
_Layer_: Product

**Main Panel Mode**:
The form the main panel shows something in — a code view, a document view,
the art view for design — picked by the app, never by hand.
The closed mode set: `render:code`, `render:doc`, `render:image`,
`render:svg`, `render:pdf`, `render:video` for files; `art`, `map`, `board`
for stage content. Adding a mode means retiring one or getting the founder's
sign-off — the same rule as Motion Vocabulary.
_Avoid_: viewer mode (bare), tab
_Layer_: Product

**Activity Panel**:
The left strip where you pick what to look at — files, surfaces, tools.
The left chrome panel hosting navigation and inventory content (files,
surfaces); one of the three content panels the panel bar switches between on
compact and medium rungs.
_Avoid_: left rail, rail (bare), sidebar
_Layer_: Product

**Composer Panel**:
The right strip where you talk to the agent — always there, in every stage.
The permanent right chrome panel hosting the chat composer; single-state in
every shell (the former two-state right rail is retired).
_Avoid_: right rail, chat panel (bare)
_Layer_: Product

**Header Panel**:
The strip across the top.
The top chrome panel: product/wordmark zone, stage navigation, environment
and session indicators.
_Avoid_: top bar, app bar
_Layer_: Product

**Footer Panel**:
The strip across the bottom — the read-only timeline of the project's stages.
The bottom chrome panel rendering the stage timeline; replaces the retired
Bottom Bar.
_Avoid_: bottom bar (retired)
_Layer_: Product

**Panel Bar**:
On phone and tablet, the switcher that shows one of the three panels at a
time.
The per-shell segmented switcher on compact and medium rungs that picks the
single visible content panel (activity / main / composer); distinct from the
tabbar, which switches shells.
_Avoid_: tabs, tab bar (for panel switching)
_Layer_: Product

**Tabbar**:
The bottom switcher on the phone for jumping between the app's sections.
The mobile bottom shell-switcher widget; a chrome widget of the compact
rung, not a navigation concept — Shell remains the grouping word.
_Avoid_: bottom navigation, tab bar (bare)
_Layer_: Product

**Railbar**:
The slim icon strip on the left of the tablet for jumping between sections.
The tablet left shell-switcher widget; the medium-rung counterpart of the
mobile tabbar.
_Avoid_: rail (bare), nav rail (as app chrome — it stays a container name)
_Layer_: Product

**Layout Template**:
During intake, you pick the rough shape of your app from a few plain colored
boxes — so the designer starts from structure, not a blank page.
The intake-chosen whole-app arrangement of named containers per form factor:
category first (closed list), then one of six archetype galleries (feed,
list-detail, supporting-pane, dashboard, hero-scroll, detail-column), shown
in device chrome at full size in a main panel; recorded in the brief and
consumed by the designer without rewriting. Whole-app level — distinct from
Archetype, which is per-surface.
_Avoid_: wireframe, theme, template (bare)
_Layer_: Product

**Human Gate**:
A decision only a person can make. The agent brings it to you, with evidence;
it can never take it.
One of three approvals an agent can reach but never pass: approval = human +
any authenticated shell, provenance-bound (shell, device/node identity,
confirm method, timestamp, hash).
_Avoid_: approval step, checkpoint, sign-off
_Layer_: Product

**Pairing**:
Connecting a phone or tablet to your daemon by scanning one QR code — no
passwords on touch devices.
One-scan QR pairing over the tailnet: single-use short-lived pre-auth key plus
host/nonce/key fingerprint; revoke drops the session immediately.
_Avoid_: login (touch devices), linking
_Layer_: Product

**Tailnet**:
Your private network of your own devices; arxa never relays through a
third-party cloud.
A self-hosted WireGuard mesh (self-host compose or hosted Tailscale); daemon
and apps are in-process nodes and approvals bind to node identity.
_Avoid_: cloud, relay, VPN (bare)
_Layer_: Product

**Reader Level**:
How technical the app's words are: plain, balanced, or technical — every
user-facing string is written three ways.
The jargon-level setting (plain / balanced / technical, default balanced):
copy falls back plain → balanced → technical; visual metrics render as X/100
match scores, technical keeps raw values.
_Avoid_: language level (it is not locale), verbosity
_Layer_: Product

**Targets**:
The platforms a project ships to — iOS, Android, macOS, web — chosen once at
project creation.
The project's platform set; platform-only by contract, and it *derives*
everything downstream: active viewport rungs, scaffolded form-factor file
sets, kit vendoring scope, build matrix.
_Avoid_: platforms (bare), devices
_Layer_: Product

**Golden**:
The approved design image a built screen is compared against, pixel by pixel.
The frozen capture used by arxa lens design-vs-built checks: byte/pixel/SSIM
comparison against it; console/page errors fail the lens
regardless of pixel match.
_Avoid_: screenshot (bare), reference image, baseline
_Layer_: Product

**Context Chip**:
A screen pinned into the chat so the agent works on exactly that screen and
nothing else.
A removable chat chip carrying one pinned surface's spec; tool-gating scopes
to the in-context set and each message checkpoints only those surfaces.
_Avoid_: attachment, mention
_Layer_: Product

**BYO Key**:
You bring your own AI key; arxa never meters or marks up inference.
Bring-your-own-key credential model: keys live in the OS vault, are never
logged, and inference cost stays the user's — a structural cost advantage,
not a discount tier.
_Avoid_: API key (as a product concept), credits, tokens (billing sense)
_Layer_: Product

**Pay-at-Scaffold** (was **Pay-at-Deploy** — renamed 2026-08-05, `0a9c87b`):
Everything is free until the app is actually generated; the entitlement is due
at first scaffold, never per seat.
The payment-gate model per `monetization-and-entitlements.md` D17/D18: an
offline, machine-bound entitlement JWT hard-blocks `emit scaffold` (fail-closed
at both `scaffoldMain` and the scaffold gate), and all stages before it run
free — the anti-credit-rage pricing story. The deploy-gate licence check and
the watermark pass are retired.
_Avoid_: subscription, per-seat, trial
_Layer_: Product

**Export-Always**:
The code is yours from day one — take it and leave whenever you like, no
export tier, no lock-in.
Every project is ordinary Stacked MVVM in the user's own repo at all times;
there is no export feature because there is nothing to export *to*.
_Avoid_: export tier, eject, lock-in
_Layer_: Product

---

## Pipeline

Terms for the deterministic machinery that turns a frozen design into a
built app.

**Pipeline**:
The conveyor belt that runs a project through its stages, stopping the moment
anything goes red.
The FSM orchestrator: it owns phase orchestration and pipeline state only —
assertions never live in it, they live in gates.
_Avoid_: workflow, script (bare), CI
_Layer_: Pipeline

**Gate**:
An automatic check that either passes or stops the line — and is proven able
to fail, so a green gate means something.
An isolated, self-tested assertion unit that reads state/files and exits pass,
fail, or not-applicable; it never calls a sibling gate, and its selftest must
include a negative case. Distinct from a Human Gate, which is a product
decision, not a script.
_Avoid_: test (bare), hook, validator — and never shortened from Human Gate
_Layer_: Pipeline

**Negative Case**:
The proof a gate can fail: break something on purpose, watch the gate catch
it and name the culprit.
The planted-defect block in every gate's selftest that asserts the gate fails
and names the offending file; a gate without one is rejected at review.
_Avoid_: failure test, edge case
_Layer_: Pipeline

**SARIF**:
The one format every check uses to report what failed and exactly where.
The shared machine-readable findings contract: every gate routes findings
through one emitter so the app, a paired device, and a CI log read the same
document, pinned to file and line with a reproduce command.
_Avoid_: report format, log output
_Layer_: Pipeline

**Freeze**:
Locking the approved design with a hash, so "what you approved" is a fact,
not a memory.
The hash-locked approval of the design manifest: approval binds to the design
hash, any post-approval change goes stale loudly, and the freeze approval is
the human gate that unlocks build.
_Avoid_: lock (bare), finalize, sign-off
_Layer_: Pipeline

**Drift**:
When reality quietly moves away from what was approved — arxa treats that
as an alarm, not a shrug.
Any divergence between the frozen manifest and current state; the drift
report plus brief-to-surface-to-code traceability is a freeze-stage
deliverable.
_Avoid_: diff, change (bare)
_Layer_: Pipeline

**Evidence**:
The per-screen proof bundle a build produces: here's the screen, here are its
tests, here's the code, here's the comparison against the golden.
The per-surface build report (screen → tests → code → probe comparison),
delivered as chat artifacts — never one giant diff.
_Avoid_: build log, output, artifacts (bare)
_Layer_: Pipeline

**Registry**:
The project's authoritative list of its surfaces, written by a human or the
intake stage — everything generated downstream traces back to it.
The authored surface inventory (id, label, render target, roles) from which
the derived structure tree is generated; gates assert the two stay in sync
with no orphans either way.
_Avoid_: config (bare), route table, manifest
_Layer_: Pipeline

**Flow**:
One journey through the app, screen by screen — sign up, buy something —
written as a chain of steps a client can read and correct.
A linear user-journey chain over registry surfaces: `{id, name, provenance,
edges}` where every endpoint is a declared surface and each screen carries at
most one outgoing and one incoming edge — no branches, no merges, no loops.
Declared at intake, or derived one draft per shell and confirmed.
_Avoid_: navigation map, flowchart, wizard
_Layer_: Pipeline

**Edge / Trigger / Action**:
One step in a flow: the screen you leave, the screen you arrive at, what the
user did to go, and how the app moves.
A flow edge `{from, to, trigger, action}` — endpoints are registry surface
ids, the trigger is the user-visible cause label, and the action is one typed
nav op: `push | replace | back | modal | system` (`modal` is a presentation
flag; `system` marks non-gesture edges such as auth-success or deep-link that
compile to route guards, never buttons). The default action is `push`.
_Avoid_: transition, link, nav event
_Layer_: Pipeline

**Producer**:
Whatever generates the design prototype — said with a hint of suspicion,
because producers are where structure gets invented or thrown away.
The generator of the design artifact; the research's measured finding is that
the htmx producer is already MVVM and a naive freeze discards that structure.
_Avoid_: generator (bare), template engine
_Layer_: Pipeline

**Scaffold**:
Generating the empty-but-correct Flutter files for every frozen surface,
which builders then fill in.
The per-surface Flutter file emission after freeze; form-factor file counts
derive from targets, never from hand decisions.
_Avoid_: boilerplate, codegen (bare)
_Layer_: Pipeline

**arxa lens**:
The robot photographer: captures screens of the design and of the built app
so they can be compared honestly.
The arxa-native capture/compare tool — `arxa/lib/lens.dart` over the CDP
client (`arxa/lib/cdp.dart`), driven via `skills/arxa-lens` — behind
moodboard shots, flows-canvas captures, and the design-vs-built visual gates
(byte/pixel against the golden; console/page errors are an automatic
failure). The promoted port of
the archived probe-runner: **for anything regarding arxa, arxa's own
tools come first** — lens (and the `arxa` CLI: gate, crud, serve, emit,
lint, watermark) before any external or archived tooling. If a capture verb
is missing, extend lens.dart/cdp.dart; never reach back for probe-runner.
_Avoid_: screenshot tool, test runner, probe-runner (archived name)
_Layer_: Pipeline

**Contract probe**:
A probe that holds any arxa-built app to the arxa opinion, not one that
knows this app.
Asserts the arxa opinion (panels, chips, no-reload HDA behavior) against ANY
served design, deriving its targets from the design's own declarations. The
behavioral sibling of the W-gate. Route discovery is `GET /__routes`, the
served design's own route table: a contract probe that names a route is
miscategorised by construction, and that is greppable — no `/design`,
`/intake` or `/build` literal may appear under
`arxa/lib/probes/contract/`. Run with `arxa design probe contract`; the
v1 set is `contract-panels` and `contract-chips`.
_Avoid_: generic probe, universal probe
_Layer_: Pipeline

**Studio suite**:
The engine's own smoke test, run through the one design it is allowed to know.
The existing ten probes: the engine's smoke test, run through its reference
design (arxa-studio). Legitimate engine concern, named for what it is —
free to hard-code studio routes, because knowing the studio IS its job. Run
with `arxa design probe studio`; `probe all` runs contract first, then this.
_Avoid_: the probe suite (bare), smoke suite (bare)
_Layer_: Pipeline

**Project**:
One client's app-in-progress: its interview answers, brief, registry, flows,
design seeds, and build evidence, kept together outside this repo.
A user project directory at `~/.arxa/projects/<name>/` with four shell dirs
— `intake/` (answers, brief, registry, flows), `design/` (seeds,
surfaces/partials, l10n), `build/` (evidence), `settings/` (project.json).
~/.arxa holds user projects only; the studio's own design stays in the
repo.
_Avoid_: workspace, repo (a project is not the repo)
_Layer_: Pipeline

**Current project**:
The project arxa is looking at right now — the studio shows it and the
pipeline writes into it.
The active project named by the one-line `~/.arxa/current` file (default
`portalo`); the design server resolves it as `--project` → `ARXA_PROJECT`
→ `current`, and `POST /__project_use` repoints it.
_Avoid_: active project, selected project
_Layer_: Pipeline

**Project overlay**:
The studio reading your project's files live as you work — no copying, no
syncing; edits appear on reload.
The design server's live-read of the current project over the studio
artifact: project files are served through the overlay at request time and
never vendored in, hot-reload watches both trees, and studio surfaces write
project files only through `POST /__project_write`.
_Avoid_: sync, import, vendoring
_Layer_: Pipeline

---

## Kit

Terms for the vendored UI code every scaffolded app is built from.

**Kit**:
One box of ready-made app machinery — auth, data, UI widgets — that a
generated app carries with it.
A single vendored package of the stacked_kit: one directory, one Dart
package, a declared capability list, a stability phase, and a playbook. Never
use "kit" for a design system's widget set.
_Avoid_: library (bare), package (bare), UI kit
_Layer_: Kit

**Capability**:
One named thing a kit can do, used to decide which kits a project actually
needs.
A capability string on a kit's registry entry; targets plus selected
capabilities determine the scoped vendoring set for a scaffolded app.
_Avoid_: feature, module
_Layer_: Kit

**dependencyMode**:
How a generated app carries its kits: copied in (vendored) or pulled from a
registry (hosted) — vendored first, hosted is a config flip away.
The `vendored | hosted` config value present from day one; vendored → hosted
is non-breaking, vendoring survives publication as an explicit mode.
_Avoid_: vendoring strategy, package mode
_Layer_: Kit

**Lucide**:
The icon set — the only icons arxa ships, written as a name, never drawn
by hand.
The icon vocabulary: `icon('name')` inlines a vendored Lucide glyph at design
time; `ArxaKitGlyphs.lucide('name')` resolves the same name in Flutter.
_Avoid_: emoji, custom icons, icon font, sprite
_Layer_: Kit

**ArxaKitGlyphs**:
How Flutter code asks for an icon by name.
The kit's glyph accessor; `ArxaKitGlyphs.lucide('name')` is the Flutter-side
spelling of the design-time `icon('name')`.
_Avoid_: IconData (bare), icon lookup
_Layer_: Kit

**Primitives**:
The small set of adaptive building blocks every Flutter view is composed
from — the per-platform look lives inside them, not in the views.
The adaptive primitive layer views compose exactly once; the native family
selection (glass / expressive / shadcn per platform) is encapsulated there.
_Avoid_: widgets (bare), components (in Flutter code)
_Layer_: Kit

**Stub**:
A capability that isn't really wired yet — always labelled as such before you
build against it.
An unimplemented provider that throws by design; kit availability is stated
honestly (wired vs. throws) because a silently-green stub is the failure the
research keeps finding.
_Avoid_: mock, placeholder, fake (as shipped behaviour)
_Layer_: Kit

**Liquid-glass law**:
The rulebook for using Apple's see-through "liquid glass" look without
visual glitches when things scroll.
The ratified ruleset for native Liquid Glass on iOS/macOS 26+ — control
allowlist, composition rules (no saveLayer over platform views, chrome-gate
every glass widget, no glass-on-glass overhang, materialization headroom,
slide-never-fade), and the deselect ladder. SSOT:
`docs/liquid-glass-allowlist.md`; enforced by kit gate tests + arxa-lint
rules, not by prose. Sibling: the M3E law (`docs/m3e-law.md`) for Android.
_Avoid_: glass rules, glass allowlist (bare), glass guidelines
_Layer_: Kit

**Chrome scaffold**:
The one widget a screen uses when its design declares a top bar — it gets
the bar and layout right on every kind of device; a screen designed without
top chrome simply doesn't use it.
`ArxaKitChromeScaffold` — the liquid-glass law's reuse unit: Scaffold-level
widget carrying the runtime tier branch (Liquid Glass → floating chrome over
a full-bleed body; Android → boxed bar rendering M3 Expressive; else boxed
fallback). Hosts never hand-assemble top chrome.
_Avoid_: app scaffold, adaptive scaffold, hand-assembled Scaffold.appBar
_Layer_: Kit

**Floating chrome**:
The glass tier's top bar: a title pill and buttons floating over content
that scrolls underneath, tucking away as you scroll.
`ArxaKitFloatingChrome` / `ArxaKitNativeFloatingBar` — full-bleed body,
native action controls, Flutter frosted title pill (glass-on-glass ban),
scroll behaviors pinned/minimize/minimizeTrailing/minimizeLeading/hide with
24px travel hysteresis; minimize (both ends tuck) is the ratified default.
_Avoid_: floating app bar, glass bar, overlay bar, floating bar (bare)
_Layer_: Kit

**Materialization headroom**:
Extra invisible space above the screen so glass buttons finish their
"appear" animation before you can see them.
The viewport overdraw (`extendBehindTopBar`) that moves the sliver
cull/re-add boundary above the physical screen top; iOS 26 glass re-runs its
materialize animation on re-attach, so the boundary must sit off-screen.
Only under native or no top chrome (law rule 4).
_Avoid_: cull margin, cache extent (it is paint, not layout)
_Layer_: Kit

**Glass tier / Native tier**:
Which look a screen is actually rendering: the real Apple see-through
material drawn by iOS itself, or a Flutter-painted imitation used everywhere
else.
The runtime branch every law rule is scoped against — glass tier (native
Liquid Glass platform views on iOS/macOS 26+), M3E tier (Compose Material 3
Expressive on Android), frosted/fallback tier (Flutter-drawn). "Native tier"
names the platform-view branch of a two-tier widget; the tier gate is always
a structural `wantNative && platform-supports` check, never a bare
`Platform.isX` test.
_Avoid_: platform check, `Platform.isIOS` / `Platform.isAndroid` branching,
fallback (bare, when the tier is meant)
_Layer_: Kit

**Chrome gate**:
The one switch that takes native glass off the screen while a screen slides
away, so it doesn't flicker back into view.
`ArxaKitNativeChromeGate` — the SOLE hide authority for native glass, with
exactly one hide reason: an opaque route transition above a gate that is not
travelling with it. Modal coverage is NOT a hide reason — a sheet or dialog
never blanks the chrome behind it; the barrier scrim dims still-painted
glass instead (rule 11 step 2, tombstoned against reintroduction). Reads
navigator gesture state, not animation state, so an interactive back-swipe
reads as the pop it is. The tab bar's **destroy-hide exception** is the one
ratified deviation: on modal, the native tab bar must be *destroyed*, not
merely unpainted — the `UITabBar` layer keeps rendering above Flutter-drawn
modal content otherwise, and the gate's `keepAlive` mode leaves it
mounted-but-unpainted, which is precisely not destroying it. Pinned by
`ui_library/test/kit/widgets/arxa_kit_tab_bar_single_hide_authority_test.dart`.
Anything else toggling chrome visibility is a violation, not a
second mechanism.
_Avoid_: chrome hider, visibility manager, hide flag (ad hoc), gate (bare —
also names the Pipeline assertion unit and "gate test"), Issue 31 exception
(upstream issue number as a name dates poorly — cite the number, don't name
after it)
_Layer_: Kit

**View slicer**:
The iOS engine step that cuts Flutter drawing into layers around native
views — the reason hidden native things must move off-screen, not just
"be invisible".
The engine's `flow/view_slicer.cc` compositing pass; it slices around
platform-view rects wherever they are, so hidden tabs are translated
off-screen (law rule 8) and overlays sit on plain anchors (law rule 7).
_Avoid_: compositor (bare), clipping bug, iOS quirk
_Layer_: Kit

**Glass warm-up**:
A boot-time trick that plays each kind of glass once before the user sees
it, so the first real screen doesn't stutter.
`ArxaKitGlassWarmup` — off-screen materialization of each glass kind at
startup (law rule 9), erasing first-push jank that per-route fixes could
not.
_Avoid_: preload, shader warm-up (it is view materialization, not shaders)
_Layer_: Kit

**Edge scrim**:
The soft fade at the top and bottom of the screen that lets content
dissolve under the status bar and tab bar instead of hard-clipping.
`ArxaKitTopEdgeScrim` / `ArxaKitBottomEdgeScrim` — Flutter-drawn
vertical gradient fills (no saveLayer, `IgnorePointer`), hosted by
`ArxaKitBottomEdgeScrimHost` (scaffold `bottomEdgeScrim` flag, default
on); the only dissolve that works on every tier; a fade, never a dimming
barrier. Rule 15: two independent toggles, do not confuse — the scaffold's
`bottomEdgeScrim` governs the scrim host; `ArxaKitScrollEdges` governs
the per-child scroll edge effect (tier-inert on glass). The top scrim is
skipped automatically under `extendBehindTopBar`; the bottom scrim reads the
RAW device inset (`MediaQuery.viewPaddingOf(context).bottom`) and must mount
outside any wrapper that mirrors bar clearance into `viewPadding`, or it
double-counts the bar block.
_Avoid_: overlay (bare), dim, barrier, shadow, scrim (bare — also names the
modal dim barrier and the snackbar blur, which are different things)
_Layer_: Kit

**Scroll edge effect**:
The progressive blur of content under a pinned bar — switched off on the
glass tier, where the edge scrim does the job instead.
`ArxaKitScrollEdgeEffect` — progressive blur applied to content pixels
beneath pinned chrome; toggled per-child by `ArxaKitScrollEdges`
(none/top/bottom/both, default both); deliberately inert on the Liquid
Glass tier because its partial-alpha fade over children washed glyphs on
native controls — the edge scrim supplies the dissolve there (rule 15, ADR
0010). Two entries, one semantic: cross-reference, never conflate.
_Avoid_: edge blur, scroll fade (bare), treating it as the glass-tier
dissolve
_Layer_: Kit

**Opaque-by-default**:
Pop-up surfaces start fully solid — see-through backing is the exception,
not the default.
Every Flutter-drawn modal/backing surface (sheet, native dialog, input bar,
the glass card's Flutter tier) takes a fully opaque base; blur is dropped
rather than paid for over platform views. The glass card's native tier is
excluded — it densifies through native tint instead.
_Avoid_: translucent default, frosted default, blur backing (Flutter tier)
_Layer_: Kit

**Transient overlay**:
Short-lived pop-ups — toasts, snackbars, the center pill — that always sit
above everything, app-wide.
The app's highest surface tier: resolves the ROOT overlay, never the
nearest one, and each tier sits on a plain anchor so nested navigators and
scrolling native glass cannot cover or slice it.
_Avoid_: toast layer (bare), notification (for toasts), nearest-overlay
show
_Layer_: Kit

**Plain anchor**:
Putting floating things (the floating bar's title pill, toast tiers) on an
ordinary non-glass native container so the engine keeps them on top instead
of erasing them.
A stationary plain-effect container (`plain` draws no glass material, so
rule 5's glass-on-glass ban stays closed — but it is NOT invisible: an
unoccluded anchor forces a view-slicer seam at its unclipped rect, seen as
a faint hard-edged rectangle on the glass tier, 2026-08-14 `e75839df`, so
the anchor must be fully occluded by its opaque surface — nothing
interposed inside it) beneath a Flutter-drawn surface. It
does not escape the view slicer — it exploits it: the anchor exists so the
surface's ops DO intersect a platform-view rect every frame, hoisting them
into the topmost overlay layer. Size the anchor to the SURFACE, never
full-screen — a full-bleed anchor swallows touches meant for content
beneath. Transient tiers additionally mount in the root overlay, but that
is rule 14, not the anchor.
_Avoid_: glass anchor, overlay hack, wrapper view, escapes the slicer (it
exploits it)
_Layer_: Kit

**Sheet**:
The slide-up panel — every sheet is the same body-sized kind with a close
button; there is no second sheet look in the app.
The body-sized Cupertino path (`arxaKitShowSheet()` →
`CNBottomSheet.showCupertino`, Flutter's `showCupertinoSheet`); unsized
callers ride a fixed medium height; native close icon top-right
(`showCloseButton`, default true); dim is a STATIC Cupertino barrier under
`showOverlay` (default true), never tracked; the body owns its own edge
(r=12 top corners + 36×5 grabber) and the route's grabber is off so there
is exactly one. The CN detent route (`showCNDetentSheet`, detent-tracked
dim, route-drawn grabber) is retired — it put two visually different sheet
chromes in the same app.
_Avoid_: detent route (retired), native sheet (neither sheet tier is
native — `…ShowNativeSheet` is retired), bottom sheet (bare), modal (bare),
half sheet
_Layer_: Kit

**Deselect ladder**:
The agreed order for switching controls back off native glass, one at a
time, if the artifacts ever return.
The rollback protocol for ruling 4's native-everywhere stance: re-demote ONE
widget type per device run, widest glass first — glass card, toolbar, search
bar / text field, sliders / switch, segmented, popup menu, split button,
button last. Never blanket-demote; attribution comes first. Reads tier, not
opacity, so a densified card is still the first re-demote.
_Avoid_: blanket demotion, ladder (bare — that is the viewport ladder),
fallback order, deselect protocol (superseded name)
_Layer_: Kit

**App fidelity mode**:
The scaffold-time, per-platform choice of design tier — the one sanctioned
global demotion.
A per-platform map in the app's scaffold config ({ios, android, web,
desktop} → `flutter | mix | native`): `mix` (default) is the kit's tier
gate as-is; `flutter` ships the Flutter tier wholesale, native wiring
tree-shaken at scaffold; `native` is strict — an unsupported tier is a
build/assert error, never a silent fallback. `flutter` is the only legal
value where no native tier exists (web, desktop today). Sanctioned
exception to the deselect ladder's blanket-demote ban; inside a running
mix/native app, demotion still follows the ladder. Rulings QF-1…QF-4 in
docs/plans/designer-scaffolder-grill-decisions.md.
_Avoid_: fidelity switch, tier mode (bare), pure-Flutter mode (use
`flutter` mode), full native (use `native` mode / strict), global demotion
_Layer_: Pipeline / Kit

**Double-bar ban**:
No screen may wrap a nested set of screens in its own top bar, or pushed
screens end up wearing two.
A structural rule of both platform laws: a surface must never wrap a nested
ROUTER in floating chrome, because shell-level chrome stacks above every
route pushed inside it. A pushed route never inherits an ancestor surface's
floating chrome — each surface owns its chrome or has none. Flagged by the
lint law pass.
_Avoid_: nested chrome, shell-level app bar, inherited chrome
_Layer_: Kit

**Chrome existence**:
Whether a screen has a top bar at all is a design decision, not something
the glass rules impose.
The laws govern COMPOSITION, never inventory: arxa-designer's frozen
anatomy decides whether a surface has top chrome; the law decides how chrome
is assembled where it exists. "Native glass always" scopes to MATERIAL, not
to presence — a bar-less surface is fully lawful and is not a lint finding.
_Avoid_: every screen needs a bar, chrome requirement, mandatory app bar
_Layer_: Kit

---

## Design medium

Terms for the server-rendered hypermedia medium (htmx + CSS, zero custom
client-side JavaScript) in which design artifacts are built. The designer
skill's own context doc remains the detailed authority; these entries are the
canonical short forms.

**Artifact**:
A generated design deliverable you can click through — the prototype itself.
A self-contained server-rendered hypermedia app (templates + viewmodels +
fixtures + assets) run by the shared Runtime.
_Avoid_: project, website, page
_Layer_: Design medium

**Runtime**:
The one shared engine that boots and serves every artifact.
The skill-vendored mini-framework (routing, named-fragment templates,
sessions, static) — one implementation, shared by all artifacts.
_Avoid_: server, backend
_Layer_: Design medium

**Surface**:
One screen of the app being designed — the unit everything is counted,
frozen, and scaffolded in.
A view template plus its co-located ViewModel; one registry entry, designed
at every active rung, frozen against goldens, scaffolded per targets.
_Avoid_: page, route, screen (except in URL/registry contexts)
_Layer_: Design medium

**Shell**:
The grouping and navigation unit of an app: the set of surfaces that share
one section's chrome and one nav destination. THE canonical grouping word —
"tab" is retired from the vocabulary (the code rename is landing with it).
The layout tier between the base page template and surfaces: section chrome
(nav, device frame) shared by a group of surfaces, and the unit the app's
navigation and the pipeline's stage grouping speak in.
The app-level shell — surfaces with ids `app.*` — carries a mandated roster
every frozen design declares: `app.splash`, `app.startup`, `app.unknown`,
plus `app.access` iff any surface requires auth; the freeze refuses a design
that omits one.
_Avoid_: tab (legacy — retired), tab-group (legacy), layout (reserved for the
base template)
_Layer_: Design medium

**ViewModel**:
The brain of one surface: prepares everything the template shows and answers
every request for it.
The per-surface server module of pure context builders plus handlers,
stateless by construction — rebuilt per request; re-render-and-swap replaces
client-side binding.
_Avoid_: controller, presenter, handler (the file holds handlers; the concept
is ViewModel)
_Layer_: Design medium

**Repository**:
The only door to stored data; nothing else may read it.
The single-source gateway over one fixture; the only data access ViewModels
may touch (indirectly) and the documented swap seam when productionizing.
_Avoid_: DAO, store
_Layer_: Design medium

**Facade Service**:
Composes stored data into exactly the shape a surface needs.
The service layer ViewModels depend on exclusively — never repositories
directly; facades compose repositories and apply request-scoped logic.
_Avoid_: service (bare)
_Layer_: Design medium

**Named Fragment**:
The part of a screen that can change on its own without reloading the rest.
A named block inside a surface's own template that the Runtime can render
alone for partial swaps — surface-private swap targets live here, not in
files.
_Avoid_: partial (that word means the shared kind)
_Layer_: Design medium

**Partial**:
A shared snippet of markup used by many surfaces.
A shared fragment file in the artifact's shared UI folders, included across
surfaces — distinct from a Named Fragment, which is private to one surface.
_Avoid_: component (retired — see Widget)
_Layer_: Design medium

**Widget Library**:
The artifact's own kit of reusable building blocks, built before any screen
is composed — widgets first, always.
The artifact-local set of parameterized macros/partials authored in the
widget-library pass *before* surfaces compose; surfaces compose only from
it, and a pattern appearing twice is extracted, never copied. Placed per the
Placement Law: narrowest scope that covers all its consumers.
_Avoid_: component library (retired — see Widget), UI kit (a kit is a
vendored package — see Kit)
_Layer_: Design medium

**Boosted MPA**:
Every screen is a real URL; navigation swaps the page body so it feels like
an app without a line of client JavaScript.
The navigation architecture: real URLs serving full pages, boosted body
swaps, and a server-side full-page-vs-fragment branch on the request header.
_Avoid_: SPA, hybrid
_Layer_: Design medium

**Client-JS-Free**:
The hard rule of the medium: no hand-written JavaScript in an artifact, ever.
Zero custom client-side JS — no script blocks, no inline event handlers, no
expression triggers; htmx plus allowlisted extensions are the only exempt
libraries, enforced by lint and a no-eval runtime flag.
_Avoid_: vanilla JS, progressive enhancement (as a licence to write JS)
_Layer_: Design medium

**Read States**:
The five ways a screen can look: idle, loading, error, empty, or showing
data — all rendered server-side.
The closed state set (idle / loading / error / empty / data) as server-side
template branches; "loading" exists client-side only as indicator CSS during
a request.
_Avoid_: UI states (bare), loading states
_Layer_: Design medium

**Data Spine**:
The single path every piece of data travels, in order: authored seed →
generated fixture → model → services → surface.
The artifact's five-stage state flow where each stage talks only to its
neighbours: seed is hand-authored truth, fixtures are generated (never
hand-edited), views never reach past their ViewModel, ViewModels never reach
past a facade. "Spine" alone is ambiguous — the architecture docs also use it
for the overall system shape — so always say *data* spine for this one.
_Avoid_: data flow (bare), spine (bare)
_Layer_: Design medium

**Viewport Ladder**:
The rule that every screen is designed at several real device widths, so
nobody downstream has to invent the tablet or desktop layout.
The three freeze widths (390 / 744 / 1280), each sitting inside a Material 3
window size class, never on a boundary; the active set is *derived from
targets*, never chosen or hardcoded.
_Avoid_: breakpoints, responsive sizes
_Layer_: Design medium

**Rung**:
One of those device widths, by name: compact, medium, or expanded.
One named step of the viewport ladder (compact 390, medium 744, expanded
1280); code refers to rung names, never pixel values.
_Avoid_: breakpoint, size, width (as a design target)
_Layer_: Design medium

**Archetype**:
The recognized layout pattern a surface follows at each rung — wide screens
re-arrange, they don't stretch.
The closed catalog of composition patterns (tab-shell, dashboard-stack,
master–detail lists, form-flow, etc.) mapping content arrangement per rung; a
surface fitting no archetype is a signal it does two jobs.
_Avoid_: template, layout pattern (bare)
_Layer_: Design medium

**Named Container**:
One labeled box in a layout template — "hero", "feed", "detail" — that the
designer later fills with real design.
The closed container vocabulary layout templates are built from (~15:
app-bar, nav, nav-rail, drawer, fab, sheet, tab-bar, hero, toolbar,
filter-bar, list, card-grid, feed, detail, supporting-pane, sidebar, footer);
rendered as plain colored boxes at intake, never styled, so feedback stays on
structure.
_Avoid_: slot, region (bare), placeholder
_Layer_: Design medium

**Auto Layout**:
Widgets keep themselves tidy: a button grows with its label, a card
stretches to fill its row — unless the designer turns it off for that piece.
The designer's default-on layout mode for widget-library widgets
(buttons, cards, inputs, list rows, navs, modals, forms, toolbars): the
Figma-equivalent property set (flow, gap, padding, alignment; child
hug/fill/fixed) emitted as flexbox data-attributes, zero client JS. Off by
default at screen/artboard level and for art-directed frames, with a
per-child escape hatch; the designer or the user may disable it per frame.
_Avoid_: constraints (as the default), absolute positioning (as the default)
_Layer_: Design medium

**Motion Vocabulary**:
The seven named ways things may move — and no eighth without retiring one.
The closed set of CSS-only motion names (swap, traverse, spotlight, reveal,
disclose, notify, pending) driven by htmx swap-lifecycle classes and native
browser primitives, all gated on no-preference for reduced motion; the one
channel that survives the freeze untouched.
_Avoid_: animation, transition (as new vocabulary names)
_Layer_: Design medium

**Lens**:
One way of looking at the same screens — as a flat grid, as journey rows, or
as one live screen inside a device frame.
A design-viewer mode over the current project's screens: `views` (a flat
grid in registry order), `flows` (one row per flow, tiles in edge-chain order
with trigger-labelled connectors), `proto` (one live screen at a real rung
inside device chrome). Same word, different thing from the **arxa lens**
(the capture/compare tool).
_Avoid_: viewer mode (bare), preview (bare)
_Layer_: Design medium

**Live tile**:
The one screen on the canvas you can actually touch and click through; every
other tile is a still picture.
The single interactive tile in the design viewer: `live=<screenId>` drops
`still=1` so the tile renders live; one live tile at a time by construction
(a single viewer key).
_Avoid_: preview tile, active screen
_Layer_: Design medium

**Widget**:
A reusable piece of UI — a button, a card, a panel — built once and used
wherever it's needed, instead of redrawn from scratch each time.
One concept, two mediums: an HTML macro/partial in the design medium, a Dart
class in the build medium. Placed per the Placement Law. THE canonical term
for a reusable UI piece — "component" is retired, in every doc and every
path, on both sides of the pipeline.
_Avoid_: component, component library (see Widget Library)
_Layer_: Design medium

**Panel**:
One of the five fixed roles of app chrome — header, main, activity,
composer, footer — that every shell mounts from.
The five role panels are thin instantiations of one base widget
(`_panel.html`), never re-implemented per shell. A panel owns its own
internal UI state; the shell owns its own state plus which panels it mounts
and their sizes — all server-side per ADR-0004.
_Avoid_: re-implementing panel chrome per shell
_Layer_: Design medium

**Placement Law**:
Where a reusable piece of UI lives: as close to the screens that use it as
possible, and no closer.
A widget lives at the narrowest scope that covers all its consumers; the
include/import graph is the only authority, checked in both directions
(generalizes gate S10's sole-consumer overlay rule). Three tiers, identical
shape on both mediums:

| scope | design medium | build medium |
|---|---|---|
| cross-shell (2+ shells) | `ui/common/widgets/` | `lib/ui/widgets/` |
| intra-shell (2+ surfaces) | `ui/views/<shell>/shared/widgets/` | `<shell>/shared/widgets/` |
| per-surface (1 surface) | `<surface>/widgets/` | `<view>/widgets/` |

Bare `<shell>/widgets/` is illegal on both sides. Empty tiers are never
created speculatively.
_Avoid_: downward-only placement (rejected — leaves placement co-managed by
graph + discretion)
_Layer_: Design medium

**Design Dial**:
The floating control baked into every design artifact, so the author can adjust the design live and clients can leave feedback on it — one control, two modes.
The always-present first-party island generated on every artifact: a radial dock with expanding panels, default on, toggleable by the operator only, never hideable by clients (watermark role). Its two modes are Design Mode and Feedback Mode.
_Avoid_: feedback dial (superseded — it was the Feedback-Mode-only ancestor), FAB, widget (reserved)
_Layer_: Design medium

**Design Mode**:
The author-only side of the Design Dial: select a piece of the design, adjust its look or wording, and see the change live.
The Design Dial mode available to the Author only, offering selection plus curated per-widget-kind facet editors (with a raw-CSS escape hatch) across three edit tiers — tokens, element style, text. Edits auto-save into the Draft Overlay; structure (add/move/reorder widgets) is never editable here.
_Layer_: Design medium

**Feedback Mode**:
The client side of the Design Dial: look at the shared design, drop Pins on it, draw over it, and track what happened to each comment.
The Design Dial mode available over a Share Link: Pins with threaded replies and a kanban lifecycle (Open / Triaged / In progress / Resolved / Won't do), freehand draw-over whose strokes persist by attaching to a Pin (never standalone; stored as a `design_dial_drawings` row, 1:1 with its Pin), per-layer toggles (comments / pins / drawings) and the Review Shade. Clients never edit the design.
_Layer_: Design medium

**Draft Overlay**:
The author's unsent adjustments, saved automatically as they work — visible on their screen, invisible to clients until Publish.
The auto-saved patch set layered over an artifact: token, element-style, and text patches recorded while designing, persisted server-side per artifact (one JSON file under `~/.arxa/drafts/`, keyed by the artifact's path — never in Supabase, never in the watched artifact tree), applied to served pages for the Author only, and never written into artifact source until committed. Clients always see the last published state, never the Draft Overlay. Patch keys ride machine identity (`data-arxa-id`) by default; when one machine id fans out to instances with DIFFERENT authored meanings (heterogeneous `data-el`), the patch binds to the authored identity instead — the key is `el:<data-el>` (amended 2026-08-24: authored identity wins on divergence; homogeneous loops keep every-row-at-once). Every open Author document applies draft changes live (same amendment: the ladder's rungs stay in sync); only guests wait for Publish.
_Avoid_: autosave (the mechanism, not the thing), unpublished changes
_Layer_: Design medium

**Publish**:
The author's manual button that makes the current design — with all committed adjustments — live at the one stable client link.
The operator-triggered deploy of committed artifact source to the artifact's single stable share URL; never automatic, always from the Design Dial. Draft Overlay content reaches clients only through a commit followed by a Publish.
_Avoid_: deploy (the pipeline verb this rides), save, push (git)
_Layer_: Design medium

**Pin**:
A comment stuck onto an exact spot of the design — it stays attached to that piece even when the design changes, and remembers where it was if that piece is removed.
A Feedback Mode comment anchored to element identity (route + viewport recorded), with a rect snapshot fallback: if the anchor element disappears, the Pin survives as an Orphaned Pin at its last known position rather than vanishing.
_Avoid_: annotation (the draw-over marks), marker, note
_Layer_: Design medium

**Orphaned Pin**:
A Pin whose piece of the design was removed — shown at its last known spot so the client's words are never silently lost.
A Pin whose element-identity anchor no longer resolves; rendered at its stored rect snapshot, flagged orphaned, still fully replyable and resolvable.
_Layer_: Design medium

**Review Shade**:
The dimmer over the design during review: slide it up to make Pins and drawings stand out, slide it down to see the design clearly.
The opacity-adjustable overlay layer between the design and the annotation layers in Feedback Mode; independent of the per-layer toggles (comments / pins / drawings), which switch content on and off while the shade only dims.
_Avoid_: overlay (bare — every artifact layer is an overlay), dimmer (the mechanism)
_Layer_: Design medium

**Share Link**:
The one link the author sends a client: opens the live design, asks for a name, and lets them comment — no account, no password.
The scoped, expiring access token (per artifact, view/comment permission) that identifies a named guest; it is the client-side counterpart of the operator's sign-in and the only access path to Feedback Mode on a published design.
_Avoid_: magic link (the mechanism), public link (it is scoped, not public)
_Layer_: Design medium

**Author**:
The person whose design it is — the only one who can change it. Clients comment; the Author edits and publishes.
The single editing identity on an artifact's Design Dial: holds Design Mode, resolves Pins, commits the Draft Overlay, and publishes. An artifact has exactly one Author.
_Avoid_: owner (billing/tenancy), operator (the arxa persona running the pipeline), designer (a role, not the identity)
_Layer_: Design medium

---

## Brand Glossary

Presentation-layer aliases only. Product copy may draw display names from
this table; nothing mechanical — code, file names, gates, docs — ever reads
it. No box-themed aliases anywhere else in the codebase.

| term | display name |
|---|---|
| _(none yet)_ | |

---

## Legacy / retired terms

Dead words and what replaced them. Never reintroduce the left column.

| retired | canonical | why |
|---|---|---|
| component / component library | **Widget** / **Widget Library** | one term everywhere, in every doc and path — D1 of the widget/panel vocabulary reconciliation |
| tab | **Shell** | Shell is THE grouping/navigation unit; the code rename is landing alongside this entry |
| tab-group / tab-group shell | **Shell** | same retirement; older flow docs still say it |
| top stage strip | **Footer Panel** | the read-only stage timeline moved to the bottom strip, which is now the footer panel; the top strip is removed |
| companion (app) | **arxa app** | consolidation (2026-07-28): one app + daemon, no separate companion |
| Totem Cloud | **tailnet** | self-hosted remote only; no third-party relay, no Totem-run cloud |
| spine (bare) | **Data Spine** | "the spine" meant both the system shape and the artifact's data flow; the artifact one is always *data* spine |
| bottom bar | **Footer Panel** | panel consolidation (2026-07-30): all chrome is named panels; dead in code (`{% block footer %}`, `#panel-footer`) |
| left rail | **Activity Panel** | same consolidation; dead in code |
| right rail | **Composer Panel** | same consolidation; the composer panel is permanent and single-state; dead in code |
| mainboard | **Main Panel** | proposed during the panel consolidation, renamed before it ever landed |
| detent route / detent-tracked dim | **`arxaKitShowSheet`** (the one body-sized Cupertino sheet) | retired 2026-08-14: it took only the unsized case and put two sheet chromes in one app; the tracked dim is now a static barrier under `showOverlay`, and the body owns its own grabber |
| Issue 31 exception | **destroy-hide exception** (Chrome gate) | retired 2026-08-14: named after an upstream issue number, which dates poorly; the number stays as a citation, the mechanism is named for what it does |
