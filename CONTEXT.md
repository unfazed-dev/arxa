# appbox

The pipeline that turns client intake into designed, verified, deployed
Flutter apps — one Dart binary (`appbox`), skills as stage fronts, gates as
the only enforcer.

## Language

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

**abx dictionary**:
The controlled vocabulary of appbox semantic terms. Every class, region
key, and emitted widget identity is drawn from it; growth happens only by
recorded proposal.
_Avoid_: class list, naming convention

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
