// flows_view.tsx — the flows intake step (replaces flows_view.html).
// One flow per main panel. Default export FlowsView: wraps MainShellView →
// Base. Named fragment exports dispatch the htmx routes registered in
// flows_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../../common/widgets/primitives.tsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../shared.tsx';
import type { Ctx, StepItem, FlowEdge } from '../shared.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// The edge chain: a vertical path of node pairs.
function EdgeChain({ item }: { item: StepItem }) {
  return (
    <ol class="edge-chain" {...inspectAttrs('intake-flows:edge-chain', { role: 'list' })}>
      {(item.edges ?? []).map((edge: FlowEdge, index) => (
        <li key={index} class="edge">
          <span class="edge-node" {...inspectAttrs('intake-flows:edge-node', { role: 'label' })}>
            <Label name="intake-flows:edge-from-label" class="edge-label">{edge.fromLabel}</Label>
            <code class="edge-id" {...inspectAttrs('intake-flows:edge-from-id', { role: 'text' })}>{edge.from}</code>
          </span>
          <span class="edge-link" {...inspectAttrs('intake-flows:edge-link', { role: 'label' })}>
            <Icon name="move-right" size={16} />
            <Label name="intake-flows:edge-trigger" class="edge-trigger">{edge.trigger}</Label>
            {edge.label ? <Label name="intake-flows:edge-chip" class="chip chip--muted">{edge.label}</Label> : null}
          </span>
          <span class="edge-node" {...inspectAttrs('intake-flows:edge-node', { role: 'label' })}>
            <Label name="intake-flows:edge-to-label" class="edge-label">{edge.toLabel}</Label>
            <code class="edge-id" {...inspectAttrs('intake-flows:edge-to-id', { role: 'text' })}>{edge.to}</code>
          </span>
        </li>
      ))}
    </ol>
  );
}

// The current (or editing) flow, large.
function FlowCard({ context, item, translate }: { context: Ctx; item: StepItem; translate: TFn }) {
  return (
    <article class={`artifact flow-artifact is-${item.state ?? ''}`}>
      <header class="artifact-head" {...inspectAttrs('intake-flows:artifact-head', { role: 'group' })}>
        {item.personaName ? <span class="chip chip--muted" {...inspectAttrs('intake-flows:persona-label', { role: 'label' })}><Icon name="user" size={14} /> {translate('intake.flows.personaLabel', { name: item.personaName }) as string}</span> : null}
        <SH.ProvChip p={item.provenance} translate={translate} />
        <span class="chip chip--muted" {...inspectAttrs('intake-flows:edge-count', { role: 'label' })}><Icon name="waypoints" size={14} /> {translate('intake.flows.edgeCount', { count: item.edges?.length ?? 0 }) as string}</span>
      </header>
      <Heading name="intake-flows:flow-name" level={2} class="display">{item.name}</Heading>
      <EdgeChain item={item} />
      {item.state === 'editing' ? (
        <form class="q-form" method="post" action={`${context.base}/save`}
              hx-post={`${context.base}/save`} hx-target="#panels" hx-swap="outerMorph">
          <input type="hidden" name="item" value={item.id} {...inspectAttrs('intake-flows:flow-id', { role: 'input' })} />
          <label class="fact-label" for={`flow-name-${item.id}`} {...inspectAttrs('intake-flows:flow-name-label', { role: 'label' })}>{translate('intake.form.name') as string}</label>
          <input type="text" id={`flow-name-${item.id}`} name="name" value={item.name} {...inspectAttrs('intake-flows:flow-name-input', { role: 'input' })} />
          <button type="submit" class="cta-main" {...inspectAttrs('intake-flows:save', { role: 'action', fn: 'submit' })}>{translate('intake.form.save') as string} <Icon name="check" size={14} /></button>
        </form>
      ) : null}
      <SH.ItemActions context={context} item={item} translate={translate} />
    </article>
  );
}

// A done flow in the complete summary: compact, re-openable.
function FlowRow({ context, item, translate }: { context: Ctx; item: StepItem; translate: TFn }) {
  return (
    <div class={`q-card is-${item.state ?? ''}`}>
      <Txt name="intake-flows:row-name" class="q-text">{item.name}</Txt>
      <span class="rv-badges" {...inspectAttrs('intake-flows:row-badges', { role: 'label' })}>
        {item.personaName ? <span class="chip chip--muted" {...inspectAttrs('intake-flows:persona-label', { role: 'label' })}><Icon name="user" size={14} /> {translate('intake.flows.personaLabel', { name: item.personaName }) as string}</span> : null}
        <Label name="intake-flows:edge-count" class="chip chip--muted">{translate('intake.flows.edgeCount', { count: item.edges?.length ?? 0 }) as string}</Label>
        {item.edited ? <Label name="intake-flows:edited" class="chip chip--muted">{translate('intake.item.edited') as string}</Label> : null}
      </span>
      <SH.ItemActions context={context} item={item} translate={translate} />
    </div>
  );
}

function FlowsStage({ context, translate }: { context: Ctx; translate: TFn }) {
  const step = context.step;
  return (
    <SH.StepStage context={context} translate={translate}>
      {step?.complete ? (
        <div class="step-summary">
          <Heading name="intake-flows:all-confirmed" level={2} class="display">{translate('intake.step.allConfirmed', { total: step.total }) as string}</Heading>
          {(step.items ?? []).map((item) => <FlowRow key={item.id} context={context} item={item} translate={translate} />)}
        </div>
      ) : (
        (step?.items ?? [])
          .filter((item) => item.state === 'current' || item.state === 'editing')
          .map((item) => <FlowCard key={item.id} context={context} item={item} translate={translate} />)
      )}
    </SH.StepStage>
  );
}

// The main panel's content: the open file, else the flows stage.
function MainContent({ context, translate }: { context: Ctx; translate: TFn }) {
  if (context.fileView) return <SH.FileView context={context} translate={translate} />;
  return <FlowsStage context={context} translate={translate} />;
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

const FlowsView: FC<ViewProps> = (context) => {
  const { translate } = context;
  return (
    <MainShellView
      title={translate('intake.flows.pageTitle') as string}
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

export default FlowsView;
