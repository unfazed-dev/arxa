# docs/design/ — the live design source

This is the **current** design source for appbox:

- `brief.md` — the design brief, elicited via the `appbox-story-mapper` skill
  (provenance-marked; `inferred` fields flagged).
- `story-map.json` — the story-map data (Epic → Feature → Story, chat-centric
  contract, 101 stories).
- `story_map.html` — the generated interactive view of the story map.
  Regenerate it from `story-map.json` via the story-map emitter; do not
  hand-edit.

This supersedes `archives/design-v2/` (personas Evan/Michelle, journeys,
flows library — written in retired `app_box` vocabulary). The archive is kept
for history only; never cite it as current.

For the system-level view (pipeline, kits, gates), see
[`docs/appbox-system-map.md`](../appbox-system-map.md).
