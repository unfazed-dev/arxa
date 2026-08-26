// _bottom-sheet.tsx — server-driven action sheet (replaces _bottom-sheet.html).
// Zero JavaScript. Same host/swap mechanics as _dialog.tsx: a trigger swaps
// the rendered component into an empty host; the sheet renders OPEN and
// slides in (`reveal` motion, widgets.css):
//
//   <button class="btn" hx-get="/share-sheet" hx-target="#sheet-host" hx-swap="innerHTML">Share</button>
//   <div id="sheet-host"></div>
//
//   import { BottomSheet } from '../../common/widgets/_bottom-sheet.tsx';
//   <BottomSheet sheet={{ title: 'Share', items: [...], dismiss: 'Cancel' }} />
//
// sheet = {
//   title?,                       // small header above the list
//   items: [{ icon?, label, href, danger? }],
//   dismiss?: 'Cancel'            // footer close, native form method="dialog"
// }
//
// Items are boosted links: picking one navigates (traverse motion) and the
// sheet's host simply isn't rendered by the next page. Close paths are the
// same as _dialog.tsx (native dismiss vs server close endpoint); the scrim
// does not click-to-dismiss (no JS).
//
// Ladder: bottom-anchored sheet on compact; from the medium rung up it
// presents as a centered dialog (M3 behaviour — CSS only, same markup).
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (blocks: .sheet, .overlay-scrim).
// Flutter: ui_library sheet service.
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface BottomSheetItem {
  icon?: string;
  label: string;
  href: string;
  danger?: boolean;
}

interface BottomSheetProps {
  sheet: {
    title?: string;
    items: BottomSheetItem[];
    dismiss?: string;
  };
}

export const BottomSheet: FC<BottomSheetProps> = ({ sheet }) => (
  <>
    <div class="overlay-scrim" aria-hidden="true"></div>
    <dialog id="sheet" class="sheet" open aria-labelledby={sheet.title ? 'sheet-title' : undefined}>
      <div class="sheet__grab" aria-hidden="true"></div>
      {sheet.title && (
        <h2 class="sheet__title" id="sheet-title">{sheet.title}</h2>
      )}
      <ul class="sheet__list">
        {sheet.items.map((item, i) => (
          <li key={i}>
            <a class={`sheet__item${item.danger ? ' sheet__item--danger' : ''}`} href={item.href}>
              {item.icon && <Icon name={item.icon} size={20} />}
              <span>{item.label}</span>
            </a>
          </li>
        ))}
      </ul>
      {sheet.dismiss && (
        <ul class="sheet__list">
          <li>
            <form method="dialog">
              <button class="sheet__item sheet__dismiss" type="submit">
                <span>{sheet.dismiss}</span>
              </button>
            </form>
          </li>
        </ul>
      )}
    </dialog>
  </>
);
