// android.tsx — Android (Material 3) device frame (replaces android.html).
// Pure HTML+CSS port of appbox-designer's starter-components/android-frame.jsx.
// Zero JavaScript. Styles live in frames.css (copy it to assets/css/).
//
// Usage — copy frames/ into your artifact (e.g. ui/widgets/frames/), then
// import and wrap your screen content as children:
//
//   import { AndroidDevice, AndroidListItem } from './frames/android.tsx';
//   <AndroidDevice frame={{ title: 'Contacts' }}>
//     <AndroidListItem item={{ leading: 'A', headline: 'Ada Lovelace',
//                             supporting: 'Online now' }} />
//   </AndroidDevice>
//
// frame options (all optional):
//   width    412      device width in px        height  892   device height
//   dark     false    dark frame/status/gesture bar (the app bar keeps the
//                     light M3 surface, exactly like the React source)
//   time     '9:30'   status-bar clock
//   title    unset    when set, renders the top app bar
//   large    false    with title: large M3 headline variant
//   keyboard false    when true, renders the Gboard keyboard
//
// Slot: children land in `<div class="frame-screen">` (scrolls).
// <AndroidDevice /> with no children renders an empty, marked screen slot
// you can paste markup into directly.
//
// Fragment note: frames are not views — a viewmodel can only fragment-render
// named exports of *_view.tsx files; to render the bare frame from a
// viewmodel, re-export it from a view.
//
// Sibling exports: AndroidStatusBar · AndroidAppBar · AndroidListItem ·
// AndroidNavBar (gesture pill) · AndroidKeyboard.
// item = { headline, supporting?, leading? (text for the primary circle) }.
import type { FC, Child } from 'hono/jsx';
// Icon path note: canonical placement is ui/widgets/frames/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface AndroidFrameOpts {
  width?: number;
  height?: number;
  dark?: boolean;
  time?: string;
  title?: string;
  large?: boolean;
  keyboard?: boolean;
}

interface AndroidDeviceProps {
  frame?: AndroidFrameOpts;
  children?: Child;
}

export const AndroidDevice: FC<AndroidDeviceProps> = ({ frame: f = {}, children }) => (
  <div
    class={`android-device${f.dark ? ' android-device--dark' : ''}`}
    style={`--md-w: ${f.width ?? 412}px; --md-h: ${f.height ?? 892}px;`}
  >
    <AndroidStatusBar frame={f} />
    {f.title !== undefined && <AndroidAppBar frame={f} />}
    <div class="frame-screen android-device__screen">
      {children ?? (
        // SLOT: screen content goes here (see this file's header comment for usage)
        null
      )}
    </div>
    {f.keyboard && <AndroidKeyboard frame={f} />}
    <AndroidNavBar frame={f} />
  </div>
);

export default AndroidDevice;

export const AndroidStatusBar: FC<{ frame?: AndroidFrameOpts }> = ({ frame: f = {} }) => (
  <div class="android-status">
    <div class="android-status__time-box">
      <span class="android-status__time">{f.time ?? '9:30'}</span>
    </div>
    <div class="android-status__camera" aria-hidden="true"></div>
    <div class="android-status__icons" aria-hidden="true">
      <span class="android-status__icons-pair">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
          <path d="M8 13.3L.67 5.97a10.37 10.37 0 0114.66 0L8 13.3z" />
        </svg>
        <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
          <path d="M14.67 14.67V1.33L1.33 14.67h13.34z" />
        </svg>
      </span>
      <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
        <rect x="3.75" y="2" width="8.5" height="13" rx="1.5" />
        <rect x="5.5" y="0.9" width="5" height="2" rx="0.5" />
      </svg>
    </div>
  </div>
);

export const AndroidAppBar: FC<{ frame: AndroidFrameOpts }> = ({ frame: f }) => (
  <div class="android-appbar">
    <div class="android-appbar__row">
      <span class="android-appbar__icon" aria-hidden="true"><Icon name="arrow-left" size={24} /></span>
      {f.large ? (
        <span class="android-appbar__spacer"></span>
      ) : (
        <span class="android-appbar__title">{f.title}</span>
      )}
      <span class="android-appbar__icon" aria-hidden="true"><Icon name="ellipsis-vertical" size={24} /></span>
    </div>
    {f.large && <div class="android-appbar__large-title">{f.title}</div>}
  </div>
);

export interface AndroidItem {
  headline: string;
  supporting?: string;
  leading?: string;
}

export const AndroidListItem: FC<{ item: AndroidItem }> = ({ item }) => (
  <div class="android-list-item">
    {item.leading && (
      <span class="android-list-item__leading" aria-hidden="true">{item.leading}</span>
    )}
    <div class="android-list-item__text">
      <div class="android-list-item__headline">{item.headline}</div>
      {item.supporting && <div class="android-list-item__supporting">{item.supporting}</div>}
    </div>
  </div>
);

export const AndroidNavBar: FC<{ frame?: AndroidFrameOpts }> = () => (
  <div class="android-nav" aria-hidden="true">
    <span class="android-nav__pill"></span>
  </div>
);

const KB_ROW1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
const KB_ROW2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
const KB_ROW3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

export const AndroidKeyboard: FC<{ frame?: AndroidFrameOpts }> = () => (
  <div class="android-kb" aria-hidden="true">
    <div class="android-kb__navbar-spacer"></div>
    <div class="android-kb__rows">
      <div class="android-kb__row">
        {KB_ROW1.map((k) => <span class="android-kb__key" key={k}>{k}</span>)}
      </div>
      <div class="android-kb__row android-kb__row--inset">
        {KB_ROW2.map((k) => <span class="android-kb__key" key={k}>{k}</span>)}
      </div>
      <div class="android-kb__row">
        <span class="android-kb__key android-kb__key--variant"></span>
        <span class="android-kb__row3">
          {KB_ROW3.map((k) => <span class="android-kb__key" key={k}>{k}</span>)}
        </span>
        <span class="android-kb__key android-kb__key--variant"></span>
      </div>
      <div class="android-kb__row">
        <span class="android-kb__key android-kb__key--symbol">?123</span>
        <span class="android-kb__key android-kb__key--variant">,</span>
        <span class="android-kb__key android-kb__key--space"></span>
        <span class="android-kb__key android-kb__key--variant">.</span>
        <span class="android-kb__key android-kb__key--return"></span>
      </div>
    </div>
  </div>
);
