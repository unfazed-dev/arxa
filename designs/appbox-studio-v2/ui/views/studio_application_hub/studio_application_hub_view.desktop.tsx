// Role: hub at the expanded rung. The stage roster is a three-column board —
//   the whole pipeline is visible at once, which is the point of the widest
//   rung: no scrolling to learn what the studio does.
// Requirements: Q-v2-1 (every stage names what it consumes and produces).
// Relationships: mounted by studio_application_hub_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';

export interface Stage {
  id: string;
  name: string;
  consumes: string;
  produces: string;
  href: string;
  enabled: boolean;
}

export interface HubProps {
  brand: string;
  stages: Stage[];
}

const StudioApplicationHubViewDesktop: FC<HubProps> = ({ brand, stages }) => (
  <div class="hub" data-inspect-surface="studio_application_hub">
    <header class="hub__bar">
      <span class="brand" data-inspect-widget="hub_brand">
        <span class="brand__mark" />
        {brand}
      </span>
      <span class="muted">pipeline</span>
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

export default StudioApplicationHubViewDesktop;
