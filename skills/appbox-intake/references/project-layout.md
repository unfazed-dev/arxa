# Project layout — ~/.appbox

## Projects live in ~/.appbox

Every user project is `~/.appbox/projects/<name>/{intake,design,build,settings}`
(`appbox project init <name>`; `APPBOX_HOME` overrides the root; the studio
design itself stays in the repo — ~/.appbox holds user projects only). Emitting
with `--project <name>` writes ALL intake outputs there:

```
~/.appbox/projects/<name>/intake/
  answers.json     the validated answers, verbatim
  brief.md         the emitted brief (inferred fields marked)
  registry.json    the seeded registry (see below)
  flows.json       declared flows, or derived drafts marked inferred
  personas.json    the elicited user types ([] when none were named)
  map.json         the story map, ids content-derived, counts baked in
  moodboard.json   boards/references/shots, shot src precomputed
  direction.json   adjectives/avoids, field provenance promoted per item
```

The last four are Slice B1. All four are pure functions of `answers.json` and
all four degrade to their EMPTY shape when the answering group is absent — every
project that existed before Slice B has all four groups missing, and re-emitting
one of those must keep working rather than fail.

**Where the last three get their input.** `direction.json` and `personas.json`
come from groups intake elicits itself (`direction`, `personas`). The other two
come from documents intake does NOT own:

| artifact | answers group | written by |
|---|---|---|
| `map.json` | `answers.map` | `appbox-story-mapper` |
| `moodboard.json` | `answers.moodboard` | `appbox-moodboarder` |

Those two skills deposit their document into `answers.json` under that key;
intake republishes it with ids, counts and `shot.src` baked in, and carries
every field it does not recognise through untouched — intake is a republisher
here, and a republisher that drops the author's fields is the bug. Shapes:
`skills/appbox-story-mapper/story-map.schema.json` and
`skills/appbox-moodboarder/moodboard.schema.json`.
