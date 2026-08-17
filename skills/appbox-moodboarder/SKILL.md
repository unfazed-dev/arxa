---
name: appbox-moodboarder
description: "Use when a story map / requirements brief should become a browsable moodboard of real reference apps — fans out one gathering subagent per epic, captures screenshots of the key screens with the appbox lens under semantic filenames, and assembles the moodboard the appbox-designer consults alongside docs/intake/brief.md. Runs after appbox-story-mapper, before design. Trigger on moodboard, design references, visual direction, 'what should it look like', gather reference apps, capture screenshots for design."
license: MIT
---

# appbox-moodboarder — requirements → references → shots → moodboard

> Per-skill playbook (the folded canon for this phase): [`MOODBOARD_playbook.mdx`](MOODBOARD_playbook.mdx)

```
story-mapper  →  moodboarder  →  appbox-designer
                 (docs/moodboards/)
```

Elicits **visual direction**, the same way the story-mapper elicits scope:
it gathers and captures; it does NOT design (architecture §22). The output is
the client's references, curated and screenshotted — the designer's job is
still the design.

## When to run

After `docs/intake/story-map.json` exists, before `appbox-designer` runs.
Also runnable standalone whenever a requirement needs visual references
("get me a moodboard for X").

**Chain position:** stage 0 of `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Upstream:** `appbox-story-mapper` — `docs/intake/story-map.json` defines the slices.
- **Downstream:** `appbox-designer`, which consults the moodboard alongside `docs/intake/brief.md` before authoring. Captures use `appbox-lens`.

## The orchestration

1. **Slice the map.** One gathering slice per epic (per feature when an epic
   holds 3+ features). Each slice gets one subagent; slices fan out in
   parallel (one message, ≤8).
2. **Gather** — each subagent runs the prompt template below.
3. **Capture** — screenshots of every key screen, via the appbox lens, under the
   filename convention below.
4. **Assemble** — one moodboard doc per slice + embedded local shots.
5. **Verify** — every embedded `![](shots/…)` path resolves to a file on
   disk. An asset check that verifies strings instead of resolving paths is
   this project's recurring green-gate defect; do not repeat it.
6. **Hand off** — the brief carries the moodboard (`intake.moodboard`
   surface); the designer consults it before authoring.

## The gathering prompt (template)

Dispatch one `explore`/`coder` subagent per slice with this shape — fill
`{{product}}`, `{{epic}}`, `{{features}}`, `{{stories}}`:

```
You are gathering design references for {{product}}.
Slice: the "{{epic}}" epic — features: {{features}}.
Requirements (the stories this epic must satisfy): {{stories}}.

Find 6–10 real, shipping applications whose UI is worth stealing from for
THIS slice. For EACH reference return:
1. name + URL (official site/docs, not a blog about it)
2. the specific screens/patterns to steal — concrete, named
   (e.g. "pipeline run timeline with per-step expandable logs"), and WHY it
   fits the stories above
3. the KEY SCREENS to capture: 1–3 per reference, each as
   {screen_slug, url} — the publicly reachable page that shows the pattern
   (docs/marketing/app URLs; skip anything behind login)
4. a freshness grade per claim: 🔥 verified by 2+ sources or official docs /
   🌡️ single source / ❄️ uncertain

Anchor searches to the current year. Return compact markdown, ≤60 lines.
```

Then the capture pass (same or a follow-up subagent):

## Capture convention (appbox lens — web shots only)

The moodboarder uses the **appbox lens** (`appboxd/lib/lens.dart` over the CDP
client `appboxd/lib/cdp.dart`) — the promoted probe-runner port, and the
standing rule applies: **appbox's own tools first, before anything else.**
Golden compare, console-error gates, and native-target captures belong to the
build visual gates (story 3.7) and flows-canvas capture (4.1), not to
moodboarding — here we only take plain shots.

| need | how |
|---|---|
| the capture | `dart run appboxd/tool/lens_shot.dart <url> <out.png> [width] [height] [settleMs]` |
| device-viewport shots (390/744) | pass the viewport as args: `… 390 844` / `… 744 1133` — references inform a full-parity app |
| full-page (below the fold) / computed tokens | **not yet ported to the lens** — extend `lens.dart`/`cdp.dart` (scroll capture, Runtime.evaluate token extraction); never reach back for the archived probe-runner |

```bash
# Per-slice isolation is built in: every `dart run` launches its own headless
# Chrome with a throwaway temp profile and an ephemeral CDP port — slices can
# run in parallel with no env juggling and no shared browser state.
dart run appboxd/tool/lens_shot.dart <url> docs/moodboards/shots/<slice>/<ref>__<screen>.png 390 844
```

**Never shoot the user's browser.** The lens always launches its own headless
Chrome (`--headless=new`, temp `--user-data-dir`, port 0 = ephemeral), so the
user's tabs are never touched. Log the final URL + title as provenance per
shot.

- Output: `docs/moodboards/shots/<slice-slug>/<ref-slug>__<screen-slug>.png`
  — lowercase ascii, double-underscore separators, numbered `__2` when one
  screen needs a second state.
- Skip (and note) screens behind auth; never capture with credentials.
- A failed capture is recorded as `_(capture failed: reason)_` in the doc —
  never a hotlinked URL silently substituted.

## Where boards live (the appbox law)

Repo-mode project (an `appbox.json` marker above cwd): boards at
`<app-dir>/moodboard/boards/<slice-slug>.md`, shots at
`<app-dir>/moodboard/shots/<slice-slug>/…`. Appbox-native project: the same
`moodboard/` shape under `~/.appbox/projects/<name>/`. The legacy
`docs/moodboards/` path is pre-law — migrate, do not extend.

## Assembly format

`moodboard/boards/<slice-slug>.md`:

```markdown
# Moodboard — {{epic}}

## <Reference name> — <URL>
![<screen>](shots/<slice-slug>/<ref>__<screen>.png)
- Steal: <pattern> — <why it fits the stories>
- Grade: 🔥/🌡️/❄️

…
## Patterns this slice must have
1. …  (top-10, each traceable to a reference above)
```

## Verify (runnable)

```bash
# every embedded shot resolves (run from the app dir)
grep -o 'shots/[^)]*' moodboard/boards/*.md | while read -r p; do
  [ -f "moodboard/$p" ] || echo "MISSING: $p"
done
```

Zero MISSING lines = pass.

## Score (the selection seam — do not skip)

Every reference is scored **0–5 per criterion** against the INTAKE-derived
rubric. This is where intake feeds moodboarding: the rubric comes from the
answers, never from taste alone.

Derive the criteria from `intake/answers.json` + `intake/direction.json`:

- each **direction adjective** → a criterion (weight 1); an adjective that
  names a concrete visual requirement — motion, 3D, animation, video — is
  **`locked: true`** and weight 3 (founder-signed, non-negotiable downstream);
- the **layoutTemplate** answer → a criterion (weight 2);
- each **avoid** → scored inverted (a reference embodying an avoid scores 0
  on the adjective it cheapens).

Each gathering/scoring subagent scores its slice's references and records
`scores` + a one-line `why` per reference. Judgment is the subagent's;
arithmetic and gates are the CLI's (`appbox moodboard check` recomputes
weighted totals — Σ(score×weight)/Σweight — and refuses lies).

## Record (the step energize taught us)

A moodboard that is not RECORDED is a moodboard the designer never sees.
After verify + scoring:

1. Write the `moodboard` answer group into `intake/answers.json`:
   `{provenance: <method line>, criteria: [...], boards: [{id, references:
   [{name, url, grade, steal, why, scores, shot: {file}}]}],
   selectionStatus: "pending"}`.
2. Re-run the intake emitter (`appbox intake emit --project <name>`, or the
   repo-mode equivalent) — it publishes `intake/moodboard.json` with ids,
   counts, `shot.src`, and COMPUTED totals.
3. Run `appbox moodboard check <intake-dir>` — green required. A locked
   criterion with no reference scoring ≥ 3 fails here, BY DESIGN: that is
   "intake wants animated 3D and the board cannot feed it" caught at the
   board, not in the shipped site.

## Selection gate (human, recorded)

Present the ranked references (per board, highest weighted total first) to
the founder and ask which are selected. Default proposal: every reference
   at total ≥ 3.5. Record `selected: true` per chosen reference, set
   `selectionStatus: "approved"`, re-emit, re-check. **The designer consumes
   ONLY selected references** — via the commission, never the raw boards.

After approval, close the fidelity ladder: extract **style tokens** for
each selected reference into `tokens` (palette hexes, type register,
radius vocabulary, motion driver — judgment from the board's annotations
and the reference's public identity) and author one `tokenSynthesis`
block (the cross-pollinated starting direction: layout from one, palette
from another, motion from a third). Re-emit; the commission renders both
as its token layer — tokens beat screenshots beat adjectives.

## Handoff

- The downstream consumer is `appbox design commission <app-dir>`: it
  compiles `design/commission.md` + `design/commission-prompt.md` from the
  brief, the direction, and ONLY the selected references with their scores,
  and REFUSES to run while `selectionStatus` is not `approved`.
- `appbox-designer`: consume the commission as a binding contract before
  authoring; the boards' "patterns this slice must have" lists remain the
  per-epic visual bar behind it.
