// kind: card
// Role: one pipeline stage as a board card — the board's repeated unit. It
//   carries the whole card, link included, so the three rung variants compose
//   it instead of each re-authoring the same anchor and label stack.
// Requirements: Q-v2-1 (a card names the stage it fronts and its
//   consumes/produces contract); Q-v2-5 (inspect triple + annotation quad).
// Relationships: composed by stage_board.tsx. Surface-scoped: the board is its
//   only consumer.
// History: created for studio v2.
import type { FC } from 'hono/jsx';

export interface StageCardData {
  id: string;
  name: string;
  brand: string;
  href: string;
  enabled: boolean;
  consumes: string;
  produces: string;
}

export interface StageCardProps {
  stage: StageCardData;
  consumesLabel: string;
  producesLabel: string;
  /** compact drops the io line — at phone width the stage name and its state
   *  are the decision; the contract is detail the user opens the stage to read. */
  compact?: boolean;
}

const StageCard: FC<StageCardProps> = ({ stage, consumesLabel, producesLabel, compact }) => (
  <a
    data-el="card"
    data-inspect-role="card"
    data-inspect-style="bordered tile · stage name over its io contract"
    data-inspect-fn="opens the shell that fronts this pipeline stage"
    data-inspect-motion="traverse"
    data-inspect-widget="stage_card"
    class={`stage-card${stage.enabled ? '' : ' stage-card--disabled'}`}
    href={stage.enabled ? stage.href : undefined}
    aria-disabled={stage.enabled ? undefined : 'true'}
    data-brand={stage.brand}
  >
    <span
      class="stage-card__name"
      data-el="card__title"
      data-inspect-role="heading"
      data-inspect-style="stage name, one line, brand-tinted"
      data-inspect-fn="names the stage this card opens"
      data-inspect-motion="none"
    >
      {stage.name}
    </span>
    {compact ? null : (
      <span
        class="stage-card__io"
        data-el="card__meta"
        data-inspect-role="label"
        data-inspect-style="muted one-liner under the name"
        data-inspect-fn="states what the stage consumes and what it produces"
        data-inspect-motion="none"
      >
        {consumesLabel} {stage.consumes} &rarr; {producesLabel} {stage.produces}
      </span>
    )}
  </a>
);

export default StageCard;
