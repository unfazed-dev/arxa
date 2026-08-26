# styles/app — the four style modules (TL-12/18/19)

One module per style: `liquid-glass` (DEFAULT), `m3-expressive`,
`shadcn`, `custom`. Each carries:

- **SPEC.md** — the binding law: tokens, per-family truths, the eight
  dropdown laws, field indicator exclusivity, motion constants, gate
  contract. Compiled from energize's component-craft.md (R1–R9p) +
  component-specs.md — those stay the SSOT.
- **overlay.css** — the gate-proven style overlay (provenance: the ez-lab
  gallery, sweep 16/16). Link AFTER the artifact's base widgets.css.
  (`custom` has no overlay: the base skin IS the style.)
- **motion.css** — the interaction-recipe constants as custom props.

## Designer use (step 0b/9)

1. Read the artifact's selected style SPEC BEFORE authoring widgets —
   the default is **liquid-glass**; the artifact must still switch styles
   via `?style=` (all four, TL-16 artifact-side).
2. The widget library emits the FAMILY CLASS CONTRACT (.btn, .menu, .mi,
   .input, .select, .seg, .sw, ...) — overlays key on those classes; a
   widget that renames them de-styles in three styles at once.
3. Dark variants are token-level under `:root[data-theme="dark"]`;
   tri-state theme control (system/light/dark); swaps are INSTANT.
4. Gates: `gates/` (beside this tree) — geometry/icons/audit/interact,
   run per style × light/dark against the artifact's specimen route.

## Coverage law (TL-19)

The widget library MUST cover every family the artifact's registry touches,
styled per the SPEC truths and BEHAVING per the interaction recipe — same
constants, same five interaction classes. A style without full family
coverage is an incomplete style; a component without recipe behavior is an
approximation. design lint + the four gates are the proof.
