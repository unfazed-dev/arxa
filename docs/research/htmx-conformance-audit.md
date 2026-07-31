# htmx conformance — the skill vs. the artifact it produced

Checked `skills/appbox-designer` and `designs/appbox-app` against
<https://htmx.org/docs/> (fetched 2026-07-27, indexed as `htmx-official-docs`).

**Verdict: the skill is docs-accurate. The artifact I generated from it is not.**
The reason nothing caught that is the point of this document.

## 1. The skill checks out

| claim | verified how | result |
|---|---|---|
| htmx 2.0.10 vendored | `npm view htmx.org version` → `2.0.10` | current, not stale |
| SRI hash is genuine | `sha384-H5SrcfygHmAuTDZphMHqBJLc3FhssKjG7w/CeCpFReSfwBWDTKpkzPP8c+cLsK+V` | **byte-identical** to the hash published in the docs' own *Installing Extensions* example |
| the 7 `htmx-config` keys are real | grepped the vendored source | all 7 present (`allowEval`, `allowScriptTags`, `globalViewTransitions`, `historyRestoreAsHxRequest`, `reportValidityOfForms`, `responseHandling`, `selfRequestsOnly`) |
| `hx-swap="none"`, `HX-Refresh`, `hx-boost`, `hx-ext` | docs *Swapping* / *Response Headers* / *Boosting* / *Extensions* | all documented, all used as documented |
| vendoring over CDN | docs: *"you may want to consider not using CDNs in production"* | follows the docs' own advice |

The skill's prose is a faithful pattern catalogue —
`hx-get` + `hx-target` + `hx-swap="outerHTML"` against a named fragment,
`hx-swap-oob` toasts, `hx-trigger="load delay:1s"` polling cancelled with 286,
`hx-push-url` for deep-linkable tabs. `examples/hello-hda` implements it:
**8 distinct htmx attributes in a single surface.**

## 2. The artifact does not

`designs/appbox-app`, 14 surfaces, **5 distinct htmx attributes**:

```
artifact   hx-boost hx-ext hx-post hx-swap hx-sync
hello-hda  hx-boost hx-ext hx-post hx-swap hx-sync  hx-get hx-target hx-trigger
```

No `hx-get`, no `hx-target`, no `hx-trigger`. Zero named-fragment renders.
And every mutating handler is the same line:

```js
export const approve = (c, h) => h.refresh(c);   // ×3 gates
export const submit  = (c, h) => h.refresh(c);   // ×4 forms
```

`h.refresh` sets `HX-Refresh: true` — **a full page reload**. So the shipped
interaction is `hx-post` → `hx-swap="none"` → reload. That is strictly worse
than `<form method="post">`: identical full reload, but it now requires
JavaScript to work at all, and under this artifact's `responseHandling`
(`{"[45]..": {swap:false, error:true}}`) a bad route fails *silently*.

Seven handlers. The theme handler is **not** one of them — `HX-Refresh` for a
`data-theme` flip is the documented escape hatch, and `helpers.mjs` says so in
a comment. The 3 gates and 4 submits are the defect.

## 3. Why every check passed

`runtime/lint.mjs` carries four rules. **All four are prohibitions**:

```
non-vendor <script>   ·   hx-on handler   ·   js: attribute   ·   [expr] filter
```

Nothing in `lint.mjs`, `selftest.sh`, or `doctor.mjs` mentions `hx-get`,
`hx-target`, or fragments. The toolchain can prove an artifact contains no
*forbidden* JavaScript; it cannot notice that an artifact uses no *htmx*. An
artifact that deleted every `hx-` attribute and served plain HTML would score
14/14 and lint clean.

Same shape as the `selftest.sh` argument bug fixed earlier this session: a
check that cannot fail is not a check. That one greened the wrong tree; this
one greens the wrong architecture.

## 4. Fix

Persist, then swap — in that order. Swapping an "approved" fragment while the
server still renders `pending` on reload trades a dull bug for a lying one; the
current `HX-Refresh` avoids it only by accident, by re-rendering from truth.
`h.session` already exists for this.

1. Gates and submits write their outcome to `h.session`, and `page` reads it.
2. Handlers answer with a named fragment via `hx-target` + `hx-swap="outerHTML"`.
3. Add a lint rule with teeth: an artifact whose only htmx verbs are `hx-post`
   answered by `h.refresh` is not a hypermedia app.

Not claimed here: anything about `<body hx-sync="this:replace">`. Resolving
`this` under inheritance needs the un-minified source or a two-request
experiment, and neither was done.

## 5. Two things the fix turned up on its way past

Neither is about htmx. Both are the same failure mode as §3 — a green result
that was green about the wrong thing.

**`lint.mjs` reads comments.** It scans raw file text, so a template *comment*
explaining why `hx-on` is banned trips the rule that bans `hx-on`. Writing the
reason down is what breaks the build. The rewrite here dodges it by not naming
the attribute; the real fix is to strip comments before matching, which is the
inverse of the `stacked_kit` lesson where comments had to be *preserved* for
opt-out markers. Selector greps strip; opt-out greps don't.

**`.gitignore` swallowed three surfaces.** Line 6 is `build/`, meant for build
output. The artifact has a surface tab called `build`, so `build.run`,
`build.finding` and `build.approve` — six files — were never committed. The
previous commit reported 58 files and read as complete. Every check passed
because every check ran against the working tree; a fresh clone would have had
`app.routes.js` importing three viewmodels that do not exist.

Fixed with a scoped negation (`!designs/*/ui/views/**/build/`), verified both
ways: the surface tab is now visible to git, and `build/app.apk` and
`runtime/build/` are still ignored.

**`lint.mjs` only banned double-quoted attributes.** The rules were
`/hx-(vals|headers)\s*=\s*"js:/` and `/hx-trigger\s*=\s*"[^"]*\[/` — quote-style
specific. The `hx-vals='{"action":"run"}'` added by this fix is the tree's first
single-quoted htmx attribute (it has to be: the value contains double quotes),
and it makes the gap reachable — `hx-vals='js:…'` would have walked past a ban
the docs describe as absolute. Widened to `['"]` and proved with a probe file
that now fails the lint.

Worth stating plainly: nothing in the toolchain compares *what git has* against
*what was rendered*. The 29 green renders in the previous commit were true of a
tree that did not exist in the repository.

## 6. How the fix was verified

Everything below ran against a tree extracted from the commit
(`git archive HEAD | tar -x`), not the working directory — the §5 lesson
applied to its own fix. 63 files in the commit, 63 on disk.

- **18 browser assertions** (Playwright, 1280 × 832, the artifact's only rung):
  each gate swaps in place with no navigation, the 422 form comes back carrying
  its error *and* the name already typed, an unacknowledged release is stopped
  by native validation before a request is issued, Run/Stop swap the build
  panel both ways, `/build` serves at all, and the chat textarea is emptied by
  the swap rather than by script. Zero console errors, zero failed requests.
- **selftest 15/15**, negative mode exits 1, lint clean, **29 renders** across
  all 14 surfaces and every brief-named state, **7 `hx-post` targets, 0
  unrouted**.

Two failures during this pass were my test's fault, not the artifact's, and are
recorded because both looked exactly like product bugs: `button[type=submit]`
matched the shell's theme control before the form under test, and `/build`
defaults to `red`, a state that deliberately offers no button.
