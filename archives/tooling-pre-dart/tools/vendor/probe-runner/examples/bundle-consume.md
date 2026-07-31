# Capture a live site into a portable bundle, then consume it

The bundle is a **content-free, firewall-audited** `bundle/` directory any builder
(an agent, a code generator, a re-skin pipeline) consumes to rebuild, re-skin, or
re-content a target without touching the original. This recipe captures a web
route, then shows the consume side (read the bundle, swap content via the asset
slots, keep the geometry/motion/tokens).

## 1. Capture → bundle

```bash
S=$CLAUDE_SKILL_DIR/scripts
# headed Chrome on CDP (the design-capture transport)
python3 $S/web_launch.py --browser chrome --url https://example.com --cdp-port 9222

# skeleton (DOMSnapshot → content-free node tree) + tokens (computed palette → semantic roles)
python3 $S/web_skeleton.py --cdp-port 9222 --out sk.json
python3 $S/web_tokens.py   --cdp-port 9222 --out tokens.json

# (optional) motion: scroll-scrubbed easing (web_anim) and/or time/event (web_flipbook)
python3 $S/web_anim.py     --cdp-port 9222 --out anim.json
python3 $S/motion_adapter.py --anim anim.json --out motion.json   # -> 10-key contract rows

# assemble + content-audit (a leak raises ContentLeak, rc=3 — the bundle is share-safe)
python3 $S/bundle_writer.py --skeleton sk.json --tokens tokens.json \
                            --motion motion.json --out bundle/
```

What lands in `bundle/`: `meta.json`, `skeleton.json` (nodes with bbox/role/
layout + `token_ref`/`anim_ref` + per-node `style`/`theme`/`responsive`/… deltas),
`tokens.json`, `motion.json` (the 10-key contract), `substrate.json`,
`assets/manifest.json` (typed swappable slots: image/text/svg).

## 2. Multi-route (a whole site)

```bash
printf 'https://example.com/\nhttps://example.com/about\n' > routes.txt
python3 $S/site_capture.py --urls-file routes.txt --out site_out --cdp-port 9222 --merge --dedup
# -> site_out/<route>/bundle/ per route + site_out/site.json (content-free manifest)
```

## 3. Consume (the builder side)

The bundle is plain JSON — read it directly. The two surfaces a re-skin/re-content
job touches:

```python
import json, pathlib
b = pathlib.Path("bundle")
sk  = json.loads((b/"skeleton.json").read_text())   # geometry + role + layout tree
tok = json.loads((b/"tokens.json").read_text())     # semantic palette + type/space/radii scales
man = json.loads((b/"assets"/"manifest.json").read_text())  # swappable content slots
mot = json.loads((b/"motion.json").read_text())     # 10-key motion contract rows

# re-skin: swap the palette roles (bg/primary/accent/…); geometry is untouched
tok["palette"]["primary"] = "#ff5500"

# re-content: fill the asset slots (text/image/svg) from your own copy
for slot in man["slots"]:
    if slot["kind"] == "text":
        ...   # your content keyed by node_id; bbox + suggested_max_glyphs guide wrapping
```

### Certify a clone matches the original

After rebuilding, certify the **geometry** is faithful with `skeleton_diff` (CSS-px
gates, same-dpr calibrated so measurement noise can't false-fail), and the
**pixels** with `pixdiff` (SSIM default):

```bash
# capture the clone into the same shape, then diff
python3 $S/web_skeleton.py --cdp-port 9222 --url https://clone.local --out sk_clone.json
python3 $S/skeleton_diff.py sk.json sk_clone.json --threshold 1.0   # certified:true/false + per-node deltas
```

## What the bundle is NOT for

A consumer that needs the **currently-running** animation values (e.g. a round-trip
"does my emitted code's `getComputedStyle()` match the design's?") should drive the
**live** target with `web_eval`/`flutter_eval`, not read the bundle. The bundle is
capture-once/rebuild-many; live inspection is a different job. Both are valid.
