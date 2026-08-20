# appbox / arxa

The pipeline that turns client intake into designed, verified, deployed
Flutter apps — one Dart binary (`appbox`), skills as stage fronts, gates as
the only enforcer. **arxa** is the product identity; **appbox** is the
engine underneath.

## Language

### Product

**Arxa**:
The product and brand: the harness, the compiled engine, and the paid
editions together. The engine keeps the appbox name until the gated full
rename.
_Avoid_: using arxa and appbox interchangeably

**Arxa harness**:
The dedicated agent harness forked from DeepSeek Harness (dsh), rebranded,
grown by plugins. Ships in three flavors: Studio (locked, buyers),
BYO-harness edition (their CLI, our binary + stub skills), operator build
(open).
_Avoid_: the dsh fork, the app

**Engine**:
The compiled pipeline binary and its verbs — the layer that owns gates,
entitlement, memory, and artifacts. Harnesses invoke it; it outlives any
harness.
_Avoid_: CLI (ambiguous), backend

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
material into appbox output.

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
A session applying appbox to a client project. It may never modify appbox
itself; its escape hatch for unseen questions is the lens eval verb.
_Avoid_: project session

**Appbox-dev session**:
A session working ON appbox — the only place verbs get added, dictionaries
grow, and promotions from eval scripts happen.

### Client review

**Appbox dial**:
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
