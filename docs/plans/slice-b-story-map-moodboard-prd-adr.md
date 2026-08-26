# Slice B — story-map + moodboard project wiring, plus PRD/ADR emission

Supersedes the "Slice B — not started" section of
[`intake-build-project-aware.md`](./intake-build-project-aware.md), which holds
the schema spec this plan implements. Read that first; this file records only
the decisions that were open, and the new PRD/ADR scope.

## Decisions taken (2026-08-02, by the operator)

| open question | decision |
|---|---|
| artifact paths | **`intake/` shell**, all five files. Already settled in the spec (`project.dart:4-6` documents `intake/` as holding story-map outputs); `projectStage` keys off `intake/registry.json` only, so new siblings are safe. Nothing under `build/`. |
| personas | **Add a new interview question now, variable N.** "Who are the main user types?" — the respondent gives as many as they have, no fixed count. Generating personas from `audience` is the confident fiction §22 forbids, so elicitation is the only honest source. |
| `feature.surfaceId` | **Omit.** No JS does the name-matching today, so it would be a stored field with no consumer and no test — a wrong value would go unnoticed. Additive later. |
| `moodboard.curated` | **Drop.** It is a date, and `project.dart:13` bans clock fields for determinism. The spec already leaned this way. |
| story-id collisions | `slug(epic).slug(feature).slug(story)`, suffix `-2`/`-3` on colliding entries only. Content-derived, never sequential — the seed's `s-1..s-34` renumbers unrelated stories on any insert. |
| `.schema.json` | Write both. `story-map.schema.json` + `moodboard.schema.json` are the first for these skills. |

## The invariant everything here must hold

Emission is a **pure function of the answers**. `emitBrief`/`emitRegistry`/
`emitFlows` are already written that way and the comments at `intake.dart:26`
and `:601` say so explicitly. Denormalisation (ids, counts, computed `src`
paths) is baked in at **emit** time so every `project_repository.js` reader
stays a dumb field-selector and `context()`'s output shape cannot drift.

A field that was not elicited is marked `[inferred]` and visible, never
silently invented. This is the rule the whole intake layer is built on and it
is what makes the PRD/ADR work below defensible rather than a hallucination
engine.

## Work breakdown

**B1 — Dart emitters + schemas.** `personas.json` (emits `[]` until the new
question is answered), `map.json`, `moodboard.json`, `direction.json` (promote
the field-level provenance onto each item), and additive `priority`/`release`
columns on `registry.json` entries. Plus both `.schema.json` drafts. Pure
functions, unit-tested against the seeds.

**B2 — the new interview question.** Variable-N personas feeding
`answers.json`, flowing through B1's emitter. Existing projects have the field
absent, which must degrade to `[]` and not to an error.

**B3 — JS repositories + facade rewiring. LANDED 2026-08-02.** `mapping`,
`brief` and `moodboard` now read the project, not studio content.
`project_repository.js` gained `personas()` / `storyMap()` / `moodboard()` /
`direction()` — field selectors over the four emitted artifacts, returning
`null` when one has never been produced. A project without them gets an honest
empty state naming the missing file and the two commands that write it; it
never falls back to the studio's own map, brief or moodboard.

The sentence this section used to carry — "until B3 lands those panels
legitimately show studio content" — is **no longer true**, and neither is the
same claim at `intake-build-project-aware.md`'s Slice B section. Three things
turned up during the rewiring that the schema spec did not anticipate:

* Several catalog strings were fixed sentences about the studio's own plan
  (`"66 stories across 9 epics"`, `"Three releases: R1 Dogfood · R2 Anywhere ·
  R3 Delight"`, `"3 boards curated 2026-07-28 · 12 captured screens"`) printed
  as the headline above whatever the project actually had. They now take the
  project's own `counts`, which the emitter totals.
* The activity thread's seeded narrative asserts studio facts ("R1 Dogfood
  carries 49 stories") in the same panel. On these three surfaces it is now
  dropped whenever a project is overlaid; with no project overlaid the studio
  is showing itself and the seed stays.
* `registry.json` entries carry no `priority`/`release` until a story-mapper
  fills those additive columns in, and an emitted story carries `priority: null`
  / `release: null` whenever the story-mapper did not grade or slot it. Every
  MoSCoW chip is guarded rather than defaulted — an unguarded one rendered
  `pri-undefined`, and any default would be a grade nobody assigned.

**B4 — PRD + ADR emission (new scope, 2026-08-02).** See below.

## B4 — PRD and ADR generation, and the line it must not cross

The ask: intake should also produce PRDs and ADRs from the gathered data.

The danger is obvious and worth naming, because this codebase has an explicit
rule against exactly it: a PRD and an ADR are documents that *look* the same
whether or not their content was elicited. An LLM-shaped "generate a PRD"
would fabricate goals, metrics and rationale that no one supplied, and it would
read as authoritative. §22 forbids that, and `emitBrief` is the precedent for
doing it honestly.

So both are **renders, not inferences**:

- **PRD** — a pure function of `answers.json`, the same way `emitBrief` is,
  with a PRD-shaped section order (problem, users, goals, non-goals, scope,
  success signals, risks, open questions). Every field that was not elicited is
  either omitted or carries the visible `[inferred]` mark. **No section is
  invented to fill a template.** An absent field produces an "Open question"
  line, which is true and useful, rather than a confident paragraph.

- **ADR** — one record per decision the pipeline **actually made and recorded**.
  An ADR whose "Decision" is a recorded pipeline choice and whose
  "Consequences" cite the artifacts it constrains is honest. An ADR speculating
  about alternatives nobody weighed is not.

  **Correction (2026-08-02) — I was wrong about the sources, and the check
  matters more than the guess.** This plan originally named kit selection, auth
  strategy, navigation model and theme derivation as recorded decisions, and
  asserted "the kit registry does enumerate them". All four were checked
  directly and **none is a recorded decision**:

  | source | finding |
  |---|---|
  | `config/kit-registry.json` | entries carry `dir/package/capabilities/backing/topology/phase/playbook/provides` — **no `alternatives`, no `rationale`, and no record that any project chose one**. It is a catalogue of kits that *exist*, not alternatives *weighed*. No `selectedKit` field exists anywhere. |
  | auth strategy | no `authStrategy`/`auth_strategy` field in `arxa/`, `config/` or `skills/`. |
  | navigation model | ADR 0003 is the studio's own hand-written prose, not per-project pipeline output. |
  | `theme_map.dart` | pure token→config map; derives a fragment, records no choice. |
  | `gen_playbook.dart:84` | a genuine hook, but no kit README carries a decision/adr/rationale heading (all 20 checked), so it finds nothing today. |

  A repo-wide grep for `decision`/`rationale`/`alternatives` in JSON and Dart
  returns nothing. `layoutTemplate` was also considered and rejected: it is an
  elicited answer with no rationale, and where its provenance is `inferred` an
  ADR built on it is precisely the §22 fiction.

  **Consequence: `emitAdrs` ships with no collector, and zero ADRs is the
  correct output today.** A collector hard-coded to `[]` was rejected because it
  would make the zero-ADR test tautological. Getting real ADRs requires
  *recording decisions first* — either intake elicits them, or the pipeline
  starts writing down the choices it makes. That is a separate piece of work and
  is now tracked as its own task; it is not something the emitter can conjure.

Numbering follows the existing convention in
`skills/arxa-designer/docs/adr/` (`NNNN-kebab-title.md`).

Both emitters must be deterministic and idempotent over their own output, and
must be provable by a test that a reverted emitter turns red.

## Order and dependencies

B1 → B3 (panels need the artifacts). B2 feeds B1's persona emitter but is
independent of B3. B4 depends on neither and can run alongside B1, provided it
owns its own files — `intake.dart` is B1's and must not be edited by two
workers at once.
