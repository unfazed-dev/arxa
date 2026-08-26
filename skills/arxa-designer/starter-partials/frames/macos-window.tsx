// macos-window.tsx — macOS Tahoe (Liquid Glass) window (replaces macos-window.html).
// Pure HTML+CSS port of arxa-designer's starter-components/macos-window.jsx.
// Zero JavaScript. Styles live in frames.css (copy it to assets/css/).
//
// Usage — copy frames/ into your artifact (e.g. ui/widgets/frames/), then
// import and wrap your app content as children:
//
//   import { MacosWindow } from './frames/macos-window.tsx';
//   <MacosWindow frame={{ title: 'Folder' }}>
//     <p>Your app content…</p>
//   </MacosWindow>
//
// frame options (all optional):
//   width    900        window width in px      height  600   window height
//   title    'Folder'   toolbar title
//   sidebar  []         list of sidebar entries, in order:
//                         { header: 'Favorites' }            section header
//                         { label: 'Recents', glyph: 'clock', selected: true }  row
//                       `glyph` is any Lucide name (default 'folder'); the
//                       selected row's glyph tints accent.
//                       The sidebar (traffic lights + glass panel) always
//                       renders, like the React original; leave the list
//                       empty for a bare sidebar.
//
// Slot: children land in `<div class="frame-screen">` (scrolls, padded
// 4px 8px like the original). <MacosWindow /> with no children renders an
// empty, marked screen slot.
//
// Fragment note: frames are not views — a viewmodel can only fragment-render
// named exports of *_view.tsx files; to render the bare window from a
// viewmodel, re-export it from a view.
//
// Sibling exports: MacTrafficLights · MacSidebar · MacSidebarItem ·
// MacSidebarHeader · MacToolbar · MacGlass (children;
// props { radius?: 296 (px, pill default), dark?: false }).
import type { FC, Child } from 'hono/jsx';
// Icon path note: canonical placement is ui/widgets/frames/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

export type MacSidebarEntry =
  | { header: string }
  | { label: string; glyph?: string; selected?: boolean };

interface MacFrameOpts {
  width?: number;
  height?: number;
  title?: string;
  sidebar?: MacSidebarEntry[];
}

interface MacosWindowProps {
  frame?: MacFrameOpts;
  children?: Child;
}

export const MacosWindow: FC<MacosWindowProps> = ({ frame: f = {}, children }) => (
  <div
    class="mac-window"
    style={`--mac-w: ${f.width ?? 900}px; --mac-h: ${f.height ?? 600}px;`}
  >
    <MacSidebar items={f.sidebar ?? []} />
    <div class="mac-window__main">
      <MacToolbar frame={f} />
      <div class="frame-screen mac-window__screen">
        {children ?? (
          // SLOT: app content goes here (see this file's header comment for usage)
          null
        )}
      </div>
    </div>
  </div>
);

export default MacosWindow;

export const MacTrafficLights: FC = () => (
  <span class="mac-traffic" aria-hidden="true">
    <span class="mac-traffic__dot mac-traffic__dot--close"></span>
    <span class="mac-traffic__dot mac-traffic__dot--min"></span>
    <span class="mac-traffic__dot mac-traffic__dot--max"></span>
  </span>
);

export const MacSidebar: FC<{ items: MacSidebarEntry[] }> = ({ items }) => (
  <div class="mac-sidebar">
    <div class="mac-sidebar__content">
      <div class="mac-sidebar__controls"><MacTrafficLights /></div>
      {items.map((item, i) =>
        'header' in item ? (
          <MacSidebarHeader title={item.header} key={i} />
        ) : (
          <MacSidebarItem item={item} key={i} />
        ),
      )}
    </div>
  </div>
);

export const MacSidebarItem: FC<{ item: { label: string; glyph?: string; selected?: boolean } }> = ({ item }) => (
  <div class={`mac-sidebar-item${item.selected ? ' is-selected' : ''}`}>
    <span class="mac-sidebar-item__icon" aria-hidden="true">
      <Icon name={item.glyph ?? 'folder'} size={14} />
    </span>
    <span class="mac-sidebar-item__label">{item.label}</span>
  </div>
);

export const MacSidebarHeader: FC<{ title: string }> = ({ title }) => (
  <div class="mac-sidebar__header">{title}</div>
);

export const MacToolbar: FC<{ frame?: MacFrameOpts }> = ({ frame: f = {} }) => (
  <div class="mac-toolbar">
    <div class="mac-toolbar__title">{f.title ?? 'Folder'}</div>
    <div class="mac-toolbar__spacer"></div>
    <MacGlass>
      <span class="mac-toolbar__action" aria-hidden="true"><Icon name="plus" size={16} /></span>
    </MacGlass>
    <MacGlass>
      <span class="mac-toolbar__search">
        <Icon name="search" size={13} />
        <span>Search</span>
      </span>
    </MacGlass>
  </div>
);

interface MacGlassProps {
  radius?: number;
  dark?: boolean;
  children?: Child;
}

export const MacGlass: FC<MacGlassProps> = ({ radius, dark, children }) => (
  <div
    class={`mac-glass${dark ? ' mac-glass--dark' : ''}`}
    style={radius ? `--mac-glass-radius: ${radius}px;` : undefined}
  >
    {children}
  </div>
);
