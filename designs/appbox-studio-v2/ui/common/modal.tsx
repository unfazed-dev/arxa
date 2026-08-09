// modal.tsx — declarative modal macro lib (replaces modal.html).
// Zero-request <details> overlay: trigger, scrim, and card all render with the
// page; opening flips [open] client-side — no host, no endpoint, no htmx. The
// OPEN <summary> stretches into the fixed scrim: click outside (or the floating
// X) closes. Esc does not close (no JS). Motion: reveal (scrim fade + card
// rise). Styles: appshell.css (.modal block).
//
//   import { Wrap } from './modal.tsx';
//   <Wrap trigger="Pair a device" cardClass="pair-modal" translate={translate}>
//     …body markup…
//   </Wrap>
import type { Child } from 'hono/jsx';
import Icon from '../../runtime/icon.tsx';
import { inspectAttrs } from '../widgets/common/studio_primitives/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface WrapProps {
  /** Trigger label (the visible button text). */
  trigger: string;
  /** Card aria-label; defaults to trigger. */
  label?: string;
  /** Extra class appended to .modal-card. */
  cardClass?: string;
  /** Close button aria-label; defaults to translate('modal.close'). */
  closeLabel?: string;
  translate: TFn;
  children?: Child;
}

export function Wrap(props: WrapProps) {
  const { trigger, label, cardClass, closeLabel, translate } = props;
  return (
    <details class="modal">
      <summary class="modal-trigger" {...inspectAttrs('modal:trigger', { role: 'label' })}>
        <span class="modal-open-label" {...inspectAttrs('modal:open-label', { role: 'text' })}>{trigger}</span>
        <span class="modal-close-label">
          <Icon name="x" size={18} label={closeLabel ?? (translate('modal.close') as string)} />
        </span>
      </summary>
      <div
        class={cardClass ? `modal-card ${cardClass}` : 'modal-card'}
        role="dialog"
        aria-modal="true"
        aria-label={label ?? trigger}
        {...inspectAttrs('modal:card', { role: 'group' })}
      >
        {props.children}
      </div>
    </details>
  );
}
