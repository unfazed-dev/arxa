# arxa / arxa

The pipeline that turns client intake into designed, verified, deployed
Flutter apps — one Dart binary (`arxa`), skills as stage fronts, gates as
the only enforcer. **arxa** is the product identity; **arxa** is the
engine underneath.

## Language

### Product

**Arxa**:
The product and brand: the harness, the compiled engine, and the paid
editions together. The engine keeps the arxa name until the gated full
rename.
_Avoid_: using arxa and arxa interchangeably

**Arxa harness**:
The dedicated agent harness composed from DeepSeek Harness (dsh) npm
packages — depended on exactly, never forked — rebranded by plugins and
profile patches. Ships in three flavors: Studio (locked, buyers),
BYO-harness edition (their CLI, our binary + stub skills), operator build
(open).
_Avoid_: the dsh fork (superseded 2026-08-21), the app

**Engine**:
The compiled pipeline binary and its verbs — the layer that owns gates,
entitlement, memory, and artifacts. Harnesses invoke it; it outlives any
harness. Runs on the customer's machine, never hosted (D98).
_Avoid_: CLI (ambiguous), backend

**Kit**:
The template library the engine scaffolds from (`kit/`: core, data,
ui_library, tools, showcase). Delivered separately from the engine — from
a signed static bucket, cached locally, some kits paid — never compiled
into the engine binary.
_Avoid_: assets, templates folder, bundle

**Stub skill**:
A shipped SKILL.md that is only a shell: it fetches its methodology body
from the engine (`arxa brief <stage>`) after the entitlement check. The
body never rests on a customer's disk and every delivery is watermarked.
_Avoid_: encrypted skill (encryption is Studio-only deterrence)

**Clients panel**:
The harness side panel: Clients → project → pipeline stages, rendered from
the engine's project registry and gate status. Sessions attach to a
client + stage, never float free.
_Avoid_: workspace, session list

### Shipping and updates

**Platform pin**:
The exact `@deepseek-ai/*` version set frozen inside an arxa studio
release, chosen by the arxa team — never a range, never user-visible as a
version. "Latest" describes the team's tracking discipline, not a property
of any user install.
_Avoid_: dsh version (user-facing sense), dependency range

**Credits page**:
The in-app accreditation surface listing every third-party component arxa
ships — name, version, license, upstream link — generated from a
machine-readable inventory. The only place the platform pin is
user-visible.
_Avoid_: about page, legal page

**Bridge**:
A local, temporary carry over an upstream (dsh) gap — a config patch, an
npm override, or an install-time patch — that must carry an upstream issue
link and a removal condition, and is re-reviewed at every bump. The
default answer to upstream breakage is holding the pin, not bridging.
_Avoid_: fork, fix (a bridge is not a fix; it has an expiry)

### Money and entitlement

**Merchant of record**:
The third party (Paddle) that sells to the customer in its own name —
collects payment, applies VAT/GST, issues invoices and refunds — and pays
arxa out. The only place money moves.
_Avoid_: payment gateway, Stripe (not the current provider)

**Entitlement**:
A fact in arxa.dev's ledger that an account holds a right — a kit tier, a
seat in an org — because the merchant of record reported a purchase.
Never money, never customer data.
_Avoid_: licence (that is the token), subscription (that is Paddle's word)

**Entitlement token**:
The signed, time-limited proof of an account's entitlements that the
engine verifies offline. Carries the claims; is not the source of them.
_Avoid_: licence key, API key

**Agency mode**:
The Studio with its business sections unlocked by an `agency` claim in the
entitlement token. Not a separate product, build, or install.
_Avoid_: the Agency app, Agency edition

**Org**:
A company's paid group inside arxa.dev: one owner (the buying account),
members, and a seat count. Holds membership only — the company's business
data stays on its own machines.
_Avoid_: team (used loosely in the harness), tenant, workspace

**Seat**:
One unit of an org's subscription quantity, occupied by one member.
Holding a seat is what puts `agency` into that member's token.

**Pro**:
The per-developer-seat entitlement that unlocks scaffold and every stage
after it. The free tier ends where Pro begins.
_Avoid_: premium, paid plan (Scale and Agency are also paid)

**Scale**:
The per-org entitlement priced on app-fleet volume — released apps and
OTA installs — with unlimited seats. Never priced per head.
_Avoid_: team plan, business plan

**Agency** (as a product):
The per-member-seat entitlement for Agency mode, bought by an org owner.
Sits beside Pro and Scale, not above them; either can add it.
_Avoid_: Scale (a different product), enterprise

**Viewer**:
A free, strictly read-only org member — a client or stakeholder — who can
read approvals, invoices and project status but cannot approve, comment,
upload or edit. Holds no Seat; never counted in the subscription
quantity. Client sign-off uses a per-item approval link, not this role.
_Avoid_: guest, client user, free seat (a Viewer holds no seat)

### Seeing (lens)

**Evidence bundle**:
The complete record of one capture: pixels, region tree, geometry, and
motion frames. Every medium the lens can see — live site, design artifact,
image, clip — produces the same bundle shape.
_Avoid_: screenshot set, capture dump

**Region tree**:
The hierarchy of named regions inside a surface, keyed by dictionary terms.
Derived from the DOM's inspect attributes when a DOM exists, from skeleton/
OCR analysis when it doesn't.
_Avoid_: node map, element tree (that's the DOM itself)

**Drill-down compare**:
Comparing two evidence bundles coarse-to-fine: whole surface first, then
down the region tree, from ONE capture. A verdict names the divergent
region and its property delta.
_Avoid_: pixel diff, visual diff (those are single levels of it)

**Capture manifest**:
The designer-emitted contract listing, per surface, the states × viewports
× regions the lens must capture, each state with the interaction that
reaches it. The single source of what gets seen.
_Avoid_: shot list, test plan

**Settle**:
The point at which a page is done moving and safe to capture — fonts
loaded, frames painted, animations frozen or expired.

### Making (designer / scaffolder)

**Arxa dictionary**:
The controlled vocabulary of semantic terms, all prefixed `arxa-`. Every
class, region key, and emitted widget identity is drawn from it; growth
happens only by recorded proposal.
_Avoid_: abx dictionary (superseded 2026-08-21), class list, naming
convention

**Memory store**:
The project-scoped record of durable facts — intake decisions, rulings,
verdicts, fix history, client preferences — owned by the engine and
written by stages as pipeline output. Harness plugins only inject and
capture; they never own it.
_Avoid_: harness memory, chat memory

**Provenance scan**:
The gate that rejects any semantic token copied from scanned reference
material into arxa output.

**Region identity**:
The stable identifier a region keeps across its three lives — design
artifact, capture manifest, emitted Flutter code — always a dictionary term.

**Asset ledger**:
The per-artifact record of every placed stock asset — provider, id,
photographer, source URLs — from which credits render and compliance is
audited.
_Avoid_: image list, media manifest

**Content pass**:
The one-time generation of a project's copy into a content artifact at
intake time; designs consume it deterministically. A slot filled by
fallback is written back, never regenerated.
_Avoid_: lorem ipsum, placeholder text, text library

### Sessions

**Using-session**:
A session applying arxa to a client project. It may never modify arxa
itself; its escape hatch for unseen questions is the lens eval verb.
_Avoid_: project session

**Arxa-dev session**:
A session working ON arxa — the only place verbs get added, dictionaries
grow, and promotions from eval scripts happen.

### Client review

**Arxa dial**:
The branded radial control baked into every design artifact: sign-in gate,
feedback capture (comment, change-list, draw-over), history, watermark.
Operator-toggleable; clients cannot hide it.
_Avoid_: FAB, feedback button, widget

**Design lock**:
The sign-in requirement on a shared design. Real on deployed previews
(verified where the design is served), cosmetic locally.

**A11y toolbox**:
The separate, request-built island of viewer preference controls
(contrast, text scale, motion, reading aids). A UX layer over an
accessible design — never a compliance mechanism.
_Avoid_: accessibility overlay
