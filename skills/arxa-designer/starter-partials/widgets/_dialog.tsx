// _dialog.tsx — server-driven modal dialog (replaces _dialog.html).
// Zero JavaScript. The shell owns an empty host; a trigger swaps the rendered
// component into it; the dialog renders OPEN (<dialog open>) and the entry
// keyframe plays on insertion (`reveal` motion, widgets.css):
//
//   <button class="btn" hx-get="/confirm" hx-target="#dialog-host" hx-swap="innerHTML">Delete</button>
//   <div id="dialog-host"></div>
//
//   import { Dialog } from '../../common/widgets/_dialog.tsx';
//   <Dialog dialog={{ title: 'Delete?', body: '…', dismiss: 'Cancel',
//                     actions: [{ label: 'Delete', href: '/done', kind: 'danger' }] }} />
//
// dialog = {
//   title, body,                  // body is plain text (escaped)
//   scrim?: true,                 // renders the dim backdrop (default true)
//   dismiss?: 'Cancel',           // native-close label (form method="dialog");
//                                 // omit for a dialog that must round-trip
//   actions?: [{ label, href, kind? }]  // boosted links (traverse away)
// }
//
// Close paths, pick per dialog:
// - native: <form method="dialog"> (the dismiss button below) — instant, no
//   server roundtrip, no exit animation. Right for confirms/cancels.
// - server: an hx-post/hx-get to a close endpoint that returns 200 with the
//   emptied host (or h.noContent when the host clears some other way). Right
//   when closing must mutate state.
// Clicking the scrim does NOT dismiss (no JS to catch it) — say so in the
// surface's design notes if the frozen product expects it.
//
// For stateless popovers/menus that never need the server, use the native
// popover form instead (button popovertarget + <div popover>, animated by
// motion.css §3) — no endpoint at all.
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (blocks: .dialog, .overlay-scrim).
// Flutter: ui_library sheet/dialog services.
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface DialogAction {
  label: string;
  href: string;
  kind?: string;
}

interface DialogProps {
  dialog: {
    title: string;
    body: string;
    scrim?: boolean;
    dismiss?: string;
    actions?: DialogAction[];
  };
}

export const Dialog: FC<DialogProps> = ({ dialog }) => (
  <>
    {dialog.scrim !== false && <div class="overlay-scrim" aria-hidden="true"></div>}
    <dialog id="dialog" class="dialog" open aria-labelledby="dialog-title">
      <div class="dialog__head">
        <h2 class="dialog__title" id="dialog-title">{dialog.title}</h2>
        {dialog.dismiss && (
          <form method="dialog">
            <button class="icon-btn" type="submit" aria-label={dialog.dismiss}>
              <Icon name="x" size={20} />
            </button>
          </form>
        )}
      </div>
      <div class="dialog__body">
        <p>{dialog.body}</p>
      </div>
      {(dialog.actions || dialog.dismiss) && (
        <div class="dialog__actions">
          {dialog.dismiss && (
            <form method="dialog">
              <button class="btn btn--ghost" type="submit">{dialog.dismiss}</button>
            </form>
          )}
          {dialog.actions?.map((action, actionIndex) => (
            <a class={`btn btn--${action.kind ?? 'ghost'}`} href={action.href} key={actionIndex}>{action.label}</a>
          ))}
        </div>
      )}
    </dialog>
  </>
);
