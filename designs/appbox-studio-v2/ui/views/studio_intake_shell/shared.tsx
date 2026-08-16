// shared.tsx — shared intake macros (replaces intake/_shared.html).
// The panel layout for the intake shell: activity panel on the left, the main
// panel center (the caller fills it), the composer panel permanently right,
// and the read-only timeline in the footer panel. Macro library — imported
// directly by the intake step views (brief / direction / flows / interview /
// mapping / moodboard / personas / surfaces) as `import * as SH`.
//
// Convention: every component takes `{ c: Ctx; t: TFn }` — `c` is the facade
// context bag, `t` the translator — matching the sibling views already
// converted. The *Swap exports + the local Panels/MainContent in each view
// forward `c` and `t` straight through.
//
// appbox:provenance
//   generator: appbox  licence: free  project: 662368770980
//   Built with appbox (free tier) — https://appbox.dev
import { Fragment, type Child } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../widgets/common/studio_primitives/widgets.tsx';
// The studio_panels barrel exports ALIASED names only (panel.tsx and
// activity_panel.tsx both export Top/Bottom — export-* would drop them).
import {
  PanelBar,
  MainPanelOpen,
  Empty as MainPanelEmpty,
  MainPanelView,
  ComposerPanelOpen,
  ActivityPanelOpen,
  ActivityPanelTop,
  ActivityPanelBottom,
  Timeline as TimelineTl,
  ComposerField as Field,
} from '../../widgets/common/studio_panels/widgets.tsx';

export type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// --- shared data shapes (the facade context bag) ---
export interface StepValue { value?: string; provenance?: string; board?: string; note?: string; }
export interface FlowEdge { from?: string; to?: string; fromLabel?: string; toLabel?: string; trigger?: string; label?: string; }
export interface StepItem {
  id?: string;
  state?: string;
  name?: string;
  label?: string;
  provenance?: string;
  edited?: boolean;
  values?: StepValue[];
  edges?: FlowEdge[];
  personaName?: string;
  answer?: string;
  text?: string;
  priority?: string;
  release?: string;
}
export interface Step {
  done?: number;
  total?: number;
  mode?: string;
  complete?: boolean;
  nextHref?: string;
  nextLabel?: string;
  items?: StepItem[];
}
export interface Question { id: string; state?: string; text?: string; answer?: string; suggestions?: string[]; }
export interface Carousel { bankLabel?: string; questions?: Question[]; editing?: boolean; }
export interface ChatMsg {
  from?: string;
  text?: string;
  quickReplies?: { action?: string; name?: string; value?: string; label?: string }[];
  artifactRef?: string;
  artifactLabel?: string;
  nextHref?: string;
  nextLabel?: string;
}
export interface FileViewC { path?: string; [k: string]: unknown; }
export interface ActivityBodyData {
  artifacts?: { ref?: string; title?: string; detail?: string; badges?: { tone?: string; label?: string }[] }[];
  files?: { path?: string; href?: string; get?: string; badge?: string; mode?: string }[];
  thread?: { text?: string; at?: string; artifact?: string; artifactLabel?: string }[];
}
export interface TimelineData { items: any[]; currentId: string; }

export interface Ctx {
  base?: string;
  panel?: string;
  eyebrow?: string;
  chips?: unknown;
  chat?: ChatMsg[];
  carousel?: Carousel;
  step?: Step;
  activityView?: string;
  activityLabel?: string;
  activityViews?: unknown[];
  activityBody?: ActivityBodyData;
  panelSize?: string;
  panelSizeHref?: string;
  panelSizePx?: number;
  fileView?: FileViewC;
  timeline?: TimelineData;
  [key: string]: unknown;
}

// The honest empty/error state for a project artifact that has not been
// produced, or exists but would not parse (ADR-0003). Naming the missing file
// and the command that writes it is the only true version of this screen.
export interface MissingArtifactA {
  tone?: string;
  badge?: string;
  headline?: string;
  lede?: string;
  howLabel?: string;
  steps?: string[];
  file?: string;
  [k: string]: unknown;
}
export function MissingArtifact({ context, a: artifact }: { context: Ctx; a: MissingArtifactA }) {
  return (
    <article class={`artifact missing-artifact is-${artifact.tone ?? ''}`} aria-live="polite">
      <header class="artifact-head">
        <Label name="intake-shared:eyebrow" class="eyebrow">{context.eyebrow}</Label>
        <Label name="intake-shared:badge" class={`rv-badge${artifact.tone === 'error' ? ' rv-warn' : ''}`}>{artifact.badge}</Label>
      </header>
      <Heading name="intake-shared:headline" level={2} class="display">{artifact.headline}</Heading>
      <Txt name="intake-shared:lede" class="artifact-lede">{artifact.lede}</Txt>
      {artifact.steps && artifact.steps.length > 0 ? (
        <Fragment>
          <Txt name="intake-shared:how-label" class="fact-label">{artifact.howLabel}</Txt>
          <ol class="missing-steps" {...inspectAttrs('intake-shared:missing-steps', { role: 'list' })}>
            {artifact.steps.map((step, index) => <li key={index} {...inspectAttrs('intake-shared:missing-step', { role: 'list row' })}>{step}</li>)}
          </ol>
        </Fragment>
      ) : null}
      {artifact.file ? <p class="artifact-detail muted"><code {...inspectAttrs('intake-shared:file-path', { role: 'text' })}>{artifact.file}</code></p> : null}
    </article>
  );
}

// --- one question card (the horizontal carousel) ---
export function QCard({ context, q: question, translate }: { context: Ctx; q: Question; translate: TFn }) {
  const base = context.base;
  return (
    <div class={`q-card is-${question.state ?? ''}`}>
      <Txt name="intake-shared:q-text" class="q-text">{question.text}</Txt>
      {(question.state === 'current' || question.state === 'editing') ? (
        <Fragment>
          <form class="q-form" method="post" action={`${base}/answer`}
                hx-post={`${base}/answer`} hx-target="#panels" hx-swap="outerMorph">
            <input type="hidden" name="q" value={question.id} {...inspectAttrs('intake-shared:q-id', { role: 'input' })} />
            <input type="text" name="text" value={question.answer ?? ''}
                   placeholder={translate('intake.answerPlaceholder') as string}
                   aria-label={translate('intake.answerAria', { question: question.text }) as string}
                   {...inspectAttrs('intake-shared:q-answer-input', { role: 'input' })} />
            <button type="submit" class="composer-send" aria-label={translate('intake.sendAnswer') as string}
                    {...inspectAttrs('intake-shared:q-send', { role: 'action', fn: 'submit' })}>
              <Icon name="arrow-up" size={18} />
            </button>
          </form>
          {question.suggestions && question.suggestions.length > 0 ? (
            <span class="q-sugs" {...inspectAttrs('intake-shared:q-suggestions', { role: 'group' })}>
              {question.suggestions.map((suggestion, index) => (
                <form key={index} method="post" action={`${base}/answer`}
                      hx-post={`${base}/answer`} hx-target="#panels" hx-swap="outerMorph">
                  <input type="hidden" name="q" value={question.id} {...inspectAttrs('intake-shared:q-sug-id', { role: 'input' })} />
                  <button type="submit" name="text" value={suggestion} {...inspectAttrs('intake-shared:q-suggestion', { role: 'action', fn: 'submit' })}>{suggestion}</button>
                </form>
              ))}
            </span>
          ) : null}
          <form class="q-skip" method="post" action={`${base}/skip`}
                hx-post={`${base}/skip`} hx-target="#panels" hx-swap="outerMorph">
            <input type="hidden" name="q" value={question.id} {...inspectAttrs('intake-shared:q-skip-id', { role: 'input' })} />
            <button type="submit" aria-label={translate('intake.skipAria') as string}
                    {...inspectAttrs('intake-shared:q-skip', { role: 'action', fn: 'skip' })}>
              {translate('intake.skip') as string} <Icon name="chevron-right" size={14} />
            </button>
          </form>
        </Fragment>
      ) : question.state === 'answered' ? (
        <Fragment>
          <Txt name="intake-shared:q-answer" class="q-answer">{question.answer}</Txt>
          <a class="q-edit" href={`${base}/edit?q=${question.id}`}
             hx-get={`${base}/edit?q=${question.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
             {...inspectAttrs('intake-shared:q-edit', { role: 'action', fn: 'edit' })}>
            {translate('intake.edit') as string}
          </a>
        </Fragment>
      ) : question.state === 'skipped' ? (
        <Fragment>
          <Txt name="intake-shared:q-skipped" class="q-answer muted">{translate('intake.skipped') as string}</Txt>
          <a class="q-edit" href={`${base}/edit?q=${question.id}`}
             hx-get={`${base}/edit?q=${question.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
             {...inspectAttrs('intake-shared:q-answer-anyway', { role: 'action', fn: 'edit' })}>
            {translate('intake.answerAnyway') as string}
          </a>
        </Fragment>
      ) : (
        <Txt name="intake-shared:q-up-next" class="q-answer muted">{translate('intake.upNext') as string}</Txt>
      )}
    </div>
  );
}

// Provenance chip: where a prefill came from (client / founder / inferred).
export function ProvChip({ p: provenance, translate }: { p?: string; translate: TFn }) {
  if (!provenance) return null;
  return <Label name={`intake-shared:prov-${provenance}`} class={`chip prov-chip prov-${provenance}`}>{translate(`intake.prov.${provenance}`) as string}</Label>;
}

// The current item's action bar: confirm the prefill as-is, or skip.
export function ItemActions({ context, item, translate }: { context: Ctx; item: StepItem; translate: TFn }) {
  const base = context.base;
  if (item.state === 'current' || item.state === 'editing') {
    return (
      <span class="item-actions" {...inspectAttrs('intake-shared:item-actions', { role: 'group' })}>
        <form method="post" action={`${base}/confirm`} hx-post={`${base}/confirm`} hx-target="#panels" hx-swap="outerMorph">
          <input type="hidden" name="item" value={item.id} {...inspectAttrs('intake-shared:item-confirm-id', { role: 'input' })} />
          <button type="submit" class="cta-main" {...inspectAttrs('intake-shared:item-confirm', { role: 'action', fn: 'confirm' })}>{translate('intake.item.confirm') as string} <Icon name="check" size={14} /></button>
        </form>
        <form method="post" action={`${base}/skip`} hx-post={`${base}/skip`} hx-target="#panels" hx-swap="outerMorph">
          <input type="hidden" name="item" value={item.id} {...inspectAttrs('intake-shared:item-skip-id', { role: 'input' })} />
          <button type="submit" class="cta-ghost" {...inspectAttrs('intake-shared:item-skip', { role: 'action', fn: 'skip' })}>{translate('intake.skip') as string} <Icon name="chevron-right" size={14} /></button>
        </form>
      </span>
    );
  }
  if (item.state === 'confirmed') {
    return (
      <a class="q-edit" href={`${base}/edit?item=${item.id}`}
         hx-get={`${base}/edit?item=${item.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
         {...inspectAttrs('intake-shared:item-edit', { role: 'action', fn: 'edit' })}>
        {translate('intake.edit') as string}
      </a>
    );
  }
  if (item.state === 'skipped') {
    return (
      <a class="q-edit" href={`${base}/edit?item=${item.id}`}
         hx-get={`${base}/edit?item=${item.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
         {...inspectAttrs('intake-shared:item-review', { role: 'action', fn: 'edit' })}>
        {translate('intake.item.reviewAnyway') as string}
      </a>
    );
  }
  return null;
}

// The item strip: one dot per item, state-coloured; done items re-open.
export function ItemStrip({ context, step, translate }: { context: Ctx; step?: Step; translate: TFn }) {
  const base = context.base;
  const items = step?.items ?? [];
  return (
    <nav class="item-strip" aria-label={translate('intake.step.stripAria') as string} {...inspectAttrs('intake-shared:item-strip', { role: 'group' })}>
      {items.map((item) => {
        const title = item.name ?? item.label ?? item.id;
        if (item.state === 'confirmed' || item.state === 'skipped') {
          return (
            <a key={item.id} class={`strip-dot is-${item.state}`} href={`${base}/edit?item=${item.id}`}
               hx-get={`${base}/edit?item=${item.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
               title={title} aria-label={title}
               {...inspectAttrs('intake-shared:strip-dot', { role: 'action', fn: 'edit' })} />
          );
        }
        return <span key={item.id} class={`strip-dot is-${item.state ?? ''}`} title={title} {...inspectAttrs('intake-shared:strip-dot-static', { role: 'label' })} />;
      })}
    </nav>
  );
}

// The step footer: accept-all while open, the next-step CTA when complete.
export function StepFoot({ context, step, translate }: { context: Ctx; step?: Step; translate: TFn }) {
  const base = context.base;
  return (
    <div class="step-foot" {...inspectAttrs('intake-shared:step-foot', { role: 'group' })}>
      {step?.complete ? (
        step.nextHref ? (
          <a class="cta-main" href={step.nextHref} {...inspectAttrs('intake-shared:step-next', { role: 'action', fn: 'navigate' })}>{translate(step.nextLabel as string) as string} <Icon name="chevron-right" size={14} /></a>
        ) : null
      ) : (
        <form method="post" action={`${base}/accept-all`} hx-post={`${base}/accept-all`} hx-target="#panels" hx-swap="outerMorph">
          <button type="submit" class="cta-ghost" {...inspectAttrs('intake-shared:step-accept-all', { role: 'action', fn: 'submit' })}>{translate('intake.item.acceptAll') as string}</button>
        </form>
      )}
    </div>
  );
}

// The step stage: header (eyebrow + progress + mode), the caller's item
// card(s) [children], the strip, the footer. One thing per main panel.
export function StepStage({ context, translate, children }: { context: Ctx; translate: TFn; children?: Child }) {
  const step = context.step;
  return (
    <section class="mp-content step-stage" id="mp-content" aria-live="polite">
      <header class="step-head">
        <Label name="intake-shared:step-eyebrow" class="eyebrow">{context.eyebrow}</Label>
        <Label name="intake-shared:step-progress" class="chip chip--muted">{translate('intake.step.progress', { done: step?.done, total: step?.total }) as string}</Label>
        {step?.mode ? <Label name={`intake-shared:step-mode-${step.mode}`} class="chip chip--muted">{translate(`intake.bank.${step.mode}`) as string}</Label> : null}
      </header>
      {children}
      <ItemStrip context={context} step={step} translate={translate} />
      <StepFoot context={context} step={step} translate={translate} />
    </section>
  );
}

// A question strip for the interview stage (questions re-open with ?q=).
export function QStrip({ context, car, translate }: { context: Ctx; car: Carousel; translate: TFn }) {
  const base = context.base;
  const qs = car.questions ?? [];
  return (
    <nav class="item-strip" aria-label={translate('intake.questionsAria', { bank: car.bankLabel }) as string} {...inspectAttrs('intake-shared:q-strip', { role: 'group' })}>
      {qs.map((question) => {
        if (question.state === 'answered' || question.state === 'skipped') {
          const dot = question.state === 'answered' ? 'confirmed' : 'skipped';
          return (
            <a key={question.id} class={`strip-dot is-${dot}`} href={`${base}/edit?q=${question.id}`}
               hx-get={`${base}/edit?q=${question.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
               title={question.text} aria-label={question.text}
               {...inspectAttrs('intake-shared:q-strip-dot', { role: 'action', fn: 'edit' })} />
          );
        }
        const dot = question.state === 'current' ? 'current' : 'upcoming';
        return <span key={question.id} class={`strip-dot is-${dot}`} title={question.text} {...inspectAttrs('intake-shared:q-strip-dot-static', { role: 'label' })} />;
      })}
    </nav>
  );
}

export function ChatMsg({ context, m: message, translate }: { context: Ctx; m: ChatMsg; translate: TFn }) {
  const base = context.base;
  if (message.from === 'user') {
    return <div class="msg msg-user" {...inspectAttrs('intake-shared:msg-user', { role: 'group' })}><Label name="intake-shared:msg-user-text" class="msg-text">{message.text}</Label></div>;
  }
  return (
    <div class="msg msg-agent" {...inspectAttrs('intake-shared:msg-agent', { role: 'group' })}>
      <Label name="intake-shared:msg-agent-text" class="msg-text">{message.text}</Label>
      {message.quickReplies && message.quickReplies.length > 0 ? (
        <span class="q-replies" {...inspectAttrs('intake-shared:q-replies', { role: 'group' })}>
          {message.quickReplies.map((quickReply, index) => (
            <form key={index} method="post" action={quickReply.action} hx-post={quickReply.action} hx-target="#panels" hx-swap="outerMorph">
              <button type="submit" class="chip chip--accent qr-chip" name={quickReply.name} value={quickReply.value} {...inspectAttrs('intake-shared:qr-chip', { role: 'action', fn: 'submit' })}>{quickReply.label}</button>
            </form>
          ))}
        </span>
      ) : null}
      {message.artifactRef || message.nextHref ? (
        <span class="msg-cta" {...inspectAttrs('intake-shared:msg-cta', { role: 'group' })}>
          {message.artifactRef ? (
            <a class="cta-main" href={`${base}/artifact/${message.artifactRef}`}
               hx-get={`${base}/artifact/${message.artifactRef}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
               {...inspectAttrs('intake-shared:msg-artifact', { role: 'action', fn: 'navigate' })}>
              {message.artifactLabel} <Icon name="chevron-right" size={14} />
            </a>
          ) : null}
          {message.nextHref ? <a class="cta-ghost" href={message.nextHref} {...inspectAttrs('intake-shared:msg-next', { role: 'action', fn: 'navigate' })}>{message.nextLabel} <Icon name="chevron-right" size={14} /></a> : null}
        </span>
      ) : null}
    </div>
  );
}

function ChatThread({ context, translate }: { context: Ctx; translate: TFn }) {
  const msgs = context.chat ?? [];
  return (
    <div class="chat-thread" aria-live="polite" {...inspectAttrs('intake-shared:chat-thread', { role: 'group' })}>
      {msgs.map((message, index) => <ChatMsg key={index} context={context} m={message} translate={translate} />)}
    </div>
  );
}

// The composer panel proper — permanent, right, single-state.
function ComposerPanel({ context, translate }: { context: Ctx; translate: TFn }) {
  return (
    <ComposerPanelOpen spec={{ eyebrow: context.eyebrow, chips: context.chips } as any} translate={translate}>
      <ChatThread context={context} translate={translate} />
      {/* Field reads its many props (composerAction, placeholder, modelMenu, …)
          straight off the context bag; spreading forwards them all. */}
      <Field translate={translate} {...(context as any)} />
    </ComposerPanelOpen>
  );
}

// The three content panels, one swap unit. Composer LEFT, activity RIGHT —
// same DOM order as every other shell, so tab + screen-reader order match.
export function Panels({ context, translate, children }: { context: Ctx; translate: TFn; children?: Child }) {
  return (
    <div class="panels" id="panels" data-panel={context.panel} {...inspectAttrs('intake-shared:panels', { role: 'group' })}>
      <PanelBar panel={context.panel} translate={translate} />
      <ComposerPanel context={context} translate={translate} />
      <MainPanelOpen>{children}</MainPanelOpen>
      <ActivityPanel context={context} translate={translate} />
    </div>
  );
}

// --- the activity panel: one multi-view frame, thread / artifacts / files ---
function ActivityBody({ context }: { context: Ctx }) {
  const base = context.base;
  const fileView = context.fileView;
  const body = context.activityBody;
  if (context.activityView === 'artifacts') {
    const arts = body?.artifacts ?? [];
    return (
      <div class="rv-list" {...inspectAttrs('intake-shared:artifact-list', { role: 'group' })}>
        {arts.map((artifact) => (
          <artifact key={artifact.ref} class="rv-card" href={`${base}/artifact/${artifact.ref}`}
             hx-get={`${base}/artifact/${artifact.ref}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
             {...inspectAttrs('intake-shared:artifact-card', { role: 'action', fn: 'navigate' })}>
            <Label name="intake-shared:artifact-title" class="rv-title">{artifact.title}</Label>
            <Label name="intake-shared:artifact-detail" class="rv-detail muted">{artifact.detail}</Label>
            {artifact.badges && artifact.badges.length > 0 ? (
              <span class="rv-badges" {...inspectAttrs('intake-shared:artifact-badges', { role: 'group' })}>
                {artifact.badges.map((badge, index) => <Label key={index} name="intake-shared:artifact-badge" class={`rv-badge rv-${badge.tone}`}>{badge.label}</Label>)}
              </span>
            ) : null}
          </artifact>
        ))}
      </div>
    );
  }
  if (context.activityView === 'files') {
    const files = body?.files ?? [];
    return (
      <ul class="rv-files" {...inspectAttrs('intake-shared:file-list', { role: 'list' })}>
        {files.map((file, index) => (
          <li key={index} {...inspectAttrs('intake-shared:file-row', { role: 'list row' })}>
            {file.mode ? (
              <a class={`rv-file${fileView && fileView.path === file.path ? ' is-active' : ''}`} href={file.href}
                 hx-get={file.get} hx-target="#panel-main" hx-swap="innerHTML" hx-push-url={file.href}
                 {...inspectAttrs('intake-shared:file-link', { role: 'action', fn: 'navigate' })}>
                <code class="rv-path" {...inspectAttrs('intake-shared:file-path', { role: 'text' })}>{file.path}</code><Label name="intake-shared:file-badge" class={`file-badge fb-${file.badge}`}>{file.badge}</Label>
              </a>
            ) : (
              <Fragment>
                <code class="rv-path" {...inspectAttrs('intake-shared:file-path', { role: 'text' })}>{file.path}</code><Label name="intake-shared:file-badge" class={`file-badge fb-${file.badge}`}>{file.badge}</Label>
              </Fragment>
            )}
          </li>
        ))}
      </ul>
    );
  }
  const thread = [...(body?.thread ?? [])].reverse();
  return (
    <div class="rv-list" {...inspectAttrs('intake-shared:thread-list', { role: 'group' })}>
      {thread.map((message, index) => (
        <div key={index} class="rv-card is-static" {...inspectAttrs('intake-shared:thread-card', { role: 'group' })}>
          <Label name="intake-shared:thread-text" class="msg-text">{message.text}</Label>
          <span class="rv-foot" {...inspectAttrs('intake-shared:thread-foot', { role: 'group' })}>
            {message.artifact ? (
              <a class="cta-ghost" href={`${base}/artifact/${message.artifact}`}
                 hx-get={`${base}/artifact/${message.artifact}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
                 {...inspectAttrs('intake-shared:thread-artifact', { role: 'action', fn: 'navigate' })}>
                {message.artifactLabel} <Icon name="chevron-right" size={14} />
              </a>
            ) : null}
            <Label name="intake-shared:thread-time" class="msg-time">{message.at}</Label>
          </span>
        </div>
      ))}
    </div>
  );
}

export function ActivityPanel({ context, translate }: { context: Ctx; translate: TFn }) {
  const spec = {
    label: context.activityLabel,
    views: context.activityViews,
    size: context.panelSize,
    sizeHref: context.panelSizeHref,
  } as any;
  return (
    <ActivityPanelOpen spec={spec} translate={translate}>
      <ActivityBody context={context} />
    </ActivityPanelOpen>
  );
}

// Targeted view-switch response (<base>/panel?view= → #panel-activity-body):
// the new body plus head + bar out-of-band.
export function ActivitySwap({ context, translate }: { context: Ctx; translate: TFn }) {
  const spec = {
    label: context.activityLabel,
    views: context.activityViews,
    size: context.panelSize,
    sizeHref: context.panelSizeHref,
  } as any;
  return (
    <Fragment>
      <ActivityBody context={context} />
      <ActivityPanelTop spec={spec} oob />
      <ActivityPanelBottom spec={spec} oob translate={translate} />
    </Fragment>
  );
}

// --- thin forwards to the shared widgets ---

// The footer-panel timeline: read-only stage line, intake item current.
export function Timeline({ context, translate, oob = false }: { context: Ctx; translate: TFn; oob?: boolean }) {
  return (
    <TimelineTl
      timeline={context.timeline as TimelineData}
      oob={oob}
      label={translate('intake.timelineLabel') as string}
      base={context.base}
      translate={translate}
    />
  );
}

// The main panel's empty read state (nothing open yet).
export function MainEmpty({ translate }: { translate: TFn }) {
  return <MainPanelEmpty translate={translate} />;
}

// The open file, rendered by the main panel's automatic mode.
export function FileView({ context, translate }: { context: Ctx; translate: TFn }) {
  return <MainPanelView file={context.fileView as any} translate={translate} />;
}
