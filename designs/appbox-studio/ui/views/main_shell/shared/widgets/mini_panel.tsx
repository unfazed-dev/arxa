// mini_panel.tsx — the mini panel: bottom-docked controller bar (replaces mini_panel.html).
// Mode toggle, viewer fullscreen, canvas undo/redo + device rung icons.
import Icon from '../../../../../runtime/icon.tsx';

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
  t: TFn;
}
export function ControllerPanel({ controller: c, t }: ControllerPanelProps) {
  return (
    <div class="mini-panel-body" id="mini-panel-controller">
      <span class="mini-panel-group" role="group" aria-label={t('miniPanel.modeGroup') as string}>
        {c.modes.map((m) => (
          <a
            key={m.key}
            class={`chip dv-chip${m.active ? ' on' : ''}`}
            href={m.href}
            hx-get={m.href}
            hx-target="#design-viewer"
            hx-swap="morph:outerHTML"
          >
            {t(`viewer.modeLabel.${m.key}`) as string}
          </a>
        ))}
      </span>
      <span class="mini-panel-group">
        <button class="ico-btn" data-action="viewer-fullscreen" title={t('miniPanel.fullscreen') as string}>
          <Icon name="maximize" size={16} />
        </button>
      </span>
      <span class="mini-panel-group" role="group" aria-label={t('miniPanel.historyGroup') as string}>
        {c.undo.can ? (
          <button
            class="ico-btn undo-btn"
            hx-post={c.undo.href}
            hx-target="#panels"
            hx-swap="morph:outerHTML"
            title={t('miniPanel.undo') as string}
          >
            <Icon name="undo-2" size={16} />
          </button>
        ) : (
          <button class="ico-btn undo-btn" disabled={true} title={t('miniPanel.undo') as string}>
            <Icon name="undo-2" size={16} />
          </button>
        )}
        {c.redo.can ? (
          <button
            class="ico-btn redo-btn"
            hx-post={c.redo.href}
            hx-target="#panels"
            hx-swap="morph:outerHTML"
            title={t('miniPanel.redo') as string}
          >
            <Icon name="redo-2" size={16} />
          </button>
        ) : (
          <button class="ico-btn redo-btn" disabled={true} title={t('miniPanel.redo') as string}>
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
  t: TFn;
}
export function MiniPanel({ v, t }: MiniPanelProps) {
  const pnl = (v?.miniPanel ?? {}) as MiniPanelData;
  return (
    <nav class="mini-panel" aria-label={t('miniPanel.aria') as string}>
      <div class="mini-panel-bar">
        <ControllerPanel controller={pnl.controller} t={t} />
        <span class="mini-panel-bar-right">
          {pnl.bar.devices && (
            <span class="mini-panel-group" role="group" aria-label={t('viewer.viewportGroup') as string}>
              {pnl.bar.devices.map((d) => (
                <a
                  key={d.key}
                  class={`mini-panel-tab${d.active ? ' is-active' : ''}`}
                  href={d.href}
                  hx-get={d.href}
                  hx-target="#design-viewer"
                  hx-swap="morph:outerHTML"
                  aria-label={t(`viewer.vp.${d.key}`) as string}
                  title={t(`viewer.vp.${d.key}`) as string}
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
