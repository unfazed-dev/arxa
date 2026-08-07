// base.tsx — root layout component (replaces ui/common/base.html).
// Wraps every surface with <html><head><body>. Child views extend this by
// passing title/locale/accent and their content as children; the head_extra
// block becomes the headExtra prop.
import { raw } from 'hono/utils/html';
import { Fragment, type FC, type Child } from 'hono/jsx';

// htmx responseHandling (first match wins): 404 and 5xx retarget into #toasts
// instead of clobbering the panel that made the request — the server sends a
// toast fragment, the good panel stays. The blanket [45].. rule is swap:false
// for every other error. Config is the only declarative channel here: with
// allowEval:false the hx-on escape hatch is dead (ADR-0002, no client JS).
// 422 still swaps in place so form validation renders where the form is.
const HTMX_CONFIG =
  '{"allowEval":false,"allowScriptTags":false,"globalViewTransitions":true,"historyRestoreAsHxRequest":false,"responseHandling":[{"code":"204","swap":false},{"code":"[23]..","swap":true},{"code":"422","swap":true},{"code":"404","swap":true,"error":true,"target":"#toasts","swapOverride":"innerHTML"},{"code":"5..","swap":true,"error":true,"target":"#toasts","swapOverride":"innerHTML"},{"code":"[45]..","swap":false,"error":true},{"code":"...","swap":true}]}';

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
        <title>{title}</title>
        <script
          src="/assets/vendor/htmx.min.js"
          integrity="sha384-H5SrcfygHmAuTDZphMHqBJLc3FhssKjG7w/CeCpFReSfwBWDTKpkzPP8c+cLsK+V"
          crossorigin="anonymous"
        ></script>
        <script
          src="/assets/vendor/preload.min.js"
          integrity="sha384-PRIcY6hH1Y5784C76/Y8SqLyTanY9rnI3B8F3+hKZFNED55hsEqMJyqWhp95lgfk"
          crossorigin="anonymous"
        ></script>
        <script
          src="/assets/vendor/head-support.js"
          integrity="sha384-cvMqHzjCJsOHgGuyB3sWXaUSv/Krm0BdzjuI1rtkjCbL1l1oHJx+cHyVRJhyuEz0"
          crossorigin="anonymous"
        ></script>
        {/* idiomorph: the `morph` swap style. Loads AFTER htmx — it registers
            as an extension. Morphing exists for one reason: viewer screen
            iframes live INSIDE swap targets, and a replace-style swap destroys
            them, so every interaction would re-fetch all frames and discard
            whatever the user had navigated to inside a live tile. */}
        <script
          src="/assets/vendor/idiomorph-ext.min.js"
          integrity="sha384-SsScJKzATF/w6suEEdLbgYGsYFLzeKfOA6PY+/C5ZPxOSuA+ARquqtz/BZz9JWU8"
          crossorigin="anonymous"
        ></script>
        <script src="/assets/vendor/canvas.js" defer></script>
        <script src="/assets/vendor/drag.js" defer></script>
        <script src="/assets/vendor/reveal.js" defer></script>
        <link rel="stylesheet" href="/assets/css/fonts.css" />
        <link rel="stylesheet" href="/assets/css/app.css" />
        <link rel="stylesheet" href="/assets/css/theme.css" />
        <link rel="stylesheet" href="/assets/css/intake.css" />
        <link rel="stylesheet" href="/assets/css/design.css" />
        <link rel="stylesheet" href="/assets/css/viewer.css" />
        <link rel="stylesheet" href="/assets/css/chrome.css" />
        <link rel="stylesheet" href="/assets/css/panels.css" />
        <link rel="stylesheet" href="/assets/css/widgets.css" />
        <link rel="stylesheet" href="/assets/css/composer.css" />
        <link rel="stylesheet" href="/assets/css/build.css" />
        <link rel="stylesheet" href="/assets/css/scaffold.css" />
        <link rel="stylesheet" href="/assets/css/appshell.css" />
        <link rel="stylesheet" href="/assets/css/error_surface.css" />
        {headExtra}
      </head>
      <body hx-boost="true" hx-sync="this:replace" hx-ext="head-support,preload,morph">
        <div id="app" data-theme={theme} data-accent={accent} data-font={font}>
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
