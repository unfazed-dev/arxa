// interview_view.tsx — the interview intake step (replaces interview_view.html).
// A horizontal question carousel. Default export InterviewView: wraps
// StudioIntakeShellView → Base. Named fragment exports dispatch the htmx routes
// registered in interview_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../widgets/common/studio_primitives/widgets.tsx';
import StudioIntakeShellView from '../studio_intake_shell_view.tsx';
import * as SH from '../shared.tsx';
import type { Ctx, Carousel, Question } from '../shared.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

const DEPTHS = ['simple', 'normal', 'advanced'] as const;

// Mode pick: three selectable cards, the journey's first move.
function ModeCards({ context, translate }: { context: Ctx; translate: TFn }) {
  return (
    <div class="mode-cards" {...inspectAttrs('intake-interview:mode-cards', { role: 'group' })}>
      {DEPTHS.map((depth) => (
        <form key={depth} method="post" action={`${context.base}/depth`} hx-post={`${context.base}/depth`} hx-target="#panels" hx-swap="outerMorph">
          <button type="submit" class="mode-card" name="depth" value={depth} {...inspectAttrs('intake-interview:mode-card', { role: 'action', fn: 'submit' })}>
            <Label name="intake-interview:mode-name" class="mode-name">{translate(`intake.bank.${depth}`) as string}</Label>
            <Label name="intake-interview:mode-desc" class="mode-desc muted">{translate(`intake.mode.desc.${depth}`) as string}</Label>
          </button>
        </form>
      ))}
    </div>
  );
}

// The answered summary: every question with its answer, re-openable.
function AnswersSummary({ context, car, translate }: { context: Ctx; car: Carousel; translate: TFn }) {
  return (
    <div class="step-summary">
      <Heading name="intake-interview:summary-title" level={2} class="display">{translate('intake.interview.summaryTitle') as string}</Heading>
      <Txt name="intake-interview:summary-lede" class="artifact-lede">{translate('intake.interview.summaryLede') as string}</Txt>
      {(car.questions ?? []).map((question: Question) => (
        <div key={question.id} class={`q-card is-${question.state ?? ''}`}>
          <Txt name="intake-interview:q-text" class="q-text">{question.text}</Txt>
          {question.state === 'answered' ? (
            <Fragment>
              <Txt name="intake-interview:q-answer" class="q-answer">{question.answer}</Txt>
              <a class="q-edit" href={`${context.base}/edit?q=${question.id}`}
                 hx-get={`${context.base}/edit?q=${question.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false" {...inspectAttrs('intake-interview:q-edit', { role: 'action', fn: 'edit' })}>{translate('intake.edit') as string}</a>
            </Fragment>
          ) : question.state === 'skipped' ? (
            <Fragment>
              <Txt name="intake-interview:q-skipped" class="q-answer muted">{translate('intake.skipped') as string}</Txt>
              <a class="q-edit" href={`${context.base}/edit?q=${question.id}`}
                 hx-get={`${context.base}/edit?q=${question.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false" {...inspectAttrs('intake-interview:q-edit', { role: 'action', fn: 'edit' })}>{translate('intake.answerAnyway') as string}</a>
            </Fragment>
          ) : null}
        </div>
      ))}
    </div>
  );
}

function InterviewStage({ context, translate }: { context: Ctx; translate: TFn }) {
  const carousel = context.carousel;
  const step = context.step;
  return (
    <section class="mp-content step-stage" id="mp-content" aria-live="polite">
      <header class="step-head">
        <Label name="intake-interview:eyebrow" class="eyebrow">{context.eyebrow}</Label>
        {carousel ? <Label name="intake-interview:bank-label" class="chip chip--muted">{carousel.bankLabel}</Label> : null}
        {step?.total ? <Label name="intake-interview:step-progress" class="chip chip--muted">{translate('intake.step.progress', { done: step.done, total: step.total }) as string}</Label> : null}
      </header>
      {!carousel ? (
        <Fragment>
          <Heading name="intake-interview:mode-title" level={2} class="display">{translate('intake.interview.modeTitle') as string}</Heading>
          <Txt name="intake-interview:mode-lede" class="artifact-lede">{translate('intake.interview.modeLede') as string}</Txt>
          <ModeCards context={context} translate={translate} />
        </Fragment>
      ) : step?.complete && !carousel.editing ? (
        <Fragment>
          <AnswersSummary context={context} car={carousel} translate={translate} />
          <div class="step-foot"><a class="cta-main" href={step.nextHref} {...inspectAttrs('intake-interview:next', { role: 'action', fn: 'navigate' })}>{translate(step.nextLabel as string) as string} <Icon name="chevron-right" size={14} /></a></div>
        </Fragment>
      ) : (
        <Fragment>
          {(carousel.questions ?? [])
            .filter((question) => question.state === 'current' || question.state === 'editing')
            .map((question) => <SH.QCard key={question.id} context={context} q={question} translate={translate} />)}
          <SH.QStrip context={context} car={carousel} translate={translate} />
        </Fragment>
      )}
    </section>
  );
}

// The main panel's content: the open file, else the interview stage.
function MainContent({ context, translate }: { context: Ctx; translate: TFn }) {
  if (context.fileView) return <SH.FileView context={context} translate={translate} />;
  return <InterviewStage context={context} translate={translate} />;
}

function Panels({ context, translate }: { context: Ctx; translate: TFn }) {
  return <SH.Panels context={context} translate={translate}><MainContent context={context} translate={translate} /></SH.Panels>;
}

// ---------- Fragment responses ----------

export function PanelsSwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return (
    <Fragment>
      <Panels context={context} translate={translate} />
      <SH.Timeline context={context} translate={translate} oob={true} />
    </Fragment>
  );
}

export function ActivitySwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return <SH.ActivitySwap context={context} translate={translate} />;
}

export function FileSwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return <MainContent context={context} translate={translate} />;
}

export function ActivityFrameSwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return <SH.ActivityPanel context={context} translate={translate} />;
}

// ---------- Page ----------

interface ViewProps {
  translate: TFn;
  [key: string]: unknown;
}

const InterviewView: FC<ViewProps> = (context) => {
  const { translate } = context;
  return (
    <StudioIntakeShellView
      title={translate('intake.interview.pageTitle') as string}
      mainClass="shell-main-loop"
      activeShell={context.activeShell as string}
      prefs={context.prefs as { accent?: string; [k: string]: unknown }}
      project={context.project as { name?: string; savedLabel?: string }}
      locale={context.locale as string}
      translate={translate}
      footer={<SH.Timeline context={context as Ctx} translate={translate} oob={false} />}
      surface={<Panels context={context as Ctx} translate={translate} />}
    />
  );
};

export default InterviewView;
