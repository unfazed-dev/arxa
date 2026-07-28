# app_box — Persona & UX Design Brief

**Audience:** the designer responsible for app_box's user experience.
**Status:** proto-personas (see `personas.md`) · living document · owner: product.
**Purpose:** one handoff artifact that tells you who app_box is for, what each
of them is trying to do, and what is pinned vs. open for you. It carries the
persona *framing* and cites [`architecture.md`](../plans/architecture.md) for
everything else — it never duplicates its tables.
**Companions:** [`personas.md`](personas.md) (full persona depth),
[`journeys/`](journeys/) (one journey map per persona).

---

## 1. The product in one paragraph

app_box is a desktop application that takes a client conversation to a shipped,
bespoke Flutter app in opinionated Stacked MVVM — designed, gated, scaffolded
and deployed, with the human holding the irreversible decisions. It runs a
pipeline (intake → prototype → freeze → scaffold → review → bundle → deploy)
with **three human gates** that an agent can reach but never mint. The desktop
UI is a viewer and controller over pipeline state, never a source of truth; the
iOS companion drives the pipeline remotely and serves prototypes at true device
width. One `stage_shell` with six tab-groups serves both personas — what you see
depends on whether you are operating the pipeline (Evan) or evaluating it
(Michelle). See `architecture.md` §1, §8.

## 2. How to read this document (rules that protect you)

- **These are proto-personas.** Grounded in the product spec (`architecture.md`
  §1) and measured research (`docs/research/`), not in user interviews. Industry
  guidance (NN/g): proto-personas are alignment hypotheses — useful now, **to be
  validated against real users later** (§8). Do not treat any behavioural claim
  as observed fact.
- **Persona content follows the actionable-over-theater rule** (NN/g, IxDF):
  every detail is included because it can change a design decision. Demographics
  are absent — they segment for marketing, not for design. Names exist as memory
  hooks only.
- **Canonical language is binding.** Use app_box, stage_shell, gate (Gate 1 /
  Gate 2 / Gate 3), registry, surface, freeze, scaffold, finding, ledger — never
  informal synonyms. "Approval" is always a human gate, never an agent action.
  "Red" always means broken, never payment. Copy that says "automatically
  approved" or "payment gate failed" is a defect.
- **Citations over copies.** Pipeline mechanics, gate definitions, kit
  inventories, and the surface contract live in the cited docs. If this brief
  and `architecture.md` disagree, `architecture.md` wins — file it as a bug
  against this brief.
- **Brand is a frozen input.** Improve ≠ rebrand. Brand tokens live in the
  loaded design system; the viewport ladder lives in the project config.

## 3. The persona/mode model at a glance

Full definitions: [`personas.md`](personas.md). Summary for standalone reading:

| Mode / persona | What it is | Seeded persona |
|---|---|---|
| **P1 — Intake** | Evan eliciting what the client wants | Evan |
| **P2 — Autonomous build** | Evan letting the pipeline run unattended | Evan |
| **P3 — Red-gate recovery** | Evan diagnosing and fixing a failure | Evan |
| **P4 — Ship** | Evan confirming release | Evan |
| **P5 — The buyer** | A different person: evaluating app_box against FlutterFlow | Michelle |

Structural fact that shapes every screen: four of the five are the same human
in different modes. Designing for "the solo developer" as one persona is what
produces a tool that only its author can run — the modes must feel different.
Evan needs depth (gates, ledgers, SARIF); Michelle needs honesty and a fast
first win. Where they conflict, **Michelle wins the first ten minutes, Evan
wins everything after**.

**Primary persona per shell:** every shell is optimized for **Evan** (he is the
operator). Michelle's flows are the evaluation subset — she traverses the same
pipeline but reads it through a legibility filter, not a machinery filter.

## 4. Personas

Full treatment in [`personas.md`](personas.md). Each persona carries: snapshot →
context of use → jobs-to-be-done → frustrations → flows that must work → design
must get right. The four modes and the buyer each have their own section there;
this brief carries the framing and the constraints, not the depth.

## 5. Cross-cutting design constraints

### 5.1 One shell, tab-composed surfaces

One `stage_shell` hosts six tab-groups — the surfaces you see depend on which
tab is active. The stage surface itself carries the nav rail, tab bar, and the
gate badge (showing the pipeline phase and gate state at a glance).

| Tab-group | Surfaces |
|---|---|
| **projects** | home (empty · list · loading), new (form · validating · error), splash, showcase |
| **design** | directions (3-up · one approved), surface (live preview · stale), approve (Gate 1: pending · approved) |
| **build** | run (idle · running · green · red), finding (file · line · rule · fix), approve (Gate 2), recovery |
| **ship** | targets (fastlane · shorebird · CF Pages), confirm (Gate 3: the triple), released |
| **chat** | home (idle · streaming · tool-call) |
| **settings** | credentials (vault tier stated), devices (paired · revoke), kits (wired vs stubbed), pair (QR · fingerprint) |

The full 20-surface inventory with states is in §10 (the registry seed).

### 5.2 The three human gates — visually distinct, agent cannot mint

| Gate | Where | What it protects | The human action |
|---|---|---|---|
| **Gate 1 — Design approval** | `design.approve` | The frozen design is the right one | Approve one direction; bind approval to the design hash |
| **Gate 2 — Build acceptance** | `build.approve` | The scaffolded work is shippable quality | Accept the green build; reject → recovery |
| **Gate 3 — Ship confirmation** | `ship.confirm` | The right build goes to the right place | Confirm target + version + account — the exact triple |

An agent may prepare, present, and reach a gate — it **cannot mint the approval
token**. The gate writes an approval token into pipeline state; the person
confirms it (`architecture.md` §12). These three gates must look different from
anything automated: approval is the product's core claim, and it should look
like it.

Gate 3 is the strictest: it is the only gate that writes to the outside world
and cannot be undone by re-running a stage (`architecture.md` §17).

### 5.3 Credential tiers — stated on screen

Credentials fork on first run (`architecture.md` §15, research:
`remote-control-and-chat.md`):

- **BYO key** → stored in the OS vault (`flutter_secure_storage` → macOS
  Keychain). The UI states which vault is active — *"stored in the macOS
  Keychain."*
- **Harness present** → shell out to an already-authenticated CLI
  (`claude`, `kimi`). app_box never sees a token it does not have to store.

The verification standard is **write → restart → read back, in a signed and
notarised build** — because two known macOS failure modes (App Group missing
from `keychain-access-groups`, hardened runtime after notarisation) fail
*silently and green* (`architecture.md` §15).

### 5.4 Stub honesty — wired vs. stubbed, before build

`settings.kits` shows every kit's status honestly. Per
[`stub-inventory.md`](../research/stub-inventory.md): 5 of 23 kits are partial;
Stripe, PayPal, both auth providers, both map providers and Vercel all throw
`UnimplementedError`. A buyer who picks Stripe and discovers the throw at build
time has been misled — the surface must show wired-versus-stub **before** she
builds against it. Never offer a target that throws.

### 5.5 Viewport derivation — targets drive widths, not the other way

`--targets` is platform-only; viewports derive (`architecture.md` §11):

| target | viewports implied |
|---|---|
| `ios` / `android` (default) | mobile (390), tablet (744) |
| `web` | mobile, tablet, desktop (1280) |
| `macos` / `linux` / `windows` | desktop (1280) |

Mobile is always present. Freeze widths sit inside each MD3 window size class,
never on the 600/840 boundaries. `--targets ios,android` freezes **two** widths;
`--targets macos` freezes **one**. The coverage gate reads targets from state
and requires exactly the derived set — a macOS-only app emits three files per
surface (`_view.dart`, `_view.desktop.dart`, `_viewmodel.dart`), not five
(`architecture.md` §16).

### 5.6 Red means broken — licence is a precondition, not a gate

The licence check runs **before** the builder phase and fails with an
unmistakable licence message. It must never be implemented as a check inside a
correctness gate — a gate that can go red for payment reasons teaches people to
distrust red, and that is the one thing this architecture cannot afford
(`architecture.md` §17). 💳 = the licence precondition, shown in flows where it
applies.

## 6. Pinned vs. open

**Pinned (not yours to redesign):** the persona/mode model; the pipeline FSM
and its three gates; the registry → `structure.json` → scaffold contract; the
surface inventory scope; the canonical language; the credential-tier model; the
viewport derivation rule; the kit-stub-honesty requirement.

**Open (your job):** information hierarchy and visual design within the frozen
tokens; interaction patterns for the flows; how gate affordances *look and
read*; empty/error/loading state wording and rendering; how the chat surface
presents streaming and tool-call states; the showcase app's content and polish.

**Red flags the research says to avoid:** a brief that dictates solutions (this
one deliberately doesn't); personas as demographic posters (these aren't);
copying SSOT tables into new docs (cite instead — the drift it causes is worse
than the click); red-for-money; offering a stub without labelling it; inferring
state from paint (the FAB shows channel state, not "did the WebView render").

## 7. How the design gets evaluated

The pipeline is the gate (`architecture.md` §5, §9): surface work passes
`pipeline.sh gate prototype|design|scaffold|review`; the frozen `design/` SSOT +
Human Gate 1 opens the chain. Downstream proof points:

- **Render gate:** every surface resolves its assets (fonts, images) — not
  string-checks, path resolution.
- **Structure gate:** the drift check catches a hand-edit to the generated
  base, asserted with `git status --porcelain` semantics.
- **Scaffold coverage gate:** exactly the derived form-factor set per surface
  — no empty files, no orphans (`architecture.md` §16, §18).
- **The showcase app launches on install** — that launch *is* the demo for
  Michelle (`journeys/michelle-buyer-journey.md`).

## 8. Validation plan (pay down the proto-persona debt)

Hypotheses to test against real users before scaling on these personas:

1. **Michelle's showcase-first hypothesis:** does the showcase app launching on
   install actually earn the first minute, or does she dismiss it as a demo?
2. **Michelle's stub-honesty trust claim:** does seeing wired-vs-stub before
   build increase trust, or does it read as "this tool is incomplete"?
3. **Evan's legibility claim:** does the SARIF-backed findings view let him
   diagnose a red gate without a scrollback, or does he still reach for the
   terminal?
4. **The three-gate visual distinction:** do Evan and Michelle both read the
   gates as "a human decision point" vs "an automated step"?

Method: 5–8 sessions per persona. Michelle: timed 20-minute evaluation on a
fresh machine. Evan: red-gate recovery on a real client build.

## 9. Sources

**Repo (cited throughout):** [`architecture.md`](../plans/architecture.md) §1–§22
· [`feature-crud.md`](../plans/feature-crud.md) ·
[`stub-remediation.md`](../plans/stub-remediation.md) ·
[`docs/research/`](../research/README.md) (9 measured research docs).

**Research (consulted 2026-07-28):**
- Persona practice: NN/g — *Personas: Make Users Memorable*, *3 Persona Types*,
  *Personas vs. JTBD*, *Why Personas Fail*.
- Brief practice: IxDF — *Design Briefs*; NN/g — *User Need Statements*;
  Atlassian — *SSoT*.
- Domain: [`competitors-and-pricing.md`](../research/competitors-and-pricing.md)
  (FlutterFlow/Adalo/Lovable/Cursor); [`stub-inventory.md`](../research/stub-inventory.md);
  [`remote-control-and-chat.md`](../research/remote-control-and-chat.md);
  [`spine-findings.md`](../research/spine-findings.md).

---

## 10. Surface inventory — the registry seed

One `stage_shell` with tabs, matching the htmx producer's convention
(`architecture.md` §13). This seeds `registry.json` (§14).

| id | tab | surface | states to design |
|---|---|---|---|
| `stage.shell` | stage | `stage_shell_view` | nav rail · tabs · gate badge |
| `projects.home` | projects | `stage_shell_projects_home_view` | empty · list · loading |
| `projects.new` | projects | `stage_shell_projects_new_view` | form · validating · error |
| `projects.splash` | projects | _null_ | first-run · onboarding |
| `projects.showcase` | projects | _null_ | the dogfood — app_box shows itself |
| `design.directions` | design | `stage_shell_design_directions_view` | 3-up · one approved |
| `design.surface` | design | `stage_shell_design_surface_view` | live preview · stale |
| `design.approve` | design | `stage_shell_design_approve_view` | **Gate 1** — pending · approved |
| `build.run` | build | `stage_shell_build_run_view` | idle · running · green · **red** |
| `build.finding` | build | `stage_shell_build_finding_view` | file · line · rule · fix |
| `build.approve` | build | `stage_shell_build_approve_view` | **Gate 2** |
| `build.recovery` | build | _null_ | red-gate · diagnose · fix · re-run |
| `ship.targets` | ship | `stage_shell_ship_targets_view` | fastlane · shorebird · CF Pages |
| `ship.confirm` | ship | `stage_shell_ship_confirm_view` | **Gate 3** — the triple |
| `ship.released` | ship | _null_ | shipped · version · rollback |
| `chat.home` | chat | `stage_shell_chat_home_view` | idle · streaming · tool-call |
| `settings.credentials` | settings | `stage_shell_settings_credentials_view` | vault tier stated |
| `settings.devices` | settings | `stage_shell_settings_devices_view` | paired · revoke |
| `settings.kits` | settings | `stage_shell_settings_kits_view` | wired vs **stubbed** |
| `settings.pair` | settings | _null_ | QR pair · fingerprint · device name |

`settings.kits` earns its place from `stub-inventory.md`: 5 of 23 kits are
partial and several providers throw. A buyer who picks Stripe and discovers
`UnimplementedError` at build time has been misled — the surface must show
wired-versus-stub honestly.

---

*Maintenance: this brief changes when the persona model, gate semantics, or
surface inventory changes — update it in the same commit as the `architecture.md`
change it mirrors. Last verified against repo truth: 2026-07-28.*
