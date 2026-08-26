// _modal.tsx — declarative modal (replaces _modal.html).
// Zero JavaScript, ZERO REQUESTS: a pure <details> toggle. Trigger, scrim,
// and card all render with the page; opening flips [open] client-side — no
// host div, no endpoint, no htmx. Complement of _dialog.tsx: _dialog is the
// server-swapped <dialog> for dynamic content (confirms that need fresh
// state); _modal is the static confirm/info overlay whose content the page
// already owns.
//
//   import { Modal } from '../../common/widgets/_modal.tsx';
//   <Modal modal={{ trigger: 'Pair a device',
//                   body: '<h2>Pair a device</h2><p>Scan the code…</p>' }} />
//
// modal = {
//   trigger,                  // closed-state summary label
//   body,                     // trusted HTML, rendered raw: compose it in the
//                             // surface (it is NOT escaped — see raw() below)
//   label?,                   // aria-label of the card (default: trigger)
//   cardClass?,               // extra class on the card (per-surface look)
//   closeLabel?               // aria-label of the floating X (default "Close")
// }
//
// Mechanics: the OPEN <summary> stretches into the fixed scrim — clicking
// anywhere outside the card closes it, and the floating X is that same
// summary. Esc does NOT close (no JS to catch it) — say so in the surface's
// design notes if the frozen product expects it.
//
// Motion: `reveal` — scrim fade + card rise (widgets.css), gated by
// prefers-reduced-motion like every widget.
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (block: .modal).
// Flutter: ui_library dialog service (static content).
import type { FC } from 'hono/jsx';
import { raw } from 'hono/utils/html';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface ModalProps {
  modal: {
    trigger: string;
    body: string;
    label?: string;
    cardClass?: string;
    closeLabel?: string;
  };
}

export const Modal: FC<ModalProps> = ({ modal }) => (
  <details class="modal">
    <summary class="modal-trigger">
      <span class="modal-open-label">{modal.trigger}</span>
      <span class="modal-close-label">
        <Icon name="x" size={18} label={modal.closeLabel ?? 'Close'} />
      </span>
    </summary>
    <div
      class={`modal-card${modal.cardClass ? ` ${modal.cardClass}` : ''}`}
      role="dialog"
      aria-modal="true"
      aria-label={modal.label ?? modal.trigger}
    >
      {/* trusted HTML, composed by the surface (replaces `| safe`) */}
      {raw(modal.body)}
    </div>
  </details>
);
