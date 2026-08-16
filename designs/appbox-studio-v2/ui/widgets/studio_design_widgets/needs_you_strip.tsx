// composedFrom: chip (no single kind realises it — the strip is a row
//   of decision chips, F4 resolution).
// Role: the needs-you strip — the decisions the design stage is waiting
//   on, one chip each. A chip is a POST trigger: deciding is manual,
//   never implicit (Q-v2-1).
// Requirements: Q-v2-1, Q-v2-5, ADR-0002.
// Relationships: composed by all three studio_design_view.<factor>.tsx
//   variants; posts to /design/compose with the chip's decision id.
// History: created for studio v2; chip classes from the v1 gate cards'
//   chip vocabulary per the VISUAL PARITY LAW.
import type { FC } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';

export interface NeedsYouChip {
  id: string;
  label: string;
  detail: string;
}

export interface NeedsYouStripProps {
  label: string;
  chips: NeedsYouChip[];
  stacked?: boolean;
}

const NeedsYouStrip: FC<NeedsYouStripProps> = ({ label, chips, stacked }) => (
  <section
    class={stacked ? 'needs-you needs-you--stacked' : 'needs-you'}
    aria-label={label}
    data-inspect-widget="needs_you_strip"
    data-inspect-role="section"
    data-inspect-style="row of decision chips over the canvas"
    data-inspect-fn="names the decisions the design stage is waiting on"
    data-inspect-motion="notify"
  >
    {chips.map((chip) => (
      <form key={chip.id} method="post" action="/design/compose" class="chip-form">
        <input type="hidden" name="decision" value={chip.id} />
        <button
          type="submit"
          class="chip chip--decision"
          title={chip.detail}
          data-inspect-role="action"
          data-inspect-style="amber decision chip with an alert icon"
          data-inspect-fn={'resolves the ' + chip.label + ' decision'}
          data-inspect-motion="pending"
        >
          <Icon name="alert-circle" size={13} />
          <span>{chip.label}</span>
        </button>
      </form>
    ))}
  </section>
);

export default NeedsYouStrip;
