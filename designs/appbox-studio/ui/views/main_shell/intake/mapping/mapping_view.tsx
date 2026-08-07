// mapping_view.tsx — the story-map intake step (replaces mapping_view.html).
// Default export MappingView: wraps MainShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in mapping_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx } from '../_shared.tsx';
import Icon from '../../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// --- story-map artifact shapes ---
interface Counts {
  stories?: number; epics?: number; features?: number;
  must?: number; should?: number; could?: number;
}
interface Rollup { done?: number; total?: number; active?: number; blocked?: number; }
interface Approval { stale?: boolean; approved?: boolean; currentVersion?: number; approvedVersion?: number; }
interface Story {
  id?: string; name?: string; status?: string; priority?: string;
  release?: string; surfaces?: string[];
}
interface Feature { name?: string; stories?: Story[]; rollup?: Rollup; }
interface Epic { name?: string; rollup?: Rollup; features?: Feature[]; }
interface Lane { release?: { name?: string; description?: string; rollup?: Rollup }; epics?: Epic[]; }
interface MapArtifact { kind?: string; headline?: string; lede?: string; counts?: Counts; lanes?: Lane[]; }
interface StoryArtifact { kind?: string; story?: Story; epic?: string; feature?: string; }
interface Artifact { kind?: string; [k: string]: unknown }

// Live status dot per story, fed by the seeded pipeline statuses.
function StatusDot({ s, t }: { s: Story; t: TFn }) {
  const label = t(`status.name.${s.status}`) as string;
  return <span class={`status-dot st-${s.status}`} title={label} aria-label={label} />;
}

// `priority` is optional on an emitted story — emitStoryMap writes null when the
// story-mapper did not grade it. Guarded, not defaulted.
function StoryCard({ c, s, t }: { c: Ctx; s: Story; t: TFn }) {
  return (
    <a class={`story-card${s.priority ? ` pri-${s.priority}` : ''}`} href={`${c.base}/artifact/story/${s.id}`}
       hx-get={`${c.base}/artifact/story/${s.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
      <StatusDot s={s} t={t} />
      <span class="story-text">{s.name}</span>
      {s.priority && <span class={`chip pri-chip pri-${s.priority}`}>{t(`pri.name.${s.priority}`) as string}</span>}
    </a>
  );
}

function RollupChip({ r, t }: { r: Rollup; t: TFn }) {
  return (
    <span class="chip chip--muted">
      {t('map.rollupDone', { done: r.done, total: r.total }) as string}
      {r.active ? ` · ${t('map.rollupActive', { count: r.active }) as string}` : ''}
      {r.blocked ? ` · ${t('map.rollupBlocked', { count: r.blocked }) as string}` : ''}
    </span>
  );
}

// Approval state on the map artifact: the gate chip, and the versioned
// re-approval badge when answers moved after approval.
function ApprovalBadge({ c, t }: { c: Ctx; t: TFn }) {
  const approval = (c.approval as Approval) ?? {};
  if (approval.stale) return <span class="rv-badge rv-warn">{t('map.staleBadge', { version: approval.currentVersion }) as string}</span>;
  if (approval.approved) return <span class="rv-badge rv-ok">{t('map.approvedBadge', { version: approval.approvedVersion }) as string}</span>;
  return <span class="rv-badge">{t('map.notApprovedBadge') as string}</span>;
}

// The live map: release swimlanes, epics as horizontally scrolling columns,
// stories as cards with live status dots; rollups per epic and per lane.
function MapCanvas({ c, a, t }: { c: Ctx; a: MapArtifact; t: TFn }) {
  const counts = a.counts ?? {};
  return (
    <article class="artifact map-artifact">
      <header class="artifact-head">
        <span class="eyebrow">{t('map.eyebrow') as string}</span>
        <ApprovalBadge c={c} t={t} />
        <span class="chip chip--muted">{t('map.storiesCount', { count: counts.stories }) as string} · {t('map.epicsCount', { count: counts.epics }) as string} · {t('map.featuresCount', { count: counts.features }) as string}</span>
      </header>
      <h2 class="display">{a.headline}</h2>
      <p class="artifact-lede">{a.lede}</p>
      <p class="map-legend">
        <span class="chip pri-chip pri-must">{t('pri.must', { count: counts.must }) as string}</span>
        <span class="chip pri-chip pri-should">{t('pri.should', { count: counts.should }) as string}</span>
        <span class="chip pri-chip pri-could">{t('pri.could', { count: counts.could }) as string}</span>
        <span class="map-legend-dots">
          <span class="status-dot st-done"></span> {t('status.name.done') as string}
          <span class="status-dot st-in-progress"></span> {t('status.name.in-progress') as string}
          <span class="status-dot st-blocked"></span> {t('status.name.blocked') as string}
          <span class="status-dot st-pending"></span> {t('status.name.pending') as string}
        </span>
      </p>
      {(a.lanes ?? []).map((lane, i) => (
        <section class="swimlane" key={i}>
          <header class="swimlane-head">
            <h3 class="swimlane-title">{lane.release?.name}</h3>
            {lane.release?.rollup && <RollupChip r={lane.release.rollup} t={t} />}
            <span class="swimlane-desc muted">{lane.release?.description}</span>
          </header>
          <div class="map-grid">
            {(lane.epics ?? []).map((epic, j) => (
              <div class="map-epic" key={j}>
                <h4 class="map-epic-name">{epic.name}</h4>
                {epic.rollup && <RollupChip r={epic.rollup} t={t} />}
                {(epic.features ?? []).map((f, k) => (
                  <div class="map-feature" key={k}>
                    <span class="map-feature-name">{f.name}</span>
                    {(f.stories ?? []).map((s, l) => <StoryCard key={l} c={c} s={s} t={t} />)}
                  </div>
                ))}
              </div>
            ))}
          </div>
        </section>
      ))}
    </article>
  );
}

// One story, large: status, priority, release, and its trace to surfaces.
function StoryCanvas({ c, a, t }: { c: Ctx; a: StoryArtifact; t: TFn }) {
  const s = a.story ?? {};
  return (
    <article class="artifact story-artifact">
      <header class="artifact-head">
        {a.epic && <span class="eyebrow">{t('story.eyebrow', { epic: a.epic, feature: a.feature }) as string}</span>}
        <span class="story-status"><StatusDot s={s} t={t} /> {t(`status.name.${s.status}`) as string}</span>
        {s.priority && <span class={`chip pri-chip pri-${s.priority}`}>{t(`pri.name.${s.priority}`) as string}</span>}
      </header>
      <h2 class="display">{s.name}</h2>
      {s.release && <p class="artifact-lede"><span class="chip chip--muted">{s.release}</span></p>}
      {s.surfaces && s.surfaces.length > 0 && (
        <Fragment>
          <p class="fact-label">{t('storyTrace') as string}</p>
          <ul class="trace-list">
            {s.surfaces.map((sid, i) => <li key={i}><code class="surface-id">{sid}</code></li>)}
          </ul>
        </Fragment>
      )}
      <p class="artifact-foot">
        <a href={`${c.base}/artifact/map/full`} hx-get={`${c.base}/artifact/map/full`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"><Icon name="chevron-left" size={14} /> {t('map.back') as string}</a>
      </p>
    </article>
  );
}

function CanvasArtifact({ c, t }: { c: Ctx; t: TFn }) {
  const a = (c.artifact as Artifact) ?? {};
  if (a.kind === 'missing') return <SH.MissingArtifact c={c} a={a} />;
  if (a.kind === 'story') return <StoryCanvas c={c} a={a as StoryArtifact} t={t} />;
  return <MapCanvas c={c} a={a as MapArtifact} t={t} />;
}

// The main panel's content: the open file, else the open artifact, else empty.
function MainContent({ c, t }: { c: Ctx; t: TFn }) {
  if (c.fileView) return <SH.FileView c={c} t={t} />;
  if (c.artifact) {
    return (
      <section class="mp-content" id="mp-content" aria-live="polite">
        <CanvasArtifact c={c} t={t} />
      </section>
    );
  }
  return <SH.MainEmpty t={t} />;
}

function Panels({ c, t }: { c: Ctx; t: TFn }) {
  return <SH.Panels c={c} t={t}><MainContent c={c} t={t} /></SH.Panels>;
}

// ---------- Fragment responses ----------

// Every stage interaction re-renders the whole panels block; the timeline rides
// along out-of-band since interview progress moves it too.
export function PanelsSwap({ c, t }: { c: Ctx; t: TFn }) {
  return (
    <Fragment>
      <Panels c={c} t={t} />
      <SH.Timeline c={c} t={t} oob={true} />
    </Fragment>
  );
}

// Activity view switching swaps the body and refreshes head + bar out-of-band.
export function ActivitySwap({ c, t }: { c: Ctx; t: TFn }) {
  return <SH.ActivitySwap c={c} t={t} />;
}

// A file row's response: the main panel renders the file in the server-picked mode.
export function FileSwap({ c, t }: { c: Ctx; t: TFn }) {
  return <MainContent c={c} t={t} />;
}

// The width grip's response: the whole activity panel re-rendered at its new
// persisted size (the aside is server state now, replacing it loses nothing).
export function ActivityFrameSwap({ c, t }: { c: Ctx; t: TFn }) {
  return <SH.ActivityPanel c={c} t={t} />;
}

// ---------- Page ----------

interface ViewProps {
  t: TFn;
  [key: string]: unknown;
}

const MappingView: FC<ViewProps> = (c) => {
  const { t } = c;
  return (
    <MainShellView
      title={t('intake.mapping.pageTitle') as string}
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

export default MappingView;
