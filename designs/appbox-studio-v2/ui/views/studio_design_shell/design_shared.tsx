// design/shared.tsx — design-shell shared panels (replaces _shared.html).
// The activity panel (screens / artifacts / files / inspector) on the right,
// the composer panel with context chips, and the design thread with per-screen
// checkpoints. Macro-only file — importing it from a fragment render emits
// nothing. Every design-stage swap targets #panels: composer, context toggle,
// and revert all re-render the one container the chat and the artifact share.
import { Fragment, type Child } from 'hono/jsx';
import {
  ActivityPanelOpen as ActivityOpen,
  ActivityPanelTop as ActivityTop,
  ActivityPanelBottom as ActivityBottom,
  ComposerPanelOpen as ComposerOpen,
  ComposerField as Field,
  MainPanelOpen as MainOpen,
  PanelBar,
  Empty,
  MainPanelView as MainView,
} from '../../widgets/common/studio_panels/widgets.tsx';
import Icon from '../../../runtime/icon.tsx';
import { TypeBadge, StatusPill, inspectAttrs, Label, Heading, Txt } from '../../widgets/common/studio_primitives/widgets.tsx';
import { FactsBar } from '../../common/facts_bar.tsx';




import { Pane } from './inspector_pane.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;
type Ctx = Record<string, any>;
export type DesignCtx = Ctx;

// ---- checkpointCard — a checkpoint in the design thread with diff + revert ----
interface CheckpointCardProps {
  e: Ctx;
  translate: TFn;
}
export function CheckpointCard({ e: checkpoint, translate }: CheckpointCardProps) {
  return (
    <div class={`checkpoint${checkpoint.reverted ? ' is-reverted' : ''}`}>
      <header class="cp-head">
        <Label name="design-checkpoint:label" class="fact-label">{translate('checkpoint.label', { id: checkpoint.id, screen: checkpoint.screen }) as string}</Label>
        <Label name="design-checkpoint:summary" class="muted">{checkpoint.summary}</Label>
        <Label name="design-checkpoint:time" class="msg-time">{checkpoint.at}</Label>
      </header>
      {checkpoint.before && (
        <div class="cp-diff">
          <span class="fact" {...inspectAttrs('design-checkpoint:before', { role: 'group' })}><Label name="design-checkpoint:before-label" class="fact-label">{translate('checkpoint.before') as string}</Label>{checkpoint.before}</span>
          <span class="fact" {...inspectAttrs('design-checkpoint:after', { role: 'group' })}><Label name="design-checkpoint:after-label" class="fact-label">{translate('checkpoint.after') as string}</Label>{checkpoint.after}</span>
        </div>
      )}
      {checkpoint.reverted ? (
        <span class="bt-action-done" {...inspectAttrs('design-checkpoint:reverted', { role: 'status' })} title={translate('checkpoint.revertedTitle') as string}>
          {translate('checkpoint.reverted') as string} <Icon name="check" size={14} />
        </span>
      ) : (
        <form
          class="cp-revert"
          method="post"
          action={`/design/chat/screen/${checkpoint.screen}/revert/${checkpoint.id}`}
          hx-post={`/design/chat/screen/${checkpoint.screen}/revert/${checkpoint.id}`}
          hx-target="#panels"
          hx-swap="outerMorph"
        >
          <button type="submit" class="ghost" {...inspectAttrs('design-checkpoint:revert', { role: 'action' })}>
            <Icon name="undo-2" size={14} /> {translate('checkpoint.revert', { id: checkpoint.id }) as string}
          </button>
        </form>
      )}
    </div>
  );
}

// ---- thread — the design chat thread (events + user/agent messages + checkpoints) ----
interface ThreadProps {
  context: Ctx;
  translate: TFn;
}
export function Thread({ context, translate }: ThreadProps) {
  return (
    <div class="chat-thread" aria-live="polite" {...inspectAttrs('design-thread:log', { role: 'group' })}>
      {(context.thread ?? []).map((message: Ctx, index: number) => {
        if (message.kind === 'event') {
          return <Txt key={index} name="design-thread:event" class="bt-event">{message.text}</Txt>;
        }
        if (message.from === 'user') {
          return <Txt key={index} name="design-thread:user-msg" class="bt-msg bt-user">{message.text}</Txt>;
        }
        return (
          <Fragment key={String(index)}>
            <Txt name="design-thread:agent-msg" class="bt-msg bt-agent">
              {message.text}
              {message.link && <Fragment>{' '}<a class="bt-link" href={message.link.href} {...inspectAttrs('design-thread:link', { role: 'action' })}>{message.link.label}</a></Fragment>}
            </Txt>
            {(message.cps ?? []).map((checkpoint: Ctx, checkpointIndex: number) => (
              <CheckpointCard key={checkpointIndex} e={checkpoint} translate={translate} />
            ))}
          </Fragment>
        );
      })}
    </div>
  );
}

// ---- composerPanel — thread + composer inside the shared frame ----
interface ComposerPanelProps {
  context: Ctx;
  translate: TFn;
}
export function ComposerPanel({ context, translate }: ComposerPanelProps) {
  const spec = { eyebrow: context.stageEyebrow ?? '', chips: context.chips };
  return (
    <ComposerOpen spec={spec} translate={translate}>
      <Thread context={context} translate={translate} />
      <Field {...context} translate={translate} />
    </ComposerOpen>
  );
}

// ---- mainEmpty — the empty read state (nothing open yet) ----
export function MainEmpty({ translate }: { translate: TFn }) {
  return <Empty translate={translate} />;
}

// ---- fileView — the open file rendered by the main panel's automatic mode ----
interface FileViewProps {
  context: Ctx;
  translate: TFn;
}
export function FileView({ context, translate }: FileViewProps) {
  return <MainView file={context.fileView} translate={translate} />;
}

// ---- panels — the three content panels, one swap unit ----
// Every stage interaction re-renders #panels outerHTML. The caller fills the
// main panel via children.
interface PanelsProps {
  context: Ctx;
  translate: TFn;
  children?: Child;
}
export function Panels({ context, translate, children }: PanelsProps) {
  return (
    <div class="panels" id="panels" data-panel={context.panel}>
      <PanelBar panel={context.panel} translate={translate} />
      <ComposerPanel context={context} translate={translate} />
      <MainOpen>{children}</MainOpen>
      <ActivityPanel context={context} translate={translate} />
    </div>
  );
}

// ---- runBar — the facts bar with run data ----
interface RunBarProps {
  context: Ctx;
  oob?: boolean;
  translate: TFn;
}
export function RunBar({ context, oob = false, translate }: RunBarProps) {
  const spec = {
    eyebrow: translate('design.runEyebrow', { number: context.run.number, brief: context.run.brief }) as string,
    state: context.run.stateLabel as string,
    facts: [
      translate('surfaces.count', { count: context.counts.screens }) as string,
      translate('design.shotsFact', { count: context.counts.shots }) as string,
      context.run.rungsLabel as string,
    ],
    filter: {
      summaryAria: translate('design.filterAria') as string,
      summaryTitle: translate('design.filterTitle') as string,
      summary: (context.filter !== 'all' ? context.filter : translate('design.allEpics')) as string,
      target: '#av-list',
      swap: 'outerHTML',
      url: '/design/panel?epic=',
      active: context.filter as string,
      options: [{ id: 'all', label: translate('design.allEpics') as string }, ...(context.epics ?? [])],
    },
  };
  return <FactsBar oob={oob} spec={spec} />;
}

// ---- screenCard — a screen card with the context pin as the only CTA ----
interface ScreenCardProps {
  s: Ctx;
  translate: TFn;
}
export function ScreenCard({ s: screen, translate }: ScreenCardProps) {
  return (
    <div class={`msg msg-agent${screen.inContext ? ` is-active msg-ctx ctx-${screen.tone}` : ''}`}>
      <header class="msg-meta" {...inspectAttrs('design-screen:meta', { role: 'nav' })}>
        <TypeBadge type="screen" label={screen.epic} />
        {screen.card?.threadCount ? (
          <span class="chip thread-badge" {...inspectAttrs('design-screen:thread-count', { role: 'status' })} title={translate('design.checkpointsTitle', { count: screen.card.threadCount }) as string}>
            <Icon name="history" size={12} /> {screen.card.threadCount}
          </span>
        ) : null}
        <StatusPill state={screen.card?.state} translate={translate} />
      </header>
      <Label name="design-screen:summary" class="msg-text">{screen.summary}</Label>
      <Label name="design-screen:detail" class="msg-detail">{screen.card?.detail}</Label>
      <footer class="msg-foot">
        <span class="msg-cta">
          <a
            class="cta-main"
            href={`/design/chat/context/${screen.id}?state=toggle`}
            hx-get={`/design/chat/context/${screen.id}?state=toggle`}
            hx-target="#panels"
            hx-swap="outerMorph"
            hx-push-url="false"
            {...inspectAttrs('design-screen:pin-toggle', { role: 'action' })}
          >
            {screen.inContext
              ? <Fragment>{translate('design.inContext') as string} <Icon name="check" size={14} /></Fragment>
              : <Fragment>{translate('design.pinToContext') as string} <Icon name="pin" size={14} /></Fragment>}
          </a>
        </span>
        <Label name="design-screen:label" class="msg-time">{screen.label}</Label>
      </footer>
    </div>
  );
}

// ---- screenList — the list of screen cards (OOB-able) ----
interface ScreenListProps {
  context: Ctx;
  oob?: boolean;
  translate: TFn;
}
export function ScreenList({ context, oob = false, translate }: ScreenListProps) {
  return (
    <div class="av-list" id="av-list" hx-swap-oob={oob ? 'outerHTML' : undefined} {...inspectAttrs('design-screen:list', { role: 'group' })}>
      {context.screens?.length
        ? context.screens.map((screen: Ctx, index: number) => <ScreenCard key={screen.id ?? index} s={screen} translate={translate} />)
        : <Txt name="design-screen:empty" class="muted">{translate('design.noScreens') as string}</Txt>}
    </div>
  );
}

// ---- activityBody — the active view's body ----
// /design/panel/:view hx-swaps this into #panel-activity-body.
interface ActivityBodyProps {
  context: Ctx;
  translate: TFn;
}
export function ActivityBody({ context, translate }: ActivityBodyProps) {
  if (context.activityView === 'artifacts') {
    return (
      <div class="av-list" id="av-list" {...inspectAttrs('design-artifact:list', { role: 'group' })}>
        {(context.artifacts ?? []).map((artifact: Ctx, index: number) => (
          <artifact key={index} class="msg msg-agent av-row" href={artifact.href} {...inspectAttrs('design-artifact:row', { role: 'action' })}>
            <header class="msg-meta"><TypeBadge type={artifact.kind} /></header>
            <Label name="design-artifact:label" class="msg-text">{artifact.label}</Label>
            <Label name="design-artifact:detail" class="msg-detail">{artifact.detail}</Label>
          </artifact>
        ))}
      </div>
    );
  }
  if (context.activityView === 'files') {
    return (
      <div class="av-list" id="av-list" {...inspectAttrs('design-file:list', { role: 'group' })}>
        {(context.files ?? []).map((file: Ctx, index: number) =>
          file.mode ? (
            <a
              key={index}
              class={`msg msg-agent av-row${context.fileView && context.fileView.path === file.path ? ' is-active' : ''}`}
              href={file.href}
              hx-get={file.get}
              hx-target="#panel-main"
              hx-swap="innerHTML"
              hx-push-url={file.href}
              {...inspectAttrs('design-file:row', { role: 'action' })}
            >
              <span class="msg-text" {...inspectAttrs('design-file:path', { role: 'text' })}><code {...inspectAttrs('design-file:path-val', { role: 'text' })}>{file.path}</code></span>
              <Label name="design-file:detail" class="msg-detail">{file.detail}</Label>
            </a>
          ) : (
            <div key={index} class="msg msg-agent av-row" {...inspectAttrs('design-file:row', { role: 'group' })}>
              <span class="msg-text" {...inspectAttrs('design-file:path', { role: 'text' })}><code {...inspectAttrs('design-file:path-val', { role: 'text' })}>{file.path}</code></span>
              <Label name="design-file:detail" class="msg-detail">{file.detail}</Label>
            </div>
          ),
        )}
      </div>
    );
  }
  if (context.activityView === 'inspector') {
    return <Pane context={context} translate={translate} />;
  }
  return (
    <Fragment>
      <RunBar context={context} oob={false} translate={translate} />
      <ScreenList context={context} oob={false} translate={translate} />
    </Fragment>
  );
}

// ---- activityPanel — the multi-view activity frame wrapping the body ----
interface ActivityPanelProps {
  context: Ctx;
  translate: TFn;
}
export function ActivityPanel({ context, translate }: ActivityPanelProps) {
  const spec = {
    label: context.activityLabel ?? '',
    views: context.activityViews ?? [],
    size: context.panelSize,
    sizeHref: context.panelSizeHref,
    panelSizePx: context.panelSizePx,
  };
  return (
    <ActivityOpen spec={spec} translate={translate}>
      <ActivityBody context={context} translate={translate} />
    </ActivityOpen>
  );
}

// ---- activitySwap — view-switch response (body + top + bottom OOB) ----
interface ActivitySwapProps {
  context: Ctx;
  translate: TFn;
}
export function ActivitySwap({ context, translate }: ActivitySwapProps) {
  const spec = {
    label: context.activityLabel ?? '',
    views: context.activityViews ?? [],
    size: context.panelSize,
    sizeHref: context.panelSizeHref,
  };
  return (
    <Fragment>
      <ActivityBody context={context} translate={translate} />
      <ActivityTop spec={spec} oob={true} />
      <ActivityBottom spec={spec} oob={true} translate={translate} />
    </Fragment>
  );
}
