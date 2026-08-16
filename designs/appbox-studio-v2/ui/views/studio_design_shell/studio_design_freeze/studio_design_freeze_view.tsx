// freeze_view.tsx — design.freeze, the frozen-manifest + approval gate
// (replaces freeze_view.html). The approval card is the human gate that unlocks
// Build; the manifest is what is locked; drift is the stale guard.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import StudioDesignShellView from '../studio_design_shell_view.tsx';
import { Panels, FileView, type DesignCtx } from '../design_shared.tsx';
import { StatusPill, inspectAttrs, Label, Heading, Txt } from '../../../widgets/common/studio_primitives/widgets.tsx';
import { Timeline as TimelineEl } from '../../../widgets/common/studio_panels/widgets.tsx';
import Icon from '../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface TraceEntry { who?: string; at?: string; text?: string; }
interface TraceRow { surface?: string; story?: string; code?: string; files?: number; }
interface DriftHistory { state?: string; at?: string; text?: string; hash?: string; }

interface FreezeViewProps extends DesignCtx {
  translate: TFn;
  locale?: string;
  locales?: string[];
  prefs?: { accent?: string; [key: string]: unknown };
  activeShell?: string;
  timeline?: { items: unknown[]; currentId: string };
  approval?: { approved?: boolean; lede?: string; note?: string };
  manifest?: {
    id?: string; goldens?: number; surfaces?: number; rungs?: number;
    hash?: string; frozenAt?: string; structure?: string;
    provenance?: { by?: string; shell?: string; device?: string; method?: string; at?: string; hash?: string };
  };
  trace?: TraceEntry[];
  traceability?: TraceRow[];
  drift?: { checked?: string; clean?: boolean; matched?: number; history?: DriftHistory[] };
  toast?: string;
}

// ---- timeline (delegates to shared) ----
function renderTimeline(context: FreezeViewProps, oob: boolean, translate: TFn) {
  return <TimelineEl timeline={context.timeline as any} oob={oob} label={translate('design.timelineLabel') as string} translate={translate} />;
}

// ---- the approval card: the human gate ----
function ApprovalCard({ context, translate }: { context: FreezeViewProps; translate: TFn }) {
  return (
    <article class={`artifact approval-card${context.approval?.approved ? ' is-approved' : ''}`} id="approval">
      <header class="artifact-head">
        <Label name="design-freeze:approval-eyebrow" class="eyebrow">{translate('freeze.approvalEyebrow') as string}</Label>
        <StatusPill state={context.approval?.approved ? 'approved' : 'pending'} translate={translate} />
      </header>
      <Heading name="design-freeze:approval-title" level={2} class="display">{context.approval?.approved ? translate('freeze.unlocked') as string : translate('freeze.approveH') as string}</Heading>
      <Txt name="design-freeze:approval-lede" class="artifact-lede">{context.approval?.lede}</Txt>
      <Txt name="design-freeze:approval-note" class="approval-note">{context.approval?.note}</Txt>
      {!context.approval?.approved ? (
        <form method="post" action="/design/freeze/messages" hx-post="/design/freeze/messages" hx-target="#panels" hx-swap="outerMorph">
          <button type="submit" name="preset" value="approve" class="cta-main" {...inspectAttrs('design-freeze:approve', { role: 'action' })}>{translate('freeze.approveCta') as string}</button>
        </form>
      ) : (
        // v1 routed this CTA to /scaffold — the scaffold stage is not in
        // the v2 roster yet (registry: startup/auth/intake/design), so the
        // handoff lands on the hub's stage roster until it is. Recorded as
        // a roster deviation, not a redesign.
        <a class="cta-main" href="/" {...inspectAttrs('design-freeze:continue', { role: 'action' })}>{translate('freeze.continueScaffold') as string} <Icon name="arrow-right" size={14} /></a>
      )}
    </article>
  );
}

// ---- the manifest: what is locked, who signed it ----
function ManifestCard({ context, translate }: { context: FreezeViewProps; translate: TFn }) {
  const manifest = context.manifest;
  return (
    <article class="artifact freeze-manifest">
      <header class="artifact-head">
        <Label name="design-freeze:manifest-eyebrow" class="eyebrow">{translate('freeze.manifestEyebrow', { id: manifest?.id }) as string}</Label>
        <StatusPill state="frozen" translate={translate} />
      </header>
      <Heading name="design-freeze:manifest-title" level={2} class="display">{translate('freeze.frozenH', { id: manifest?.id }) as string}</Heading>
      <Txt name="design-freeze:manifest-lede" class="artifact-lede">{translate('freezeLede') as string}</Txt>
      <p class="big-metric" {...inspectAttrs('design-freeze:goldens-metric', { role: 'text' })}>
        {manifest?.goldens}
        <Label name="design-freeze:goldens-label" class="big-metric-label">{translate('freeze.goldensLabel', { surfaces: manifest?.surfaces, rungs: manifest?.rungs }) as string}</Label>
      </p>
      <div class="evidence-chain">
        <span class="fact" {...inspectAttrs('design-freeze:manifest-hash', { role: 'group' })}><Label name="design-freeze:hash-label" class="fact-label">{translate('freeze.manifestLabel') as string}</Label><code {...inspectAttrs('design-freeze:hash', { role: 'text' })}>{manifest?.hash}</code></span>
        <span class="fact" {...inspectAttrs('design-freeze:frozen-at', { role: 'group' })}><Label name="design-freeze:frozen-label" class="fact-label">{translate('freeze.frozenLabel') as string}</Label>{manifest?.frozenAt}</span>
      </div>
      <dl class="provenance">
        <div><dt {...inspectAttrs('design-freeze:prov-approvedBy', { role: 'label' })}>{translate('prov.approvedBy') as string}</dt><dd {...inspectAttrs('design-freeze:prov-approvedBy-val', { role: 'text' })}>{manifest?.provenance?.by} · {manifest?.provenance?.shell}</dd></div>
        <div><dt {...inspectAttrs('design-freeze:prov-device', { role: 'label' })}>{translate('prov.device') as string}</dt><dd {...inspectAttrs('design-freeze:prov-device-val', { role: 'text' })}>{manifest?.provenance?.device}</dd></div>
        <div><dt {...inspectAttrs('design-freeze:prov-confirm', { role: 'label' })}>{translate('prov.confirm') as string}</dt><dd {...inspectAttrs('design-freeze:prov-confirm-val', { role: 'text' })}>{manifest?.provenance?.method} · {manifest?.provenance?.at}</dd></div>
        <div><dt {...inspectAttrs('design-freeze:prov-hash', { role: 'label' })}>{translate('prov.hash') as string}</dt><dd {...inspectAttrs('design-freeze:prov-hash-val', { role: 'text' })}><code {...inspectAttrs('design-freeze:prov-hash-code', { role: 'text' })}>{manifest?.provenance?.hash}</code></dd></div>
      </dl>
      <Txt name="design-freeze:structure" class="artifact-foot muted">{manifest?.structure}</Txt>
    </article>
  );
}

// ---- the trace: approvals and provenance, in order ----
function TraceCard({ context, translate }: { context: FreezeViewProps; translate: TFn }) {
  return (
    <article class="artifact">
      <header class="artifact-head">
        <Label name="design-freeze:trace-eyebrow" class="eyebrow">{translate('traceEyebrow') as string}</Label>
      </header>
      <div class="log-lines" {...inspectAttrs('design-freeze:log-lines', { role: 'group' })}>
        {(context.trace ?? []).map((traceEntry, index) => (
          <p key={index} class={`log-line log-${traceEntry.who === 'you' ? 'user' : 'agent'}`} {...inspectAttrs('design-freeze:log-line', { role: 'text' })}>
            <Label name="design-freeze:log-time" class="log-time">{traceEntry.at}</Label>
            <Label name="design-freeze:log-who" class="log-who">{traceEntry.who === 'you' ? translate('log.you') as string : translate('log.agent') as string}</Label>
            <Label name="design-freeze:log-text" class="log-text">{traceEntry.text}</Label>
          </p>
        ))}
      </div>
    </article>
  );
}

// ---- traceability: brief story, surface, code ----
function TraceabilityCard({ context, translate }: { context: FreezeViewProps; translate: TFn }) {
  return (
    <article class="artifact">
      <header class="artifact-head">
        <Label name="design-freeze:traceability-eyebrow" class="eyebrow">{translate('traceabilityEyebrow') as string}</Label>
        <Label name="design-freeze:traced-count" class="chip chip--muted">{translate('freeze.tracedCount', { count: (context.traceability ?? []).length }) as string}</Label>
      </header>
      <div class="trace-rows" {...inspectAttrs('design-freeze:trace-rows', { role: 'group' })}>
        {(context.traceability ?? []).map((traceabilityRow, index) => (
          <div class="trace-row" key={index} {...inspectAttrs('design-freeze:trace-row', { role: 'list row' })}>
            <code class="trace-surface" {...inspectAttrs('design-freeze:trace-surface', { role: 'text' })}>{traceabilityRow.surface}</code>
            <Label name="design-freeze:trace-story" class="trace-story">{traceabilityRow.story}</Label>
            <span class="trace-code" {...inspectAttrs('design-freeze:trace-code', { role: 'group' })}><code {...inspectAttrs('design-freeze:trace-code-val', { role: 'text' })}>{traceabilityRow.code}</code> <Label name="design-freeze:trace-files" class="muted">· {translate('freeze.files', { count: traceabilityRow.files }) as string}</Label></span>
          </div>
        ))}
      </div>
    </article>
  );
}

// ---- drift: the loud stale guard ----
function DriftCard({ context, translate, oob }: { context: FreezeViewProps; translate: TFn; oob?: boolean }) {
  const drift = context.drift;
  return (
    <article class="artifact" id="drift" hx-swap-oob={oob ? 'outerHTML' : undefined}>
      <header class="artifact-head">
        <Label name="design-freeze:drift-eyebrow" class="eyebrow">{translate('drift.eyebrow', { when: drift?.checked }) as string}</Label>
        <StatusPill state={drift?.clean ? 'pass' : 'red'} translate={translate} />
      </header>
      <Heading name="design-freeze:drift-title" level={2} class="display">{translate('drift.matchedH', { matched: drift?.matched }) as string}</Heading>
      <Txt name="design-freeze:drift-lede" class="artifact-lede">{translate('driftLede') as string}</Txt>
      {(drift?.history ?? []).map((historyEntry, index) => (
        <div class="finding finding-warning" key={index}>
          <header class="finding-head">
            <Label name="design-freeze:drift-sev" class={`sev sev-warning`}>{translate(`status.name.${historyEntry.state}`) as string}</Label>
            <Label name="design-freeze:drift-check" class="finding-check muted">{historyEntry.at}</Label>
          </header>
          <Txt name="design-freeze:drift-note" class="finding-note">{historyEntry.text}</Txt>
          <footer class="finding-foot">
            <span class="muted" {...inspectAttrs('design-freeze:drift-refrozen', { role: 'text' })}>{translate('drift.refrozen') as string} <code {...inspectAttrs('design-freeze:drift-hash', { role: 'text' })}>{historyEntry.hash}</code></span>
          </footer>
        </div>
      ))}
      <form method="post" action="/design/freeze/recheck" hx-post="/design/freeze/recheck" hx-target="#drift" hx-swap="outerHTML">
        <button type="submit" class="ghost" {...inspectAttrs('design-freeze:recheck', { role: 'action' })}><Icon name="refresh-cw" size={14} /> {translate('drift.recheck') as string}</button>
        <Label name="design-freeze:hashing" class="htmx-indicator muted">{translate('drift.hashing') as string}</Label>
      </form>
    </article>
  );
}

// ---- the freeze canvas (all cards stacked) ----
function FreezeCanvas({ context, translate }: { context: FreezeViewProps; translate: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <div class="freeze-stack">
        <ApprovalCard context={context} translate={translate} />
        <ManifestCard context={context} translate={translate} />
        <TraceCard context={context} translate={translate} />
        <TraceabilityCard context={context} translate={translate} />
        <DriftCard context={context} translate={translate} />
      </div>
    </section>
  );
}

// ---- main content: open file, else the freeze cards ----
function MainContent({ context, translate }: { context: FreezeViewProps; translate: TFn }) {
  if (context.fileView) return <FileView context={context} translate={translate} />;
  return FreezeCanvas({ context, translate });
}

// ---- panels ----
function renderPanels(context: FreezeViewProps) {
  return <Panels context={context} translate={context.translate}>{MainContent({ context, translate: context.translate })}</Panels>;
}

// ---- Fragment responses ----
export function FileSwap(context: FreezeViewProps) {
  return MainContent({ context, translate: context.translate });
}

export function PanelsSwap(context: FreezeViewProps) {
  return renderPanels(context);
}

export function DriftSwap(context: FreezeViewProps) {
  return (
    <Fragment>
      {DriftCard({ context, translate: context.translate })}
      <div hx-swap-oob="beforeend:#toasts">
        <div class="toast" id="toast-drift" {...inspectAttrs('design-freeze:toast', { role: 'text' })}>{context.toast}</div>
      </div>
    </Fragment>
  );
}

// ---- Page ----
const FreezeView: FC<FreezeViewProps> = (props) => (
  <StudioDesignShellView
    title={props.translate('design.freeze.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'design'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop"
    footer={renderTimeline(props, false, props.translate)}
    surface={renderPanels(props)}
    translate={props.translate}
  />
);

export default FreezeView;
