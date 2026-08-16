// kind: panel-activity
// Role: the activity panel — the design stage's event log as a timed
//   list. Desktop-only rail (the registry mounts it in the full studio
//   arrangement; tablet/mobile drop it, not fold it — it is ambient, not
//   blocking).
// Requirements: Q-v2-3, Q-v2-5, ADR-0002.
// Relationships: composed by studio_design_view.desktop.tsx.
// History: created for studio v2; panel vocabulary from v1 panels.css
//   per the VISUAL PARITY LAW.
import type { FC } from 'hono/jsx';

export interface ActivityItem {
  id: string;
  time: string;
  actor: string;
  event: string;
}

export interface ActivityPanelProps {
  title: string;
  items: ActivityItem[];
}

const ActivityPanel: FC<ActivityPanelProps> = ({ title, items }) => (
  <aside
    class="panel-activity"
    aria-labelledby="activity-h"
    data-inspect-widget="activity"
    data-inspect-role="section"
    data-inspect-style="left rail event log, one row per event"
    data-inspect-fn="shows what the design stage has been doing"
    data-inspect-motion="reveal"
  >
    <h2
      id="activity-h"
      class="panel-activity-title"
      data-inspect-role="heading"
      data-inspect-style="small section heading"
      data-inspect-fn="names the activity rail"
      data-inspect-motion="none"
    >
      {title}
    </h2>
    <ol
      class="activity-list"
      data-el="list-row__item"
      data-inspect-role="list"
      data-inspect-style="timed rows: time, actor, event"
      data-inspect-fn="records the stage's recent events"
      data-inspect-motion="reveal"
    >
      {items.map((item) => (
        <li key={item.id} class="activity-row">
          <span class="activity-time muted">{item.time}</span>
          <span class="activity-actor">{item.actor}</span>
          <span class="activity-event muted">{item.event}</span>
        </li>
      ))}
    </ol>
  </aside>
);

export default ActivityPanel;
