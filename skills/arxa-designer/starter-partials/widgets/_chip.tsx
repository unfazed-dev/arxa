// _chip.tsx — status/filter chip (replaces _chip.html).
// Zero JavaScript. Render one per chip, typically inside a wrapping row:
//
//   import { Chip } from '../../common/widgets/_chip.tsx';
//   <div class="chip-row">
//     {chips.map((chip, i) => <Chip chip={chip} key={i} />)}
//   </div>
//
// chip = {
//   label: string,             // required
//   tone?: 'accent' | 'muted', // optional; default accent
//   sm?: true,                 // optional; compact sizing
//   removeHref?: string        // optional; GET removes the chip in place
//                              // (hx-target is this chip, hx-swap outerHTML;
//                              // the route responds with an empty body)
// }
//
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (block: .chip).
// Flutter: ArxaKitChip / ArxaKitFilterChip.
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface ChipProps {
  chip: {
    label: string;
    tone?: 'accent' | 'muted';
    sm?: boolean;
    removeHref?: string;
  };
}

export const Chip: FC<ChipProps> = ({ chip }) => (
  <span class={`chip chip--${chip.tone ?? 'accent'}${chip.sm ? ' chip--sm' : ''}`}>
    {chip.label}
    {chip.removeHref && (
      <a
        class="chip__remove"
        href={chip.removeHref}
        hx-get={chip.removeHref}
        hx-target="closest .chip"
        hx-swap="outerHTML"
        aria-label={`Remove ${chip.label}`}
      >
        <Icon name="x" size={12} />
      </a>
    )}
  </span>
);
