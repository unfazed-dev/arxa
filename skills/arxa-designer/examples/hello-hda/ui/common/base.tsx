// base.tsx — layout component wrapping all pages.
// Replaces ui/common/base.html ({% extends "base.html" %}).
import { raw } from 'hono/utils/html';
import { Fragment, type FC, type Child } from 'hono/jsx';

interface BaseProps {
  title?: string;
  locale?: string;
  children?: Child;
}

const Base: FC<BaseProps> = ({
  title = 'hello-hda',
  locale = 'en',
  children,
}) => (
  <Fragment>
    {raw('<!doctype html>')}
    <html data-arxa-id="ui-common-base-e1" lang={locale}>
      <head data-arxa-id="ui-common-base-e2">
        <meta data-arxa-id="ui-common-base-e3" charset="utf-8" />
        <meta data-arxa-id="ui-common-base-e4" name="viewport" content="width=device-width, initial-scale=1" />
        {/* htmx 4 config: transitions (renamed from globalViewTransitions);
            implicitInheritance restores v2's attribute inheritance (v4 turns
            it off — without it the body's hx-boost/hx-sync reach nothing);
            noSwap restates the old responseHandling blackout — 4xx/5xx never
            clobber a panel (204/304 are v4 defaults). v4 validates forms with
            reportValidity() natively (reportValidityOfForms is gone), and
            allowEval/historyRestoreAsHxRequest have no v4 equivalent — the
            eval switch is htmx.initSecurity(), custom JS this artifact bans
            (ADR-0002); hx-on is simply never used. */}
        <meta data-arxa-id="ui-common-base-e5" name="htmx-config" content='{"transitions":true,"implicitInheritance":true,"noSwap":[204,304,"4xx","5xx"]}' />
        <title data-arxa-id="ui-common-base-e6">{title}</title>
        <script data-arxa-id="ui-common-base-e7"
          src="/assets/vendor/htmx4.min.js"
          integrity="sha384-6lyVbhrs13b9z7mLOpt/N6R76rtkEBWgCjAXRs/DSWyi2AMnQSs10ijWk+PI8n7W"
          crossorigin="anonymous"
        ></script>
        {/* the palette plane (docs/plans/arxa-palette-plane-universal.md):
            tokens first — the corpus reads only these vars; palette.js owns
            the attribute + theme-color live; the serve-time machinery stamps
            data-palette and injects the generated sheet links. */}
        <meta data-arxa-id="ui-common-base-e11" name="theme-color" content="#007EA7" />
        <link data-arxa-id="ui-common-base-e12" rel="stylesheet" href="/assets/css/tokens.css" />
        <link data-arxa-id="ui-common-base-e8" rel="stylesheet" href="/assets/css/app.css" />
        <script data-arxa-id="ui-common-base-e13" src="/assets/app/palette.js" defer></script>
        {/* font.js owns the font plane (grilled 2026-09-13): the per-role
            data-font-* attributes, the ONE css2 link, memory + broadcast. */}
        <script data-arxa-id="ui-common-base-e13f" src="/assets/app/font.js" defer></script>
      </head>
      {/* hx-status:422 escapes the 4xx no-swap blackout (empty merge) so a
          validation response swaps in place — the old responseHandling
          `{"code":"422","swap":true}` rule restated for htmx 4. */}
      <body hx-boost="true" hx-sync="this:replace" {...{ 'hx-status:422': '{}' }}>
        <div data-arxa-id="ui-common-base-e9" id="app">
          {children}
        </div>
        <div data-arxa-id="ui-common-base-e10" id="toasts"></div>
      </body>
    </html>
  </Fragment>
);

export default Base;
