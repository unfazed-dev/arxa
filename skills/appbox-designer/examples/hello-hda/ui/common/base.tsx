// base.tsx — layout component wrapping all pages.
// Replaces ui/common/base.html ({% extends "base.html" %}).
import { raw } from 'hono/utils/html';
import { Fragment, type FC, type Child } from 'hono/jsx';

interface BaseProps {
  title?: string;
  locale?: string;
  accent?: string;
  children?: Child;
}

const Base: FC<BaseProps> = ({
  title = 'hello-hda',
  locale = 'en',
  accent = 'blueviolet',
  children,
}) => (
  <Fragment>
    {raw('<!doctype html>')}
    <html lang={locale}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        {/* htmx 4 config: transitions (renamed from globalViewTransitions);
            implicitInheritance restores v2's attribute inheritance (v4 turns
            it off — without it the body's hx-boost/hx-sync reach nothing);
            noSwap restates the old responseHandling blackout — 4xx/5xx never
            clobber a panel (204/304 are v4 defaults). v4 validates forms with
            reportValidity() natively (reportValidityOfForms is gone), and
            allowEval/historyRestoreAsHxRequest have no v4 equivalent — the
            eval switch is htmx.initSecurity(), custom JS this artifact bans
            (ADR-0002); hx-on is simply never used. */}
        <meta name="htmx-config" content='{"transitions":true,"implicitInheritance":true,"noSwap":[204,304,"4xx","5xx"]}' />
        <title>{title}</title>
        <script
          src="/assets/vendor/htmx4.min.js"
          integrity="sha384-6lyVbhrs13b9z7mLOpt/N6R76rtkEBWgCjAXRs/DSWyi2AMnQSs10ijWk+PI8n7W"
          crossorigin="anonymous"
        ></script>
        <link rel="stylesheet" href="/assets/css/app.css" />
      </head>
      {/* hx-status:422 escapes the 4xx no-swap blackout (empty merge) so a
          validation response swaps in place — the old responseHandling
          `{"code":"422","swap":true}` rule restated for htmx 4. */}
      <body hx-boost="true" hx-sync="this:replace" {...{ 'hx-status:422': '{}' }}>
        <div id="app" style={`--accent: ${accent}`}>
          {children}
        </div>
        <div id="toasts"></div>
      </body>
    </html>
  </Fragment>
);

export default Base;
