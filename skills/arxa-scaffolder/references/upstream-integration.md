# Upstream Integration

## What reaches you from composers (Q14) and what you report (Q15)

Three composers exist upstream — intake interview, design-update, and the feature-add
entry point in studio UI. **None of them ever writes a file, a delta, or a line of your
output.** They emit **registry patches**, validated strictly against the registry schema
(retry on validation failure); deterministic code applies valid patches. What reaches
you is therefore always the same thing: a new registry version and its frozen run
artifact. There is no separate sync path and none is needed — a design-composer creating
a screen emits an intake-level registry patch, and the derived pipeline (diff → run
artifact → designer → your delta run) flows from there.

Consequences for you:

- **Never accept LLM-authored files.** If something proposes emitted content directly,
  that is a bug upstream, not an input.
- For cross-boundary changes the LLM may *propose* a 3-way merge, but a deterministic
  validator applies it (Q9↔Q14). Unvalidated LLM output is never applied.
- The approval gate is not yours to fire and fires **only** when a derived diff touches
  a locked decision. Routine additive changes are gated by probes alone — do not invent
  extra confirmation steps; approval fatigue is the failure being avoided.

Report progress as **structured run events** the studio renders itself (Q15). The studio
viewer draws pipeline progress natively; `genui` / A2UI is explicitly out of scope, since
runtime LLM-composed UI is what Q10/Q14 forbid.

## Studio cutover is parallel-run (Q13)

When the new showcase-anatomy design shell arrives it is generated **alongside** the
current studio design shell behind a flag — never as a replacement. Probes render the
same screens through both and diff. Views flip **one at a time**, each only when its
probe is green; flipping back is a toggle, not a revert. The old shell is deleted only
once every view is flipped and green. Do not emit anything that assumes the old shell is
already gone.
