// widget_editor.tsx — the drawer Tools tab's inline property editor
// (replaces widget_editor.html's `pane` macro). Views lens only; flows and
// prototype stay read-only by decision. Server-rendered, pure htmx (ADR-0002):
// every value shown and every write lives server-side. Edits hit the widget's
// SOURCE element, so `appliesTo` names every screen the change reaches.
// Macro library file — imported directly by view components.
import { inspectAttrs } from '../../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Step {
  on?: boolean;
  val: string;
  v?: string; // k steps (pad/gap) render s.v
  m?: string; // resize modes render t('viewer.wedit.mode.' ~ s.m)
}

interface Sel {
  name?: string;
  kind: string;
}

interface PaneProps {
  translate: TFn;
  sel?: Sel | null;
  file?: string;
  screens?: string[];
  attrHref?: string;
  pads?: Step[];
  gaps?: Step[];
  resizeX?: Step[];
  resizeY?: Step[];
}

export function Pane(props: PaneProps) {
  const { translate } = props;
  if (!props.sel) return null;
  const screens = props.screens ?? [];
  const attrHref = props.attrHref ?? '';
  const pads = props.pads ?? [];
  const gaps = props.gaps ?? [];
  const resizeX = props.resizeX ?? [];
  const resizeY = props.resizeY ?? [];

  return (
    <div class="dv-wedit-card" {...inspectAttrs('widget-editor', { role: 'panel' })}>
      <div class="dv-wedit-head">
        <b>{props.sel.name || props.sel.kind}</b>
        <code class="dv-wedit-file">{props.file}</code>
      </div>
      <p class="dv-wedit-prov">
        {translate('viewer.wedit.appliesTo', { n: screens.length }) as string} · {screens.join(' · ')}
      </p>
      <div class="dv-wedit-row">
        <span class="dv-wedit-label">{translate('viewer.wedit.pad') as string}</span>
        <span class="dv-wedit-steps">
          {pads.map((step) => (
            <button
              type="button"
              class={`chip dv-wedit-step${step.on ? ' on' : ''}`}
              hx-post={attrHref}
              hx-vals={`{"attr": "data-pad", "value": "${step.val}"}`}
              hx-target="closest .dv-wedit"
              hx-swap="innerHTML"
              key={step.val}
            >
              {step.v}
            </button>
          ))}
        </span>
      </div>
      <div class="dv-wedit-row">
        <span class="dv-wedit-label">{translate('viewer.wedit.gap') as string}</span>
        <span class="dv-wedit-steps">
          {gaps.map((step) => (
            <button
              type="button"
              class={`chip dv-wedit-step${step.on ? ' on' : ''}`}
              hx-post={attrHref}
              hx-vals={`{"attr": "data-gap", "value": "${step.val}"}`}
              hx-target="closest .dv-wedit"
              hx-swap="innerHTML"
              key={step.val}
            >
              {step.v}
            </button>
          ))}
        </span>
      </div>
      {/* Per-axis sizing modes. Same chip shape and toggle-off rule as the k
          steps above. The canvas handles hug/fill by gesture; fixed is only
          here, because no drag direction honestly means "keep your size". */}
      <div class="dv-wedit-row">
        <span class="dv-wedit-label">{translate('viewer.wedit.resizeX') as string}</span>
        <span class="dv-wedit-steps">
          {resizeX.map((step) => (
            <button
              type="button"
              class={`chip dv-wedit-step dv-wedit-mode${step.on ? ' on' : ''}`}
              hx-post={attrHref}
              hx-vals={`{"attr": "data-resize-x", "value": "${step.val}"}`}
              hx-target="closest .dv-wedit"
              hx-swap="innerHTML"
              key={step.val}
            >
              {translate(`viewer.wedit.mode.${step.m}`) as string}
            </button>
          ))}
        </span>
      </div>
      <div class="dv-wedit-row">
        <span class="dv-wedit-label">{translate('viewer.wedit.resizeY') as string}</span>
        <span class="dv-wedit-steps">
          {resizeY.map((step) => (
            <button
              type="button"
              class={`chip dv-wedit-step dv-wedit-mode${step.on ? ' on' : ''}`}
              hx-post={attrHref}
              hx-vals={`{"attr": "data-resize-y", "value": "${step.val}"}`}
              hx-target="closest .dv-wedit"
              hx-swap="innerHTML"
              key={step.val}
            >
              {translate(`viewer.wedit.mode.${step.m}`) as string}
            </button>
          ))}
        </span>
      </div>
    </div>
  );
}
