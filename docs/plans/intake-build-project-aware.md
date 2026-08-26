# intake + build go project-aware (kimitail finding 1)

Status: Slice A in flight 2026-08-02. Slice B not started.

Finding 1 said "intake_model and build_model are still studio fixtures —
fix with the same overlay pattern as design_model". That framing is wrong
in a way worth recording, because it makes the work look like a migration
when most of it isn't one.

## The reframe: intake_model conflates three phases

`designs/arxa-studio/models/intake_model/` is a single fixture standing
in for the output of **three** pipeline phases:

| Phase | Skill | Owns | Project-side home |
|---|---|---|---|
| intake | `skills/arxa-intake` | answers, registry, flows | `intake/` — exists |
| story-mapper | `skills/arxa-story-mapper` | `map`, MoSCoW priority/release | none — never wired |
| moodboarder | `skills/arxa-moodboarder` | `moodboard` | none — never wired |

Canonical elicitation list: `skills/arxa-intake/intake.schema.json:1-78`.
It has **no** `personas`, `map`, or `moodboard` field. That is deliberate,
not an omission.

`docs/plans/architecture.md:895` — **"Intake elicits; it does not
generate."** Lines 897-899: a phase that writes the brief "produces
confident fiction — requirements nobody asked for, stated with the same
authority as ones they did."

So inventing a project-side personas or moodboard schema would violate
§22 directly. The correct move for those is to wire the phases that
legitimately own them, or leave them studio-local.

## Classification of intake_model's 13 keys

- **(a) genuine leaks — project data read from the studio fixture.**
  `project` name, `surfaces` step, `direction.adjectives/avoids`, `flows`
  (already done). Fixed in Slice A.
- **(b) correctly studio-local — the wizard's own machinery.** `personas`,
  `questionBanks`, `state`, `narrative`, `replies`/`replyFallback`,
  `statuses`, `files`. 8 of 13 keys. These are arxa asking, not the
  client answering.
  `personas` specifically = arxa's own proto-personas
  (`docs/plans/architecture.md:14`, `docs/VOCABULARY.md:43-49`), not a
  client-intake concept.
- **(c) belongs to story-mapper / moodboarder.** `map`, `moodboard`, and
  the MoSCoW half of `brief.surfaces`. No project wiring exists for either
  phase; no data exists for any project. Slice B.

The `brief.surfaces` key is the actual latent bug: the *surfaces wizard
step* (intake's, class a) and the *brief document's surface table*
(story-mapper's, class c) share one field name while being different
concepts.

## The projectStage trap — read before touching `build/`

`arxa/lib/project.dart:114-129`:

```dart
if (buildDir.existsSync() &&
    buildDir.listSync(recursive: true).whereType<File>()
            .any((f) => f.path.endsWith('.json'))) {
  return 'gates';
}
```

**Any `.json` anywhere under a project's `build/`, recursively, advances
that project to stage `gates`.** So the obvious migration — copy
`build_model` to `build/models/build_model/` mirroring design_model —
would falsely advance every project. Do not seed fixture json under
`build/`.

Compounding this: **no evidence writer exists in arxa at all.** Grep
over `arxa/lib/*.dart` finds three `build/` references, none a writer
(`project.dart:116` the check itself, `project_cli.dart:81` help text,
`design_tools.dart:279` a comment). An empty `build/` is not an edge case,
it is the only reachable state today for every project.

Therefore build's correct behaviour is: read real evidence when it exists,
render an honest empty state when it doesn't, and never seed demo data.

## Slice A — in flight

1. `project_repository.js` — add `answers()` reading `intake/answers.json`
   (nothing read it before).
2. `intake_facade.js:437` — project name from the project, not the seed.
3. `intake_facade.js:95` — surfaces step reads `proj.registry()`. Loses
   `priority`/`release`; the project has no equivalent (they are
   story-mapper's columns — see class c).
4. `intake_facade.js:118` — direction reads `answers.json.direction.value`,
   a verbatim structural match. The `references` sub-group has no project
   source and is dropped/guarded.
5. `build_repository.js` — read the project overlay, plus an outer catch
   returning an empty-evidence sentinel satisfying every `build_facade.js`
   getter.
6. `loop_viewmodel.js` + `loop_view.html` — new "no evidence yet" branch.
   None existed.
7. `screen_stub_view.html` — delete the Petal & Stem branded branches
   (finding 6). The generic `{% else %}` fallback already exists, so this
   is pure deletion. Note the template is a **shared** renderer: design's
   canvas/proto/thumb iframes point at it too (`git show 0faf823`), so
   verification must cover the design lens, not just build.

Every project read must be absent-tolerant: no overlay renders an honest
empty state, never studio demo data, never a 500.

## Slice B — not started

Give story-mapper and moodboarder a project-side home:

- decide their artifact paths (`intake/` sibling? their own shell?) —
  note `projectStage` currently keys off `intake/registry.json` only, so
  new files under `intake/` are safe, but anything under `build/` is not
- Dart emitters for `story-map.json` and the moodboard artifact
- JS repositories + facade rewiring for the `mapping`, `brief` and
  `moodboard` panels
- persona elicitation, if wanted, must be a **new interview question**
  feeding `answers.json` — generating personas from `audience` would be
  exactly the confident fiction §22 forbids

~~Until then those three panels legitimately show studio content, and the
findings doc should say so rather than calling them unfinished migration.~~
**No longer true — B3 landed 2026-08-02.** `mapping`, `brief` and `moodboard`
read the current project (`project_repository.js`'s `personas()` / `storyMap()`
/ `moodboard()` / `direction()`), and a project that has never run the
story-mapper or moodboarder gets an honest empty state naming the missing file
and the commands that write it — not the studio's copy of the same document.
See `slice-b-story-map-moodboard-prd-adr.md` for what the rewiring turned up
that the schema spec below did not anticipate.

### Slice B schema spec (designed 2026-08-02, not implemented)

Design principle: bake denormalisation (ids, counts, computed src paths) in
at **emit** time, the job `generate.mjs` does for the studio fixture. Every
new `project_repository.js` reader is then a dumb field-selector and
`context()`'s output shape cannot change.

All five live under the `intake/` shell — `project.dart:4-6` documents it as
holding "answers, brief, registry, flows, **story-map outputs**". Same
`readProjectFixture('intake/X.json')` pattern already used by
`registry()`/`flows()`. Nothing goes under `build/` (stage trap above).

**1. `personas.json`** — `[{id, name, role, goals[], frustrations[],
contexts[], proficiency, accessibility, provenance}]`, matching the seed's
9 keys exactly. **Not derivable from `answers.json`** — `audience` is one
JTBD sentence with no name/role/goals. **Requires a new interview
question**; generating personas from `audience` is the confident fiction
§22 forbids. Empty: `[]`.

**2. `map.json`** — `{releases[{name, stories, provenance}], epics[{id,
name, storyCount, provenance, features[{id, name, surfaceId,
stories[{id, name, priority, release, provenance}]}]}], counts{epics,
features, stories, must, should, could, byRelease}, statuses{storyId:
state}}`.
Story ids must be **content-derived** —
`slug(epic).slug(feature).slug(story)`, not the seed's `s-1..s-34` which is
sequential across the whole document and renumbers unrelated stories on any
insert. Collision suffix `-2`/`-3` applies only to colliding entries.
Not derivable from `answers.json` — story-mapper's own elicitation.

**3. `moodboard.json`** — `{curated, method, boards[{id, title, slice,
informs, references[{name, url, grade, shot{file, caption, id, src}, steal,
why, provenance}]}], counts{boards, references, shots}}`. `shot.id` =
`<boardId>--<file-no-ext>`, `shot.src` =
`/assets/images/moodboard/<boardId>/<file>`, both precomputed as
`generate.mjs` does. Note the seed's top-level `moodboard.provenance` is
free-text methodology, **not** the `client|founder|inferred` enum — renamed
`method` here, with real per-reference provenance. `board.file` (a
studio-authoring markdown pointer) is dropped.

**4. `direction.json`** — `{adjectives[{value, provenance}],
avoids[{value, provenance}], references[{board, note}]}`.
`answers.json.direction` already matches structurally but carries **one**
provenance for the whole field while the facade wants per-item; promote the
field's provenance onto each item at emit time. `references` stays `[]`
until a moodboard exists. **Largely landed in Slice A** — the facade now
reads `answers.json` directly; this file only matters if direction grows
beyond what intake elicits.

**5. Surfaces priority/release — extend `registry.json` entries.** Decided
by existing shipped intent, not preference: `intake.dart:645-654`
(`seedFromBrief`) already treats `priority`/`release`/`states` as additive
optional registry columns, commented *"arxa-story-mapper emits
priority/release"*. `gate_intake` reads only `id,label,shell,comp,route,
surface` (+`states`/`requiresAuth`/`tab`), so additive fields are safe. No
sidecar, no fold into `map.json`.

**Open questions — decide before implementing:**
1. `moodboard.curated` is a date, but `project.dart:13` bans clock fields
   for determinism. Options: drop it, make it a non-auto-populated "as of"
   note, or exempt this file. Leaning drop.
2. Story-id collision suffixing is invented from the `slug()` precedent —
   no existing convention to point at.
3. `map.json`'s `feature.surfaceId` makes story-mapper's
   "features attach to intake surfaces" rule an explicit stored fact. But
   no JS currently does that name-matching, so it may solve a problem that
   doesn't exist yet. Confirm before committing to it.
4. Personas: fixed N or "how many?" — a product call the docs don't settle.
5. No `.schema.json` exists for story-mapper or moodboarder. These would be
   the first, i.e. drafts of `story-map.schema.json` +
   `moodboard.schema.json`.
