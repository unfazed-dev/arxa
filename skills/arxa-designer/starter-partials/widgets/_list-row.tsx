// _list-row.tsx — one list row (replaces _list-row.html).
// Zero JavaScript. Rows live inside a section card; the surface loops:
//
//   import { ListRow } from '../../common/widgets/_list-row.tsx';
//   <section class="list-section">
//     <h2 class="list-section__header">General</h2>
//     <div class="list-section__card">
//       {rows.map((row) => <ListRow row={row} key={row.id} />)}
//     </div>
//   </section>
//
// row = {
//   id: '42',                   // required; the root id is row-<id>, so a
//                               // mutation response can re-render one row
//   title, subtitle?, detail?,
//   icon?,                      // Lucide kebab-case name for the leading tile
//   href?,                      // makes the whole row a link (+ chevron)
//   chevron?,                   // default: shown when href is set
//   oob?                        // true: root carries hx-swap-oob="outerHTML"
//                               // (targets its own id — the updated-row pattern)
// }
//
// Row update flow: POST mutates one record; the handler responds
// hx-swap="none" + renders this row with row.oob = true — htmx swaps the
// updated row over the old one in place (`swap` motion).
//
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (blocks: .list-section, .list-row).
// Flutter: ArxaKitListTile (row), ArxaKitListSection (grouped card + header).
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface ListRowProps {
  row: {
    id: string;
    title: string;
    subtitle?: string;
    detail?: string;
    icon?: string;
    href?: string;
    chevron?: boolean;
    oob?: boolean;
  };
}

export const ListRow: FC<ListRowProps> = ({ row }) => {
  const Tag = row.href ? 'a' : 'div';
  return (
    <Tag
      id={`row-${row.id}`}
      class="list-row"
      hx-swap-oob={row.oob ? 'outerHTML' : undefined}
      href={row.href}
    >
      {row.icon && (
        <span class="list-row__leading">
          <Icon name={row.icon} size={18} />
        </span>
      )}
      <span class="list-row__text">
        <span class="list-row__title">{row.title}</span>
        {row.subtitle && <span class="list-row__subtitle">{row.subtitle}</span>}
      </span>
      {row.detail && <span class="list-row__detail">{row.detail}</span>}
      {((row.href && row.chevron === undefined) || row.chevron) && (
        <Icon name="chevron-right" size={18} cls="list-row__chevron" />
      )}
    </Tag>
  );
};
