// composer_panel.tsx — the shell's chat panel (replaces composer_panel.html).
// Single-state, always mounted. Top = stage eyebrow + pinned context chips.
// Body = caller's thread + composer card. Bottom deliberately off.
// The original open/close macro pair is merged into a single wrapper (Open).
import { Fragment, type Child } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import { Open as PanelOpen, Top as PanelTop } from '../../../../common/widgets/_panel.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

const PID = 'panel-composer';

interface ComposerChip {
  id: string;
  label: string;
  tone?: string;
  removeHref?: string;
}

interface ComposerSpec {
  eyebrow: string;
  chips?: ComposerChip[];
}

// HeadContent — the top section's content: eyebrow + pinned context chips.
interface HeadContentProps {
  spec: ComposerSpec;
  t: TFn;
}
export function HeadContent({ spec, t }: HeadContentProps) {
  const tones = ['cyan', 'olive', 'amber', 'violet'];
  return (
    <Fragment>
      <span class="eyebrow">{spec.eyebrow}</span>
      {spec.chips && (
        <span class="ctx-row chat-ctx">
          {spec.chips.map((chip, idx) => (
            <span key={chip.id} class={`chip ctx-chip ctx-${chip.tone ?? tones[idx % 4]}`}>
              <code>{chip.id}</code>
              <span class="ctx-label">{chip.label}</span>
              {chip.removeHref && (
                <a
                  class="ctx-x"
                  href={chip.removeHref}
                  hx-get={chip.removeHref}
                  hx-target="#panels"
                  hx-swap="morph:outerHTML"
                  hx-push-url="false"
                  aria-label={t('chat.removeChip', { label: chip.label }) as string}
                >
                  <Icon name="x" size={12} />
                </a>
              )}
            </span>
          ))}
        </span>
      )}
    </Fragment>
  );
}

// Top — standalone top section for out-of-band refresh.
interface TopProps {
  spec: ComposerSpec;
  oob?: boolean;
  t: TFn;
}
export function Top({ spec, oob, t }: TopProps) {
  return (
    <PanelTop pid={PID} oob={oob}>
      <HeadContent spec={spec} t={t} />
    </PanelTop>
  );
}

// Open — the panel wrapper (replaces the open + close macro pair).
// Callers: <Open spec={spec} t={t}>thread + composer card</Open>
interface OpenProps {
  spec: ComposerSpec;
  t: TFn;
  children?: Child;
}
export function Open({ spec, t, children }: OpenProps) {
  return (
    <PanelOpen
      role="composer"
      id={PID}
      top={<HeadContent spec={spec} t={t} />}
      bottom={false}
      resize={{ edge: 'end' }}
      t={t}
    >
      {children}
    </PanelOpen>
  );
}
