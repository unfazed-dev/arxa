// _toast.tsx — one toast, OOB-swapped into #toasts (replaces _toast.html).
// Zero JavaScript. The toast host lives in the base layout
// (<div id="toasts">); the mutation endpoint responds with this component
// and NOTHING else, while the triggering form/button opts out of the normal
// swap:
//
//   <form hx-post="/items/42/delete" hx-swap="none">…</form>
//
//   export const del = (context, helpers) => {
//     facade.delete(c.req.param('id'));
//     return h.render(c, 'ui/common/widgets/_toast.tsx',
//       { toast: { text: 'Item deleted', kind: 'success', linger: true } });
//   };
//
// toast = {
//   text,
//   kind?: 'info' | 'success' | 'error',  // default info; picks the icon
//   icon?,                                // Lucide name, overrides the kind icon
//   linger?                               // adds toast--linger: fades after
//                                         // --toast-ttl (notify motion, motion.css §5)
// }
//
// Motion is `notify`: entry/exit animations live in motion.css; the node
// leaves the DOM the next time the server re-renders #toasts — CSS hides,
// only the server removes.
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (block: .toast, plus the #toasts host).
// Flutter: AppBoxKitNotificationService.show.
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

type ToastKind = 'info' | 'success' | 'error';

const KIND_ICONS: Record<ToastKind, string> = {
  info: 'info',
  success: 'check-circle-2',
  error: 'circle-alert',
};

interface ToastProps {
  toast: {
    text: string;
    kind?: ToastKind;
    icon?: string;
    linger?: boolean;
  };
}

export const Toast: FC<ToastProps> = ({ toast }) => {
  const kind = toast.kind ?? 'info';
  return (
    <div
      class={`toast toast--${kind}${toast.linger ? ' toast--linger' : ''}`}
      hx-swap-oob="beforeend:#toasts"
      role="status"
    >
      <Icon name={toast.icon ?? KIND_ICONS[kind]} size={18} cls="toast__icon" />
      <span class="toast__text">{toast.text}</span>
    </div>
  );
};
