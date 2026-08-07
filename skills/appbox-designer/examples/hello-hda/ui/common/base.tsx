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
        {/* htmx 4 config: transitions (renamed from globalViewTransitions). */}
        <meta name="htmx-config" content='{"transitions":true}' />
        <title>{title}</title>
        <script
          src="/assets/vendor/htmx4.min.js"
          integrity="sha384-6lyVbhrs13b9z7mLOpt/N6R76rtkEBWgCjAXRs/DSWyi2AMnQSs10ijWk+PI8n7W"
          crossorigin="anonymous"
        ></script>
        <link rel="stylesheet" href="/assets/css/app.css" />
      </head>
      <body hx-boost="true" hx-sync="this:replace">
        <div id="app" style={`--accent: ${accent}`}>
          {children}
        </div>
        <div id="toasts"></div>
      </body>
    </html>
  </Fragment>
);

export default Base;
