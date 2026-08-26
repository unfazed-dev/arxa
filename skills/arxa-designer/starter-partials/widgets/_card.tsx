// _card.tsx — content card (replaces _card.html).
// Zero JavaScript. Render one per card, typically inside a .card-grid (the
// dashboard-stack archetype: 1 → 2 → 3 columns across the ladder):
//
//   import { Card } from '../../common/widgets/_card.tsx';
//   <div class="card-grid">
//     {cards.map((card) => <Card card={card} key={card.id} />)}
//   </div>
//
// card = {
//   id: '7',                  // required; the root id is card-<id>, so the
//                             // card can be an htmx/OOB target
//   media?: '/assets/images/x.jpg',   // optional image URL
//   title?, subtitle?, body?,         // body is plain text (escaped)
//   actions?: [{ label, href, kind? }],      // ghost buttons, optional
//   vt?: true                 // optional spotlight: tags the card with a
//                             // stable view-transition-name for a shared-
//                             // element morph across boosted navigation
//                             // (name derived per-record, per motion.css §2)
// }
//
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (blocks: .card, .card-grid).
// Flutter: ArxaKitGlassCard / ArxaKitFrostedSurface.
import type { FC } from 'hono/jsx';

interface CardAction {
  label: string;
  href: string;
  kind?: string;
}

interface CardProps {
  card: {
    id: string;
    media?: string;
    title?: string;
    subtitle?: string;
    body?: string;
    actions?: CardAction[];
    vt?: boolean;
  };
}

export const Card: FC<CardProps> = ({ card }) => (
  <article
    id={`card-${card.id}`}
    class="card"
    style={card.vt ? `view-transition-name: card-${card.id};` : undefined}
  >
    {card.media && <img class="card__media" src={card.media} alt="" />}
    {card.title && <h3 class="card__title">{card.title}</h3>}
    {card.subtitle && <p class="card__subtitle">{card.subtitle}</p>}
    {card.body && <p class="card__body">{card.body}</p>}
    {card.actions && (
      <div class="card__actions">
        {card.actions.map((action, actionIndex) => (
          <a class={`btn btn--${action.kind ?? 'ghost'}`} href={action.href} key={actionIndex}>{action.label}</a>
        ))}
      </div>
    )}
  </article>
);
