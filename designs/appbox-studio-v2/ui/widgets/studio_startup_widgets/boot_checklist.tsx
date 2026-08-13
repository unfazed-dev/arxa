// kind: list-row
// Role: the boot sequence as a state-per-step list, plus the trigger that ends
//   the ceremony. Steps and trigger live in one widget because the trigger's
//   enabled state IS the list's terminal state — splitting them would let a
//   rung render one without the other.
// Requirements: Q-v2-1; Q-v2-5 (inspect triple + annotation quad on every
//   emitted element).
// Relationships: composed by all three studio_startup_view.<factor>.tsx
//   variants and by the #progress Named Fragment; composes proceed_trigger.tsx.
// History: created for studio v2. Self-polling removed (htmx aborted its own
//   poll — see git history). Restyled to the v1 splash step list per user
//   directive (task #22): ol.startup-steps / li.startup-step with is-done /
//   is-current states, check icon on done steps, dot marker otherwise. The
//   done/running/waiting state model is unchanged; only the emitted classes
//   moved to the v1 vocabulary so v1 appshell.css styles them.
import type { FC } from 'hono/jsx';
import ProceedTrigger from './proceed_trigger.tsx';
import Icon from '../../../runtime/icon.tsx';

export interface BootStep {
  id: string;
  label: string;
  state: 'done' | 'running' | 'waiting';
}

export interface BootChecklistProps {
  steps: BootStep[];
  ready: boolean;
  proceedLabel: string;
  /** Proceed endpoint; carries the boot guard's validated ?to return-to (R3). */
  proceedHref?: string;
  block?: boolean;
}

const stepClass = (state: BootStep['state']): string =>
  state === 'done' ? 'startup-step is-done' : state === 'running' ? 'startup-step is-current' : 'startup-step';

const BootChecklist: FC<BootChecklistProps> = ({ steps, ready, proceedLabel, proceedHref, block }) => (
  <div
    data-el="list-row"
    data-inspect-role="section"
    data-inspect-style="v1 splash step list over a single trigger"
    data-inspect-fn="reports boot progress and releases the hand-off when every step lands"
    data-inspect-motion="pending"
    data-inspect-widget="boot_checklist"
  >
    <ol class="startup-steps">
      {steps.map((step) => (
        <li
          key={step.id}
          class={stepClass(step.state)}
          data-state={step.state}
          data-el="list-row__item"
          data-inspect-role="list row"
          data-inspect-style="check or dot + label, dimmed until the step runs"
          data-inspect-fn="names one boot step and shows whether it is done, running or waiting"
          data-inspect-motion="reveal"
        >
          {step.state === 'done' ? (
            <Icon name="check" size={14} />
          ) : (
            <span
              class="startup-dot"
              data-el="list-row__dot"
              data-inspect-role="badge"
              data-inspect-style="small round marker, pulsing while the step runs"
              data-inspect-fn="shows this step's state at a glance"
              data-inspect-motion="notify"
            />
          )}
          <span
            data-el="list-row__label"
            data-inspect-role="label"
            data-inspect-style="step name, muted while waiting"
            data-inspect-fn="names the artifact this step needs"
            data-inspect-motion="none"
            class={step.state === 'waiting' ? 'muted' : undefined}
          >
            {step.label}
          </span>
        </li>
      ))}
    </ol>
    <div
      class="checklist__footer"
      data-el="list-row__footer"
      data-inspect-role="section"
      data-inspect-style="trigger row under the step list"
      data-inspect-fn="holds the manual hand-off out of the ceremony"
      data-inspect-motion="none"
    >
      <ProceedTrigger href={proceedHref ?? '/startup/proceed'} label={proceedLabel} ready={ready} block={block} />
    </div>
  </div>
);

export default BootChecklist;
