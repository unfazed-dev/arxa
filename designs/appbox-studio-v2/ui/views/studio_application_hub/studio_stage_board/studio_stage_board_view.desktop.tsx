// Role: the board at the expanded rung — a multi-column grid. At this width
//   every stage is visible at once, which is the whole point of a hub: the
//   pipeline is a shape you scan, not a list you page through.
// Requirements: Q-v2-1, Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_stage_board_view.tsx; composes
//   widgets/stage_board.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import StageBoard from './widgets/stage_board.tsx';
import type { StageCardData } from './widgets/stage_card.tsx';

export interface BoardProps {
  brand: string;
  stages: StageCardData[];
  title: string;
  subtitle: string;
  consumesLabel: string;
  producesLabel: string;
}

const StudioStageBoardViewDesktop: FC<BoardProps> = ({ stages, title, subtitle, consumesLabel, producesLabel }) => (
  <div data-inspect-surface="studio_stage_board">
    <h1 class="title">{title}</h1>
    <p class="subtitle">{subtitle}</p>
    <StageBoard stages={stages} consumesLabel={consumesLabel} producesLabel={producesLabel} density="wide" />
  </div>
);

export default StudioStageBoardViewDesktop;
