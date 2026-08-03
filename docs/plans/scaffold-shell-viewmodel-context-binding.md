# scaffold shell: `c.*` renders undefined — root cause and fix

Status: diagnosed, fix owned by the two screen authors (not a spine defect).
Supersedes the wiring-gap hypothesis in `docs/plans/scaffold-run-handoff-findings.md`.

## Symptom

`/scaffold` and `/scaffold/run` return 200, templates render, `t()` resolves,
but every facade-sourced `c.*` read is `undefined`. All five `?state=` variants
return an identical byte count (24509 B on /scaffold/run), i.e. the query is
ignored.

## Root cause

`appboxd/lib/design_server/worker_assets/worker_shim.js` (helper `render`):

```js
render(c, viewRef, ctx, st) {
  ctx = ctx || {};
  const prefs = ...;
  const bag = Object.assign({ prefs, locale: ..., locales }, ctx);
  bag.c = bag;                       // <-- self-reference, assigned AFTER the merge
  return c.html(templatesRender(viewRef, bag));
}
```

The template's `c` is the bag itself. A viewmodel therefore passes screen data
**spread at top level**; any `c:` key in `ctx` is clobbered by `bag.c = bag`.

Both scaffold viewmodels nest under `c:`:

```js
const ctx = (c, h, screen) => ({
  activeShell: 'scaffold',
  c: facade.context(...),            // <-- discarded
});
```

They are the only 4 sites in the repo that do this (2 in `run_viewmodel.js`,
2 in `picker_viewmodel.js`). `freeze_viewmodel.js` and `loop_viewmodel.js`
spread: `{ activeShell: 'design', ...facade.freezeContext(...) }`.

Proof of the clobber:

```
$ node -e "const f={a:1};const b=Object.assign({},{activeShell:'scaffold',c:f});b.c=b;
           console.log(b.c.a, b.c.activeShell)"
undefined scaffold
```

## Why this is not a routing/binding gap

- `app.routes.js` imports and spreads `scaffoldRoutes`; `routes.scaffold.js`
  binds `picker.page` / `run.page`.
- `worker_shim.js:242` returns a hard 404 for an unmatched path, and
  `templatesRender` is called from exactly one place — `h.render`. There is no
  static/asset fallback for `/scaffold*`.
- Therefore **200 + rendered `t()` output proves `page` ran and called
  `h.render`**. The handler executes; its context is thrown away.
- Discriminator: `c.activeShell`, `c.prefs`, `c.locale` *do* resolve (they are
  bag keys); only facade-sourced keys are undefined. A never-invoked viewmodel
  would 404 instead.

## Fix (4 sites, screen authors' files)

```js
const ctx = (c, h, screen) => ({
  activeShell: 'scaffold',
  ...facade.context(h.session(c).data, h.t(c), h.locale(c),
                    screen || c.req.query('state') || 'success'),
});
```

Same change in each `panelSize` handler. No template or macro edits: the
`#panelsSwap` / `#gridSwap` macro path renders `f.macro(c)` with the same bag,
so those swaps start working from the identical change.

## Open spine items (this worktree's lane)

- `routes.scaffold.js` binds only `page` + `panelSize`. Picker's facade emits
  hrefs with no route entry: `GET /scaffold/add?kit=`, `GET /scaffold/remove?kit=`,
  `GET /scaffold/remove/confirm?kit=`, and `POST /scaffold/messages`
  (composer; no viewmodel export exists for it yet).
- `cancelRemove` is exported but `cancelHref` is `/scaffold` — confirm whether
  the export is dead or needs its own path.
- ~~`scaffold.picker` registry entry must list `signedOut` in the lens states~~
  **RETRACTED.** This item was false and generated a bad ask to chrome-integration.
  `states` *is* a real optional registry key (`emit_structure.dart` reads it,
  validates it, and emits `statesProvenance`), but its vocabulary is closed to
  `['loading','empty','error']` (`appboxd/lib/intake.dart`). `signedOut`,
  `notEntitled` **and `success`** are all inadmissible — adding any of them
  hard-fails emit, it is not a silent schema break. The six lens states are
  facade-driven off the `?state=` request param and already render distinctly
  (six distinct byte sizes, zero `undefined`); no registry change was ever
  needed. There is also no lens/preview dropdown UI anywhere in this worktree
  to edit — `notEntitled` appears only in my facade, my view, seeds/l10n, and
  these docs. See scaffold-shell-kit-picker-decisions.md § "Registry `states`
  cannot carry `signedOut` / `notEntitled` / `success`".
