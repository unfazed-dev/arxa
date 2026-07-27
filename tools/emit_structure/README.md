# emit_structure

Derives `<design-root>/structure.json` — the shell/surface map the structure
gate drift-checks against — from the **authored layer**: the producer's
`models/screens_model/registry.json` and `app.routes.js`.

```sh
tools/emit_structure/emit_structure.py --app <app-root> --design-dir designs/app-box-app        # emit
tools/emit_structure/emit_structure.py --app <app-root> --design-dir designs/app-box-app --check # drift guard
tools/emit_structure/emit_structure.py --self-test                                              # hermetic
```

## Why it exists

Structure used to be invented downstream — shell parsed out of a filename
prefix, viewmodel identity eyeballed off rendered HTML — then argued about three
phases later. This emitter closes the loop at the source: the producer already
knows the structure, so it writes it down, and the structure gate asserts it.

## How it joins

1. **registry** — reads `models/screens_model/registry.json` as JSON (no regex).
   Every entry is emitted, `surface: null` included.
2. **tabRoots** — lifted from the `tabRoots` export of `app.routes.js`. A producer
   with no `tabRoots` (or an empty map) **fails** — an empty object no longer
   passes vacuously.
3. **surfaceId join** — each entry with a surface is joined to its viewmodel on
   the viewmodel's **exported `surfaceId`** (== the registry entry's `id`), never
   on filename similarity. A missing `surfaceId` is a **hard failure naming the
   viewmodel**; an orphan viewmodel (a `surfaceId` the registry never claims) is
   a hard failure naming the file. There is no normalizer — `giftcards`↔`gift_cards`
   is a lexical trap that a normalizer would half-close and leave failing silently.

## Exclusion semantics

`surface: null` **is** the exclusion. There is deliberately no second "excluded"
list — a hand-maintained list is one you pad to keep a gate green. The count
reconciles exactly: `registry == frozen + exclusions`.

## Per-screen fields

`id`, `tab`, `comp`, `shell`, `surface`, plus the resolved `viewmodel` path and
its declared `deps` (the `services/facades/*` and `services/repositories/*`
modules it imports, design-root-relative). `tab → shell` is a pure rename table
(one shell per tab), so `shell` is *derived* from the surface's `<shell>_shell_`
prefix, never hand-maintained.

## Output shape

```jsonc
{
  "$schema": "app-box/structure@1",
  "registry": "models/screens_model/registry.json",
  "tabRoots": { "projects": "/", "design": "/design", ... },
  "screens": [
    { "id": "projects.home", "tab": "projects", "comp": "ProjectsHome",
      "shell": "stage_shell", "surface": "stage_shell_projects_home_view",
      "viewmodel": "ui/views/.../home_viewmodel.js",
      "deps": ["services/facades/project_facade.js", "services/facades/shell_facade.js"] },
    { "id": "projects.splash", "tab": "projects", "comp": "ProjectsSplash",
      "shell": "stage_shell", "surface": null, "viewmodel": null, "deps": [] }
  ]
}
```
