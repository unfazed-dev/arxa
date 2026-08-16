// composedFrom: list-row + form-field (no single kind realises it — the
//   thread is a turn list plus a composer, F4 resolution).
// Role: the interview as a vertical thread — the v1 question carousel
//   restructured. Mode cards (simple/normal/advanced) lead; answered
//   turns render as v1 q-cards; the current question's composer pins
//   the bottom. Every turn state is reachable by hand — nothing
//   self-advances.
// Requirements: Q-v2-1 (manual advancement), Q-v2-5 (inspect triple +
//   annotation quad), VISUAL PARITY LAW (q-card/mode-card vocabulary).
// Relationships: composed by all three studio_intake_view.<factor>.tsx
//   variants; posts to /intake/answer (studio_intake_viewmodel.js).
// History: created for studio v2; classes carried from v1
//   interview_view.tsx.
import type { FC } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import type { InterviewMode, InterviewTurn } from '../../views/studio_intake_shell/studio_intake/studio_intake_view.desktop.tsx';

export interface InterviewThreadProps {
  modes: InterviewMode[];
  turns: InterviewTurn[];
  currentQuestion: string;
  answerLabel: string;
  answerPlaceholder: string;
  skipLabel: string;
  /** compact rung: composer pins to the bottom of the scroll column */
  stacked?: boolean;
}

const turnClass = (state: InterviewTurn['state']): string =>
  state === 'answered' ? 'q-card is-answered' : state === 'skipped' ? 'q-card is-skipped' : 'q-card is-current';

const InterviewThread: FC<InterviewThreadProps> = ({ modes, turns, currentQuestion, answerLabel, answerPlaceholder, skipLabel, stacked }) => (
  <div
    class={stacked ? 'interview-thread interview-thread--stacked' : 'interview-thread'}
    data-el="list-row"
    data-inspect-widget="interview_thread"
    data-inspect-role="section"
    data-inspect-style="v1 q-card vocabulary as a vertical thread, composer pinned last"
    data-inspect-fn="carries the interview turns and collects the current answer"
    data-inspect-motion="reveal"
  >
    <div
      class="mode-cards"
      data-inspect-role="group"
      data-inspect-style="three selectable cards — the journey's first move"
      data-inspect-fn="picks the interview depth"
      data-inspect-motion="none"
    >
      {modes.map((mode) => (
        <form key={mode.id} method="post" action="/intake/answer">
          <input type="hidden" name="mode" value={mode.id} />
          <button
            type="submit"
            class="mode-card"
            name="depth"
            value={mode.id}
            data-inspect-role="action"
            data-inspect-style="selectable card with name and description"
            data-inspect-fn={'picks the ' + mode.name + ' interview depth'}
            data-inspect-motion="pending"
          >
            <span class="mode-name">{mode.name}</span>
            <span class="mode-desc muted">{mode.desc}</span>
          </button>
        </form>
      ))}
    </div>
    <ol
      class="thread-turns"
      data-el="list-row__item"
      data-inspect-role="list"
      data-inspect-style="answered and skipped turns as v1 q-cards"
      data-inspect-fn="shows every question the interview already covered"
      data-inspect-motion="reveal"
    >
      {turns.map((turn) => (
        <li key={turn.id} class={turnClass(turn.state)}>
          <span
            class="q-text"
            data-inspect-role="text"
            data-inspect-style="the question, verbatim"
            data-inspect-fn="restates what was asked"
            data-inspect-motion="none"
          >
            {turn.question}
          </span>
          {turn.state === 'answered' ? (
            <span
              class="q-answer"
              data-inspect-role="text"
              data-inspect-style="the recorded answer under its question"
              data-inspect-fn="records the client's answer"
              data-inspect-motion="none"
            >
              {turn.answer}
            </span>
          ) : (
            <span
              class="q-answer muted"
              data-inspect-role="text"
              data-inspect-style="skipped marker for an unanswered turn"
              data-inspect-fn="marks the turn as skipped, not lost"
              data-inspect-motion="none"
            >
              <Icon name="skip-forward" size={12} />
            </span>
          )}
        </li>
      ))}
    </ol>
    <form
      class="thread-composer"
      method="post"
      action="/intake/answer"
      data-el="form-field"
      data-inspect-role="form"
      data-inspect-style="current question over input row with submit and skip"
      data-inspect-fn="collects the current answer — the interview's one live trigger"
      data-inspect-motion="none"
    >
      <p
        class="q-text q-text--current"
        data-inspect-role="text"
        data-inspect-style="the current question, emphasised"
        data-inspect-fn="asks what the thread is waiting on"
        data-inspect-motion="none"
      >
        {currentQuestion}
      </p>
      <div class="composer-row">
        <input
          type="text"
          name="answer"
          aria-label={answerLabel}
          placeholder={answerPlaceholder}
          data-el="form-field__input"
          data-inspect-role="input"
          data-inspect-style="single-line answer input"
          data-inspect-fn="holds the answer being composed"
          data-inspect-motion="none"
        />
        <button
          type="submit"
          class="btn btn--primary"
          data-el="cta-link"
          data-inspect-role="button"
          data-inspect-style="primary submit beside the input"
          data-inspect-fn="records the answer and moves the thread"
          data-inspect-motion="pending"
        >
          {answerLabel}
        </button>
        <button
          type="submit"
          name="skip"
          value="1"
          class="btn ghost"
          data-inspect-role="button"
          data-inspect-style="quiet skip trigger"
          data-inspect-fn="skips the question without losing it"
          data-inspect-motion="pending"
        >
          {skipLabel}
        </button>
      </div>
    </form>
  </div>
);

export default InterviewThread;
