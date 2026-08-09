// kind: list-row
// Role: the boot sequence as a state-per-step list, plus the trigger that ends
//   the ceremony. Steps and trigger live in one widget because the trigger's
//   enabled state IS the list's terminal state — splitting them would let a
//   rung render one without the other.
// Requirements: Q-v2-1; Q-v2-5 (inspect triple + annotation quad on every
//   emitted element).
// Relationships: composed by all three studio_startup_view.<factor>.tsx
//   variants and by the #progress Named Fragment; composes proceed_trigger.tsx.
// History: created for studio v2. Self-polling removed: the widget carried
//   hx-get="/startup/progress" + hx-swap="outerHTML", which deleted the element
//   owning the in-flight request on every swap — htmx aborted its own poll
//   (AbortError) ~3x per 600ms cycle, so every rung failed the console gate. A
//   prototype has no real boot to observe; the sequence is driven by hand with
//   ?step= (see studio_startup_viewmodel.js), which also keeps goldens
//   deterministic. The trigger, not a timer, still ends the ceremony (Q-v2-1).
import type { FC } from 'hono/jsx';
import ProceedTrigger from './proceed_trigger.tsx';

export interface BootStep {
  id: string;
  label: string;
  state: 'done' | 'running' | 'waiting';
}

export interface BootChecklistProps {
  steps: BootStep[];
  ready: boolean;
  proceedLabel: string;
  block?: boolean;
}

const BootChecklist: FC<BootChecklistProps> = ({ steps, ready, proceedLabel, block }) => (
  <div
    id="boot-progress"
    data-el="list-row"
    data-inspect-role="section"
    data-inspect-style="stacked step list over a single trigger"
    data-inspect-fn="reports boot progress and releases the hand-off when every step lands"
    data-inspect-motion="pending"
    data-inspect-widget="boot_checklist"
  >
    <ul class="checklist">
      {steps.map((s) => (
        <li
          key={s.id}
          class="checklist__item"
          data-state={s.state}
          data-el="list-row__item"
          data-inspect-role="list row"
          data-inspect-style="dot + label, dimmed until the step runs"
          data-inspect-fn="names one boot step and shows whether it is done, running or waiting"
          data-inspect-motion="reveal"
        >
          <span
            class="checklist__dot"
            data-el="list-row__dot"
            data-inspect-role="badge"
            data-inspect-style="small round marker, filled once the step is done"
            data-inspect-fn="shows this step's state at a glance"
            data-inspect-motion="notify"
          />
          <span
            data-el="list-row__label"
            data-inspect-role="label"
            data-inspect-style="step name, muted while waiting"
            data-inspect-fn="names the artifact this step needs"
            data-inspect-motion="none"
            class={s.state === 'waiting' ? 'muted' : undefined}
          >
            {s.label}
          </span>
        </li>
      ))}
    </ul>
    <div
      class="checklist__footer"
      data-el="list-row__footer"
      data-inspect-role="section"
      data-inspect-style="trigger row under the step list"
      data-inspect-fn="holds the manual hand-off out of the ceremony"
      data-inspect-motion="none"
    >
      <ProceedTrigger href="/startup/proceed" label={proceedLabel} ready={ready} block={block} />
    </div>
  </div>
);

export default BootChecklist;
