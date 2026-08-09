// base.tsx — root layout component (replaces ui/common/base.html).
// Wraps every surface with <html><head><body>. Child views extend this by
// passing title/locale/accent and their content as children; the head_extra
// block becomes the headExtra prop.
import { raw } from 'hono/utils/html';
import { Fragment, type FC, type Child } from 'hono/jsx';
import { inspectAttributes } from '../widgets/common/studio_primitives/widgets.tsx';

// htmx 4 config. v2's responseHandling has no meta-config equivalent in v4 —
// the per-status rules live on <body> as hx-status:<pattern> attributes (see
// below). `transitions` is the renamed globalViewTransitions. v4 turns OFF
// v2's attribute inheritance by default; without implicitInheritance the
// body's hx-boost/hx-sync/hx-status would apply to nothing inside it.
// allowEval and historyRestoreAsHxRequest are gone entirely: v4 evaluates
// hx-on/hx-confirm expressions through htmx.initSecurity() Function
// constructors (the only switch, and it is custom JS — banned here by
// ADR-0002); this artifact never uses hx-on, so the eval path stays dead by
// convention instead.
const HTMX_CONFIG = '{"transitions":true,"implicitInheritance":true}';

// Cache-busted vendor script URL (content hash from worker_shim boot).
const vendorSrc = (name: string) => {
  const rev = (globalThis as any).__vendorRev?.[name];
  return `/assets/vendor/${name}${rev ? `?rev=${rev}` : ''}`;
};

// The v2 responseHandling rules, restated for htmx 4: hx-status:<pattern> on
// <body> (inherited by every request source). Patterns try exact → "40x" →
// "4xx", first hit wins. 404 and 5xx retarget into #toasts instead of
// clobbering the panel that made the request — the server sends a toast
// fragment, the good panel stays. 422 escapes the 4xx blackout (empty merge)
// so form validation renders where the form is. 204/304 stay no-swap via the
// default noSwap config. Colon attributes are not valid JSX names, so the
// spread form it is.
const HTMX_RESPONSE_RULES = {
  'hx-status:404': '{"target":"#toasts","swap":"innerHTML"}',
  'hx-status:5xx': '{"target":"#toasts","swap":"innerHTML"}',
  'hx-status:4xx': '{"swap":"none"}',
  'hx-status:422': '{}',
};

interface BaseProps {
  title?: string;
  locale?: string;
  accent?: string;
  theme?: string;
  font?: string;
  headExtra?: Child;
  children?: Child;
}

const Base: FC<BaseProps> = ({
  title = 'appbox',
  locale = 'en',
  accent = 'cyan',
  theme = 'light',
  font = 'lexend',
  headExtra,
  children,
}) => (
  <Fragment>
    {raw('<!doctype html>')}
    <html lang={locale}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="htmx-config" content={HTMX_CONFIG} />
        <title {...inspectAttributes('base:title', { role: 'text' })}>{title}</title>
        <script
          src="/assets/vendor/htmx4.min.js"
          integrity="sha384-6lyVbhrs13b9z7mLOpt/N6R76rtkEBWgCjAXRs/DSWyi2AMnQSs10ijWk+PI8n7W"
          crossorigin="anonymous"
        ></script>
        {/* htmx 4: morph is a core swap style (outerMorph), not an extension.
            Morphing exists for one reason: viewer screen iframes live INSIDE
            swap targets, and a replace-style swap destroys them, so every
            interaction would re-fetch all frames and discard whatever the
            user had navigated to inside a live tile. The v2 preload/head-
            support extensions are gone — hx-ext does not exist in v4, the
            studio never used hx-preload, and v4 core lifts <title> itself. */}
        <script src={vendorSrc('canvas.js')} defer></script>
        <script src={vendorSrc('drag.js')} defer></script>
        <script src={vendorSrc('reveal.js')} defer></script>
        <link rel="stylesheet" href="/ui/styles/common/styles.css" />
        <link rel="stylesheet" href="/ui/styles/studio_application_hub/styles.css" />
        <link rel="stylesheet" href="/ui/styles/studio_dashboard_shell/styles.css" />
        <link rel="stylesheet" href="/ui/styles/studio_startup_shell/styles.css" />
        {headExtra}
      </head>
      <body hx-boost="true" hx-sync="this:replace" {...HTMX_RESPONSE_RULES}>
        <div id="app" data-theme={theme} data-accent={accent} data-font={font} {...inspectAttributes('base:app-root', { role: 'group' })}>
          {children}
        </div>
        {/* OOB/retarget tray. aria-live polite: a toast swapped in here is
            announced but must not interrupt (Material snackbar rule). */}
        <div id="toasts" aria-live="polite" aria-atomic="true"></div>
      </body>
    </html>
  </Fragment>
);

export default Base;
