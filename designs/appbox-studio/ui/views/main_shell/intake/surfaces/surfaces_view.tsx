// surfaces_view.tsx — the surfaces intake step (replaces surfaces_view.html).
// Default export SurfacesView: wraps MainShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in surfaces_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx, Step } from '../_shared.tsx';
import Icon from '../../../../../runtime/icon.tsx';
import { inspectAttrs, Heading, Txt } from '../../../../common/widgets/primitives.tsx';

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
function SurfaceRow({ s, t }: { s: Surface; t: TFn }) {
  return (
    <li class="surface-row">
      <span class="surface-label" {...inspectAttrs('intake-surfaces:row-label', { role: 'label' })}>{s.label}</span>
      <code class="surface-id" {...inspectAttrs('intake-surfaces:row-id', { role: 'text' })}>{s.id}</code>
      {s.priority && <span class={`chip pri-chip pri-${s.priority}`} {...inspectAttrs('intake-surfaces:row-priority', { role: 'label' })}>{t(`pri.name.${s.priority}`) as string}</span>}
      {s.release && <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:row-release', { role: 'label' })}>{s.release}</span>}
      <SH.ProvChip p={s.provenance} t={t} />
      <span class="surface-states">
        <span class="fact-label" {...inspectAttrs('intake-surfaces:states-label', { role: 'label' })}>{t('intake.surfaces.statesLabel') as string}</span>
        {(s.states ?? []).map((st, i) => <span key={i} class="chip chip--sm chip--muted" {...inspectAttrs('intake-surfaces:state-chip', { role: 'label' })}>{st}</span>)}
      </span>
    </li>
  );
}

// The current/editing shell group, large: every surface it carries, then the
// shared confirm/skip actions — save is confirm, no correction form.
function GroupCard({ c, item, t }: { c: Ctx; item: SurfaceGroup; t: TFn }) {
  return (
    <article class={`artifact surface-group-card is-${item.state}`}>
      <header class="artifact-head">
        <Heading name="intake-surfaces:group-title" level={2} class="display">{item.label}</Heading>
        <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:surface-count', { role: 'label' })}>{t('intake.surfaces.surfaceCount', { count: (item.surfaces ?? []).length }) as string}</span>
        {item.edited && <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:edited-flag', { role: 'label' })}>{t('intake.item.edited') as string}</span>}
      </header>
      <ul class="surface-list" {...inspectAttrs('intake-surfaces:surface-list', { role: 'list' })}>
        {(item.surfaces ?? []).map((s, i) => <SurfaceRow key={i} s={s} t={t} />)}
      </ul>
      <SH.ItemActions c={c} item={item} t={t} />
    </article>
  );
}

// A done group, compact: label + count, with the shared revisit link.
function SummaryCard({ c, item, t }: { c: Ctx; item: SurfaceGroup; t: TFn }) {
  return (
    <div class={`q-card is-${item.state}`}>
      <p class="q-text" {...inspectAttrs('intake-surfaces:summary-text', { role: 'text' })}>{item.label} <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:summary-count', { role: 'label' })}>{t('intake.surfaces.surfaceCount', { count: (item.surfaces ?? []).length }) as string}</span> {item.edited && <span class="chip chip--muted" {...inspectAttrs('intake-surfaces:summary-edited', { role: 'label' })}>{t('intake.item.edited') as string}</span>}</p>
      <SH.ItemActions c={c} item={item} t={t} />
    </div>
  );
}

// The typeform stage: only the open group while walking (upcoming renders
// nothing); the compact summary of every group once complete.
function SurfacesStage({ c, t }: { c: Ctx; t: TFn }) {
  const step = (c.step as Step) ?? {};
  return (
    <SH.StepStage c={c} t={t}>
      {step.complete ? (
        <Fragment>
          <Txt name="intake-surfaces:all-confirmed" class="artifact-lede">{t('intake.step.allConfirmed', { total: step.total }) as string}</Txt>
          {(step.items ?? []).map((item, i) => <SummaryCard key={i} c={c} item={item as unknown as SurfaceGroup} t={t} />)}
        </Fragment>
      ) : (
        (step.items ?? []).map((item, i) => {
          const group = item as unknown as SurfaceGroup;
          if (group.state === 'current' || group.state === 'editing') {
            return <GroupCard key={i} c={c} item={group} t={t} />;
          }
          return null;
        })
      )}
    </SH.StepStage>
  );
}

// The main panel's content: the open file, else the surfaces stage.
function MainContent({ c, t }: { c: Ctx; t: TFn }) {
  if (c.fileView) return <SH.FileView c={c} t={t} />;
  return <SurfacesStage c={c} t={t} />;
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

const SurfacesView: FC<ViewProps> = (c) => {
  const { t } = c;
  return (
    <MainShellView
      title={t('intake.surfaces.pageTitle') as string}
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

export default SurfacesView;
