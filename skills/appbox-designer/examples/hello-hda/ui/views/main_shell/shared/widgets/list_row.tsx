// list_row.tsx — one list row (replaces _list-row.html).
// Conditionally renders as <a> or <div> based on row.href.
import type { FC } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';

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

const ListRow: FC<ListRowProps> = ({ row }) => {
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
      {(row.href && row.chevron === undefined || row.chevron) && (
        <Icon name="chevron-right" size={18} cls="list-row__chevron" />
      )}
    </Tag>
  );
};

export default ListRow;
