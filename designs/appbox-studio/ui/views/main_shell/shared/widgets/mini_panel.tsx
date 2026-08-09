// mini_panel.tsx — the mini panel: bottom-docked controller bar (replaces mini_panel.html).
// Mode toggle, viewer fullscreen, canvas undo/redo + device rung icons.
import Icon from '../../../../../runtime/icon.tsx';
import { inspectAttrs } from '../../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface MiniMode {
  key: string;
  active?: boolean;
  href: string;
}

interface MiniDevice {
  key: string;
  icon: string;
  active?: boolean;
  href: string;
}

interface MiniController {
  modes: MiniMode[];
  undo: { can: boolean; href: string };
  redo: { can: boolean; href: string };
}

interface MiniPanelData {
  bar: { devices: MiniDevice[] | null };
  controller: MiniController;
}

// ControllerPanel — mode chips, fullscreen, undo/redo (the bar's left cluster).
interface ControllerPanelProps {
  controller: MiniController;
  translate: TFn;
}
export function ControllerPanel({ controller: c, translate }: ControllerPanelProps) {
  return (
    <div class="mini-panel-body" id="mini-panel-controller" {...inspectAttrs('mini-panel:controller', { role: 'toolbar' })}>
      <span class="mini-panel-group" role="group" aria-label={translate('miniPanel.modeGroup') as string}>
        {c.modes.map((m) => (
          <a
            key={m.key}
            class={`chip dv-chip${m.active ? ' on' : ''}`}
            href={m.href}
            hx-get={m.href}
            hx-target="#design-viewer"
            hx-swap="outerMorph"
          >
            {translate(`viewer.modeLabel.${m.key}`) as string}
          </a>
        ))}
      </span>
      <span class="mini-panel-group">
        <button class="ico-btn" data-action="viewer-fullscreen" title={translate('miniPanel.fullscreen') as string}>
          <Icon name="maximize" size={16} />
        </button>
      </span>
      <span class="mini-panel-group" role="group" aria-label={translate('miniPanel.historyGroup') as string}>
        {c.undo.can ? (
          <button
            class="ico-btn undo-btn"
            hx-post={c.undo.href}
            hx-target="#panels"
            hx-swap="outerMorph"
            title={translate('miniPanel.undo') as string}
          >
            <Icon name="undo-2" size={16} />
          </button>
        ) : (
          <button class="ico-btn undo-btn" disabled={true} title={translate('miniPanel.undo') as string}>
            <Icon name="undo-2" size={16} />
          </button>
        )}
        {c.redo.can ? (
          <button
            class="ico-btn redo-btn"
            hx-post={c.redo.href}
            hx-target="#panels"
            hx-swap="outerMorph"
            title={translate('miniPanel.redo') as string}
          >
            <Icon name="redo-2" size={16} />
          </button>
        ) : (
          <button class="ico-btn redo-btn" disabled={true} title={translate('miniPanel.redo') as string}>
            <Icon name="redo-2" size={16} />
          </button>
        )}
      </span>
    </div>
  );
}

// MiniPanel — the bar: controller + device rungs pushed right.
interface MiniPanelProps {
  v?: { miniPanel?: MiniPanelData | Record<string, unknown>; [key: string]: unknown };
  translate: TFn;
}
export function MiniPanel({ v, translate }: MiniPanelProps) {
  const pnl = (v?.miniPanel ?? {}) as MiniPanelData;
  return (
    <nav class="mini-panel" aria-label={translate('miniPanel.aria') as string} {...inspectAttrs('mini-panel', { role: 'toolbar' })}>
      <div class="mini-panel-bar">
        <ControllerPanel controller={pnl.controller} translate={translate} />
        <span class="mini-panel-bar-right">
          {pnl.bar.devices && (
            <span class="mini-panel-group" role="group" aria-label={translate('viewer.viewportGroup') as string}>
              {pnl.bar.devices.map((d) => (
                <a
                  key={d.key}
                  class={`mini-panel-tab${d.active ? ' is-active' : ''}`}
                  href={d.href}
                  hx-get={d.href}
                  hx-target="#design-viewer"
                  hx-swap="outerMorph"
                  aria-label={translate(`viewer.vp.${d.key}`) as string}
                  title={translate(`viewer.vp.${d.key}`) as string}
                >
                  <Icon name={d.icon} size={16} />
                </a>
              ))}
            </span>
          )}
        </span>
      </div>
    </nav>
  );
}
