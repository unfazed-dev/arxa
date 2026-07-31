---
name: "generate-images"
description: "Generate images\nSource real raster art, icons, illustrations (free libraries / user-provided) or place honest placeholders"
---
# Generate images

Use real raster images — illustrations, icons, hero/section art, mascots and characters, textures, and genuine data infographics — when a design lands better with a real picture than a placeholder. This is the single source of truth for **how to source a raster image**; every flow (decks, mobile prototypes, hi-fi mockups, docs, animations, "something cool") points here instead of repeating the rule. It does not decide *whether* a flow wants imagery — the calling flow already decided; this resolves the source and gets the file.

## Generate only when it helps

Imagery is opt-in, not reflexive.
- Generate when content earns a picture: a conceptual metaphor, a hero/section image, a mascot/character to thread through a design, an app icon, a texture, or a genuine infographic.
- **Always offer a "none / minimal" path.** Fold one question into the flow's opening clarifying round — whether to add imagery and in what style — recommending a direction from the source material + chosen aesthetic / brand. If the content clearly won't benefit (dense data UI, terse internal review, explicit "keep it minimal"), don't ask — just proceed without.
- A clean placeholder beats a bad generated attempt. Generate only when it genuinely helps.

## Divide the labor

Route to clean HTML/CSS by editability and exactness: anything that must stay live-editable, selectable, pixel-exact, or data-bound — tables a user will edit, exact financial figures, charts bound to numbers, dense small print — belongs in HTML/CSS. Reserve raster for what raster is good at: conceptual scenes, characters/mascots, hero and section art, textures, and genuine infographics (an infographic's narrative text and labels don't need pixel exactness). Keep one shared style/identity block across all images in a project so look and character stay consistent.

## Source the image

the harness has no built-in image-generation tool. Resolve the source once, in this order:

1. **Real images from free libraries** — fetch real photos/art from Unsplash, Pexels, or Wikimedia Commons with `curl` via `Bash` (e.g. `curl -L -o designs/<project>/imgs/NN-….jpg '<url>'`). Prefer direct file URLs; respect each source's license/attribution expectations.
2. **Ask the user** — if no library image fits (a specific mascot, on-brand illustration, exact infographic), ask the user to provide the file or generate it externally and drop it into the project. Hand them the prompt file (below) if they generate it themselves.
3. **Honest placeholder** — a clearly-labeled placeholder box (dimensions + one-line description of the intended image), never a fake "image-looking" SVG scene.

Do not silently fall through the list: if 1 comes up empty and the user can't help, say so and use the placeholder openly.

## Hard rules

- **Never substitute SVG, HTML, or canvas** for a raster image you decided the design wants. If you can't source one, fall through to an honest placeholder — do not emit `<svg>` or CSS/HTML art as a stand-in. This holds even for "diagram-like" content; the caller already decided it wants a raster.
- **Prompt file when generating externally.** If the user will generate an image for you, write the full, final prompt to `prompts/NN-{type}-[slug].md` and hand it over — the file is the reproducibility record.

## Output & placement

- Save kept images inside the project (`designs/<project>/imgs/`), with any prompt files in `designs/<project>/prompts/`, so deliverables stay self-contained. Some flows have their own convention (a mobile prototype's icon is `icon.png` in the project root) — follow the calling flow.
- Place images on white or contrasting areas; full-bleed art aspect-fills, screenshots / diagrams aspect-fit. **View each image file (`ReadMediaFile`) and verify it loaded** before finishing.
- The HTML page that embeds the images is the recorded asset (`appbox design record-asset`); the raster files themselves are ordinary project files referenced by it — not separately recorded.
