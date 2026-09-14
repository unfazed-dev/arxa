# Project layout — ~/.arxa

## Projects live in ~/.arxa

Every user project is `~/.arxa/projects/<name>/{intake,design,build,settings}`
(`arxa project init <name>`; `ARXA_HOME` overrides the root; the studio
design itself stays in the repo — ~/.arxa holds user projects only). Emitting
with `--project <name>` writes ALL intake outputs there:

```
~/.arxa/projects/<name>/intake/
  answers.json     the validated answers, verbatim
  brief.md         the emitted brief (inferred fields marked)
  registry.json    the seeded registry (see below)
  flows.json       declared flows, or derived drafts marked inferred
  personas.json    the elicited user types ([] when none were named)
  map.json         the story map, ids content-derived, counts baked in
  moodboard.json   boards/references/shots, shot src precomputed
  direction.json   adjectives/avoids, field provenance promoted per item
  brandcolors.json stated brand hexes + role hints ([] when none were stated)
```

The four Slice-B1 files (`personas`/`map`/`moodboard`/`direction`) are pure
functions of `answers.json` and degrade to their EMPTY shape when the answering
group is absent — every project that existed before Slice B has all four groups
missing, and re-emitting one of those must keep working rather than fail.
`brandcolors.json` (the palette plane, arxa-palette-plane-universal Q6) obeys
the same law: a pure function of the `brandColors` group, `[]` when it is
absent — absent is never an error. It is the machine-readable slot
`arxa palette reseed` consumes as the default palette's first candidate.

**Where they get their input.** `direction.json`, `personas.json` and
`brandcolors.json` come from groups intake elicits itself (`direction`,
`personas`, `brandColors`). The other two come from documents intake does
NOT own:

| artifact | answers group | written by |
|---|---|---|
| `map.json` | `answers.map` | `arxa-story-mapper` |
| `moodboard.json` | `answers.moodboard` | `arxa-moodboarder` |

Those two skills deposit their document into `answers.json` under that key;
intake republishes it with ids, counts and `shot.src` baked in, and carries
every field it does not recognise through untouched — intake is a republisher
here, and a republisher that drops the author's fields is the bug. Shapes:
`skills/arxa-story-mapper/story-map.schema.json` and
`skills/arxa-moodboarder/moodboard.schema.json`.
