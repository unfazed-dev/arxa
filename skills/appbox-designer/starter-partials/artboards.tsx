// artboards.tsx — static side-by-side comparison page (full-page example,
// replaces artboards.html).
// The htmx-edition replacement for the upstream design-canvas (ADR-0002:
// the canvas's pan/zoom/reorder is JS-bound and intentionally dropped).
// Zero JavaScript: a labeled grid of .artboard figures plus a CSS :target
// focus mode.
//
// Usage
// -----
// This is a complete page component. NOTE: unlike the old artboards.html it
// no longer opens standalone straight off disk — it is rendered through the
// design server like every view. The "server-driven version" the old comment
// described is now simply the component's props: the viewmodel supplies
// `artboards` and the loop below stamps the figures:
//
//   artboards: [{ label: 'Home v1', content: <HomeV1 /> }, …]
//
// Swap each artboard's `content` for a real screen (a frames/ device frame,
// a view fragment, static markup). When `content` is omitted a demo
// placeholder screen renders. Screens render at natural size; the thumbnail
// scale is --ab-thumb.
//
// Focus mode: every artboard is wrapped in <a href="#ab-N">. Clicking makes
// the figure the :target — CSS turns it into a full-viewport dimmed overlay
// with the canvas at natural size (scrollable if oversized). Each overlay
// carries an explicit <a href="#">close</a>; the bare "#" clears :target.
// body:has(.artboard:target) locks background scroll where :has() exists.
//
// Honest limitation (be straight with users): this is a comparison page, not
// a canvas — no pan, no free zoom, no drag-reorder, no comment pins. The
// nearest upgrades within the boundary: browser zoom inside the focused
// overlay, and reordering = editing props order (server-side). Anything
// richer is design-canvas territory, dropped per ADR-0002.
import { raw } from 'hono/utils/html';
import { Fragment, type FC, type Child } from 'hono/jsx';

const CSS = `
    :root {
      --ab-bg: #f4f4f6;
      --ab-fg: #17181c;
      --ab-dim: #6b7280;
      --ab-thumb: .4;             /* thumbnail zoom (canvas is 402×874) */
      --ab-overlay: rgb(8 10 14 / .85);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--ab-bg);
      color: var(--ab-fg);
      font-family: ui-sans-serif, system-ui, sans-serif;
    }
    .page-head { padding: 32px 32px 24px; }
    .page-head h1 { margin: 0 0 6px; font-size: 22px; }
    .page-head p { margin: 0; color: var(--ab-dim); font-size: 14px; }

    .artboards {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(min(100%, 300px), 1fr));
      gap: 28px;
      padding: 0 32px 48px;
    }
    .artboard { margin: 0; display: flex; flex-direction: column; gap: 8px; }
    .artboard__open {
      display: block;
      height: 380px;
      overflow: hidden;
      border-radius: 12px;
      border: 1px solid rgb(0 0 0 / .08);
      background: #fff;
    }
    @supports not (zoom: 1) {
      /* no zoom: thumbs can't shrink — let the cell scroll instead */
      .artboard__open { overflow: auto; }
    }
    .artboard__canvas {
      display: block;
      width: 402px;
      height: 874px;
      zoom: var(--ab-thumb);
    }
    .artboard figcaption { font-size: 14px; font-weight: 600; }
    .artboard__close { display: none; }

    /* ---- zero-JS focus mode: the figure itself becomes the overlay ---- */
    .artboard:target {
      position: fixed;
      inset: 0;
      z-index: 50;
      margin: 0;
      padding: 24px;
      display: grid;
      place-items: center;
      align-content: center;
      gap: 14px;
      background: var(--ab-overlay);
      backdrop-filter: blur(6px);
      -webkit-backdrop-filter: blur(6px);
    }
    .artboard:target .artboard__open {
      pointer-events: none;         /* already focused; don't re-navigate */
      height: auto;
      max-height: 82vh;
      overflow: auto;               /* oversized screens stay reachable */
      border: 0;
      border-radius: 18px;
      background: transparent;
    }
    .artboard:target .artboard__canvas { zoom: 1; }
    .artboard:target figcaption { color: #fff; font-size: 15px; }
    .artboard:target .artboard__close {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      position: fixed;
      top: 18px;
      right: 22px;
      width: 40px;
      height: 40px;
      border-radius: 50%;
      background: rgb(255 255 255 / .12);
      color: #fff;
      font-size: 20px;
      text-decoration: none;
    }
    @supports selector(:has(*)) {
      body:has(.artboard:target) { overflow: hidden; }
    }
    @media (prefers-reduced-motion: no-preference) {
      .artboard:target { animation: ab-focus-in .18s ease-out; }
      @keyframes ab-focus-in { from { opacity: 0; } }
    }

    /* demo placeholder screens (replace with real screens via content) */
    .demo { padding: 20px; display: flex; flex-direction: column; gap: 14px; }
    .demo__status { height: 22px; border-radius: 6px; background: rgb(0 0 0 / .12); width: 55%; }
    .demo__hero { height: 220px; border-radius: 16px; background: var(--demo-hue, #8b5cf6); }
    .demo__line { height: 16px; border-radius: 5px; background: rgb(0 0 0 / .1); }
    .demo__line--short { width: 62%; }
    .demo__card { height: 96px; border-radius: 12px; background: rgb(0 0 0 / .06); }
    .demo--2 { --demo-hue: #0d9488; }
    .demo--3 { --demo-hue: #ea580c; }
    .demo--4 { --demo-hue: #2563eb; }
`;

interface Artboard {
  label: string;
  content?: Child;
}

interface ArtboardsProps {
  artboards: Artboard[];
  title?: string;
  lede?: Child;
  locale?: string;
}

// Demo placeholder (used when an artboard has no `content`); the hue cycles
// through the demo--N modifiers like the original hardcoded figures.
const DemoScreen: FC<{ index: number }> = ({ index }) => {
  const mod = ['', 'demo--2', 'demo--3', 'demo--4'][index % 4];
  return (
    <span class={`demo${mod ? ` ${mod}` : ''}`}>
      <span class="demo__status"></span>
      <span class="demo__hero"></span>
      <span class="demo__line"></span>
      <span class="demo__line demo__line--short"></span>
      <span class="demo__card"></span>
      <span class="demo__card"></span>
    </span>
  );
};

const Artboards: FC<ArtboardsProps> = ({
  artboards,
  title = 'Onboarding — variant comparison',
  lede,
  locale = 'en',
}) => (
  <Fragment>
    {raw('<!doctype html>')}
    <html lang={locale}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Artboards — screen comparison</title>
        {/* page-local styles (hoist into app.css if the page ships) */}
        <style dangerouslySetInnerHTML={{ __html: CSS }} />
      </head>
      <body>
        <header class="page-head">
          <h1>{title}</h1>
          <p>
            {lede ?? (
              <>
                {artboards.length} candidate screens, side by side. Click one to
                focus it; the overlay is pure <code>:target</code> CSS — no
                JavaScript anywhere on this page.
              </>
            )}
          </p>
        </header>

        <main class="artboards">
          {artboards.map((ab, i) => (
            <figure class="artboard" id={`ab-${i + 1}`} key={i}>
              <a class="artboard__open" href={`#ab-${i + 1}`} aria-label={`Focus ${ab.label}`}>
                <span class="artboard__canvas">
                  {ab.content ?? <DemoScreen index={i} />}
                </span>
              </a>
              <figcaption data-screen-label={ab.label}>{ab.label}</figcaption>
              <a class="artboard__close" href="#" aria-label="Close focus view">×</a>
            </figure>
          ))}
        </main>
      </body>
    </html>
  </Fragment>
);

export default Artboards;
