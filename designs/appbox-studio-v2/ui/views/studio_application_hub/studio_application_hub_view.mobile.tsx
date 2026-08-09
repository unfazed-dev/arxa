// Role: hub at the compact rung. The board collapses to a single ordered
//   list — at this width the pipeline is a sequence you walk, not a board you
//   survey, so the stage index is shown and the I/O line wraps under the name.
// Requirements: Q-v2-1.
// Relationships: mounted by studio_application_hub_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { HubProps } from './studio_application_hub_view.desktop.tsx';

const StudioApplicationHubViewMobile: FC<HubProps> = ({ brand, stages }) => (
  <div class="hub" data-inspect-surface="studio_application_hub">
    <header class="hub__bar">
      <span class="brand" data-inspect-widget="hub_brand">
        <span class="brand__mark" />
        {brand}
      </span>
    </header>
    <main class="hub__body">
      <ol class="hub__grid" style="list-style: none; margin: 0; padding: 0;" data-inspect-widget="hub_stage_board">
        {stages.map((s, i) => (
          <li key={s.id}>
            <a
              class="stage-card"
              href={s.href}
              aria-disabled={s.enabled ? undefined : 'true'}
              data-inspect-widget={`hub_stage_card_${s.id}`}
            >
              <div class="stage-card__name">
                <span class="muted">{i + 1}.</span> {s.name}
              </div>
              <div class="stage-card__io">consumes {s.consumes}</div>
              <div class="stage-card__io">produces {s.produces}</div>
            </a>
          </li>
        ))}
      </ol>
    </main>
  </div>
);

export default StudioApplicationHubViewMobile;
