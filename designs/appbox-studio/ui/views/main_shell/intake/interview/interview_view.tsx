// interview_view.tsx — the interview intake step (replaces interview_view.html).
// A horizontal question carousel. Default export InterviewView: wraps
// MainShellView → Base. Named fragment exports dispatch the htmx routes
// registered in interview_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../../common/widgets/primitives.tsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx, Carousel, Question } from '../_shared.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

const DEPTHS = ['simple', 'normal', 'advanced'] as const;

// Mode pick: three selectable cards, the journey's first move.
function ModeCards({ c, translate }: { c: Ctx; translate: TFn }) {
  return (
    <div class="mode-cards" {...inspectAttrs('intake-interview:mode-cards', { role: 'group' })}>
      {DEPTHS.map((d) => (
        <form key={d} method="post" action={`${c.base}/depth`} hx-post={`${c.base}/depth`} hx-target="#panels" hx-swap="outerMorph">
          <button type="submit" class="mode-card" name="depth" value={d} {...inspectAttrs('intake-interview:mode-card', { role: 'action', fn: 'submit' })}>
            <Label name="intake-interview:mode-name" class="mode-name">{translate(`intake.bank.${d}`) as string}</Label>
            <Label name="intake-interview:mode-desc" class="mode-desc muted">{translate(`intake.mode.desc.${d}`) as string}</Label>
          </button>
        </form>
      ))}
    </div>
  );
}

// The answered summary: every question with its answer, re-openable.
function AnswersSummary({ c, car, translate }: { c: Ctx; car: Carousel; translate: TFn }) {
  return (
    <div class="step-summary">
      <Heading name="intake-interview:summary-title" level={2} class="display">{translate('intake.interview.summaryTitle') as string}</Heading>
      <Txt name="intake-interview:summary-lede" class="artifact-lede">{translate('intake.interview.summaryLede') as string}</Txt>
      {(car.questions ?? []).map((q: Question) => (
        <div key={q.id} class={`q-card is-${q.state ?? ''}`}>
          <Txt name="intake-interview:q-text" class="q-text">{q.text}</Txt>
          {q.state === 'answered' ? (
            <Fragment>
              <Txt name="intake-interview:q-answer" class="q-answer">{q.answer}</Txt>
              <a class="q-edit" href={`${c.base}/edit?q=${q.id}`}
                 hx-get={`${c.base}/edit?q=${q.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false" {...inspectAttrs('intake-interview:q-edit', { role: 'action', fn: 'edit' })}>{translate('intake.edit') as string}</a>
            </Fragment>
          ) : q.state === 'skipped' ? (
            <Fragment>
              <Txt name="intake-interview:q-skipped" class="q-answer muted">{translate('intake.skipped') as string}</Txt>
              <a class="q-edit" href={`${c.base}/edit?q=${q.id}`}
                 hx-get={`${c.base}/edit?q=${q.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false" {...inspectAttrs('intake-interview:q-edit', { role: 'action', fn: 'edit' })}>{translate('intake.answerAnyway') as string}</a>
            </Fragment>
          ) : null}
        </div>
      ))}
    </div>
  );
}

function InterviewStage({ c, translate }: { c: Ctx; translate: TFn }) {
  const carousel = c.carousel;
  const step = c.step;
  return (
    <section class="mp-content step-stage" id="mp-content" aria-live="polite">
      <header class="step-head">
        <Label name="intake-interview:eyebrow" class="eyebrow">{c.eyebrow}</Label>
        {carousel ? <Label name="intake-interview:bank-label" class="chip chip--muted">{carousel.bankLabel}</Label> : null}
        {step?.total ? <Label name="intake-interview:step-progress" class="chip chip--muted">{translate('intake.step.progress', { done: step.done, total: step.total }) as string}</Label> : null}
      </header>
      {!carousel ? (
        <Fragment>
          <Heading name="intake-interview:mode-title" level={2} class="display">{translate('intake.interview.modeTitle') as string}</Heading>
          <Txt name="intake-interview:mode-lede" class="artifact-lede">{translate('intake.interview.modeLede') as string}</Txt>
          <ModeCards c={c} translate={translate} />
        </Fragment>
      ) : step?.complete && !carousel.editing ? (
        <Fragment>
          <AnswersSummary c={c} car={carousel} translate={translate} />
          <div class="step-foot"><a class="cta-main" href={step.nextHref} {...inspectAttrs('intake-interview:next', { role: 'action', fn: 'navigate' })}>{translate(step.nextLabel as string) as string} <Icon name="chevron-right" size={14} /></a></div>
        </Fragment>
      ) : (
        <Fragment>
          {(carousel.questions ?? [])
            .filter((q) => q.state === 'current' || q.state === 'editing')
            .map((q) => <SH.QCard key={q.id} c={c} q={q} translate={translate} />)}
          <SH.QStrip c={c} car={carousel} translate={translate} />
        </Fragment>
      )}
    </section>
  );
}

// The main panel's content: the open file, else the interview stage.
function MainContent({ c, translate }: { c: Ctx; translate: TFn }) {
  if (c.fileView) return <SH.FileView c={c} translate={translate} />;
  return <InterviewStage c={c} translate={translate} />;
}

function Panels({ c, translate }: { c: Ctx; translate: TFn }) {
  return <SH.Panels c={c} translate={translate}><MainContent c={c} translate={translate} /></SH.Panels>;
}

// ---------- Fragment responses ----------

export function PanelsSwap({ c, translate }: { c: Ctx; translate: TFn }) {
  return (
    <Fragment>
      <Panels c={c} translate={translate} />
      <SH.Timeline c={c} translate={translate} oob={true} />
    </Fragment>
  );
}

export function ActivitySwap({ c, translate }: { c: Ctx; translate: TFn }) {
  return <SH.ActivitySwap c={c} translate={translate} />;
}

export function FileSwap({ c, translate }: { c: Ctx; translate: TFn }) {
  return <MainContent c={c} translate={translate} />;
}

export function ActivityFrameSwap({ c, translate }: { c: Ctx; translate: TFn }) {
  return <SH.ActivityPanel c={c} translate={translate} />;
}

// ---------- Page ----------

interface ViewProps {
  translate: TFn;
  [key: string]: unknown;
}

const InterviewView: FC<ViewProps> = (c) => {
  const { translate } = c;
  return (
    <MainShellView
      title={translate('intake.interview.pageTitle') as string}
      mainClass="shell-main-loop"
      activeShell={c.activeShell as string}
      prefs={c.prefs as { accent?: string; [k: string]: unknown }}
      project={c.project as { name?: string; savedLabel?: string }}
      locale={c.locale as string}
      translate={translate}
      footer={<SH.Timeline c={c as Ctx} translate={translate} oob={false} />}
      surface={<Panels c={c as Ctx} translate={translate} />}
    />
  );
};

export default InterviewView;
