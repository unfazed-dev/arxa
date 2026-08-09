// kind: list-row
// Role: the roster as a board. Owns the iteration over stages so the rung
//   variants stay declarative — they pick a density, not a loop.
// Requirements: Q-v2-1 (pipeline<->shell coherence), Q-v2-5.
// Relationships: composed by all three studio_stage_board_view.<factor>.tsx
//   variants; composes stage_card.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import StageCard from './stage_card.tsx';
import type { StageCardData } from './stage_card.tsx';

export interface StageBoardProps {
  stages: StageCardData[];
  consumesLabel: string;
  producesLabel: string;
  /** wide | pair | stack — the rung picks the density, the board keeps the law. */
  density: 'wide' | 'pair' | 'stack';
  compact?: boolean;
}

const StageBoard: FC<StageBoardProps> = ({ stages, consumesLabel, producesLabel, density, compact }) => (
  <div
    class={`hub__grid hub__grid--${density}`}
    data-el="list-row"
    data-inspect-role="section"
    data-inspect-style="card grid · one tile per pipeline stage"
    data-inspect-fn="lists every stage the studio can open"
    data-inspect-motion="none"
    data-inspect-widget="stage_board"
  >
    {stages.map((s) => (
      <StageCard
        key={s.id}
        stage={s}
        consumesLabel={consumesLabel}
        producesLabel={producesLabel}
        compact={compact}
      />
    ))}
  </div>
);

export default StageBoard;
