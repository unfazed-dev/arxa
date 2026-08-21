# Deliberately absent capabilities

These are JS-bound by nature — do not recreate them:
- **design-canvas pan/zoom** → use `starter-partials/artboards.tsx` (static
  side-by-side comparison surface)
- **animation timeline engine**, **animated video**, **video export** → use
  scroll-driven CSS motion studies (`starter-partials/motion.css`)
- **image-slot drag/drop** → use a static placeholder plus the artifact's
  `assets/` folder

Slide decks and printable documents are out of scope. This skill designs
applications.
