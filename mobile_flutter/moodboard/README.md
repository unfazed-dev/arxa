# arxa-studio-mobile — moodboard

This stage holds the visual references: one markdown board per epic under
`boards/`, screenshots under `shots/`, and the scored record in
`../intake/moodboard.json`.

What starts it: the story map existing in `../intake/` (it defines the
slices). The `arxa-moodboarder` skill fans out one gathering subagent per
epic, captures key screens with the arxa lens, then SCORES every
reference 0-5 against the intake-derived criteria (founder adjectives and
locked requirements weighted highest) and records the scores. Selection is
a human gate: the highest-scoring slice, approved or overridden by you,
becomes the designer's visual mandate. A locked intake criterion (e.g.
"animated 3D backgrounds") with no reference scoring >= 3 fails the record
check.
