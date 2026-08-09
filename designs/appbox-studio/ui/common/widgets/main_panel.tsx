// main_panel.tsx — the Main Panel: the center chrome region, the single render
// destination for all content, plus the per-shell panel bar and the file viewer.
// Replaces ui/common/widgets/main_panel.html.
import { raw } from 'hono/utils/html';
import type { Child } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import { inspectAttrs } from './primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// The file viewer payload. One mode is picked server-side from the file
// extension (services/facades/file_views.js): render:code | render:doc |
// render:image | render:svg | render:pdf | render:video.
export interface FileView {
  path?: string;
  mode?: string;
  modeName?: string;
  lang?: string;
  body?: string;
  html?: string;
  src?: string;
  backHref?: string;
}

// `.panel-main` is the transparent flex SLOT, not the card. The original template
// exposed it as an open()/close() macro pair; in TSX it wraps its
// children directly. The original also interpolated a raw `spec.attrs`
// attribute string — dropped here: every caller passes `{}` and a raw
// attribute string is not expressible as JSX props (extend this component if a
// caller ever needs extra hooks).
interface MainPanelOpenProps {
  id?: string;
  children?: Child;
}
export function Open(props: MainPanelOpenProps) {
  return <div class="panel-main" id={props.id ?? 'panel-main'} {...inspectAttrs('panel:main', { role: 'panel' })}>{props.children}</div>;
}

// panelBar — the per-shell segmented switcher that picks the single visible
// content panel. Server-rendered links, state via ?panel=; plain boosted
// navigation, zero JS. Rung order mirrors the panel order on expanded:
// composer, main, activity. Hidden on expanded. Distinct from the tabbar.
interface PanelBarItem {
  id: string;
  icon: string;
  labelKey: string;
}
const PANEL_BAR_ITEMS: PanelBarItem[] = [
  { id: 'composer', icon: 'messages-square', labelKey: 'panelBar.composer' },
  { id: 'main', icon: 'square', labelKey: 'panelBar.main' },
  { id: 'activity', icon: 'panel-left', labelKey: 'panelBar.activity' },
];
interface PanelBarProps {
  panel?: string;
  translate: TFn;
}
export function PanelBar(props: PanelBarProps) {
  const { panel, translate } = props;
  return (
    <nav class="panel-bar" aria-label={translate('panelBar.aria') as string} {...inspectAttrs('panel-bar', { role: 'toolbar' })}>
      {PANEL_BAR_ITEMS.map(p => (
        <a
          key={p.id}
          class={`panel-bar-item${panel === p.id ? ' is-active' : ''}`}
          href={`?panel=${p.id}`}
          {...(panel === p.id ? { 'aria-current': 'true' } : {})}
        >
          <Icon name={p.icon} size={16} />
          <span class="panel-bar-label">{translate(p.labelKey) as string}</span>
        </a>
      ))}
    </nav>
  );
}

// empty — the empty read state, rendered inside #panel-main.
interface EmptyProps {
  translate: TFn;
}
export function Empty(props: EmptyProps) {
  return (
    <section class="mp-content mp-empty" id="mp-content" {...inspectAttrs('panel:main:empty', { role: 'panel' })}>
      <p class="muted">{props.translate('mainPanel.empty') as string}</p>
    </section>
  );
}

// One renderer per mode of the closed set. Shared props — each renderer takes
// the same file payload and reads only the fields its mode needs.
interface FileRendererProps {
  f: FileView;
}
export function RenderCode(props: FileRendererProps) {
  const { f } = props;
  return <pre class="mp-code"><code class={`lang-${f.lang}`}>{f.body}</code></pre>;
}

export function RenderDoc(props: FileRendererProps) {
  return <article class="mp-doc">{raw(props.f.html ?? '')}</article>;
}

export function RenderImage(props: FileRendererProps) {
  const { f } = props;
  return <img class="mp-media" src={f.src} alt={f.path} />;
}

export function RenderSvg(props: FileRendererProps) {
  const { f } = props;
  return <img class="mp-media mp-svg" src={f.src} alt={f.path} />;
}

export function RenderPdf(props: FileRendererProps) {
  const { f } = props;
  return <embed class="mp-media mp-pdf" src={f.src} type="application/pdf" />;
}

export function RenderVideo(props: FileRendererProps) {
  const { f } = props;
  return <video class="mp-media" src={f.src} controls={true} preload="metadata" />;
}

// Picks the mode's body from the server-chosen f.mode.
function fileBody(f: FileView) {
  switch (f.mode) {
    case 'render:code': return <RenderCode f={f} />;
    case 'render:doc': return <RenderDoc f={f} />;
    case 'render:image': return <RenderImage f={f} />;
    case 'render:svg': return <RenderSvg f={f} />;
    case 'render:pdf': return <RenderPdf f={f} />;
    case 'render:video': return <RenderVideo f={f} />;
    default: return null;
  }
}

// view — the open file: head (path, the mode the server picked, the back link
// to the stage default) + the mode's body.
interface ViewProps {
  f: FileView;
  translate: TFn;
}
export function View(props: ViewProps) {
  const { f, translate } = props;
  return (
    <section class="mp-content mp-file" id="mp-content" aria-live="polite" {...inspectAttrs('file-view', { role: 'panel' })}>
      <header class="mp-file-head">
        <code class="mp-file-path">{f.path}</code>
        <span class="chip chip--muted">{translate(`mainPanel.mode.${f.modeName}`) as string}</span>
        <a class="mp-file-back" href={f.backHref}>
          <Icon name="chevron-left" size={14} /> {translate('mainPanel.back') as string}
        </a>
      </header>
      {fileBody(f)}
    </section>
  );
}

export { Open as default };
