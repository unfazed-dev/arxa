# Inspector widget migration — implementation review

Date: 2026-08-08. Reviewer gate: `appbox design lint` + full `appbox design probe all`
against a disposable project (`portalo-probe`, served on :4330 per the probe guard's
recipe). Full log was at `/tmp/probe-all-4330.log` (tmp is session-scoped; verdicts
recorded here).

## Gates

- **Lint: CLEAN** — no ad-hoc JS, widget/panel gate W1–W6 clean on `designs/appbox-studio`.
- **Probe suite: 10/15 passed.** `widget-tools` (drawer editor, provenance honesty,
  selection round-trip, drag handles) fully passes — the core of the migration works.

## Failing probes (8 assertions, 5 probes)

1. **boost** (2) — `same document (boosted, no full load) — window token=null`:
   navigation from `portalo.home` → `portalo.category` does a full page load, not a
   boosted swap. And `inspect param rides along in links` fails: `&inspect` is dropped
   on `/build/screens/portalo.category`. Inspect-state continuity across navigation was
   an explicit plan requirement — treat as a real regression/gap.
2. **no-reload** (1) — `morph extension wired`: htmx `4.0.0-beta6` present but
   `Idiomorph loaded: undefined`. The morph extension isn't in the served runtime
   bundle; likely lost when the runtime/vendor set changed. Probably the root cause of
   the boost failure above (full loads instead of morphs).
3. **widget-logic** (2) — every row classifies as `unwired,unwired,edge,unwired,unwired`;
   probes expect `static` rows (card + email field) and `unknown` for templated names
   (Apple/Google buttons). The wiring classifier lost granularity — only
   wired/edge/unwired survive.
4. **inspect** (1) — `carousel icon is active` when switching the activity panel to the
   inspector view: icon active-state not set on view switch.
5. **composer-draft** (2) — textarea does not clear after send on `/design` and
   `/design/freeze` (8s timeout, probe reports real state). May share the missing-morph
   root cause (response swap never lands).

## Suggested fix order

Wire Idiomorph back into the vendored runtime first (likely clears boost + possibly
composer-draft), then the `&inspect` param propagation, then the widget-logic
classifier (`static`/`unknown` tiers), then the carousel icon state.

## Repro

```
cp -R ~/.appbox/projects/portalo ~/.appbox/projects/portalo-probe   # if absent
dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --project portalo-probe --port 4330
dart run appboxd/bin/appbox.dart design probe all --base http://localhost:4330
```
