# JSX prototype patterns — the shard form the crew consumes

> The crew's deterministic stages (`capture_design`, `parse_jsx`, `capture_data`) read **source JSX
> shards**, not a bundled artifact. atlet (the reference fixture) proves the design is React 18 +
> Babel JSX decomposed into shards: a shell `<Name>.html` + one `<screen>.jsx` per screen +
> `data.jsx` (seed) + `icons.jsx` + `styles.css`. Match this form or the pipeline can't parse you.

## Architecture — sharded single-shell (the atlet-proven form)
```
design/
├── Atlet.html          # shell: React 18 + Babel CDN, the App state machine, mounts every screen
├── home.jsx            # one shard per screen (home/detail/otp/…)
├── detail.jsx
├── otp.jsx
├── data.jsx            # SEED_* arrays — the literal DB seed values
├── icons.jsx           # icon set (real svgs, never emoji)
├── styles.css          # shared styles
└── assets.jsx          # bespoke charts (Tier 2 — see assets-frontier.md)
```

**Why sharded, not one file:** `capture_design` captures each screen from its **own shard + shared
shards** (NOT the full bundle, which over-expands and mis-attributes components). One giant file
breaks per-screen capture.

**Why React+Babel CDN (not Vite/TS/bundled):** the crew reads *source* JSX. A bundled single-HTML
(Anthropic's `web-artifacts-builder` stack) is opaque to `parse_jsx`. Pinned versions only (see
`verification.md` for the pinned CDN URLs).

## The shell — every screen MUST mount on `window.*` (parity gate)
`parity.py --all` mounts each design component standalone: `window.Home`, `window.SignInView`, etc.,
with hardcoded `SCREEN_PROPS`. atlet's `Atlet.html` does this implicitly (Babel renders `App`); your
shell must do it **explicitly**. A screen not on `window` → parity throws a null-reference.

Shell skeleton:
```jsx
// Atlet.html — <script type="text/babel">
// …pinned React + Babel CDN…
// screens (one per shard, inlined or fetched — see "loading shards" below)
function App() {
  const [route, setRoute] = React.useState('home');
  // route → screen component; callbacks drive setRoute
  return route === 'home' ? <Home onOpenDetail={…} /> : <Detail … />;
}
// ⚠️ MANDATORY: mount every screen globally so parity.py --all can stand each up alone
Object.assign(window, { Home, Detail, Otp, SignIn, /* every screenFlow screen */ });
ReactDOM.createRoot(document.getElementById('root')).render(<App />);
```

### Loading shards — `file://` vs HTTP
Under `file://` the browser blocks external `<script src>` as cross-origin. Two valid paths:
1. **Inline all shards** into the shell's single `<script type="text/babel">` (default; "double-click
   to open"). Reference local images as base64 data URLs (no server assumed).
2. **External shards** only when the single file exceeds ~1000 lines — then ship a one-line server
   instruction (`python3 -m http.server`) and document the URL. The crew runs over HTTP during
   capture, so external shards are fine *for the pipeline*; inlining is the user-facing default.

## data.jsx — the seed (values; structure lives in data_model.json — Tier 2)
The crew's latest inversion: **values in `data.jsx`, structure in `data_model.json`**, joined by
`seedFrom.map`. Author both, internally consistent (see `data-model.md`).
```jsx
// data.jsx — seed VALUES
const SEED_WORKOUTS = [
  { id: 'w1', name: 'Morning Run', target: 5, unit: 'km', notes: 'easy pace', streak: 3 },
  // …
];
Object.assign(window, { SEED_WORKOUTS });
```
**Never** fabricate seed that looks real but isn't — honest placeholders ("TODO real seed") beat
fake-but-plausible numbers.

## Component decomposition — match what classify will bucket
Each visually-load-bearing or interactive node becomes a primitive `classify` resolves against
`catalogs/primitives-canonical.json`. Decompose so that:
- **Screens** = drawn pages (`Home`, `Detail`, `Otp`) → `pages[]` + `screenFlow[]`.
- **SharedComponents** = built-once units (`TabBar`, `WorkoutCard`, `StatHeader`) → `sharedComponents[]`.
- **Design-time tooling** (TweaksPanel, EDITMODE, accent-hue controls) → `skipped[]` reason
  `design-tool` for *primitives capture* (it is not a user-facing screen, so `classify` must not
  bucket it as a page). **But the TweaksPanel itself is MANDATORY** — the earlier "EXCLUDE it, don't
  build it" instruction was wrong and caused the atlet-v2 regression. A tweak controller that
  live-mutates the token CSS vars is how the designer + operator verify the system end-to-end.
  `designer_gate.check_tweak_panel` fails any iteration that omits it. The panel must expose **all
  four axes** (the closed set — every token group the design authors):
  1. **Color / theme** — accent hue swatches (`oklch`) + light/dark/auto → `--accent`, `--bone`, `--ink`.
  2. **Typography** — number font (mono/sans) + display pairing → `--mono`, `--display`.
  3. **Radius + spacing** — a slider exercising `--r-sm/md/lg/xl` + the `--space` density scale.
  4. **Motion** — reduce-motion toggle + speed multiplier → scales the rise/entrance durations.
  Each control calls `document.documentElement.style.setProperty(...)` from a token value, so the
  whole app recolors/reforms live. Detection the gate keys on: `setProperty` spanning ≥3 of these axes.

  ### The panel MUST have a visible, draggable trigger (the FAB)
  A panel that opens *only* via host `postMessage('__activate_edit_mode')` is **invisible in a
  standalone browser** (file:// or served) — the exact "where is the tweak controller? cannot see
  it at all" regression. The gate (`check_tweak_panel` → `_has_visible_trigger`) fails any panel
  without a user-reachable trigger. The canonical trigger is a **draggable floating button (FAB)**
  inspired by the roster FAB in `pixel_77/business/site`'s `GarrisonHero`:

  ```jsx
  const TweakFab = ({ open, setOpen, state, setState }) => {
    const fabRef = React.useRef(null);
    const dragRef = React.useRef(null);
    const FAB = 48, PAD = 10;
    const clamp = (x, y) => ({
      x: Math.min(Math.max(PAD, x), Math.max(PAD, window.innerWidth - FAB - PAD)),
      y: Math.min(Math.max(PAD, y), Math.max(PAD, window.innerHeight - FAB - PAD)),
    });
    const onDown = (e) => {
      const el = fabRef.current; const fr = el.getBoundingClientRect();
      dragRef.current = { id: e.pointerId, dx: e.clientX - fr.left, dy: e.clientY - fr.top,
        sx: e.clientX, sy: e.clientY, moved: false };
      el.setPointerCapture(e.pointerId);               // drag never loses the pointer
    };
    const onMove = (e) => {
      const d = dragRef.current; if (!d || e.pointerId !== d.id) return;
      if (!d.moved && Math.hypot(e.clientX - d.sx, e.clientY - d.sy) < 5) return; // dead-zone
      d.moved = true; setOpen(false);                   // dragging dismisses an open panel
      const el = fabRef.current; const p = clamp(e.clientX - d.dx, e.clientY - d.dy);
      el.style.left = p.x + 'px'; el.style.top = p.y + 'px';
      el.style.right = 'auto'; el.style.bottom = 'auto';
    };
    const onUp = (e) => {
      const d = dragRef.current; if (!d || e.pointerId !== d.id) return;
      const moved = d.moved; dragRef.current = null;
      if (!moved) setOpen(o => !o);                     // tap (no drag) → toggle
    };
    const rowDelay = (i, n) => open ? (i * 45) : ((n - 1 - i) * 25); // stagger open, reverse on close
    return (<React.Fragment>
      {open && <div className="tweak-fab-panel" role="group" aria-label="Design tweaks">
        {/* 4-axis rows — each with style={{transitionDelay: rowDelay(i,N)+'ms'}} */}
      </div>}
      <button ref={fabRef} className="tweak-fab" aria-expanded={open}
        aria-label={open ? 'Close tweaks' : 'Open tweaks — drag to move'}
        onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp}
        onPointerCancel={() => (dragRef.current = null)}>
        <span aria-hidden="true">{open ? '✕' : '⚙'}</span>
      </button>
    </React.Fragment>);
  };
  ```
  ```css
  .tweak-fab {
    position: fixed; bottom: 84px; right: 16px; width: 48px; height: 48px;
    border-radius: 50%; border: 1px solid var(--accent); background: var(--accent);
    color: var(--paper); cursor: grab; touch-action: none; z-index: 200; /* drag mustn't scroll */
    transition: filter .2s, transform .2s, box-shadow .3s;
  }
  .tweak-fab:hover { box-shadow: 0 0 0 6px var(--accent-soft); }
  .tweak-fab:active { cursor: grabbing; }
  .tweak-fab-panel { position: fixed; bottom: 142px; right: 16px; z-index: 200; /* token-driven */ }
  .tweak-fab-row {
    opacity: 0; transform: translateY(-8px);
    transition: opacity .26s ease, transform .26s cubic-bezier(.2,.7,.3,1);
  }
  .tweak-fab-wrap.open .tweak-fab-row { opacity: 1; transform: none; } /* stagger via inline delay */
  @media (prefers-reduced-motion: reduce) {
    .tweak-fab-row { transition-duration: .01s; transition-delay: 0s !important; }
  }
  ```

  The five hard parts (don't get these wrong):
  - **`setPointerCapture`** on pointerdown — without it the drag dies the moment the pointer
    leaves the button (it can't track `pointermove`/`pointerup` off-element).
  - **`touch-action: none`** on the button — without it, on touch devices the drag scrolls the
    page instead of moving the button.
  - **5px dead-zone** before `moved=true` — distinguishes a tap (toggle) from a drag (reposition).
    Without it every touch toggles AND drags.
  - **viewport clamp** — the FAB must never be droppable off-screen (lost forever). `clamp()` keeps
    it inside `[PAD, edge - FAB - PAD]`.
  - **staggered rows** — each row's `transitionDelay` is `i*45ms` opening, reversed on close, so the
    reveal reads as motion (the user asked for "staggered animation/motion"), not a flash. Collapse
    to ~0ms under `prefers-reduced-motion`.

  The gate detects this via a `.tweak-fab` / `tweak-trigger` class **or** a `pointerdown`/`onClick`
  handler on a fixed-position element. postMessage-only activation does NOT pass.

Callback props, not hardcoded state: screens take `onEnter` / `onClose` / `onTabChange` / `onOpen`.
TabBar/buttons/cards get `cursor: pointer` + hover feedback.

## Three technical red-lines (React+Babel, never violate)
1. **Never** `const styles = {...}` across components — name-collides. Use unique names:
   `const terminalStyles = {...}`, `const homeStyles = {...}`.
2. **Scopes don't share** across `<script type="text/babel">` blocks — export via
   `Object.assign(window, {...})`.
3. **Never** `scrollIntoView` — breaks container scroll; use other DOM scroll methods.

## Fixed-size content (the only place you self-scale)
Slides/video have a fixed canvas; auto-scale + letterbox via JS (not CSS `transform` alone, which
mis-handles overflow). Not relevant to most app prototypes (they're scrollable, not fixed-canvas).
