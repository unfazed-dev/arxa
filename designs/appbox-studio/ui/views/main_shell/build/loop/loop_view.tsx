// loop_view.tsx — Build loop surface (replaces loop_view.html).
//
// The run thread IS the chat: stage / evidence / chart / gate cards stream
// into the composer panel — centered when nothing is open, docked right when
// an artifact is in the main panel. Gate decisions are chat acts.
// Extends main_shell_view; all 33 macros are exported functions (registry
// auto-lowercases the names).

import { Fragment, type FC } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import MainShellView from '../../main_shell_view.tsx';
import { StatusPill, TypeBadge, CtaLink, inspectAttrs, Label, Heading, Txt } from '../../../../common/widgets/primitives.tsx';
import { PanelBar, Empty, View as MainView, Open as MainPanelOpen } from '../../../../common/widgets/main_panel.tsx';
import { Open as ComposerPanelOpen } from '../../shared/widgets/composer_panel.tsx';
import { Open as ActivityPanelOpen, Top as ActivityTop, Bottom as ActivityBottom } from '../../shared/widgets/activity_panel.tsx';
import { Field } from '../../shared/widgets/composer.tsx';
import { DesignViewer } from '../../shared/widgets/design_viewer.tsx';
import { Timeline as RenderTimeline } from '../../shared/widgets/timeline.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// ---- context types ----------------------------------------------------------

interface RunState {
  number: string | number;
  brief: string;
  stateLabel: string;
  started: string;
  elapsed: string;
  policy: { stopOnRed: boolean; escLimit: number | string };
  pausedByYou?: boolean;
}

interface Message {
  from: string;
  text: string;
  active?: boolean;
  tone?: string;
  at: string;
  card?: { type: string; label?: string; state?: string; detail?: string; gateId?: string };
  artifact?: string;
}

interface StageItem {
  n: number;
  id: string;
  label: string;
  state: string;
  duration?: string;
  summary?: string;
  detail?: string;
  attempts?: { n: number; state: string; note?: string }[];
}

interface GateItem {
  id: string;
  state: string;
  label: string;
  context: string;
  provenance?: { by?: string; shell?: string; device?: string; method?: string; at?: string; hash?: string };
  note?: string;
}

interface FindingItem {
  severity: string;
  file: string;
  line: number;
  check: string;
  expected: string;
  actual: string;
  reproduce: string;
  state: string;
  fingerprint: string;
  note: string;
}

interface ChartData {
  maxDuration: { duration: string };
  bars: { label: string; state: string; pct: string | number; duration: string }[];
}

interface LogLine {
  from: string;
  tone?: string;
  at: string;
  text: string;
}

interface ActivityViewDef {
  id: string;
  icon: string;
  label: string;
  href: string;
  active?: boolean;
}

interface ArtifactIdx {
  ref: string;
  kind: string;
  label: string;
  state?: string;
}

interface CommitItem {
  hash: string;
  at: string;
  message: string;
}

interface FileRowItem {
  path: string;
  mode?: boolean;
  href?: string;
  get?: string;
  status: string;
}

interface TimelineDataObj {
  items: { kind: string; state: string; label: string; ref: string; href?: string }[];
  currentId: string;
}

interface Prefs {
  accent?: string;
  theme?: string;
  [key: string]: unknown;
}

// The build loop render context. Every exported macro receives this as props.
interface LoopProps {
  translate: TFn;
  panel?: string;
  messages?: Message[];
  chips?: { id: string; label: string; tone?: string; removeHref?: string }[];
  run?: RunState;
  fileView?: { path?: string; mode?: string; modeName?: string; lang?: string; body?: string; html?: string; src?: string; backHref?: string };
  artifact?: {
    kind: string;
    gate?: GateItem;
    stage?: StageItem;
    stageCount?: number;
    list?: FindingItem[];
    gateName?: string;
    chart?: ChartData;
    messages?: LogLine[];
    evidence?: unknown;
  };
  activityView?: string;
  activityViews?: ActivityViewDef[];
  panelSize?: string;
  panelSizeHref?: string;
  stages?: StageItem[];
  filter?: string;
  artifacts?: ArtifactIdx[];
  activeArtifact?: string;
  commits?: CommitItem[];
  files?: FileRowItem[];
  viewer?: Record<string, unknown>;
  opFired?: boolean;
  noEvidence?: boolean;
  timeline?: TimelineDataObj;
  locale?: string;
  prefs?: Prefs;
  activeShell?: string;
  composerAction?: string;
  placeholder?: string;
  [key: string]: unknown;
}

// ===== the chat: thread cards + composer ====================================

// One thread card. Pending gates get inline quick-replies; every artifact
// card keeps the "view in the main panel" CTA that docks the chat.
interface MsgCardProps {
  m: Message;
  translate: TFn;
}
export function MsgCard({ m, translate }: MsgCardProps) {
  if (m.from === 'user') {
    return (
      <div class="msg msg-user">
        <Label name="loop:msg-text" class="msg-text">{m.text}</Label>
      </div>
    );
  }
  const className = `msg msg-agent${m.active ? ' is-active' : ''}${m.tone ? ` msg-tone-${m.tone}` : ''}`;
  return (
    <div class={className}>
      <header class="msg-meta" {...inspectAttrs('loop:msg-meta', { role: 'nav' })}>
        <TypeBadge type={m.card!.type} label={m.card!.label} />
        {m.card!.state && <StatusPill state={m.card!.state} size="sm" translate={translate} />}
      </header>
      <Label name="loop:msg-text" class="msg-text">{m.text}</Label>
      {m.card!.detail && <Label name="loop:msg-detail" class="msg-detail">{m.card!.detail}</Label>}
      {m.card!.type === 'gate' && m.card!.state === 'pending' && (
        <span class="gate-quick">
          <form method="post" action="/build/gates/decide"
                hx-post="/build/gates/decide" hx-target="#panels" hx-swap="outerMorph">
            <input type="hidden" name="gate" value={m.card!.gateId} {...inspectAttrs('loop:gate-id', { role: 'input' })} />
            <button type="submit" name="decision" value="approved" class="btn-approve" {...inspectAttrs('loop:approve', { role: 'action' })}>{translate('action.approve') as string}</button>
            <button type="submit" name="decision" value="rejected" class="btn-reject ghost" {...inspectAttrs('loop:reject', { role: 'action' })}>{translate('action.reject') as string}</button>
          </form>
          <CtaLink href={`/build/chips/pin?ref=gate/${m.card!.gateId}`} label={translate('build.rejectWithNote') as string}
              glyph="undo-2" variant="ghost" size={13}
              title={translate('build.rejectWithNoteTitle') as string}
              hx={{ target: '#panels' }} />
        </span>
      )}
      <footer class="msg-foot" {...inspectAttrs('loop:msg-foot', { role: 'group' })}>
        {m.artifact && (
          <span class="msg-cta" {...inspectAttrs('loop:msg-cta', { role: 'group' })}>
            {m.active ? (
              <CtaLink href={`/build/artifact/${m.artifact}`} label={translate('build.onCanvas') as string}
                  glyph="circle-dot" variant="main" size={12} hx={{ target: '#panels' }} />
            ) : (
              <CtaLink href={`/build/artifact/${m.artifact}`} label={translate('build.viewOnCanvas') as string}
                  variant="main" size={13} hx={{ target: '#panels' }} />
            )}
          </span>
        )}
        <Label name="loop:msg-time" class="msg-time">{m.at}</Label>
      </footer>
    </div>
  );
}

export function ChatThread(props: LoopProps) {
  return (
    <div class="av-list chat-thread" id="chat-thread" {...inspectAttrs('loop:chat-thread', { role: 'group' })}>
      {[...(props.messages ?? [])].reverse().map((m, i) => (
        <MsgCard key={i} m={m} translate={props.translate} />
      ))}
    </div>
  );
}

// The single input path — the shared composer card. With a gate chip pinned,
// this is the note input.
export function ComposerPanel(props: LoopProps) {
  const spec = {
    eyebrow: props.translate('build.runEyebrow', { number: props.run?.number, brief: props.run?.brief }) as string,
    chips: props.chips,
  };
  return (
    <ComposerPanelOpen spec={spec} translate={props.translate}>
      <ChatThread {...props} />
      {/* Field reads composerAction, placeholder, modelMenu, etc. from the render context. */}
      <Field {...(props as any)} />
    </ComposerPanelOpen>
  );
}

// ===== the main panel content ===============================================

// The main panel's content: the open file, else the open artifact, else empty.
export function MainContent(props: LoopProps) {
  const { translate } = props;
  if (props.fileView) {
    return <MainView f={props.fileView} translate={translate} />;
  }
  if (props.artifact) {
    return (
      <section class="mp-content" id="mp-content" aria-live="polite">
        <CanvasArtifact {...props} />
      </section>
    );
  }
  return <Empty translate={translate} />;
}

// The three content panels, one swap unit. Composer LEFT, activity RIGHT.
interface PanelsProps extends LoopProps {
  oob?: boolean;
}
export function Panels(props: PanelsProps) {
  const { translate } = props;
  return (
    <div class="panels" id="panels" data-panel={props.panel} {...(props.oob ? { 'hx-swap-oob': 'outerHTML' } : {})}>
      <PanelBar panel={props.panel} translate={translate} />
      <ComposerPanel {...props} />
      <MainPanelOpen>
        <MainContent {...props} />
      </MainPanelOpen>
      <ActivityPanel {...props} />
    </div>
  );
}

// ===== the activity panel ===================================================

export function RunView(props: LoopProps) {
  const { translate } = props;
  const run = props.run!;
  return (
    <div class="av-view run-view">
      <header class="av-view-head">
        <Label name="loop:run-eyebrow" class="eyebrow">{translate('build.runEyebrow', { number: run.number, brief: run.brief }) as string}</Label>
        <strong class="facts-state" {...inspectAttrs('loop:run-state', { role: 'text' })}>{run.stateLabel}</strong>
        <span class="facts-list">
          <Label name="loop:fact-started">{translate('build.started') as string} {run.started}</Label>
          <Label name="loop:fact-elapsed">{translate('build.elapsedFact') as string} {run.elapsed}</Label>
          <Label name="loop:fact-stop-on-red">{translate('facts.stopOnRed') as string} {run.policy.stopOnRed ? (translate('build.on') as string) : (translate('build.off') as string)}</Label>
          <Label name="loop:fact-esc">{translate('facts.esc') as string} {run.policy.escLimit}</Label>
        </span>
      </header>
      <form class="run-controls" method="post" action="/build/run/control"
            hx-post="/build/run/control" hx-target="#panel-activity-body" hx-swap="innerHTML"
            {...inspectAttrs('loop:run-controls', { role: 'group' })}>
        {run.pausedByYou ? (
          <button type="submit" name="action" value="resume" class="btn-approve" {...inspectAttrs('loop:resume-run', { role: 'action' })}><Icon name="play" size={14} /> {translate('build.resumeRun') as string}</button>
        ) : (
          <button type="submit" name="action" value="pause" class="ghost" {...inspectAttrs('loop:pause-run', { role: 'action' })}><Icon name="pause" size={14} /> {translate('build.pauseRun') as string}</button>
        )}
      </form>
      <ol class="run-stages" {...inspectAttrs('loop:stages', { role: 'list' })}>
        {(props.stages ?? []).map((s, i) => (
          <li class="run-stage" key={i}>
            <span class="run-stage-main">
              <Label name="loop:stage-label" class="run-stage-label">{s.n}. {s.label}</Label>
              <StatusPill state={s.state} translate={translate} />
            </span>
            {['active', 'queued', 'held'].includes(s.state) && (
              <span class="run-stage-acts" {...inspectAttrs('loop:stage-acts', { role: 'group' })}>
                {s.state === 'held' ? (
                  <form method="post" action={`/build/stages/${s.id}/control`}
                        hx-post={`/build/stages/${s.id}/control`} hx-target="#panels" hx-swap="outerMorph">
                    <button type="submit" name="action" value="resume" class="ico-btn"
                      title={translate('build.resumeStage', { label: s.label }) as string}
                      aria-label={translate('build.resumeStage', { label: s.label }) as string}
                      {...inspectAttrs('loop:stage-resume', { role: 'action' })}><Icon name="play" size={14} /></button>
                  </form>
                ) : (
                  <form method="post" action={`/build/stages/${s.id}/control`}
                        hx-post={`/build/stages/${s.id}/control`} hx-target="#panels" hx-swap="outerMorph">
                    <button type="submit" name="action" value="pause" class="ico-btn"
                      title={translate('build.pauseStage', { label: s.label }) as string}
                      aria-label={translate('build.pauseStage', { label: s.label }) as string}
                      {...inspectAttrs('loop:stage-pause', { role: 'action' })}><Icon name="pause" size={14} /></button>
                  </form>
                )}
                <form method="post" action={`/build/stages/${s.id}/control`}
                      hx-post={`/build/stages/${s.id}/control`} hx-target="#panels" hx-swap="outerMorph">
                  <button type="submit" name="action" value="cancel" class="ico-btn"
                    title={translate('build.cancelStage', { label: s.label }) as string}
                    aria-label={translate('build.cancelStage', { label: s.label }) as string}
                    {...inspectAttrs('loop:stage-cancel', { role: 'action' })}><Icon name="x" size={14} /></button>
                </form>
              </span>
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}

export function ThreadView(props: LoopProps) {
  const { translate } = props;
  const filters = [
    { id: 'all', label: translate('build.filter.all') as string },
    { id: 'stage', label: translate('build.filter.stage') as string },
    { id: 'gate', label: translate('build.filter.gate') as string },
    { id: 'findings', label: translate('build.filter.findings') as string },
    { id: 'evidence', label: translate('build.filter.evidence') as string },
    { id: 'note', label: translate('build.filter.note') as string },
  ];
  return (
    <div class="av-view thread-view">
      <Txt name="loop:filter-note" class="av-view-note muted">{translate('build.filterNote') as string}</Txt>
      <nav class="thread-filter" aria-label={translate('build.filterAria') as string} {...inspectAttrs('loop:filter-nav', { role: 'group' })}>
        {filters.map(o => (
          <a key={o.id}
             class={`filter-item${props.filter === o.id ? ' is-active' : ''}`}
             href={`/build/panel?type=${o.id}`}
             hx-get={`/build/panel?type=${o.id}`} hx-target="#panel-activity-body" hx-swap="innerHTML" hx-push-url="false"
             {...inspectAttrs('loop:filter-link', { role: 'action' })}>{o.label}</a>
        ))}
      </nav>
    </div>
  );
}

export function ArtifactsView(props: LoopProps) {
  const { translate } = props;
  return (
    <div class="av-view artifacts-view">
      <ul class="artifact-index" {...inspectAttrs('loop:artifact-list', { role: 'list' })}>
        {(props.artifacts ?? []).map((a, i) => (
          <li key={i}>
            <a class={`artifact-index-link${props.activeArtifact === a.ref ? ' is-active' : ''}`}
               href={`/build/artifact/${a.ref}`}
               hx-get={`/build/artifact/${a.ref}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
               {...inspectAttrs('loop:artifact-link', { role: 'action' })}>
              <TypeBadge type={a.kind} />
              <Label name="loop:artifact-label" class="artifact-index-label">{a.label}</Label>
              {a.state && <StatusPill state={a.state} translate={translate} />}
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function CommitsView(props: LoopProps) {
  return (
    <div class="av-view commits-view">
      <Txt name="loop:commits-note" class="av-view-note muted">{props.translate('build.commitsNote') as string}</Txt>
      <ol class="commit-list" {...inspectAttrs('loop:commit-list', { role: 'list' })}>
        {[...(props.commits ?? [])].reverse().map((commit, i) => (
          <li class="commit" key={i}>
            <span class="commit-head"><code class="commit-hash" {...inspectAttrs('loop:commit-hash', { role: 'text' })}>{commit.hash}</code><Label name="loop:commit-time" class="msg-time">{commit.at}</Label></span>
            <Label name="loop:commit-msg" class="commit-msg">{commit.message}</Label>
          </li>
        ))}
      </ol>
    </div>
  );
}

export function FilesView(props: LoopProps) {
  const { translate } = props;
  return (
    <div class="av-view files-view">
      <Txt name="loop:files-note" class="av-view-note muted">{translate('build.filesNote') as string}</Txt>
      <ul class="file-list" {...inspectAttrs('loop:file-list', { role: 'list' })}>
        {(props.files ?? []).map((f, i) => (
          <li class="file-row" key={i} {...inspectAttrs('loop:file-row', { role: 'list row' })}>
            {f.mode ? (
              <a class={`file-link${props.fileView && props.fileView.path === f.path ? ' is-active' : ''}`}
                 href={f.href}
                 hx-get={f.get} hx-target="#panel-main" hx-swap="innerHTML" hx-push-url={f.href}
                 {...inspectAttrs('loop:file-link', { role: 'action' })}>
                <code class="file-path" {...inspectAttrs('loop:file-path', { role: 'text' })}>{f.path}</code>
                <span class={`chip chip--muted file-status-${f.status}`} {...inspectAttrs('loop:file-status', { role: 'label' })}>{translate(`build.fileStatus.${f.status}`) as string}</span>
              </a>
            ) : (
              <Fragment>
                <code class="file-path" {...inspectAttrs('loop:file-path', { role: 'text' })}>{f.path}</code>
                <span class={`chip chip--muted file-status-${f.status}`} {...inspectAttrs('loop:file-status', { role: 'label' })}>{translate(`build.fileStatus.${f.status}`) as string}</span>
              </Fragment>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function ActivityBody(props: LoopProps) {
  switch (props.activityView) {
    case 'thread': return <ThreadView {...props} />;
    case 'artifacts': return <ArtifactsView {...props} />;
    case 'commits': return <CommitsView {...props} />;
    case 'files': return <FilesView {...props} />;
    default: return <RunView {...props} />;
  }
}

// Head label + active carousel icon — refreshed out-of-band on every
// panel-affecting act; the <aside> itself is never replaced.
export function ActivityChrome(props: LoopProps) {
  const spec = {
    label: props.translate(`activityView.${props.activityView}`) as string,
    views: props.activityViews ?? [],
    size: props.panelSize as any,
    sizeHref: props.panelSizeHref,
  };
  return (
    <Fragment>
      <ActivityTop spec={spec} oob={true} />
      <ActivityBottom spec={spec} oob={true} translate={props.translate} />
    </Fragment>
  );
}

// Targeted response for acts inside the panel: new body + head + bar OOB.
export function ActivityTarget(props: LoopProps) {
  return (
    <Fragment>
      <ActivityBody {...props} />
      <ActivityChrome {...props} />
    </Fragment>
  );
}

export function ActivityPanel(props: LoopProps) {
  const spec = {
    label: props.translate(`activityView.${props.activityView}`) as string,
    views: props.activityViews ?? [],
    size: props.panelSize as any,
    sizeHref: props.panelSizeHref,
  };
  return (
    <ActivityPanelOpen spec={spec} translate={props.translate}>
      <ActivityBody {...props} />
    </ActivityPanelOpen>
  );
}

// The width grip's response: the whole activity panel re-rendered at its
// new persisted size.
export function ActivityFrameSwap(props: LoopProps) {
  return <ActivityPanel {...props} />;
}

// ===== the shell timeline ===================================================

// Footer-panel resident, read-only.
interface TimelineProps extends LoopProps {
  oob?: boolean;
}
export function Timeline(props: TimelineProps) {
  return (
    <RenderTimeline
      timeline={props.timeline}
      oob={props.oob}
      label={props.translate('build.timelineLabel') as string}
      translate={props.translate}
    />
  );
}

// ===== Canvas artifacts: one thing at a time, large =========================

export function GateCanvas(props: { gate: GateItem; translate: TFn; [key: string]: unknown }) {
  const { gate, translate } = props;
  return (
    <article class={`artifact gate-artifact gate-${gate.state}`}>
      <header class="artifact-head">
        <Label name="loop:gate-eyebrow" class="eyebrow">{translate('build.humanGate') as string}</Label>
        <StatusPill state={gate.state} translate={translate} />
      </header>
      <Heading name="loop:gate-title" level={2} class="display">{gate.label}</Heading>
      <Txt name="loop:gate-context" class="artifact-lede">{gate.context}</Txt>

      {gate.state === 'pending' ? (
        <Fragment>
          <div class="gate-actions" id="gate-actions">
            <form class="gate-buttons" method="post" action="/build/gates/decide"
                  hx-post="/build/gates/decide" hx-target="#panels" hx-swap="outerMorph">
              <input type="hidden" name="gate" value={gate.id} {...inspectAttrs('loop:gate-id', { role: 'input' })} />
              <button type="submit" name="decision" value="approved" class="btn-approve" {...inspectAttrs('loop:approve', { role: 'action' })}>{translate('action.approve') as string}</button>
              <button type="submit" name="decision" value="rejected" class="btn-reject ghost" {...inspectAttrs('loop:reject', { role: 'action' })}>{translate('action.reject') as string}</button>
              <span class="htmx-indicator muted" {...inspectAttrs('loop:minting', { role: 'text' })}>{translate('build.minting') as string}</span>
            </form>
            <CtaLink href={`/build/chips/pin?ref=gate/${gate.id}`} label={translate('build.rejectWithNoteLong') as string}
                glyph="undo-2" variant="ghost" hx={{ target: '#panels' }} />
          </div>
          <Txt name="loop:gate-foot" class="artifact-foot muted">{translate('gateFoot') as string}</Txt>
        </Fragment>
      ) : gate.provenance ? (
        <Fragment>
          <dl class="provenance">
            <div><dt {...inspectAttrs('loop:prov-label', { role: 'label' })}>{translate('prov.decidedBy') as string}</dt><dd {...inspectAttrs('loop:prov-value', { role: 'text' })}>{gate.provenance.by} · {gate.provenance.shell}</dd></div>
            <div><dt {...inspectAttrs('loop:prov-label', { role: 'label' })}>{translate('prov.device') as string}</dt><dd {...inspectAttrs('loop:prov-value', { role: 'text' })}>{gate.provenance.device}</dd></div>
            <div><dt {...inspectAttrs('loop:prov-label', { role: 'label' })}>{translate('prov.confirm') as string}</dt><dd {...inspectAttrs('loop:prov-value', { role: 'text' })}>{gate.provenance.method} · {gate.provenance.at}</dd></div>
            <div><dt {...inspectAttrs('loop:prov-label', { role: 'label' })}>{translate('prov.hash') as string}</dt><dd><code {...inspectAttrs('loop:prov-hash', { role: 'text' })}>{gate.provenance.hash}</code></dd></div>
          </dl>
          {gate.note && <Txt name="loop:gate-note" class="gate-note">{translate('build.yourNote') as string} {gate.note}</Txt>}
        </Fragment>
      ) : (
        <Txt name="loop:gate-unreachable" class="artifact-foot muted">{translate('build.gateNotReachable') as string}</Txt>
      )}
    </article>
  );
}

export function StageCanvas(props: { s: StageItem; total: number; run?: RunState; translate: TFn; [key: string]: unknown }) {
  const { s, total, translate } = props;
  return (
    <article class={`artifact stage-artifact stage-state-${s.state}`}>
      <header class="artifact-head">
        <Label name="loop:stage-eyebrow" class="eyebrow">{translate('build.stageEyebrow', { n: s.n, total }) as string}</Label>
        <StatusPill state={s.state} translate={translate} />
      </header>
      <Heading name="loop:stage-title" level={2} class="display">{s.label}</Heading>
      <Txt name="loop:stage-metric" class="big-metric">{s.duration}<Label name="loop:stage-metric-label" class="big-metric-label">{translate('build.onTheLine') as string}</Label></Txt>
      <Txt name="loop:stage-lede" class="artifact-lede">{s.summary}</Txt>
      <Txt name="loop:stage-detail" class="artifact-detail muted">{s.detail}</Txt>
      {s.attempts && (
        <ol class="attempts" {...inspectAttrs('loop:attempts', { role: 'list' })}>
          {s.attempts.map((a, i) => (
            <li class={`attempt attempt-${a.state}`} key={i}>
              <Label name="loop:attempt-n" class="attempt-n">{translate('build.attemptOf', { n: a.n, total: props.run?.policy.escLimit }) as string}</Label>
              <StatusPill state={a.state} translate={translate} />
              <Label name="loop:attempt-note" class="muted">{a.note}</Label>
            </li>
          ))}
        </ol>
      )}
      {s.state === 'recovered' && (
        <p class="artifact-foot">
          <CtaLink href="/build/artifact/findings/coverage" label={translate('build.seeFindings') as string} hx={{ target: '#panels' }} />
        </p>
      )}
    </article>
  );
}

export function FindingsCanvas(props: { a: { list?: FindingItem[]; [key: string]: unknown }; translate: TFn; [key: string]: unknown }) {
  const { a, translate } = props;
  return (
    <article class="artifact findings-artifact">
      <header class="artifact-head">
        <Label name="loop:findings-eyebrow" class="eyebrow">{translate('build.findingsEyebrow', { gate: a.gate }) as string}</Label>
        <span class="chip chip--muted" {...inspectAttrs('loop:findings-chip', { role: 'label' })}>{translate('build.findingsChip', { count: a.list?.length ?? 0 }) as string}</span>
      </header>
      <Heading name="loop:findings-title" level={2} class="display">{translate('findingsHeadline') as string}</Heading>
      <Txt name="loop:findings-lede" class="artifact-lede">{translate('findingsLede') as string}</Txt>
      <div class="finding-list" {...inspectAttrs('loop:finding-list', { role: 'group' })}>
        {(a.list ?? []).map((f, i) => (
          <article class={`finding finding-${f.severity}`} key={i}>
            <header class="finding-head">
              <span class={`sev sev-${f.severity}`} {...inspectAttrs('loop:finding-severity', { role: 'label' })}>{translate(`finding.severity.${f.severity}`) as string}</span>
              <code class="finding-loc" {...inspectAttrs('loop:finding-loc', { role: 'text' })}>{f.file}:{f.line}</code>
              <Label name="loop:finding-check" class="finding-check muted">{f.check}</Label>
            </header>
            <dl class="finding-body">
              <div><dt {...inspectAttrs('loop:finding-expected-label', { role: 'label' })}>{translate('finding.expected') as string}</dt><dd {...inspectAttrs('loop:finding-expected-value', { role: 'text' })}>{f.expected}</dd></div>
              <div><dt {...inspectAttrs('loop:finding-actual-label', { role: 'label' })}>{translate('finding.actual') as string}</dt><dd {...inspectAttrs('loop:finding-actual-value', { role: 'text' })}>{f.actual}</dd></div>
            </dl>
            <p class="reproduce"><Label name="loop:finding-reproduce-label" class="fact-label">{translate('finding.reproduce') as string}</Label><code {...inspectAttrs('loop:finding-reproduce-cmd', { role: 'text' })}>{f.reproduce}</code></p>
            <footer class="finding-foot">
              <span class="chip chip--muted" {...inspectAttrs('loop:finding-state', { role: 'label' })}>{f.state}</span>
              <span class="muted" {...inspectAttrs('loop:finding-fingerprint', { role: 'text' })}>{translate('finding.fingerprint') as string} <code {...inspectAttrs('loop:finding-fingerprint-hash', { role: 'text' })}>{f.fingerprint}</code></span>
            </footer>
            <Txt name="loop:finding-note" class="finding-note muted">{f.note}</Txt>
          </article>
        ))}
      </div>
    </article>
  );
}

export function ChartCanvas(props: { chart: ChartData; run?: RunState; translate: TFn; [key: string]: unknown }) {
  const { chart, translate } = props;
  return (
    <article class="artifact chart-artifact">
      <header class="artifact-head">
        <Label name="loop:chart-eyebrow" class="eyebrow">{translate('build.chartEyebrow', { number: props.run?.number }) as string}</Label>
      </header>
      <Heading name="loop:chart-title" level={2} class="display">{translate('build.chartHeadline') as string}</Heading>
      <Txt name="loop:chart-lede" class="artifact-lede">{translate('build.chartLede', { duration: chart.maxDuration.duration, elapsed: props.run?.elapsed }) as string}</Txt>
      <div class="bars" role="img" aria-label={translate('build.chartAria', { duration: chart.maxDuration.duration }) as string} {...inspectAttrs('loop:chart-bars', { role: 'group' })}>
        {chart.bars.map((b, i) => (
          <div class="bar-row" key={i}>
            <Label name="loop:bar-label" class="bar-label">{b.label}</Label>
            <span class="bar-track"><span class={`bar bar-${b.state}`} style={`--pct: ${b.pct}`} /></span>
            <Label name="loop:bar-value" class="bar-value">{b.duration}</Label>
          </div>
        ))}
      </div>
      <p class="chart-note muted"><span class="legend-swatch"></span>{translate('chartNote') as string}</p>
    </article>
  );
}

export function LogCanvas(props: { messages: LogLine[]; run?: RunState; translate: TFn; [key: string]: unknown }) {
  const { messages, translate } = props;
  return (
    <article class="artifact log-artifact">
      <header class="artifact-head">
        <Label name="loop:log-eyebrow" class="eyebrow">{translate('logEyebrow') as string} · {translate('build.runShort', { number: props.run?.number }) as string}</Label>
        <span class="chip chip--muted" {...inspectAttrs('loop:log-chip', { role: 'label' })}>{translate('build.elapsedChip', { elapsed: props.run?.elapsed }) as string}</span>
      </header>
      <Heading name="loop:log-title" level={2} class="display">{translate('build.logHeadline') as string}</Heading>
      <div class="log-lines" {...inspectAttrs('loop:log-lines', { role: 'group' })}>
        {messages.map((m, i) => (
          <p class={`log-line log-${m.from}${m.tone ? ` log-tone-${m.tone}` : ''}`} key={i}>
            <Label name="loop:log-time" class="log-time">{m.at}</Label>
            <Label name="loop:log-who" class="log-who">{m.from === 'user' ? (translate('log.you') as string) : (translate('log.agent') as string)}</Label>
            <Label name="loop:log-text" class="log-text">{m.text}</Label>
          </p>
        ))}
      </div>
    </article>
  );
}

export function ViewerSwap(props: LoopProps) {
  return <DesignViewer v={props.viewer as any} translate={props.translate} />;
}

export function EvidenceCanvas(props: { evidence?: unknown; viewer?: unknown; translate: TFn; [key: string]: unknown }) {
  const { translate } = props;
  return (
    <article class="artifact evidence-artifact">
      <header class="artifact-head">
        <Label name="loop:evidence-eyebrow" class="eyebrow">{translate('evidenceEyebrow') as string}</Label>
      </header>
      <Heading name="loop:evidence-title" level={2} class="display">{translate('evidenceHeadline') as string}</Heading>
      <Txt name="loop:evidence-lede" class="artifact-lede">{translate('evidenceLede') as string}</Txt>
      {props.viewer && <DesignViewer v={props.viewer as any} translate={translate} />}
    </article>
  );
}

export function CanvasArtifact(props: LoopProps) {
  const a = props.artifact!;
  switch (a.kind) {
    case 'gate': return <GateCanvas {...props} gate={a.gate!} />;
    case 'stage': return <StageCanvas {...props} s={a.stage!} total={a.stageCount!} />;
    case 'findings': return <FindingsCanvas {...props} a={a} />;
    case 'chart': return <ChartCanvas {...props} chart={a.chart!} />;
    case 'log': return <LogCanvas {...props} messages={a.messages!} />;
    case 'evidence': return <EvidenceCanvas {...props} evidence={a.evidence} />;
    default: return null;
  }
}

// ===== Fragment responses ===================================================

export function PanelsSwap(props: LoopProps) {
  return <Panels {...props} />;
}

export function MessageSwap(props: LoopProps) {
  return (
    <Fragment>
      <Panels {...props} />
      {props.opFired && <Timeline {...props} oob={true} />}
    </Fragment>
  );
}

export function DecisionSwap(props: LoopProps) {
  return (
    <Fragment>
      <Panels {...props} />
      <Timeline {...props} oob={true} />
      <div hx-swap-oob="beforeend:#toasts"><div class="toast" id="toast-decision" {...inspectAttrs('loop:toast-decision', { role: 'text' })}>{props.run?.stateLabel}</div></div>
    </Fragment>
  );
}

export function ControlSwap(props: LoopProps) {
  return (
    <Fragment>
      <Panels {...props} />
      <Timeline {...props} oob={true} />
    </Fragment>
  );
}

export function FilterSwap(props: LoopProps) {
  return (
    <Fragment>
      <ActivityTarget {...props} />
      <Panels {...props} oob={true} />
    </Fragment>
  );
}

export function ActivityViewSwap(props: LoopProps) {
  return <ActivityTarget {...props} />;
}

export function FileSwap(props: LoopProps) {
  return <MainContent {...props} />;
}

export function RunSwap(props: LoopProps) {
  return (
    <Fragment>
      <ActivityTarget {...props} />
      <Panels {...props} oob={true} />
      <div hx-swap-oob="beforeend:#toasts"><div class="toast" id="toast-run" {...inspectAttrs('loop:toast-run', { role: 'text' })}>{props.run?.stateLabel}</div></div>
    </Fragment>
  );
}

// ===== No build evidence yet ================================================
// Nothing in appboxd writes build evidence, so this is what EVERY project
// shows today. Literal copy — l10n is outside this change's scope.

export function NoEvidence(_props: LoopProps) {
  return (
    <div class="panels" id="panels" data-panel="main">
      <div class="panel-main" id="panel-main">
        <section class="mp-content mp-empty" id="mp-content">
          <Txt name="loop:no-evidence">No build evidence yet — run a build to populate this surface.</Txt>
          <Txt name="loop:no-evidence-hint" class="muted">Stages, human gates, findings and screen evidence appear here once a run has written them.</Txt>
        </section>
      </div>
    </div>
  );
}

// ===== Page (default export) ================================================

const LoopView: FC<LoopProps> = (props) => (
  <MainShellView
    translate={props.translate}
    title={props.translate('build.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'build'}
    prefs={props.prefs}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop"
    surface={props.noEvidence ? <NoEvidence {...props} /> : <Panels {...props} />}
    footer={!props.noEvidence ? <Timeline {...props} oob={false} /> : null}
  />
);

export default LoopView;
