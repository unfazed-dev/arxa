// screen_stub_view.tsx — Stand-in render of a client design screen (replaces
// screen_stub_view.html). Served as the iframe document on the evidence canvas.
// In the shipped app this src is the designer artifact the daemon serves; here
// it is an honest labelled stub.
//
// appbox:provenance
//   generator: app-box  licence: free  project: 662368770980
//   Built with app-box (free tier) — https://appbox.dev

import { Fragment, type FC, type Child } from 'hono/jsx';
import { raw } from 'hono/utils/html';
import { inspectAttrs, Label, Heading, Txt } from '../../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// Cache-busted vendor script URL (content hash from worker_shim boot).
const vendorSrc = (name: string) => {
  const rev = (globalThis as any).__vendorRev?.[name];
  return `/assets/vendor/${name}${rev ? `?v=${rev}` : ''}`;
};

interface ScreenStubViewProps {
  translate: TFn;
  locale?: string;
  surface?: string;
  vp?: string;
  // The dynamic {% include partial %} becomes a pre-rendered Child prop: the
  // server resolves the project screen partial and passes the rendered content.
  partial?: Child;
  still?: boolean;
  embed?: boolean;
  inspect?: boolean;
  theme?: string;
  accent?: string;
  font?: string;
  width?: number;
  kind?: string;
  themeOverride?: string;
  walk?: boolean;
  [key: string]: unknown;
}

const ScreenStubView: FC<ScreenStubViewProps> = (props) => {
  // kimitail: pqs is computed but not rendered — carried so boosted navigation
  // inside the iframe preserves vp/embed/still/inspect/theme on every hop.
  const pqs = `?vp=${props.vp}${props.embed ? '&embed=1' : ''}${props.still ? '&still=1' : ''}${props.inspect ? '&inspect=1' : ''}${props.themeOverride ? `&theme=${props.themeOverride}` : ''}`;

  return (
    <Fragment>
      {raw('<!doctype html>')}
      <html lang={props.locale}>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title {...inspectAttrs('screen-stub:title', { role: 'text' })}>{props.surface} · {props.vp}</title>
          <link rel="stylesheet" href="/assets/css/fonts.css" />
          <link rel="stylesheet" href="/assets/css/app.css" />
          <link rel="stylesheet" href="/assets/css/theme.css" />
          {props.partial && (
            <Fragment>
              <link rel="stylesheet" href="/assets/css/appshell.css" />
              <link rel="stylesheet" href="/assets/css/media.css" />
            </Fragment>
          )}
          {/* Boosted MPA (ADR-0003) for frames the user can click (live tile,
              proto lens). `still` frames are canvas tiles: interactive in place
              but navigation inert via canvas.js, so they stay script-free.
              htmx 4 `transitions` animates the body swap with zero JS and no
              hx-on is used (ADR-0002 no-custom-JS — v4 has no allowEval). */}
          {!props.still && (
            <Fragment>
              {/* implicitInheritance: htmx4 stops inheriting attributes by
                  default — without it the body's hx-boost/hx-sync never reach
                  the partial's links and every click is a full document load,
                  which is exactly the reload this boosted stub exists to
                  avoid. */}
              <meta name="htmx-config" content='{"transitions":true,"implicitInheritance":true}' />
              <script src="/assets/vendor/htmx4.min.js" integrity="sha384-6lyVbhrs13b9z7mLOpt/N6R76rtkEBWgCjAXRs/DSWyi2AMnQSs10ijWk+PI8n7W" crossorigin="anonymous" />
            </Fragment>
          )}
        </head>
        {/* inspect MUST be a real conditional attribute, not an interpolated
            string — auto-escaping would break dataset.inspectArmed matching. */}
        <body
          class={`stub-body${props.embed ? ' stub-embed' : ''}`}
          data-surface={props.surface}
          {...(props.inspect ? { 'data-inspect-armed': 'true' } : {})}
          {...(!props.still ? { 'hx-boost': 'true', 'hx-sync': 'this:replace' } : {})}
        >
          <div id="app" data-theme={props.theme} data-accent={props.accent} data-font={props.font}>
            <div class="stub-screen" style={props.embed ? undefined : `max-width: ${props.width}px`} {...inspectAttrs('screen-stub:screen', { role: 'group' })}>
              {!props.embed && (
                <header class="stub-nav" data-el="nav-bar" data-inspect-role="nav" data-inspect-style="app bar · brand + links" data-inspect-motion="none" data-inspect-fn="Top-level navigation and brand for the screen">
                  {props.partial ? (
                    <Label name="screen-stub:brand" class="stub-brand">{props.translate('app.brand') as string}</Label>
                  ) : (
                    <Label name="screen-stub:brand" class="stub-brand">appbox</Label>
                  )}
                  {!props.partial && <Label name="screen-stub:nav-links" class="stub-nav-links">{props.translate(`stub.kind.${props.kind}`) as string}</Label>}
                </header>
              )}

              {props.partial ? props.partial : (
                <Fragment>
                  <section class="stub-hero" data-el="hero" data-inspect-role="hero" data-inspect-style="display headline + note" data-inspect-motion="reveal" data-inspect-fn="Names the screen being previewed">
                    <Heading name="screen-stub:hero-title" level={1}>{props.translate(`stub.kind.${props.kind}`) as string}</Heading>
                    <Txt name="screen-stub:preview-note">{props.translate('stub.previewNote') as string}</Txt>
                  </section>
                  <section class="stub-rows" {...inspectAttrs('screen-stub:rows', { role: 'group' })}>
                    {[1, 2, 3].map(i => (
                      <div class="stub-row" data-el={`list-item:Block ${i}`} data-inspect-role="list row" data-inspect-style="row · thumb + label" data-inspect-motion="none" data-inspect-fn="Content placeholder row" key={i}>
                        <span class="stub-thumb sm"></span>
                        <Label name="screen-stub:row-name" class="stub-row-name">{props.translate('stub.block', { kind: props.kind, i }) as string}</Label>
                      </div>
                    ))}
                  </section>
                </Fragment>
              )}

              {!props.embed && (
                <Label name="screen-stub:tag" class="stub-tag">{props.translate('stub.tag', { surface: props.surface, vp: props.vp }) as string}</Label>
              )}
            </div>
          </div>
          {props.inspect && <script src={vendorSrc('inspect.js')} />}
          {/* The flow-walk island, loaded ONLY on the current step of a walked
              flow row. The tap fires a flow edge in here, but the row that moves
              lives in the parent — a boundary markup cannot cross, so this is a
              named island (ADR-0002 amendment 2026-08-02). */}
          {props.walk && <script src={vendorSrc('flowwalk.js')} />}
        </body>
      </html>
    </Fragment>
  );
};

export default ScreenStubView;
