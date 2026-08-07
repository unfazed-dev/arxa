// browser-window.tsx — Chrome browser window (dark, macOS) (replaces browser-window.html).
// Pure HTML+CSS port of appbox-designer's starter-components/browser-window.jsx.
// Zero JavaScript. Styles live in frames.css (copy it to assets/css/).
//
// Usage — copy frames/ into your artifact (e.g. ui/widgets/frames/), then
// import and wrap your page content as children:
//
//   import { BrowserWindow } from './frames/browser-window.tsx';
//   <BrowserWindow frame={{ url: 'example.com' }}>
//     <p>Your page content…</p>
//   </BrowserWindow>
//
// frame options (all optional):
//   width    900                window width in px
//   height   600                window height in px
//   url      'example.com'      URL-bar text
//   tabs     [{ title: 'New Tab', active: true }]
//                               tab strip; set active: true on exactly one.
//                               The active tab gets the curved scoops.
//
// Slot: children land in `<div class="frame-screen">` (white page area,
// scrolls). <BrowserWindow /> with no children renders an empty, marked
// screen slot.
//
// Fragment note: frames are not views — a viewmodel can only fragment-render
// named exports of *_view.tsx files; to render the bare window from a
// viewmodel, re-export it from a view.
//
// Sibling exports: BrowserTrafficLights · BrowserTabBar · BrowserTab ·
// BrowserToolbar.
import type { FC, Child } from 'hono/jsx';
// Icon path note: canonical placement is ui/widgets/frames/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

export interface BrowserTabSpec {
  title?: string;
  glyph?: string;
  active?: boolean;
}

interface BrowserFrameOpts {
  width?: number;
  height?: number;
  url?: string;
  tabs?: BrowserTabSpec[];
}

interface BrowserWindowProps {
  frame?: BrowserFrameOpts;
  children?: Child;
}

export const BrowserWindow: FC<BrowserWindowProps> = ({ frame: f = {}, children }) => (
  <div
    class="browser-window"
    style={`--browser-w: ${f.width ?? 900}px; --browser-h: ${f.height ?? 600}px;`}
  >
    <BrowserTabBar frame={f} />
    <BrowserToolbar frame={f} />
    <div class="frame-screen browser-window__screen">
      {children ?? (
        // SLOT: page content goes here (see this file's header comment for usage)
        null
      )}
    </div>
  </div>
);

export default BrowserWindow;

export const BrowserTrafficLights: FC = () => (
  <span class="browser-traffic" aria-hidden="true">
    <span class="browser-traffic__dot browser-traffic__dot--close"></span>
    <span class="browser-traffic__dot browser-traffic__dot--min"></span>
    <span class="browser-traffic__dot browser-traffic__dot--max"></span>
  </span>
);

export const BrowserTabBar: FC<{ frame?: BrowserFrameOpts }> = ({ frame: f = {} }) => {
  const tabs = f.tabs ?? [{ title: 'New Tab', active: true }];
  return (
    <div class="browser-tabbar">
      <BrowserTrafficLights />
      <div class="browser-tabbar__tabs">
        {tabs.map((t, i) => <BrowserTab tab={t} key={i} />)}
      </div>
    </div>
  );
};

export const BrowserTab: FC<{ tab: BrowserTabSpec }> = ({ tab: t }) => (
  <div class={`browser-tab${t.active ? ' is-active' : ''}`}>
    {t.active && (
      <>
        <svg class="browser-tab__scoop browser-tab__scoop--left" width="8" height="10" viewBox="0 0 8 10" aria-hidden="true">
          <path d="M0 10C2 9 6 8 8 0V10H0Z" fill="currentColor" />
        </svg>
        <svg class="browser-tab__scoop browser-tab__scoop--right" width="8" height="10" viewBox="0 0 8 10" aria-hidden="true">
          <path d="M0 10C2 9 6 8 8 0V10H0Z" fill="currentColor" />
        </svg>
      </>
    )}
    <span class="browser-tab__icon" aria-hidden="true"><Icon name={t.glyph ?? 'globe'} size={14} /></span>
    <span class="browser-tab__title">{t.title ?? 'New Tab'}</span>
  </div>
);

export const BrowserToolbar: FC<{ frame?: BrowserFrameOpts }> = ({ frame: f = {} }) => (
  <div class="browser-toolbar">
    <span class="browser-toolbar__icon" aria-hidden="true"><Icon name="arrow-left" size={16} /></span>
    <div class="browser-toolbar__url">
      <span class="browser-toolbar__lock" aria-hidden="true"><Icon name="lock" size={12} /></span>
      <span class="browser-toolbar__url-text">{f.url ?? 'example.com'}</span>
    </div>
    <span class="browser-toolbar__icon" aria-hidden="true"><Icon name="refresh-cw" size={14} /></span>
  </div>
);
