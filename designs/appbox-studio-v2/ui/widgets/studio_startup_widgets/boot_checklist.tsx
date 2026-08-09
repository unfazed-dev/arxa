// kind: list-row
// Role: the boot sequence as a state-per-step list, plus the trigger that ends
//   the ceremony. Steps and trigger live in one widget because the trigger's
//   enabled state IS the list's terminal state — splitting them would let a
//   rung render one without the other.
// Requirements: Q-v2-1; Q-v2-5 (data-inspect-widget on every emitted widget).
// Relationships: composed by all three studio_startup_view.<factor>.tsx
//   variants and by the #progress Named Fragment; composes proceed_trigger.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import ProceedTrigger from './proceed_trigger.tsx';
import type { BootStep } from '../../views/studio_startup_shell/studio_startup/studio_startup_view.desktop.tsx';

export interface BootChecklistProps {
  steps: BootStep[];
  ready: boolean;
  block?: boolean;
}

const BootChecklist: FC<BootChecklistProps> = ({ steps, ready, block }) => (
  <div
    id="boot-progress"
    data-inspect-widget="boot_checklist"
    hx-get="/startup/progress"
    hx-trigger={ready ? undefined : 'load delay:600ms'}
    hx-swap="outerHTML"
  >
    <ul class="checklist">
      {steps.map((s) => (
        <li key={s.id} class="checklist__item" data-state={s.state}>
          <span class="checklist__dot" />
          <span class={s.state === 'waiting' ? 'muted' : undefined}>{s.label}</span>
        </li>
      ))}
    </ul>
    <div style="margin-top: 24px;">
      <ProceedTrigger href="/startup/proceed" label="Open the studio" ready={ready} block={block} />
    </div>
  </div>
);

export default BootChecklist;
