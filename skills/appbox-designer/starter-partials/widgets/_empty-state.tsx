// _empty-state.tsx — empty/zero-results state (replaces _empty-state.html).
// Zero JavaScript. Render it server-side in place of the list — the view
// branches on the data (centered-state archetype: same composition at every
// rung, width capped by CSS):
//
//   import { EmptyState } from '../../common/widgets/_empty-state.tsx';
//   {rows.length > 0 ? (… the list …) : (
//     <EmptyState empty={{ icon: 'inbox', title: 'Nothing here yet' }} />
//   )}
//
// empty = {
//   icon?: 'inbox',              // Lucide kebab-case name (default inbox)
//   title, body?,
//   action?: { label, href }     // optional primary action (boosted link)
// }
//
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (block: .empty-state).
// Flutter: none — compose icon + copy + AppBoxKitNativeButton.
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface EmptyStateProps {
  empty: {
    icon?: string;
    title: string;
    body?: string;
    action?: { label: string; href: string };
  };
}

export const EmptyState: FC<EmptyStateProps> = ({ empty }) => (
  <div class="empty-state">
    <Icon name={empty.icon ?? 'inbox'} size={40} cls="empty-state__icon" />
    <h2 class="empty-state__title">{empty.title}</h2>
    {empty.body && <p class="empty-state__body">{empty.body}</p>}
    {empty.action && (
      <a class="btn" href={empty.action.href}>{empty.action.label}</a>
    )}
  </div>
);
