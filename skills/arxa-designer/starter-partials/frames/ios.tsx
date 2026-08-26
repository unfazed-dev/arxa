// ios.tsx — iOS 26 (Liquid Glass) device frame (replaces ios.html).
// Pure HTML+CSS port of arxa-designer's starter-components/ios-frame.jsx.
// Zero JavaScript. Styles live in frames.css (copy it to assets/css/).
//
// Usage — copy frames/ into your artifact (e.g. ui/widgets/frames/), then
// import and wrap your screen content as children:
//
//   import { IosDevice, IosList } from './frames/ios.tsx';
//   <IosDevice frame={{ title: 'Settings' }}>
//     <IosList header="General" rows={[
//       { title: 'Airplane Mode', icon: '#ff9500', glyph: 'plane' },
//       { title: 'Wi-Fi', detail: 'Home', icon: '#007aff', glyph: 'wifi' },
//     ]} />
//   </IosDevice>
//
// frame options (all optional):
//   width    402      device width in px        height  874   device height
//   dark     false    dark chrome (adds .ios-device--dark)
//   time     '9:41'   status-bar clock
//   title    unset    when set, renders the nav bar (glass pills + large title)
//   keyboard false    when true, renders the liquid-glass keyboard
//
// Slot: children land in `<div class="frame-screen">` (scrolls).
// <IosDevice /> with no children renders an empty, marked screen slot you
// can paste markup into directly.
//
// Fragment note: frames are not views — a viewmodel can only fragment-render
// named exports of *_view.tsx files; to render the bare frame from a
// viewmodel, re-export it from a view.
//
// Sibling exports: IosStatusBar · IosNavBar · IosPill (children) ·
// IosList · IosListRow · IosKeyboard.
// row = { title, detail?, icon? (CSS color for the badge), glyph? (Lucide
// name, white on the badge), chevron? (default true) }.
import type { FC, Child } from 'hono/jsx';
// Icon path note: canonical placement is ui/widgets/frames/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface IosFrameOpts {
  width?: number;
  height?: number;
  dark?: boolean;
  time?: string;
  title?: string;
  keyboard?: boolean;
}

interface IosDeviceProps {
  frame?: IosFrameOpts;
  children?: Child;
}

export const IosDevice: FC<IosDeviceProps> = ({ frame: f = {}, children }) => (
  <div
    class={`ios-device${f.dark ? ' ios-device--dark' : ''}`}
    style={`--ios-w: ${f.width ?? 402}px; --ios-h: ${f.height ?? 874}px;`}
  >
    <div class="ios-device__island" aria-hidden="true"></div>
    <IosStatusBar frame={f} />
    <div class="ios-device__body">
      {f.title !== undefined && <IosNavBar frame={f} />}
      <div class="frame-screen ios-device__screen">
        {children ?? (
          // SLOT: screen content goes here (see this file's header comment for usage)
          null
        )}
      </div>
      {f.keyboard && <IosKeyboard frame={f} />}
    </div>
    <div class="ios-device__home" aria-hidden="true"><span class="ios-device__home-bar"></span></div>
  </div>
);

export default IosDevice;

export const IosStatusBar: FC<{ frame?: IosFrameOpts }> = ({ frame: f = {} }) => (
  <div class="ios-status">
    <div class="ios-status__cell ios-status__time-cell">
      <span class="ios-status__time">{f.time ?? '9:41'}</span>
    </div>
    <div class="ios-status__cell ios-status__icons" aria-hidden="true">
      <svg width="19" height="12" viewBox="0 0 19 12" fill="currentColor">
        <rect x="0" y="7.5" width="3.2" height="4.5" rx="0.7" />
        <rect x="4.8" y="5" width="3.2" height="7" rx="0.7" />
        <rect x="9.6" y="2.5" width="3.2" height="9.5" rx="0.7" />
        <rect x="14.4" y="0" width="3.2" height="12" rx="0.7" />
      </svg>
      <svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor">
        <path d="M8.5 3.2C10.8 3.2 12.9 4.1 14.4 5.6L15.5 4.5C13.7 2.7 11.2 1.5 8.5 1.5C5.8 1.5 3.3 2.7 1.5 4.5L2.6 5.6C4.1 4.1 6.2 3.2 8.5 3.2Z" />
        <path d="M8.5 6.8C9.9 6.8 11.1 7.3 12 8.2L13.1 7.1C11.8 5.9 10.2 5.1 8.5 5.1C6.8 5.1 5.2 5.9 3.9 7.1L5 8.2C5.9 7.3 7.1 6.8 8.5 6.8Z" />
        <circle cx="8.5" cy="10.5" r="1.5" />
      </svg>
      <svg width="27" height="13" viewBox="0 0 27 13">
        <rect x="0.5" y="0.5" width="23" height="12" rx="3.5" fill="none" stroke="currentColor" stroke-opacity="0.35" />
        <rect x="2" y="2" width="20" height="9" rx="2" fill="currentColor" />
        <path d="M25 4.5V8.5C25.8 8.2 26.5 7.2 26.5 6.5C26.5 5.8 25.8 4.8 25 4.5Z" fill="currentColor" fill-opacity="0.4" />
      </svg>
    </div>
  </div>
);

export const IosPill: FC<{ children?: Child }> = ({ children }) => (
  <div class="ios-pill">{children}</div>
);

export const IosNavBar: FC<{ frame: IosFrameOpts }> = ({ frame: f }) => (
  <div class="ios-nav">
    <div class="ios-nav__row">
      <IosPill>
        <span class="ios-pill__icon"><Icon name="chevron-left" size={22} strokeWidth={2.5} /></span>
      </IosPill>
      <IosPill>
        <span class="ios-pill__icon"><Icon name="ellipsis" size={20} /></span>
      </IosPill>
    </div>
    <div class="ios-nav__title">{f.title}</div>
  </div>
);

export interface IosRow {
  title: string;
  detail?: string;
  icon?: string;
  glyph?: string;
  chevron?: boolean;
}

export const IosListRow: FC<{ row: IosRow }> = ({ row }) => (
  <div class={`ios-row${row.icon ? ' ios-row--icon' : ''}`}>
    {row.icon && (
      <span class="ios-row__icon" style={`background: ${row.icon};`} aria-hidden="true">
        {row.glyph && <Icon name={row.glyph} size={18} />}
      </span>
    )}
    <span class="ios-row__title">{row.title}</span>
    {row.detail && <span class="ios-row__detail">{row.detail}</span>}
    {row.chevron !== false && (
      <svg class="ios-row__chevron" width="8" height="14" viewBox="0 0 8 14" fill="none" aria-hidden="true">
        <path d="M1 1l6 6-6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    )}
  </div>
);

export const IosList: FC<{ header?: string; rows?: IosRow[] }> = ({ header, rows = [] }) => (
  <div class="ios-list">
    {header && <div class="ios-list__header">{header}</div>}
    <div class="ios-list__card">
      {rows.map((row, i) => <IosListRow row={row} key={i} />)}
    </div>
  </div>
);

const KB_ROW1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
const KB_ROW2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
const KB_ROW3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

export const IosKeyboard: FC<{ frame?: IosFrameOpts }> = () => (
  <div class="ios-kb" aria-hidden="true">
    <div class="ios-kb__suggest">
      <span class="ios-kb__suggest-word">“The”</span>
      <span class="ios-kb__suggest-sep"></span>
      <span class="ios-kb__suggest-word">the</span>
      <span class="ios-kb__suggest-sep"></span>
      <span class="ios-kb__suggest-word">to</span>
    </div>
    <div class="ios-kb__rows">
      <div class="ios-kb__row">
        {KB_ROW1.map((keyLabel) => <span class="ios-kb__key" key={keyLabel}>{keyLabel}</span>)}
      </div>
      <div class="ios-kb__row ios-kb__row--inset">
        {KB_ROW2.map((keyLabel) => <span class="ios-kb__key" key={keyLabel}>{keyLabel}</span>)}
      </div>
      <div class="ios-kb__row ios-kb__row--wide">
        <span class="ios-kb__key ios-kb__key--special">
          <svg width="19" height="17" viewBox="0 0 19 17" fill="currentColor"><path d="M9.5 1L1 9.5h4.5V16h8V9.5H18L9.5 1z" /></svg>
        </span>
        <span class="ios-kb__row3">
          {KB_ROW3.map((keyLabel) => <span class="ios-kb__key" key={keyLabel}>{keyLabel}</span>)}
        </span>
        <span class="ios-kb__key ios-kb__key--special">
          <svg width="23" height="17" viewBox="0 0 23 17" fill="none">
            <path d="M7 1h13a2 2 0 012 2v11a2 2 0 01-2 2H7l-6-7.5L7 1z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" />
            <path d="M10 5l7 7M17 5l-7 7" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
          </svg>
        </span>
      </div>
      <div class="ios-kb__row">
        <span class="ios-kb__key ios-kb__key--bottom">ABC</span>
        <span class="ios-kb__key"></span>
        <span class="ios-kb__key ios-kb__key--bottom ios-kb__key--return">
          <svg width="20" height="14" viewBox="0 0 20 14" fill="none"><path d="M18 1v6H4m0 0l4-4M4 7l4 4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" /></svg>
        </span>
      </div>
    </div>
    <div class="ios-kb__bottom-spacer"></div>
  </div>
);
