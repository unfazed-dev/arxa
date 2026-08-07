// variant-panel.tsx — server-driven tweaks/variant panel (replaces variant-panel.html).
// Zero JavaScript: the open/close toggle is plain <details>, and every
// control is a plain GET link or GET form. Render once near the end of a
// shell or base layout (copy this file + keep the <style> block, or hoist
// the rules into app.css):
//
//   import { VariantPanel } from '../widgets/variant-panel.tsx';
//   <VariantPanel variants={variants} prefs={prefs} />
//
// How it works — the server owns the state (State Playbook: cookies = small
// prefs). A control navigates to a /prefs/* endpoint; the endpoint sets the
// prefs cookie and answers HX-Refresh, so htmx reloads the page and the
// server re-renders it with the new variant/accent. Register the endpoints
// in app.routes.js and implement them in a viewmodel:
//
//   ['GET', '/prefs/variant', prefs.setVariant],
//   ['GET', '/prefs/accent',  prefs.setAccent],
//
//   export const setVariant = (c, h) => {
//     h.setPrefs(c, { variant: c.req.query('id') ?? 'default' });
//     return h.refresh(c);                       // HX-Refresh
//   };
//   export const setAccent = (c, h) => {
//     h.setPrefs(c, { accent: c.req.query('value') ?? 'blueviolet' });
//     return h.refresh(c);
//   };
//
// Expected endpoints (GET; query params as shown):
//   /prefs/variant?id=<variant-id>   — picks the design variant
//   /prefs/accent?value=<color>      — picks the accent
// Each sets a cookie (h.setPrefs) and answers HX-Refresh (h.refresh). Note:
// boosted requests carry HX-Request, so h.refresh is right; if you also
// serve these URLs unboosted, branch and 303-redirect back instead.
// The runtime merges cookie prefs into every render context, so views read
// prefs.variant / prefs.accent directly (see the active-state markup).
//
// Props expected by the example markup below:
//   variants: [{ id: 'a', label: 'A — Warm', current: true }, …]
//   (supply it from the viewmodel; prefs.variant marks `current`.)
// The <details> element is the whole toggle mechanism — its body is hidden
// when closed, no script, no checkbox hack.
import type { FC } from 'hono/jsx';

const CSS = `
.variant-panel {
  --vp-bg: #17181c;
  --vp-fg: #e8eaed;
  --vp-dim: #9aa0a6;
  --vp-accent: var(--accent, blueviolet);
  --vp-radius: 12px;
  position: fixed;
  right: 16px;
  bottom: 16px;
  z-index: 90;
  font-family: ui-sans-serif, system-ui, sans-serif;
  font-size: 13px;
  color: var(--vp-fg);
}
.variant-panel__toggle {
  list-style: none;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  border-radius: 999px;
  background: var(--vp-bg);
  border: 1px solid color-mix(in srgb, var(--vp-fg) 18%, transparent);
  box-shadow: 0 8px 24px rgba(0, 0, 0, .3);
  font-weight: 600;
  float: right;
}
.variant-panel__toggle::-webkit-details-marker { display: none; }
.variant-panel__toggle::before {
  content: "";
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--vp-accent);
}
.variant-panel__body {
  clear: both;
  margin-top: 8px;
  min-width: 220px;
  padding: 14px;
  border-radius: var(--vp-radius);
  background: var(--vp-bg);
  border: 1px solid color-mix(in srgb, var(--vp-fg) 18%, transparent);
  box-shadow: 0 12px 40px rgba(0, 0, 0, .35);
}
.variant-panel__title { margin: 0 0 8px; font-weight: 700; }
.variant-panel__variants { display: flex; flex-direction: column; gap: 2px; }
.variant-panel__variant {
  display: block;
  padding: 6px 8px;
  border-radius: 8px;
  color: var(--vp-fg);
  text-decoration: none;
}
.variant-panel__variant:hover { background: color-mix(in srgb, var(--vp-fg) 10%, transparent); }
.variant-panel__variant.is-active {
  background: color-mix(in srgb, var(--vp-accent) 22%, transparent);
  font-weight: 700;
}
.variant-panel__empty { color: var(--vp-dim); margin: 0; }
.variant-panel__form {
  display: flex;
  gap: 6px;
  align-items: end;
  margin: 12px 0 0;
  padding-top: 12px;
  border-top: 1px solid color-mix(in srgb, var(--vp-fg) 14%, transparent);
}
.variant-panel__form label { display: flex; flex-direction: column; gap: 4px; flex: 1; color: var(--vp-dim); }
.variant-panel__form select { font: inherit; padding: 4px 6px; }
.variant-panel__form button {
  font: inherit;
  font-weight: 600;
  padding: 5px 10px;
  border: 0;
  border-radius: 8px;
  background: var(--vp-accent);
  color: #fff;
  cursor: pointer;
}
`;

interface Variant {
  id: string;
  label: string;
  current?: boolean;
}

interface VariantPanelProps {
  variants?: Variant[];
  prefs?: { accent?: string };
}

export const VariantPanel: FC<VariantPanelProps> = ({ variants = [], prefs = {} }) => (
  <>
    {/* page-local styles, zero-JS (hoist into app.css if preferred) */}
    <style dangerouslySetInnerHTML={{ __html: CSS }} />

    <details class="variant-panel">
      <summary class="variant-panel__toggle">Variants</summary>
      <div class="variant-panel__body">
        <p class="variant-panel__title">Design variants</p>
        <nav class="variant-panel__variants" aria-label="Design variants">
          {variants.length > 0 ? (
            variants.map((v) => (
              <a
                class={`variant-panel__variant${v.current ? ' is-active' : ''}`}
                href={`/prefs/variant?id=${encodeURIComponent(v.id)}`}
                aria-current={v.current ? 'true' : undefined}
                key={v.id}
              >
                {v.label}
              </a>
            ))
          ) : (
            <p class="variant-panel__empty">
              No variants in props — this is the example markup; supply a{' '}
              <code>variants</code> list (see header).
            </p>
          )}
        </nav>
        <form class="variant-panel__form" method="get" action="/prefs/accent">
          <label>
            Accent
            <select name="value">
              <option value="blueviolet" selected={prefs.accent === 'blueviolet'}>Iris</option>
              <option value="teal" selected={prefs.accent === 'teal'}>Lagoon</option>
              <option value="tomato" selected={prefs.accent === 'tomato'}>Signal</option>
            </select>
          </label>
          <button type="submit">Apply</button>
        </form>
      </div>
    </details>
  </>
);

export default VariantPanel;
