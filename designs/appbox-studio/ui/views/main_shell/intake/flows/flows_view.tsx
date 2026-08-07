// flows_view.tsx — the flows intake step (replaces flows_view.html).
// One flow per main panel. Default export FlowsView: wraps MainShellView →
// Base. Named fragment exports dispatch the htmx routes registered in
// flows_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx, StepItem, FlowEdge } from '../_shared.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// The edge chain: a vertical path of node pairs.
function EdgeChain({ item }: { item: StepItem }) {
  return (
    <ol class="edge-chain">
      {(item.edges ?? []).map((e: FlowEdge, i) => (
        <li key={i} class="edge">
          <span class="edge-node">
            <span class="edge-label">{e.fromLabel}</span>
            <code class="edge-id">{e.from}</code>
          </span>
          <span class="edge-link">
            <Icon name="move-right" size={16} />
            <span class="edge-trigger">{e.trigger}</span>
            {e.label ? <span class="chip chip--muted">{e.label}</span> : null}
          </span>
          <span class="edge-node">
            <span class="edge-label">{e.toLabel}</span>
            <code class="edge-id">{e.to}</code>
          </span>
        </li>
      ))}
    </ol>
  );
}

// The current (or editing) flow, large.
function FlowCard({ c, item, t }: { c: Ctx; item: StepItem; t: TFn }) {
  return (
    <article class={`artifact flow-artifact is-${item.state ?? ''}`}>
      <header class="artifact-head">
        {item.personaName ? <span class="chip chip--muted"><Icon name="user" size={14} /> {t('intake.flows.personaLabel', { name: item.personaName }) as string}</span> : null}
        <SH.ProvChip p={item.provenance} t={t} />
        <span class="chip chip--muted"><Icon name="waypoints" size={14} /> {t('intake.flows.edgeCount', { count: item.edges?.length ?? 0 }) as string}</span>
      </header>
      <h2 class="display">{item.name}</h2>
      <EdgeChain item={item} />
      {item.state === 'editing' ? (
        <form class="q-form" method="post" action={`${c.base}/save`}
              hx-post={`${c.base}/save`} hx-target="#panels" hx-swap="morph:outerHTML">
          <input type="hidden" name="item" value={item.id} />
          <label class="fact-label" for={`flow-name-${item.id}`}>{t('intake.form.name') as string}</label>
          <input type="text" id={`flow-name-${item.id}`} name="name" value={item.name} />
          <button type="submit" class="cta-main">{t('intake.form.save') as string} <Icon name="check" size={14} /></button>
        </form>
      ) : null}
      <SH.ItemActions c={c} item={item} t={t} />
    </article>
  );
}

// A done flow in the complete summary: compact, re-openable.
function FlowRow({ c, item, t }: { c: Ctx; item: StepItem; t: TFn }) {
  return (
    <div class={`q-card is-${item.state ?? ''}`}>
      <p class="q-text">{item.name}</p>
      <span class="rv-badges">
        {item.personaName ? <span class="chip chip--muted"><Icon name="user" size={14} /> {t('intake.flows.personaLabel', { name: item.personaName }) as string}</span> : null}
        <span class="chip chip--muted">{t('intake.flows.edgeCount', { count: item.edges?.length ?? 0 }) as string}</span>
        {item.edited ? <span class="chip chip--muted">{t('intake.item.edited') as string}</span> : null}
      </span>
      <SH.ItemActions c={c} item={item} t={t} />
    </div>
  );
}

function FlowsStage({ c, t }: { c: Ctx; t: TFn }) {
  const step = c.step;
  return (
    <SH.StepStage c={c} t={t}>
      {step?.complete ? (
        <div class="step-summary">
          <h2 class="display">{t('intake.step.allConfirmed', { total: step.total }) as string}</h2>
          {(step.items ?? []).map((item) => <FlowRow key={item.id} c={c} item={item} t={t} />)}
        </div>
      ) : (
        (step?.items ?? [])
          .filter((item) => item.state === 'current' || item.state === 'editing')
          .map((item) => <FlowCard key={item.id} c={c} item={item} t={t} />)
      )}
    </SH.StepStage>
  );
}

// The main panel's content: the open file, else the flows stage.
function MainContent({ c, t }: { c: Ctx; t: TFn }) {
  if (c.fileView) return <SH.FileView c={c} t={t} />;
  return <FlowsStage c={c} t={t} />;
}

function Panels({ c, t }: { c: Ctx; t: TFn }) {
  return <SH.Panels c={c} t={t}><MainContent c={c} t={t} /></SH.Panels>;
}

// ---------- Fragment responses ----------

export function PanelsSwap({ c, t }: { c: Ctx; t: TFn }) {
  return (
    <Fragment>
      <Panels c={c} t={t} />
      <SH.Timeline c={c} t={t} oob={true} />
    </Fragment>
  );
}

export function ActivitySwap({ c, t }: { c: Ctx; t: TFn }) {
  return <SH.ActivitySwap c={c} t={t} />;
}

export function FileSwap({ c, t }: { c: Ctx; t: TFn }) {
  return <MainContent c={c} t={t} />;
}

export function ActivityFrameSwap({ c, t }: { c: Ctx; t: TFn }) {
  return <SH.ActivityPanel c={c} t={t} />;
}

// ---------- Page ----------

interface ViewProps {
  t: TFn;
  [key: string]: unknown;
}

const FlowsView: FC<ViewProps> = (c) => {
  const { t } = c;
  return (
    <MainShellView
      title={t('intake.flows.pageTitle') as string}
      mainClass="shell-main-loop"
      activeShell={c.activeShell as string}
      prefs={c.prefs as { accent?: string; [k: string]: unknown }}
      project={c.project as { name?: string; savedLabel?: string }}
      locale={c.locale as string}
      t={t}
      footer={<SH.Timeline c={c as Ctx} t={t} oob={false} />}
      surface={<Panels c={c as Ctx} t={t} />}
    />
  );
};

export default FlowsView;
