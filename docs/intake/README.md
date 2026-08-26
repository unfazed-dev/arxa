# docs/intake/ — the live intake-chain source

This is the **current** intake source for arxa — story-mapper artifacts
(the chain's tail). Designer-stage artifacts live in `designs/<name>/`, never here:

- `brief.md` — the design brief, elicited via the `arxa-story-mapper` skill
  (provenance-marked; `inferred` fields flagged).
- `story-map.json` — the story-map data (Epic → Feature → Story, chat-centric
  contract, 101 stories).
- `story_map.html` — the generated interactive view of the story map.
  Regenerate it from `story-map.json` via the story-map emitter; do not
  hand-edit.

This supersedes `archives/design-v2/` (personas Evan/Michelle, journeys,
flows library — written in retired `arxa` vocabulary). The archive is kept
for history only; never cite it as current.

For the system-level view (pipeline, kits, gates), see
[`docs/arxa-system-map.md`](../arxa-system-map.md).
