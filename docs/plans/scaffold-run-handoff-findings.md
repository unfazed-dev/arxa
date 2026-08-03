# scaffold.run — handoff findings (authoring agent)

## Status
`scaffold.run` triple (view + viewmodel + facade + repository + seeds + l10n) is
authored and **proven correct in isolation**. It does not yet render correctly
through the design server because of a wiring gap outside this agent's scope.

## Evidence: the triple is correct
Direct import of `services/facades/scaffold_run_facade.js`, `context({}, t, 'en', state)`:

| state     | c.state   | writes | kits |
|-----------|-----------|--------|------|
| pre       | pre       | 0      | 6    |
| completed | completed  | 9      | 6    |
| warning   | warning   | 9      | 6    |
| failed    | failed    | 4      | 6    |
| blocked   | blocked   | 0      | 6    |

`c.structure` = `{path:"structure.json", frozen:true, screens:11, shells:6, revision:"r7"}`
24 context keys returned. `run_viewmodel.js` exports `page, panelSize, surfaceId('scaffold.run')`.

## The gap (owner: chrome-integration)
Rendered through the server, **every `c.*` value is `undefined`** and `?state=`
is ignored (identical 24509 B for all five states) — i.e. the viewmodel's `page`
export never runs; the view template is rendered without viewmodel context.

Discriminating test — pre-existing screens are fine, both *new* scaffold screens are not:

| route                      | status | bytes | `undefined` |
|----------------------------|--------|-------|-------------|
| /design/freeze (existing)  | 200    | 62588 | **0**       |
| /build (existing)          | 200    | 17833 | **0**       |
| /scaffold (picker, new)    | 200    | 19016 | 5           |
| /scaffold/run (new)        | 200    | 24509 | 12          |

Registry entries exist (`scaffold.run -> /scaffold/run`, `scaffold.picker -> /scaffold`).
No `app_routes.js` / `scaffold.js` route module exists anywhere in the repo, so the
scaffold shell's viewmodel binding is the missing piece. Both new scaffold screens
fail identically, which rules out a per-file defect.

**Do not "fix" this by editing the facades/viewmodels — they are correct.**

## Also outstanding
`design lint` fails on a file owned by the picker agent, not on scaffold.run:
`picker_view.html: W4: mounts _panel.html, which is not one of the five panel roles`.

## D7 (done)
build.loop scaffold fixture row deleted from `models/build_model/run.en.json`.
Verified: JSON parses, `/build` renders 200 / 17833 B / 0 `undefined` / no errors,
and the build page no longer surfaces the scaffold row.
