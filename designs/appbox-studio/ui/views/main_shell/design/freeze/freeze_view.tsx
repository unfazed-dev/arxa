// freeze_view.tsx — design.freeze, the frozen-manifest + approval gate
// (replaces freeze_view.html). The approval card is the human gate that unlocks
// Build; the manifest is what is locked; drift is the stale guard.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import { Panels, FileView, type DesignCtx } from '../_shared.tsx';
import { StatusPill } from '../../../../common/widgets/primitives.tsx';
import { Timeline as TimelineEl } from '../../shared/widgets/timeline.tsx';
import Icon from '../../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface TraceEntry { who?: string; at?: string; text?: string; }
interface TraceRow { surface?: string; story?: string; code?: string; files?: number; }
interface DriftHistory { state?: string; at?: string; text?: string; hash?: string; }

interface FreezeViewProps extends DesignCtx {
  t: TFn;
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
function renderTimeline(c: FreezeViewProps, oob: boolean, t: TFn) {
  return <TimelineEl timeline={c.timeline as any} oob={oob} label={t('design.timelineLabel') as string} t={t} />;
}

// ---- the approval card: the human gate ----
function ApprovalCard({ c, t }: { c: FreezeViewProps; t: TFn }) {
  return (
    <article class={`artifact approval-card${c.approval?.approved ? ' is-approved' : ''}`} id="approval">
      <header class="artifact-head">
        <span class="eyebrow">{t('freeze.approvalEyebrow') as string}</span>
        <StatusPill state={c.approval?.approved ? 'approved' : 'pending'} t={t} />
      </header>
      <h2 class="display">{c.approval?.approved ? t('freeze.unlocked') as string : t('freeze.approveH') as string}</h2>
      <p class="artifact-lede">{c.approval?.lede}</p>
      <p class="approval-note">{c.approval?.note}</p>
      {!c.approval?.approved ? (
        <form method="post" action="/design/freeze/messages" hx-post="/design/freeze/messages" hx-target="#panels" hx-swap="outerMorph">
          <button type="submit" name="preset" value="approve" class="cta-main">{t('freeze.approveCta') as string}</button>
        </form>
      ) : (
        <a class="cta-main" href="/scaffold">{t('freeze.continueScaffold') as string} <Icon name="arrow-right" size={14} /></a>
      )}
    </article>
  );
}

// ---- the manifest: what is locked, who signed it ----
function ManifestCard({ c, t }: { c: FreezeViewProps; t: TFn }) {
  const m = c.manifest;
  return (
    <article class="artifact freeze-manifest">
      <header class="artifact-head">
        <span class="eyebrow">{t('freeze.manifestEyebrow', { id: m?.id }) as string}</span>
        <StatusPill state="frozen" t={t} />
      </header>
      <h2 class="display">{t('freeze.frozenH', { id: m?.id }) as string}</h2>
      <p class="artifact-lede">{t('freezeLede') as string}</p>
      <p class="big-metric">
        {m?.goldens}
        <span class="big-metric-label">{t('freeze.goldensLabel', { surfaces: m?.surfaces, rungs: m?.rungs }) as string}</span>
      </p>
      <div class="evidence-chain">
        <span class="fact"><span class="fact-label">{t('freeze.manifestLabel') as string}</span><code>{m?.hash}</code></span>
        <span class="fact"><span class="fact-label">{t('freeze.frozenLabel') as string}</span>{m?.frozenAt}</span>
      </div>
      <dl class="provenance">
        <div><dt>{t('prov.approvedBy') as string}</dt><dd>{m?.provenance?.by} · {m?.provenance?.shell}</dd></div>
        <div><dt>{t('prov.device') as string}</dt><dd>{m?.provenance?.device}</dd></div>
        <div><dt>{t('prov.confirm') as string}</dt><dd>{m?.provenance?.method} · {m?.provenance?.at}</dd></div>
        <div><dt>{t('prov.hash') as string}</dt><dd><code>{m?.provenance?.hash}</code></dd></div>
      </dl>
      <p class="artifact-foot muted">{m?.structure}</p>
    </article>
  );
}

// ---- the trace: approvals and provenance, in order ----
function TraceCard({ c, t }: { c: FreezeViewProps; t: TFn }) {
  return (
    <article class="artifact">
      <header class="artifact-head">
        <span class="eyebrow">{t('traceEyebrow') as string}</span>
      </header>
      <div class="log-lines">
        {(c.trace ?? []).map((e, i) => (
          <p key={i} class={`log-line log-${e.who === 'you' ? 'user' : 'agent'}`}>
            <span class="log-time">{e.at}</span>
            <span class="log-who">{e.who === 'you' ? t('log.you') as string : t('log.agent') as string}</span>
            <span class="log-text">{e.text}</span>
          </p>
        ))}
      </div>
    </article>
  );
}

// ---- traceability: brief story, surface, code ----
function TraceabilityCard({ c, t }: { c: FreezeViewProps; t: TFn }) {
  return (
    <article class="artifact">
      <header class="artifact-head">
        <span class="eyebrow">{t('traceabilityEyebrow') as string}</span>
        <span class="chip chip--muted">{t('freeze.tracedCount', { count: (c.traceability ?? []).length }) as string}</span>
      </header>
      <div class="trace-rows">
        {(c.traceability ?? []).map((r, i) => (
          <div class="trace-row" key={i}>
            <code class="trace-surface">{r.surface}</code>
            <span class="trace-story">{r.story}</span>
            <span class="trace-code"><code>{r.code}</code> <span class="muted">· {t('freeze.files', { count: r.files }) as string}</span></span>
          </div>
        ))}
      </div>
    </article>
  );
}

// ---- drift: the loud stale guard ----
function DriftCard({ c, t, oob }: { c: FreezeViewProps; t: TFn; oob?: boolean }) {
  const d = c.drift;
  return (
    <article class="artifact" id="drift" hx-swap-oob={oob ? 'outerHTML' : undefined}>
      <header class="artifact-head">
        <span class="eyebrow">{t('drift.eyebrow', { when: d?.checked }) as string}</span>
        <StatusPill state={d?.clean ? 'pass' : 'red'} t={t} />
      </header>
      <h2 class="display">{t('drift.matchedH', { matched: d?.matched }) as string}</h2>
      <p class="artifact-lede">{t('driftLede') as string}</p>
      {(d?.history ?? []).map((h, i) => (
        <div class="finding finding-warning" key={i}>
          <header class="finding-head">
            <span class="sev sev-warning">{t(`status.name.${h.state}`) as string}</span>
            <span class="finding-check muted">{h.at}</span>
          </header>
          <p class="finding-note">{h.text}</p>
          <footer class="finding-foot">
            <span class="muted">{t('drift.refrozen') as string} <code>{h.hash}</code></span>
          </footer>
        </div>
      ))}
      <form method="post" action="/design/freeze/recheck" hx-post="/design/freeze/recheck" hx-target="#drift" hx-swap="outerHTML">
        <button type="submit" class="ghost"><Icon name="refresh-cw" size={14} /> {t('drift.recheck') as string}</button>
        <span class="htmx-indicator muted">{t('drift.hashing') as string}</span>
      </form>
    </article>
  );
}

// ---- the freeze canvas (all cards stacked) ----
function FreezeCanvas({ c, t }: { c: FreezeViewProps; t: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <div class="freeze-stack">
        <ApprovalCard c={c} t={t} />
        <ManifestCard c={c} t={t} />
        <TraceCard c={c} t={t} />
        <TraceabilityCard c={c} t={t} />
        <DriftCard c={c} t={t} />
      </div>
    </section>
  );
}

// ---- main content: open file, else the freeze cards ----
function MainContent({ c, t }: { c: FreezeViewProps; t: TFn }) {
  if (c.fileView) return <FileView c={c} t={t} />;
  return FreezeCanvas({ c, t });
}

// ---- panels ----
function renderPanels(c: FreezeViewProps) {
  return <Panels c={c} t={c.t}>{MainContent({ c, t: c.t })}</Panels>;
}

// ---- Fragment responses ----
export function FileSwap(c: FreezeViewProps) {
  return MainContent({ c, t: c.t });
}

export function PanelsSwap(c: FreezeViewProps) {
  return renderPanels(c);
}

export function DriftSwap(c: FreezeViewProps) {
  return (
    <Fragment>
      {DriftCard({ c, t: c.t })}
      <div hx-swap-oob="beforeend:#toasts">
        <div class="toast" id="toast-drift">{c.toast}</div>
      </div>
    </Fragment>
  );
}

// ---- Page ----
const FreezeView: FC<FreezeViewProps> = (props) => (
  <MainShellView
    title={props.t('design.freeze.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'design'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop"
    footer={renderTimeline(props, false, props.t)}
    surface={renderPanels(props)}
    t={props.t}
  />
);

export default FreezeView;
