# Filmstrip ↔ viewport sync (views lens)

Requirement: in the design shell's viewer panel (views lens), the filmstrip
thumbs must sync BOTH ways with the current screen in the canvas viewport,
with an accent outline on both the thumb and the screen tile.

## Decisions

- **Mechanism**: extend `canvas.js` (existing named island, ADR-0002) — this
  is canvas view-state, exactly its charter. No sixth island, no new script
  tag, no allowlist change.
- **Current screen** = the tile whose vertical center is nearest the canvas
  viewport's center. Derived client-side; never server state (a round-trip
  per scroll frame is absurd, and ADR-0002 islands are view-state-only).
- **One vocabulary**: `.on` marks the current screen on BOTH the thumb
  (already accent-styled) and the tile (new rule, same accent tokens).
- **Thumb contract**: `href="#dvt-views--<id>"` — the tile id IS the link.
  No data attributes. `hx-boost` skips local anchors, so JS-off degrades to
  native fragment scroll. The island preventDefaults and smooth-centers.
- **Behavior change**: views-strip thumb click was pin-to-chat-context
  (`contextHref` GET). It becomes navigation. Pinning stays on each tile's
  hover toolbar — no feature lost, and a filmstrip that mutates chat context
  on click cannot also be a navigator.

## Edits

1. `designs/arxa-studio/ui/views/main_shell/shared/widgets/design_viewer.html`
   — filmstrip macro: anchor → `#dvt-views--<id>`, drop hx-* attrs, rewrite
   the macro comment.
2. `skills/arxa-designer/runtime/vendor/canvas.js` — strip-sync: rAF scroll
   detection → mark `.on` both sides + keep thumb in view; delegated strip
   click → smooth-center tile, latch until scrollend. Re-marks on every
   `htmx.onLoad` scan (morphs wipe client classes).
3. `designs/arxa-studio/assets/css/viewer.css` + `app.css` — `.dv-tile.on`
   accent outline beside the existing `.dv-thumb.on` rules (both files carry
   the pair deliberately).
4. `skills/arxa-designer/docs/adr/0002-zero-custom-client-js-boundary.md`
   — amend canvas.js charter with strip-sync; fix its stale header if needed.
5. `_integration_viewer.md` — update filmstrip contract note if it documents
   thumb-click-pins.

## Verification

Serve arxa-studio on a spare port (read-only GETs + view-state JS only;
never the user's 4319 / `~/.arxa/current`). Lens `--expect` asserts:
initial state has exactly one `.dv-thumb.on` + one `.dv-tile.on` with equal
ids; clicking the last thumb moves `.on` on both sides and scrolls the
canvas; programmatic scroll-to-bottom moves `.on` without a click. Negative:
detection asserts must fail if `.on` marking is removed.
