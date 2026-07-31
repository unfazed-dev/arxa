---
name: appbox-moodboarder
description: "Turn a story map / requirements brief into a browsable moodboard of real reference apps — fans out one gathering subagent per epic, captures screenshots of the key screens with the appbox lens under semantic filenames, and assembles the moodboard the appbox-designer consults alongside docs/design/brief.md. Runs after appbox-story-mapper, before design. Trigger on moodboard, design references, visual direction, 'what should it look like', gather reference apps, capture screenshots for design."
license: MIT
---

# appbox-moodboarder — requirements → references → shots → moodboard

```
story-mapper  →  moodboarder  →  appbox-designer
                 (docs/moodboards/)
```

Elicits **visual direction**, the same way the story-mapper elicits scope:
it gathers and captures; it does NOT design (architecture §22). The output is
the client's references, curated and screenshotted — the designer's job is
still the design.

## When to run

After `docs/design/story-map.json` exists, before `appbox-designer` runs.
Also runnable standalone whenever a requirement needs visual references
("get me a moodboard for X").

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

## Capture convention (probe-runner — the web block only)

The moodboarder uses probe-runner's **host-web block** — nothing else. Motion
recovery, bundles, pixel/skeleton/colour diffs, and the native-target verbs
belong to the build visual gates (story 3.7) and flows-canvas capture (4.1),
not to moodboarding.

| verb | use |
|---|---|
| `web_open` + `web_shot` | the capture (CDP; Chrome default, Safari fallback) |
| `web_emu` | device-viewport shots (390/744) — references inform a full-parity app |
| `web_scroll` | full-page captures when the pattern is below the fold |
| `web_tokens` *(optional)* | computed palette/type/radii/shadows → `tokens.json` beside the shot — upgrades "picture to eyeball" to "tokens to steal" |

```bash
PROBE=appbox lens (appboxd/lib/lens.dart)/scripts        # resolves to the vendored copy (O1); shell-out, no import dep

# Per-slice isolation — MANDATORY when capture slices run in parallel.
# Every web verb drives CDP targets[0]; one shared Chrome = slices navigate
# each other's tab mid-capture. probe-runner's own env vars give each slice
# its own Chrome instance + profile; no hand-rolled CDP needed:
export PROBE_RUNNER_CHROME_CDP_PORT=93<NN>               # unique per slice (9331, 9332, …)
export PROBE_RUNNER_CHROME_USER_DATA_DIR=/tmp/probe-mb-<slice-slug>

python3 $PROBE/web_open.py <url>                # navigate (Chrome/CDP); web_shot.py takes NO --url
python3 $PROBE/web_shot.py --out <path.png>     # capture the open page; safaridriver when no Chrome
```

**Never shoot the user's browser.** probe-runner launches its own Chrome with
a dedicated `--user-data-dir`, so the user's tabs are only at risk if they run
personal Chrome with CDP on the same port — the per-slice port above (93xx,
not 9222) avoids that too. If you must share one Chrome instance instead
(single-slice run), create a fresh tab via CDP `Target.createTarget`, shoot,
close it — per shot, with the final URL + title logged as provenance. Never
blindly reuse `targets[0]` across slices.

- Output: `docs/moodboards/shots/<slice-slug>/<ref-slug>__<screen-slug>.png`
  — lowercase ascii, double-underscore separators, numbered `__2` when one
  screen needs a second state.
- Skip (and note) screens behind auth; never capture with credentials.
- A failed capture is recorded as `_(capture failed: reason)_` in the doc —
  never a hotlinked URL silently substituted.

## Assembly format

`docs/moodboards/<slice-slug>.md`:

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
# every embedded shot resolves
grep -o 'shots/[^)]*' docs/moodboards/*.md | while read -r p; do
  [ -f "docs/moodboards/$p" ] || echo "MISSING: $p"
done
```

Zero MISSING lines = pass.

## Handoff

- `docs/moodboards/` is named in `docs/design/brief.md`'s world via the
  `intake.moodboard` surface (story-map dataset) — regeneration keeps it.
- `appbox-designer`: consult the moodboard slice for the epic you are
  authoring BEFORE writing surfaces; the "patterns this slice must have"
  list is the visual bar.
