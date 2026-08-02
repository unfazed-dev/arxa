# intake + build go project-aware (kimitail finding 1)

Status: Slice A in flight 2026-08-02. Slice B not started.

Finding 1 said "intake_model and build_model are still studio fixtures —
fix with the same overlay pattern as design_model". That framing is wrong
in a way worth recording, because it makes the work look like a migration
when most of it isn't one.

## The reframe: intake_model conflates three phases

`designs/appbox-studio/models/intake_model/` is a single fixture standing
in for the output of **three** pipeline phases:

| Phase | Skill | Owns | Project-side home |
|---|---|---|---|
| intake | `skills/appbox-intake` | answers, registry, flows | `intake/` — exists |
| story-mapper | `skills/appbox-story-mapper` | `map`, MoSCoW priority/release | none — never wired |
| moodboarder | `skills/appbox-moodboarder` | `moodboard` | none — never wired |

Canonical elicitation list: `skills/appbox-intake/intake.schema.json:1-78`.
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
  `statuses`, `files`. 8 of 13 keys. These are appbox asking, not the
  client answering.
  `personas` specifically = appbox's own proto-personas
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

`appboxd/lib/project.dart:114-129`:

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

Compounding this: **no evidence writer exists in appboxd at all.** Grep
over `appboxd/lib/*.dart` finds three `build/` references, none a writer
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

Until then those three panels legitimately show studio content, and the
findings doc should say so rather than calling them unfinished migration.
