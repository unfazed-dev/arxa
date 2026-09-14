# Guardrail test and common mistakes

## The guardrail, as a test

The engine's self-test is the proof the guardrail holds:
```sh
arxa intake --self-test
```
It asserts, negatively: feed N surfaces, the emitted registry has exactly N
(no invented entries); every `surface` is `null`; every `inferred` field is
marked in the brief and the mark does not leak onto `client` fields; bad
provenance / malformed ids / duplicate ids are all rejected and named; a
malformed `brandColors` entry (bad hex, unknown role, missing provenance)
is rejected and named; absent brand colors emit `brandcolors.json` = `[]`
— never a placeholder hex.

## Common mistakes

- **Inventing a field the client did not state.** If they were silent, the
  field is `inferred` with a placeholder, or absent. Never fabricate a
  requirement with `client` provenance.
- **Binding a `surface`.** Intake names; design binds. A non-null surface in a
  seed means intake did design's job — the self-test fails it.
- **Rephrasing the client.** Capture verbatim. Polishing their words is editing
  the brief, which is generation by another name.
- **Inventing or rephrasing a brand hex.** The one field with no
  `inferred`-placeholder escape: an invented hex does not sit flagged in the
  brief — the palette reseed consumes `brandcolors.json` and the placeholder
  becomes the site's DEFAULT palette; you have manufactured the palette
  itself. Rephrasing is the same sin in miniature — 'rounding' `#1b3a4b` to
  a nicer value edits what the client stated. Verbatim, or absent: there is
  no third state. A hex found by search or lens is `inferred` until the
  client confirms it; never `client`.
- **Forgetting intake is optional.** Forcing it on a first run costs the buyer
  the demo that earns trust. A hand-written brief, or none at all, is valid.
- **Trusting the emit without validating.** `emit` validates internally and
  refuses to write on error, but run `validate` while you author to catch
  provenance and id mistakes early.
