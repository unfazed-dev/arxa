// _shared.tsx — shared intake macros (replaces intake/_shared.html).
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
import Icon from '../../../../runtime/icon.tsx';
import {
  PanelBar,
  Open as MainPanelOpen,
  Empty as MainPanelEmpty,
  View as MainPanelView,
} from '../../../common/widgets/main_panel.tsx';
import { Open as ComposerPanelOpen } from '../shared/widgets/composer_panel.tsx';
import {
  Open as ActivityPanelOpen,
  Top as ActivityPanelTop,
  Bottom as ActivityPanelBottom,
} from '../shared/widgets/activity_panel.tsx';
import { Timeline as TimelineTl } from '../shared/widgets/timeline.tsx';
import { Field } from '../shared/widgets/composer.tsx';

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
export function MissingArtifact({ c, a }: { c: Ctx; a: MissingArtifactA }) {
  return (
    <article class={`artifact missing-artifact is-${a.tone ?? ''}`} aria-live="polite">
      <header class="artifact-head">
        <span class="eyebrow">{c.eyebrow}</span>
        <span class={`rv-badge${a.tone === 'error' ? ' rv-warn' : ''}`}>{a.badge}</span>
      </header>
      <h2 class="display">{a.headline}</h2>
      <p class="artifact-lede">{a.lede}</p>
      {a.steps && a.steps.length > 0 ? (
        <Fragment>
          <p class="fact-label">{a.howLabel}</p>
          <ol class="missing-steps">
            {a.steps.map((s, i) => <li key={i}>{s}</li>)}
          </ol>
        </Fragment>
      ) : null}
      {a.file ? <p class="artifact-detail muted"><code>{a.file}</code></p> : null}
    </article>
  );
}

// --- one question card (the horizontal carousel) ---
export function QCard({ c, q, t }: { c: Ctx; q: Question; t: TFn }) {
  const base = c.base;
  return (
    <div class={`q-card is-${q.state ?? ''}`}>
      <p class="q-text">{q.text}</p>
      {(q.state === 'current' || q.state === 'editing') ? (
        <Fragment>
          <form class="q-form" method="post" action={`${base}/answer`}
                hx-post={`${base}/answer`} hx-target="#panels" hx-swap="outerMorph">
            <input type="hidden" name="q" value={q.id} />
            <input type="text" name="text" value={q.answer ?? ''}
                   placeholder={t('intake.answerPlaceholder') as string}
                   aria-label={t('intake.answerAria', { question: q.text }) as string} />
            <button type="submit" class="composer-send" aria-label={t('intake.sendAnswer') as string}>
              <Icon name="arrow-up" size={18} />
            </button>
          </form>
          {q.suggestions && q.suggestions.length > 0 ? (
            <span class="q-sugs">
              {q.suggestions.map((s, i) => (
                <form key={i} method="post" action={`${base}/answer`}
                      hx-post={`${base}/answer`} hx-target="#panels" hx-swap="outerMorph">
                  <input type="hidden" name="q" value={q.id} />
                  <button type="submit" name="text" value={s}>{s}</button>
                </form>
              ))}
            </span>
          ) : null}
          <form class="q-skip" method="post" action={`${base}/skip`}
                hx-post={`${base}/skip`} hx-target="#panels" hx-swap="outerMorph">
            <input type="hidden" name="q" value={q.id} />
            <button type="submit" aria-label={t('intake.skipAria') as string}>
              {t('intake.skip') as string} <Icon name="chevron-right" size={14} />
            </button>
          </form>
        </Fragment>
      ) : q.state === 'answered' ? (
        <Fragment>
          <p class="q-answer">{q.answer}</p>
          <a class="q-edit" href={`${base}/edit?q=${q.id}`}
             hx-get={`${base}/edit?q=${q.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
            {t('intake.edit') as string}
          </a>
        </Fragment>
      ) : q.state === 'skipped' ? (
        <Fragment>
          <p class="q-answer muted">{t('intake.skipped') as string}</p>
          <a class="q-edit" href={`${base}/edit?q=${q.id}`}
             hx-get={`${base}/edit?q=${q.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
            {t('intake.answerAnyway') as string}
          </a>
        </Fragment>
      ) : (
        <p class="q-answer muted">{t('intake.upNext') as string}</p>
      )}
    </div>
  );
}

// Provenance chip: where a prefill came from (client / founder / inferred).
export function ProvChip({ p, t }: { p?: string; t: TFn }) {
  if (!p) return null;
  return <span class={`chip prov-chip prov-${p}`}>{t(`intake.prov.${p}`) as string}</span>;
}

// The current item's action bar: confirm the prefill as-is, or skip.
export function ItemActions({ c, item, t }: { c: Ctx; item: StepItem; t: TFn }) {
  const base = c.base;
  if (item.state === 'current' || item.state === 'editing') {
    return (
      <span class="item-actions">
        <form method="post" action={`${base}/confirm`} hx-post={`${base}/confirm`} hx-target="#panels" hx-swap="outerMorph">
          <input type="hidden" name="item" value={item.id} />
          <button type="submit" class="cta-main">{t('intake.item.confirm') as string} <Icon name="check" size={14} /></button>
        </form>
        <form method="post" action={`${base}/skip`} hx-post={`${base}/skip`} hx-target="#panels" hx-swap="outerMorph">
          <input type="hidden" name="item" value={item.id} />
          <button type="submit" class="cta-ghost">{t('intake.skip') as string} <Icon name="chevron-right" size={14} /></button>
        </form>
      </span>
    );
  }
  if (item.state === 'confirmed') {
    return (
      <a class="q-edit" href={`${base}/edit?item=${item.id}`}
         hx-get={`${base}/edit?item=${item.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
        {t('intake.edit') as string}
      </a>
    );
  }
  if (item.state === 'skipped') {
    return (
      <a class="q-edit" href={`${base}/edit?item=${item.id}`}
         hx-get={`${base}/edit?item=${item.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
        {t('intake.item.reviewAnyway') as string}
      </a>
    );
  }
  return null;
}

// The item strip: one dot per item, state-coloured; done items re-open.
export function ItemStrip({ c, step, t }: { c: Ctx; step?: Step; t: TFn }) {
  const base = c.base;
  const items = step?.items ?? [];
  return (
    <nav class="item-strip" aria-label={t('intake.step.stripAria') as string}>
      {items.map((item) => {
        const title = item.name ?? item.label ?? item.id;
        if (item.state === 'confirmed' || item.state === 'skipped') {
          return (
            <a key={item.id} class={`strip-dot is-${item.state}`} href={`${base}/edit?item=${item.id}`}
               hx-get={`${base}/edit?item=${item.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
               title={title} aria-label={title} />
          );
        }
        return <span key={item.id} class={`strip-dot is-${item.state ?? ''}`} title={title} />;
      })}
    </nav>
  );
}

// The step footer: accept-all while open, the next-step CTA when complete.
export function StepFoot({ c, step, t }: { c: Ctx; step?: Step; t: TFn }) {
  const base = c.base;
  return (
    <div class="step-foot">
      {step?.complete ? (
        step.nextHref ? (
          <a class="cta-main" href={step.nextHref}>{t(step.nextLabel as string) as string} <Icon name="chevron-right" size={14} /></a>
        ) : null
      ) : (
        <form method="post" action={`${base}/accept-all`} hx-post={`${base}/accept-all`} hx-target="#panels" hx-swap="outerMorph">
          <button type="submit" class="cta-ghost">{t('intake.item.acceptAll') as string}</button>
        </form>
      )}
    </div>
  );
}

// The step stage: header (eyebrow + progress + mode), the caller's item
// card(s) [children], the strip, the footer. One thing per main panel.
export function StepStage({ c, t, children }: { c: Ctx; t: TFn; children?: Child }) {
  const step = c.step;
  return (
    <section class="mp-content step-stage" id="mp-content" aria-live="polite">
      <header class="step-head">
        <span class="eyebrow">{c.eyebrow}</span>
        <span class="chip chip--muted">{t('intake.step.progress', { done: step?.done, total: step?.total }) as string}</span>
        {step?.mode ? <span class="chip chip--muted">{t(`intake.bank.${step.mode}`) as string}</span> : null}
      </header>
      {children}
      <ItemStrip c={c} step={step} t={t} />
      <StepFoot c={c} step={step} t={t} />
    </section>
  );
}

// A question strip for the interview stage (questions re-open with ?q=).
export function QStrip({ c, car, t }: { c: Ctx; car: Carousel; t: TFn }) {
  const base = c.base;
  const qs = car.questions ?? [];
  return (
    <nav class="item-strip" aria-label={t('intake.questionsAria', { bank: car.bankLabel }) as string}>
      {qs.map((q) => {
        if (q.state === 'answered' || q.state === 'skipped') {
          const dot = q.state === 'answered' ? 'confirmed' : 'skipped';
          return (
            <a key={q.id} class={`strip-dot is-${dot}`} href={`${base}/edit?q=${q.id}`}
               hx-get={`${base}/edit?q=${q.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
               title={q.text} aria-label={q.text} />
          );
        }
        const dot = q.state === 'current' ? 'current' : 'upcoming';
        return <span key={q.id} class={`strip-dot is-${dot}`} title={q.text} />;
      })}
    </nav>
  );
}

export function ChatMsg({ c, m, t }: { c: Ctx; m: ChatMsg; t: TFn }) {
  const base = c.base;
  if (m.from === 'user') {
    return <div class="msg msg-user"><span class="msg-text">{m.text}</span></div>;
  }
  return (
    <div class="msg msg-agent">
      <span class="msg-text">{m.text}</span>
      {m.quickReplies && m.quickReplies.length > 0 ? (
        <span class="q-replies">
          {m.quickReplies.map((r, i) => (
            <form key={i} method="post" action={r.action} hx-post={r.action} hx-target="#panels" hx-swap="outerMorph">
              <button type="submit" class="chip chip--accent qr-chip" name={r.name} value={r.value}>{r.label}</button>
            </form>
          ))}
        </span>
      ) : null}
      {m.artifactRef || m.nextHref ? (
        <span class="msg-cta">
          {m.artifactRef ? (
            <a class="cta-main" href={`${base}/artifact/${m.artifactRef}`}
               hx-get={`${base}/artifact/${m.artifactRef}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
              {m.artifactLabel} <Icon name="chevron-right" size={14} />
            </a>
          ) : null}
          {m.nextHref ? <a class="cta-ghost" href={m.nextHref}>{m.nextLabel} <Icon name="chevron-right" size={14} /></a> : null}
        </span>
      ) : null}
    </div>
  );
}

function ChatThread({ c, t }: { c: Ctx; t: TFn }) {
  const msgs = c.chat ?? [];
  return (
    <div class="chat-thread" aria-live="polite">
      {msgs.map((m, i) => <ChatMsg key={i} c={c} m={m} t={t} />)}
    </div>
  );
}

// The composer panel proper — permanent, right, single-state.
function ComposerPanel({ c, t }: { c: Ctx; t: TFn }) {
  return (
    <ComposerPanelOpen spec={{ eyebrow: c.eyebrow, chips: c.chips } as any} t={t}>
      <ChatThread c={c} t={t} />
      {/* Field reads its many props (composerAction, placeholder, modelMenu, …)
          straight off the context bag; spreading forwards them all. */}
      <Field t={t} {...(c as any)} />
    </ComposerPanelOpen>
  );
}

// The three content panels, one swap unit. Composer LEFT, activity RIGHT —
// same DOM order as every other shell, so tab + screen-reader order match.
export function Panels({ c, t, children }: { c: Ctx; t: TFn; children?: Child }) {
  return (
    <div class="panels" id="panels" data-panel={c.panel}>
      <PanelBar panel={c.panel} t={t} />
      <ComposerPanel c={c} t={t} />
      <MainPanelOpen>{children}</MainPanelOpen>
      <ActivityPanel c={c} t={t} />
    </div>
  );
}

// --- the activity panel: one multi-view frame, thread / artifacts / files ---
function ActivityBody({ c }: { c: Ctx }) {
  const base = c.base;
  const fileView = c.fileView;
  const body = c.activityBody;
  if (c.activityView === 'artifacts') {
    const arts = body?.artifacts ?? [];
    return (
      <div class="rv-list">
        {arts.map((a) => (
          <a key={a.ref} class="rv-card" href={`${base}/artifact/${a.ref}`}
             hx-get={`${base}/artifact/${a.ref}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
            <span class="rv-title">{a.title}</span>
            <span class="rv-detail muted">{a.detail}</span>
            {a.badges && a.badges.length > 0 ? (
              <span class="rv-badges">
                {a.badges.map((b, i) => <span key={i} class={`rv-badge rv-${b.tone}`}>{b.label}</span>)}
              </span>
            ) : null}
          </a>
        ))}
      </div>
    );
  }
  if (c.activityView === 'files') {
    const files = body?.files ?? [];
    return (
      <ul class="rv-files">
        {files.map((f, i) => (
          <li key={i}>
            {f.mode ? (
              <a class={`rv-file${fileView && fileView.path === f.path ? ' is-active' : ''}`} href={f.href}
                 hx-get={f.get} hx-target="#panel-main" hx-swap="innerHTML" hx-push-url={f.href}>
                <code class="rv-path">{f.path}</code><span class={`file-badge fb-${f.badge}`}>{f.badge}</span>
              </a>
            ) : (
              <Fragment>
                <code class="rv-path">{f.path}</code><span class={`file-badge fb-${f.badge}`}>{f.badge}</span>
              </Fragment>
            )}
          </li>
        ))}
      </ul>
    );
  }
  const thread = [...(body?.thread ?? [])].reverse();
  return (
    <div class="rv-list">
      {thread.map((m, i) => (
        <div key={i} class="rv-card is-static">
          <span class="msg-text">{m.text}</span>
          <span class="rv-foot">
            {m.artifact ? (
              <a class="cta-ghost" href={`${base}/artifact/${m.artifact}`}
                 hx-get={`${base}/artifact/${m.artifact}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
                {m.artifactLabel} <Icon name="chevron-right" size={14} />
              </a>
            ) : null}
            <span class="msg-time">{m.at}</span>
          </span>
        </div>
      ))}
    </div>
  );
}

export function ActivityPanel({ c, t }: { c: Ctx; t: TFn }) {
  const spec = {
    label: c.activityLabel,
    views: c.activityViews,
    size: c.panelSize,
    sizeHref: c.panelSizeHref,
  } as any;
  return (
    <ActivityPanelOpen spec={spec} t={t}>
      <ActivityBody c={c} />
    </ActivityPanelOpen>
  );
}

// Targeted view-switch response (<base>/panel?view= → #panel-activity-body):
// the new body plus head + bar out-of-band.
export function ActivitySwap({ c, t }: { c: Ctx; t: TFn }) {
  const spec = {
    label: c.activityLabel,
    views: c.activityViews,
    size: c.panelSize,
    sizeHref: c.panelSizeHref,
  } as any;
  return (
    <Fragment>
      <ActivityBody c={c} />
      <ActivityPanelTop spec={spec} oob />
      <ActivityPanelBottom spec={spec} oob t={t} />
    </Fragment>
  );
}

// --- thin forwards to the shared widgets ---

// The footer-panel timeline: read-only stage line, intake item current.
export function Timeline({ c, t, oob = false }: { c: Ctx; t: TFn; oob?: boolean }) {
  return (
    <TimelineTl
      timeline={c.timeline as TimelineData}
      oob={oob}
      label={t('intake.timelineLabel') as string}
      base={c.base}
      t={t}
    />
  );
}

// The main panel's empty read state (nothing open yet).
export function MainEmpty({ t }: { t: TFn }) {
  return <MainPanelEmpty t={t} />;
}

// The open file, rendered by the main panel's automatic mode.
export function FileView({ c, t }: { c: Ctx; t: TFn }) {
  return <MainPanelView f={c.fileView as any} t={t} />;
}
