// Role: hub at the medium rung. Two columns instead of three — the board still
//   reads as a board, but each card keeps a legible measure rather than being
//   squeezed to fit a third column.
// Requirements: Q-v2-1.
// Relationships: mounted by studio_application_hub_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { HubProps } from './studio_application_hub_view.desktop.tsx';

const StudioApplicationHubViewTablet: FC<HubProps> = ({ brand, stages }) => (
  <div class="hub" data-inspect-surface="studio_application_hub">
    <header class="hub__bar">
      <span class="brand" data-inspect-widget="hub_brand">
        <span class="brand__mark" />
        {brand}
      </span>
    </header>
    <main class="hub__body">
      <div class="hub__grid" data-inspect-widget="hub_stage_board">
        {stages.map((s) => (
          <a
            key={s.id}
            class="stage-card"
            href={s.href}
            aria-disabled={s.enabled ? undefined : 'true'}
            data-inspect-widget={`hub_stage_card_${s.id}`}
          >
            <div class="stage-card__name">{s.name}</div>
            <div class="stage-card__io">
              consumes {s.consumes} &rarr; produces {s.produces}
            </div>
          </a>
        ))}
      </div>
    </main>
  </div>
);

export default StudioApplicationHubViewTablet;
