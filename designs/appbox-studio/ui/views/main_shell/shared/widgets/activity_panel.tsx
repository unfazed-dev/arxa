// activity_panel.tsx — the shell's multi-view panel (replaces activity_panel.html).
// Thin instantiation of _panel: top = active view label, body = caller content,
// bottom = views carousel. The original open/close macro pair is merged into a
// single wrapper component (Open) — see the conversion guide on open/close pairs.
import type { Child } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import { Open as PanelOpen, Top as PanelTop, Bottom as PanelBottom } from '../../../../common/widgets/_panel.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

const PID = 'panel-activity';

interface ActivityView {
  id: string;
  icon: string;
  label: string;
  href: string;
  active?: boolean;
}

interface ActivitySpec {
  label: string;
  views: ActivityView[];
  size?: 's' | 'm' | 'l';
  sizeHref?: string;
  panelSizePx?: number;
}

// Label — the active view's label, shown in the top section.
interface LabelProps {
  spec: ActivitySpec;
}
export function Label({ spec }: LabelProps) {
  return <strong class="panel-label">{spec.label}</strong>;
}

// Views — the views carousel: one icon per registered view.
interface ViewsProps {
  spec: ActivitySpec;
  t: TFn;
}
export function Views({ spec, t }: ViewsProps) {
  return (
    <nav class="panel-views" aria-label={t('panel.activity.views') as string}>
      {spec.views.map((v) => (
        <a
          key={v.id}
          class={`panel-views-icon${v.active ? ' is-active' : ''}`}
          href={v.href}
          hx-get={v.href}
          hx-target={`#${PID}-body`}
          hx-swap="innerHTML"
          hx-push-url="false"
          title={v.label}
          aria-label={v.label}
        >
          <Icon name={v.icon} size={18} />
        </a>
      ))}
    </nav>
  );
}

// Top — standalone top section for out-of-band refresh.
interface TopProps {
  spec: ActivitySpec;
  oob?: boolean;
}
export function Top({ spec, oob }: TopProps) {
  return (
    <PanelTop pid={PID} oob={oob}>
      <Label spec={spec} />
    </PanelTop>
  );
}

// Bottom — standalone bottom section for out-of-band refresh.
interface BottomProps {
  spec: ActivitySpec;
  oob?: boolean;
  t: TFn;
}
export function Bottom({ spec, oob, t }: BottomProps) {
  return (
    <PanelBottom pid={PID} oob={oob}>
      <Views spec={spec} t={t} />
    </PanelBottom>
  );
}

// Open — the panel wrapper (replaces the open + close macro pair).
// Callers: <Open spec={spec} t={t}>…active view content…</Open>
interface OpenProps {
  spec: ActivitySpec;
  t: TFn;
  children?: Child;
}
export function Open({ spec, t, children }: OpenProps) {
  return (
    <PanelOpen
      role="activity"
      id={PID}
      size={spec.panelSizePx ? undefined : spec.size ?? 's'}
      width={spec.panelSizePx}
      top={<Label spec={spec} />}
      bottom={<Views spec={spec} t={t} />}
      resize={spec.sizeHref ? { edge: 'start', persist: 'activity' } : undefined}
      t={t}
    >
      {children}
    </PanelOpen>
  );
}
