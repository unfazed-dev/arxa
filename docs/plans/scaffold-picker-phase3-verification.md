# scaffold.picker — Phase 3 verification (lint + lens + live routes)

All evidence below was taken against a **correctly launched design server**:

```
dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319
```

run from the worktree root
(`.kimi-code/worktrees/scaffold-shell-worktree`).

## 0. Measurement hazard that invalidated an earlier round

Two distinct traps produced false evidence earlier in this phase. Both are worth
knowing because both *look like passes*:

1. **Wrong server.** `appbox serve` is the app/API server; `appbox design serve`
   is the design server. `appbox serve` 404s every design surface, and because
   404 bodies are uniform, a six-state sweep against it returns *byte-identical
   results for every state* — which reads exactly like a state-binding bug. An
   earlier reported table ("23333 B identical across six states, 5 `undefined`
   each") was this artifact and is formally superseded by §2.
2. **Wrong tree.** Bash runs in the worktree; the context-mode sandbox runs in
   the main repo checkout. The main repo has no `picker_view.html` at all, so
   any sandbox command using a *relative* path silently measured a different
   tree. All commands here use absolute paths or an explicit `cd` to the
   worktree.

The design server also loads its route table **at boot**, so newly added routes
404 until it is restarted.

## 1. Lint — exit 0

```
dart run appboxd/bin/appbox.dart design lint designs/appbox-studio   # exit 0
lint clean: no custom client-side JS in .../designs/appbox-studio
widget/panel gate clean: W1–W6 in .../designs/appbox-studio
```

The prior W4 failure (`picker_view.html: mounts _panel.html`, not one of the
five panel roles) was fixed by switching to the shared `sh.panels(c)`
composition rather than mounting the partial directly.

## 2. Six read states — 0 `undefined`, all differentiate

| state | bytes | `undefined` |
|---|---|---|
| success | 82702 | 0 |
| empty | 80944 | 0 |
| loading | 27416 | 0 |
| error | 28004 | 0 |
| notentitled | 81233 | 0 |
| signedout | 81207 | 0 |

Root cause of the earlier `undefined` tokens was the shim's
`const bag = Object.assign(...); bag.c = bag` self-reference: screen data must
be **spread at top level**, not nested under `c:`. Fixed in `3b5aeae`.

State tokens are lowercase canonical (`notentitled`, `signedout`) — `1647f67`.

## 3. Lens viewport ladder — 3 rungs, 0 problems, exit 0

```
lens shoot compact (390px):   ok
lens shoot medium (744px):    ok
lens shoot expanded (1280px): ok
lens shoot: 3 rung(s), 0 problem(s)
```

`lens shoot` fails on console errors or horizontal overflow; none occurred.

## 4. Mutation routes — live, 200, 0 `undefined`

All mutations are **POST with a form body** (`kit=<id>`); the kit id never
travels in the query string from the view.

| route | export | status | fragment root |
|---|---|---|---|
| `POST /scaffold/add` | `picker.add` | 200 | `#picker-grid` |
| `POST /scaffold/remove` | `picker.remove` | 200 | `#picker-grid` |
| `POST /scaffold/remove/confirm` | `picker.removeConfirm` | 200 | `#panels` (grid nested) |
| `POST /scaffold/remove/cancel` | `picker.cancelRemove` | 200 | `#picker-grid` |

`cancelRemove` must be a **server route**, not a link back to `/scaffold`:
clearing `session.pendingRemove` is what ends the confirm. Re-rendering the page
would leave it set and re-show the dialog forever (`4d0ece8`).

### `removeConfirm` precedence — measured, not assumed

`session.pendingRemove` **wins when set**; `?kit=` is consulted only when it is
absent.

- fresh session `?kit=auth` → 65342 B; `?kit=payments` → 64393 B (so `kit` *is*
  read)
- with `pendingRemove=auth` set, `?kit=payments` → 65342 B (the pending kit
  wins)

The two agree in every real flow. An earlier comment in `routes.scaffold.js`
stated this precedence backwards and has been corrected.

## 5. Known gap — confirm dialog is not laddered

The confirm dialog is reachable only via POST, and `lens shoot` navigates by
GET, so the dialog layout is **not** covered by the 3-rung pass in §3. "3 rungs,
0 problems" refers to the picker grid only. Laddering the dialog needs either a
GET-addressable state param or a CDP click step; neither exists today.

## 6. Unowned route

`POST /scaffold/messages` → `composerAction` has **no owner**: no
`sendMessage`/`composerAction` export exists in the picker or run viewmodel, and
nothing in `ui/` references the path. Scaffold surfaces run the shared composer
disabled. It should not be registered until it has an owner.

## Lane note

The five route tuples are an edit to `routes.scaffold.js`, which belongs to
chrome-integration. It was made to get the mutations testable and has been
reported to them for accept-or-revert; it should not land in the Phase 3 commit
unacknowledged.
