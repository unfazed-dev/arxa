// activity_panel.tsx — the shell's multi-view panel (replaces activity_panel.html).
// Thin instantiation of _panel: top = active view label, body = caller content,
// bottom = views carousel. The original open/close macro pair is merged into a
// single wrapper component (Open) — see the conversion guide on open/close pairs.
import type { Child } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import { Open as PanelOpen, Top as PanelTop, Bottom as PanelBottom } from '../../../../common/widgets/panel.tsx';
import { inspectAttrs } from '../../../../common/widgets/primitives.tsx';

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
  return <strong class="panel-label" {...inspectAttrs('panel:activity:label', { role: 'label' })}>{spec.label}</strong>;
}

// Views — the views carousel: one icon per registered view.
interface ViewsProps {
  spec: ActivitySpec;
  translate: TFn;
}
export function Views({ spec, translate }: ViewsProps) {
  return (
    <nav class="panel-views" aria-label={translate('panel.activity.views') as string} {...inspectAttrs('panel:activity:views', { role: 'nav' })}>
      {spec.views.map((view) => (
        <a
          key={view.id}
          class={`panel-views-icon${view.active ? ' is-active' : ''}`}
          href={view.href}
          hx-get={view.href}
          hx-target={`#${PID}-body`}
          hx-swap="innerHTML"
          hx-push-url="false"
          title={view.label}
          aria-label={view.label}
        >
          <Icon name={view.icon} size={18} />
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
  translate: TFn;
}
export function Bottom({ spec, oob, translate }: BottomProps) {
  return (
    <PanelBottom pid={PID} oob={oob}>
      <Views spec={spec} translate={translate} />
    </PanelBottom>
  );
}

// Open — the panel wrapper (replaces the open + close macro pair).
// Callers: <Open spec={spec} t={t}>…active view content…</Open>
interface OpenProps {
  spec: ActivitySpec;
  translate: TFn;
  children?: Child;
}
export function Open({ spec, translate, children }: OpenProps) {
  return (
    <PanelOpen
      role="activity"
      id={PID}
      size={spec.panelSizePx ? undefined : spec.size ?? 's'}
      width={spec.panelSizePx}
      top={<Label spec={spec} />}
      bottom={<Views spec={spec} translate={translate} />}
      resize={spec.sizeHref ? { edge: 'start', persist: 'activity' } : undefined}
      translate={translate}
    >
      {children}
    </PanelOpen>
  );
}
