// surfaces_view.tsx — the surfaces intake step (replaces surfaces_view.html).
// Default export SurfacesView: wraps StudioIntakeShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in surfaces_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import StudioIntakeShellView from '../studio_intake_shell_view.tsx';
import * as SH from '../shared.tsx';
import type { Ctx, Step } from '../shared.tsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs, Heading, Txt } from '../../../widgets/common/studio_primitives/widgets.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// --- surfaces artifact shapes ---
interface Surface {
  id?: string;
  label?: string;
  priority?: string;
  release?: string;
  provenance?: string;
  states?: string[];
}
interface SurfaceGroup {
  id?: string;
  state?: string;
  label?: string;
  edited?: boolean;
  surfaces?: Surface[];
}

// One surface row: label, id, priority, release, provenance, and the states the
// screen must cover. MoSCoW priority/release are optional (story-mapper's, not
// intake's) — unguarded `~` would stringify undefined into a made-up grade.
function SurfaceRow({ s: surface, translate }: { s: Surface; translate: TFn }) {
  return (
    <li class="surface-row">
      <span class="surface-label" {...inspectAttrs('intake-surfaces:row-label', { role: 'label' })}>{surface.label}</span>
      <code class="surface-id" {...inspectAttrs('intake-surfaces:row-id', { role: 'text' })}>{surface.id}</code>
      {surface.priority && <span class={`chip pri-chip pri-${surface.priority}`} {...inspectAttrs('intake-surfaces:row-priority', { role: 'label' })}>{translate(`pri.name.${surface.priority}`) as string}</span>}
      {surface.release && <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:row-release', { role: 'label' })}>{surface.release}</span>}
      <SH.ProvChip p={surface.provenance} translate={translate} />
      <span class="surface-states">
        <span class="fact-label" {...inspectAttrs('intake-surfaces:states-label', { role: 'label' })}>{translate('intake.surfaces.statesLabel') as string}</span>
        {(surface.states ?? []).map((st, index) => <span key={index} class="chip chip--sm chip--muted" {...inspectAttrs('intake-surfaces:state-chip', { role: 'label' })}>{st}</span>)}
      </span>
    </li>
  );
}

// The current/editing shell group, large: every surface it carries, then the
// shared confirm/skip actions — save is confirm, no correction form.
function GroupCard({ context, item, translate }: { context: Ctx; item: SurfaceGroup; translate: TFn }) {
  return (
    <article class={`artifact surface-group-card is-${item.state}`}>
      <header class="artifact-head">
        <Heading name="intake-surfaces:group-title" level={2} class="display">{item.label}</Heading>
        <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:surface-count', { role: 'label' })}>{translate('intake.surfaces.surfaceCount', { count: (item.surfaces ?? []).length }) as string}</span>
        {item.edited && <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:edited-flag', { role: 'label' })}>{translate('intake.item.edited') as string}</span>}
      </header>
      <ul class="surface-list" {...inspectAttrs('intake-surfaces:surface-list', { role: 'list' })}>
        {(item.surfaces ?? []).map((surface, index) => <SurfaceRow key={index} s={surface} translate={translate} />)}
      </ul>
      <SH.ItemActions context={context} item={item} translate={translate} />
    </article>
  );
}

// A done group, compact: label + count, with the shared revisit link.
function SummaryCard({ context, item, translate }: { context: Ctx; item: SurfaceGroup; translate: TFn }) {
  return (
    <div class={`q-card is-${item.state}`}>
      <p class="q-text" {...inspectAttrs('intake-surfaces:summary-text', { role: 'text' })}>{item.label} <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:summary-count', { role: 'label' })}>{translate('intake.surfaces.surfaceCount', { count: (item.surfaces ?? []).length }) as string}</span> {item.edited && <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:summary-edited', { role: 'label' })}>{translate('intake.item.edited') as string}</span>}</p>
      <SH.ItemActions context={context} item={item} translate={translate} />
    </div>
  );
}

// The typeform stage: only the open group while walking (upcoming renders
// nothing); the compact summary of every group once complete.
function SurfacesStage({ context, translate }: { context: Ctx; translate: TFn }) {
  const step = (context.step as Step) ?? {};
  return (
    <SH.StepStage context={context} translate={translate}>
      {step.complete ? (
        <Fragment>
          <Txt name="intake-surfaces:all-confirmed" class="artifact-lede">{translate('intake.step.allConfirmed', { total: step.total }) as string}</Txt>
          {(step.items ?? []).map((item, index) => <SummaryCard key={index} context={context} item={item as unknown as SurfaceGroup} translate={translate} />)}
        </Fragment>
      ) : (
        (step.items ?? []).map((item, index) => {
          const group = item as unknown as SurfaceGroup;
          if (group.state === 'current' || group.state === 'editing') {
            return <GroupCard key={index} context={context} item={group} translate={translate} />;
          }
          return null;
        })
      )}
    </SH.StepStage>
  );
}

// The main panel's content: the open file, else the surfaces stage.
function MainContent({ context, translate }: { context: Ctx; translate: TFn }) {
  if (context.fileView) return <SH.FileView context={context} translate={translate} />;
  return <SurfacesStage context={context} translate={translate} />;
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

const SurfacesView: FC<ViewProps> = (context) => {
  const { translate } = context;
  return (
    <StudioIntakeShellView
      title={translate('intake.surfaces.pageTitle') as string}
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

export default SurfacesView;
