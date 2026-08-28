# arxa-studio-mobile — intake

This stage holds the intake chain: `answers.json`, `brief.md`, `prd.md`,
`registry.json`, `flows.json`, `personas.json`, `direction.json`,
`moodboard.json`, `decisions.json` + the `adr/` directory, plus the
story-map outputs.

What starts it: a client conversation (the `arxa-intake` skill elicits
requirements; `arxa-story-mapper` emits the brief). The answers are the
founder-stated source of truth — targets, locales, and `kind: site | app`
sync from here into `arxa.json` at the app-dir root.

Run `arxa intake` stages from this directory; outputs land here and are
committed like any other repo file.
