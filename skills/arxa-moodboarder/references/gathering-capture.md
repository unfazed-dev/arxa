# Gathering and capture

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

## Capture convention (arxa lens — web shots only)

The moodboarder uses the **arxa lens** (`arxa/lib/lens.dart` over the CDP
client `arxa/lib/cdp.dart`) — the promoted probe-runner port, and the
standing rule applies: **arxa's own tools first, before anything else.**
Golden compare, console-error gates, and native-target captures belong to the
build visual gates (story 3.7) and flows-canvas capture (4.1), not to
moodboarding — here we only take plain shots.

| need | how |
|---|---|
| the capture | `dart run arxa/tool/lens_shot.dart <url> <out.png> [width] [height] [settleMs]` |
| device-viewport shots (390/744) | pass the viewport as args: `… 390 844` / `… 744 1133` — references inform a full-parity app |
| full-page (below the fold) | `lens_shot.dart … --full` — captures the whole scroll height |
| computed design tokens | `arxa lens tokens <url>` → `extractTokens` (`arxa/lib/lens/tokens.dart`) — palette/type/radius measured from the live DOM; the verb the suitor evidence layer is built on |
| derived palette (5 hexes + anchors + selection trail) | `arxa palette derive --from <input> --json` — the palette engine (`arxa/lib/palette_derive.dart`); the two moodboard-side inputs are below |

```bash
# Per-slice isolation is built in: every `dart run` launches its own headless
# Chrome with a throwaway temp profile and an ephemeral CDP port — slices can
# run in parallel with no env juggling and no shared browser state.
dart run arxa/tool/lens_shot.dart <url> moodboard/shots/<slice>/<ref>__<screen>.png 390 844
```

**Never shoot the user's browser.** The lens always launches its own headless
Chrome (`--headless=new`, temp `--user-data-dir`, port 0 = ephemeral), so the
user's tabs are never touched. Log the final URL + title as provenance per
shot.

- Output: `moodboard/shots/<slice-slug>/<ref-slug>__<screen-slug>.png`
  — lowercase ascii, double-underscore separators, numbered `__2` when one
  screen needs a second state.
- Skip (and note) screens behind auth; never capture with credentials.
- A failed capture is recorded as `_(capture failed: reason)_` in the doc —
  never a hotlinked URL silently substituted.

## Palette derivation (the engine's two doors)

Palette hexes on the record are DERIVED by the palette engine, not
judged, wherever the reference is reachable. The engine takes exactly
two moodboard-side inputs, both measured by construction:

- **a reference URL** — `arxa palette derive --from <url> --json`: the
  url adapter clusters the live page's lens tokens (extractTokens
  clusters → select 5);
- **a shot on disk** — `arxa palette derive --from <shot-path> --json`:
  the image adapter runs the lens pixel probe over the PNG
  (headless-Chrome canvas, zero native deps) and clusters its pixels.

Write the `--json` output — swatch, anchors, and the selection trail
(clusters, counts, source) — verbatim to
`moodboard/evidence/<ref-slug>__palette.json` and cite it from the
suitor or reference `evidence` list (kind `palette`). Per the
evidence law the recorded `file` stays RELATIVE to
`<app-dir>/moodboard/` (`evidence/<ref-slug>__palette.json`); the
gate resolves it on disk, and an unresolved citation is a lie it
catches. A reference with neither URL nor shot cannot feed the engine —
palette there stays `judged`, the weaker evidence, flagged as such.
