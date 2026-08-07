// design/_shared.tsx — design-shell shared panels (replaces _shared.html).
// The activity panel (screens / artifacts / files / inspector) on the right,
// the composer panel with context chips, and the design thread with per-screen
// checkpoints. Macro-only file — importing it from a fragment render emits
// nothing. Every design-stage swap targets #panels: composer, context toggle,
// and revert all re-render the one container the chat and the artifact share.
import { Fragment, type Child } from 'hono/jsx';
import Icon from '../../../../runtime/icon.tsx';
import { TypeBadge, StatusPill, inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';
import { FactsBar } from '../../../common/facts_bar.tsx';
import { Open as ActivityOpen, Top as ActivityTop, Bottom as ActivityBottom } from '../shared/widgets/activity_panel.tsx';
import { Open as ComposerOpen } from '../shared/widgets/composer_panel.tsx';
import { Field } from '../shared/widgets/composer.tsx';
import { Open as MainOpen, PanelBar, Empty, View as MainView } from '../../../common/widgets/main_panel.tsx';
import { Pane } from './inspector_pane.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;
type Ctx = Record<string, any>;
export type DesignCtx = Ctx;

// ---- checkpointCard — a checkpoint in the design thread with diff + revert ----
interface CheckpointCardProps {
  e: Ctx;
  t: TFn;
}
export function CheckpointCard({ e, t }: CheckpointCardProps) {
  return (
    <div class={`checkpoint${e.reverted ? ' is-reverted' : ''}`}>
      <header class="cp-head">
        <Label name="design-checkpoint:label" class="fact-label">{t('checkpoint.label', { id: e.id, screen: e.screen }) as string}</Label>
        <Label name="design-checkpoint:summary" class="muted">{e.summary}</Label>
        <Label name="design-checkpoint:time" class="msg-time">{e.at}</Label>
      </header>
      {e.before && (
        <div class="cp-diff">
          <span class="fact" {...inspectAttrs('design-checkpoint:before', { role: 'group' })}><Label name="design-checkpoint:before-label" class="fact-label">{t('checkpoint.before') as string}</Label>{e.before}</span>
          <span class="fact" {...inspectAttrs('design-checkpoint:after', { role: 'group' })}><Label name="design-checkpoint:after-label" class="fact-label">{t('checkpoint.after') as string}</Label>{e.after}</span>
        </div>
      )}
      {e.reverted ? (
        <span class="bt-action-done" {...inspectAttrs('design-checkpoint:reverted', { role: 'status' })} title={t('checkpoint.revertedTitle') as string}>
          {t('checkpoint.reverted') as string} <Icon name="check" size={14} />
        </span>
      ) : (
        <form
          class="cp-revert"
          method="post"
          action={`/design/chat/screen/${e.screen}/revert/${e.id}`}
          hx-post={`/design/chat/screen/${e.screen}/revert/${e.id}`}
          hx-target="#panels"
          hx-swap="outerMorph"
        >
          <button type="submit" class="ghost" {...inspectAttrs('design-checkpoint:revert', { role: 'action' })}>
            <Icon name="undo-2" size={14} /> {t('checkpoint.revert', { id: e.id }) as string}
          </button>
        </form>
      )}
    </div>
  );
}

// ---- thread — the design chat thread (events + user/agent messages + checkpoints) ----
interface ThreadProps {
  c: Ctx;
  t: TFn;
}
export function Thread({ c, t }: ThreadProps) {
  return (
    <div class="chat-thread" aria-live="polite" {...inspectAttrs('design-thread:log', { role: 'group' })}>
      {(c.thread ?? []).map((m: Ctx, i: number) => {
        if (m.kind === 'event') {
          return <Txt key={i} name="design-thread:event" class="bt-event">{m.text}</Txt>;
        }
        if (m.from === 'user') {
          return <Txt key={i} name="design-thread:user-msg" class="bt-msg bt-user">{m.text}</Txt>;
        }
        return (
          <Fragment key={String(i)}>
            <Txt name="design-thread:agent-msg" class="bt-msg bt-agent">
              {m.text}
              {m.link && <Fragment>{' '}<a class="bt-link" href={m.link.href} {...inspectAttrs('design-thread:link', { role: 'action' })}>{m.link.label}</a></Fragment>}
            </Txt>
            {(m.cps ?? []).map((e: Ctx, j: number) => (
              <CheckpointCard key={j} e={e} t={t} />
            ))}
          </Fragment>
        );
      })}
    </div>
  );
}

// ---- composerPanel — thread + composer inside the shared frame ----
interface ComposerPanelProps {
  c: Ctx;
  t: TFn;
}
export function ComposerPanel({ c, t }: ComposerPanelProps) {
  const spec = { eyebrow: c.stageEyebrow ?? '', chips: c.chips };
  return (
    <ComposerOpen spec={spec} t={t}>
      <Thread c={c} t={t} />
      <Field {...c} t={t} />
    </ComposerOpen>
  );
}

// ---- mainEmpty — the empty read state (nothing open yet) ----
export function MainEmpty({ t }: { t: TFn }) {
  return <Empty t={t} />;
}

// ---- fileView — the open file rendered by the main panel's automatic mode ----
interface FileViewProps {
  c: Ctx;
  t: TFn;
}
export function FileView({ c, t }: FileViewProps) {
  return <MainView f={c.fileView} t={t} />;
}

// ---- panels — the three content panels, one swap unit ----
// Every stage interaction re-renders #panels outerHTML. The caller fills the
// main panel via children.
interface PanelsProps {
  c: Ctx;
  t: TFn;
  children?: Child;
}
export function Panels({ c, t, children }: PanelsProps) {
  return (
    <div class="panels" id="panels" data-panel={c.panel}>
      <PanelBar panel={c.panel} t={t} />
      <ComposerPanel c={c} t={t} />
      <MainOpen>{children}</MainOpen>
      <ActivityPanel c={c} t={t} />
    </div>
  );
}

// ---- runBar — the facts bar with run data ----
interface RunBarProps {
  c: Ctx;
  oob?: boolean;
  t: TFn;
}
export function RunBar({ c, oob = false, t }: RunBarProps) {
  const spec = {
    eyebrow: t('design.runEyebrow', { number: c.run.number, brief: c.run.brief }) as string,
    state: c.run.stateLabel as string,
    facts: [
      t('surfaces.count', { count: c.counts.screens }) as string,
      t('design.shotsFact', { count: c.counts.shots }) as string,
      c.run.rungsLabel as string,
    ],
    filter: {
      summaryAria: t('design.filterAria') as string,
      summaryTitle: t('design.filterTitle') as string,
      summary: (c.filter !== 'all' ? c.filter : t('design.allEpics')) as string,
      target: '#av-list',
      swap: 'outerHTML',
      url: '/design/panel?epic=',
      active: c.filter as string,
      options: [{ id: 'all', label: t('design.allEpics') as string }, ...(c.epics ?? [])],
    },
  };
  return <FactsBar oob={oob} spec={spec} />;
}

// ---- screenCard — a screen card with the context pin as the only CTA ----
interface ScreenCardProps {
  s: Ctx;
  t: TFn;
}
export function ScreenCard({ s, t }: ScreenCardProps) {
  return (
    <div class={`msg msg-agent${s.inContext ? ` is-active msg-ctx ctx-${s.tone}` : ''}`}>
      <header class="msg-meta" {...inspectAttrs('design-screen:meta', { role: 'nav' })}>
        <TypeBadge type="screen" label={s.epic} />
        {s.card?.threadCount ? (
          <span class="chip thread-badge" {...inspectAttrs('design-screen:thread-count', { role: 'status' })} title={t('design.checkpointsTitle', { count: s.card.threadCount }) as string}>
            <Icon name="history" size={12} /> {s.card.threadCount}
          </span>
        ) : null}
        <StatusPill state={s.card?.state} t={t} />
      </header>
      <Label name="design-screen:summary" class="msg-text">{s.summary}</Label>
      <Label name="design-screen:detail" class="msg-detail">{s.card?.detail}</Label>
      <footer class="msg-foot">
        <span class="msg-cta">
          <a
            class="cta-main"
            href={`/design/chat/context/${s.id}?state=toggle`}
            hx-get={`/design/chat/context/${s.id}?state=toggle`}
            hx-target="#panels"
            hx-swap="outerMorph"
            hx-push-url="false"
            {...inspectAttrs('design-screen:pin-toggle', { role: 'action' })}
          >
            {s.inContext
              ? <Fragment>{t('design.inContext') as string} <Icon name="check" size={14} /></Fragment>
              : <Fragment>{t('design.pinToContext') as string} <Icon name="pin" size={14} /></Fragment>}
          </a>
        </span>
        <Label name="design-screen:label" class="msg-time">{s.label}</Label>
      </footer>
    </div>
  );
}

// ---- screenList — the list of screen cards (OOB-able) ----
interface ScreenListProps {
  c: Ctx;
  oob?: boolean;
  t: TFn;
}
export function ScreenList({ c, oob = false, t }: ScreenListProps) {
  return (
    <div class="av-list" id="av-list" hx-swap-oob={oob ? 'outerHTML' : undefined} {...inspectAttrs('design-screen:list', { role: 'group' })}>
      {c.screens?.length
        ? c.screens.map((s: Ctx, i: number) => <ScreenCard key={s.id ?? i} s={s} t={t} />)
        : <Txt name="design-screen:empty" class="muted">{t('design.noScreens') as string}</Txt>}
    </div>
  );
}

// ---- activityBody — the active view's body ----
// /design/panel/:view hx-swaps this into #panel-activity-body.
interface ActivityBodyProps {
  c: Ctx;
  t: TFn;
}
export function ActivityBody({ c, t }: ActivityBodyProps) {
  if (c.activityView === 'artifacts') {
    return (
      <div class="av-list" id="av-list" {...inspectAttrs('design-artifact:list', { role: 'group' })}>
        {(c.artifacts ?? []).map((a: Ctx, i: number) => (
          <a key={i} class="msg msg-agent av-row" href={a.href} {...inspectAttrs('design-artifact:row', { role: 'action' })}>
            <header class="msg-meta"><TypeBadge type={a.kind} /></header>
            <Label name="design-artifact:label" class="msg-text">{a.label}</Label>
            <Label name="design-artifact:detail" class="msg-detail">{a.detail}</Label>
          </a>
        ))}
      </div>
    );
  }
  if (c.activityView === 'files') {
    return (
      <div class="av-list" id="av-list" {...inspectAttrs('design-file:list', { role: 'group' })}>
        {(c.files ?? []).map((f: Ctx, i: number) =>
          f.mode ? (
            <a
              key={i}
              class={`msg msg-agent av-row${c.fileView && c.fileView.path === f.path ? ' is-active' : ''}`}
              href={f.href}
              hx-get={f.get}
              hx-target="#panel-main"
              hx-swap="innerHTML"
              hx-push-url={f.href}
              {...inspectAttrs('design-file:row', { role: 'action' })}
            >
              <span class="msg-text" {...inspectAttrs('design-file:path', { role: 'text' })}><code {...inspectAttrs('design-file:path-val', { role: 'text' })}>{f.path}</code></span>
              <Label name="design-file:detail" class="msg-detail">{f.detail}</Label>
            </a>
          ) : (
            <div key={i} class="msg msg-agent av-row" {...inspectAttrs('design-file:row', { role: 'group' })}>
              <span class="msg-text" {...inspectAttrs('design-file:path', { role: 'text' })}><code {...inspectAttrs('design-file:path-val', { role: 'text' })}>{f.path}</code></span>
              <Label name="design-file:detail" class="msg-detail">{f.detail}</Label>
            </div>
          ),
        )}
      </div>
    );
  }
  if (c.activityView === 'inspector') {
    return <Pane c={c} t={t} />;
  }
  return (
    <Fragment>
      <RunBar c={c} oob={false} t={t} />
      <ScreenList c={c} oob={false} t={t} />
    </Fragment>
  );
}

// ---- activityPanel — the multi-view activity frame wrapping the body ----
interface ActivityPanelProps {
  c: Ctx;
  t: TFn;
}
export function ActivityPanel({ c, t }: ActivityPanelProps) {
  const spec = {
    label: c.activityLabel ?? '',
    views: c.activityViews ?? [],
    size: c.panelSize,
    sizeHref: c.panelSizeHref,
    panelSizePx: c.panelSizePx,
  };
  return (
    <ActivityOpen spec={spec} t={t}>
      <ActivityBody c={c} t={t} />
    </ActivityOpen>
  );
}

// ---- activitySwap — view-switch response (body + top + bottom OOB) ----
interface ActivitySwapProps {
  c: Ctx;
  t: TFn;
}
export function ActivitySwap({ c, t }: ActivitySwapProps) {
  const spec = {
    label: c.activityLabel ?? '',
    views: c.activityViews ?? [],
    size: c.panelSize,
    sizeHref: c.panelSizeHref,
  };
  return (
    <Fragment>
      <ActivityBody c={c} t={t} />
      <ActivityTop spec={spec} oob={true} />
      <ActivityBottom spec={spec} oob={true} t={t} />
    </Fragment>
  );
}
