// mapping_view.tsx — the story-map intake step (replaces mapping_view.html).
// Default export MappingView: wraps StudioIntakeShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in mapping_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import StudioIntakeShellView from '../studio_intake_shell_view.tsx';
import * as SH from '../shared.tsx';
import type { Ctx } from '../shared.tsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../widgets/common/studio_primitives/widgets.tsx';

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
function StatusDot({ s: story, translate }: { s: Story; translate: TFn }) {
  const label = translate(`status.name.${story.status}`) as string;
  return <span class={`status-dot st-${story.status}`} title={label} aria-label={label} />;
}

// `priority` is optional on an emitted story — emitStoryMap writes null when the
// story-mapper did not grade it. Guarded, not defaulted.
function StoryCard({ context, s: story, translate }: { context: Ctx; s: Story; translate: TFn }) {
  return (
    <a class={`story-card${story.priority ? ` pri-${story.priority}` : ''}`} href={`${context.base}/artifact/story/${story.id}`}
       hx-get={`${context.base}/artifact/story/${story.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
       {...inspectAttrs('intake-mapping:story-card', { role: 'action', fn: 'navigate' })}>
      <StatusDot s={story} translate={translate} />
      <Label name="intake-mapping:story-name" class="story-text">{story.name}</Label>
      {story.priority && <Label name="intake-mapping:story-priority" class={`chip pri-chip pri-${story.priority}`}>{translate(`pri.name.${story.priority}`) as string}</Label>}
    </a>
  );
}

function RollupChip({ r: rollup, translate }: { r: Rollup; translate: TFn }) {
  return (
    <span class="chip chip--muted" {...inspectAttrs('intake-mapping:rollup', { role: 'label' })}>
      {translate('map.rollupDone', { done: rollup.done, total: rollup.total }) as string}
      {rollup.active ? ` · ${translate('map.rollupActive', { count: rollup.active }) as string}` : ''}
      {rollup.blocked ? ` · ${translate('map.rollupBlocked', { count: rollup.blocked }) as string}` : ''}
    </span>
  );
}

// Approval state on the map artifact: the gate chip, and the versioned
// re-approval badge when answers moved after approval.
function ApprovalBadge({ context, translate }: { context: Ctx; translate: TFn }) {
  const approval = (context.approval as Approval) ?? {};
  if (approval.stale) return <Label name="intake-mapping:stale-badge" class="rv-badge rv-warn">{translate('map.staleBadge', { version: approval.currentVersion }) as string}</Label>;
  if (approval.approved) return <Label name="intake-mapping:approved-badge" class="rv-badge rv-ok">{translate('map.approvedBadge', { version: approval.approvedVersion }) as string}</Label>;
  return <Label name="intake-mapping:not-approved-badge" class="rv-badge">{translate('map.notApprovedBadge') as string}</Label>;
}

// The live map: release swimlanes, epics as horizontally scrolling columns,
// stories as cards with live status dots; rollups per epic and per lane.
function MapCanvas({ context, a: artifact, translate }: { context: Ctx; a: MapArtifact; translate: TFn }) {
  const counts = artifact.counts ?? {};
  return (
    <article class="artifact map-artifact">
      <header class="artifact-head">
        <Label name="intake-mapping:eyebrow" class="eyebrow">{translate('map.eyebrow') as string}</Label>
        <ApprovalBadge context={context} translate={translate} />
        <span class="chip chip--muted" {...inspectAttrs('intake-mapping:counts', { role: 'label' })}>{translate('map.storiesCount', { count: counts.stories }) as string} · {translate('map.epicsCount', { count: counts.epics }) as string} · {translate('map.featuresCount', { count: counts.features }) as string}</span>
      </header>
      <Heading name="intake-mapping:headline" level={2} class="display">{artifact.headline}</Heading>
      <Txt name="intake-mapping:lede" class="artifact-lede">{artifact.lede}</Txt>
      <p class="map-legend">
        <Label name="intake-mapping:pri-must" class="chip pri-chip pri-must">{translate('pri.must', { count: counts.must }) as string}</Label>
        <Label name="intake-mapping:pri-should" class="chip pri-chip pri-should">{translate('pri.should', { count: counts.should }) as string}</Label>
        <Label name="intake-mapping:pri-could" class="chip pri-chip pri-could">{translate('pri.could', { count: counts.could }) as string}</Label>
        <span class="map-legend-dots">
          <span class="status-dot st-done"></span> {translate('status.name.done') as string}
          <span class="status-dot st-in-progress"></span> {translate('status.name.in-progress') as string}
          <span class="status-dot st-blocked"></span> {translate('status.name.blocked') as string}
          <span class="status-dot st-pending"></span> {translate('status.name.pending') as string}
        </span>
      </p>
      {(artifact.lanes ?? []).map((lane, index) => (
        <section class="swimlane" key={index}>
          <header class="swimlane-head">
            <Heading name="intake-mapping:swimlane-title" level={3} class="swimlane-title">{lane.release?.name}</Heading>
            {lane.release?.rollup && <RollupChip r={lane.release.rollup} translate={translate} />}
            <Label name="intake-mapping:swimlane-desc" class="swimlane-desc muted">{lane.release?.description}</Label>
          </header>
          <div class="map-grid" {...inspectAttrs('intake-mapping:map-grid', { role: 'group' })}>
            {(lane.epics ?? []).map((epic, epicIndex) => (
              <div class="map-epic" key={epicIndex}>
                <h4 class="map-epic-name" {...inspectAttrs('intake-mapping:epic-name', { role: 'heading' })}>{epic.name}</h4>
                {epic.rollup && <RollupChip r={epic.rollup} translate={translate} />}
                {(epic.features ?? []).map((feature, featureIndex) => (
                  <div class="map-feature" key={featureIndex}>
                    <Label name="intake-mapping:feature-name" class="map-feature-name">{feature.name}</Label>
                    {(feature.stories ?? []).map((story, storyIndex) => <StoryCard key={storyIndex} context={context} s={story} translate={translate} />)}
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
function StoryCanvas({ context, a: artifact, translate }: { context: Ctx; a: StoryArtifact; translate: TFn }) {
  const story = artifact.story ?? {};
  return (
    <article class="artifact story-artifact">
      <header class="artifact-head" {...inspectAttrs('intake-mapping:story-head', { role: 'group' })}>
        {artifact.epic && <Label name="intake-mapping:story-eyebrow" class="eyebrow">{translate('story.eyebrow', { epic: artifact.epic, feature: artifact.feature }) as string}</Label>}
        <span class="story-status" {...inspectAttrs('intake-mapping:story-status', { role: 'label' })}><StatusDot s={story} translate={translate} /> {translate(`status.name.${story.status}`) as string}</span>
        {story.priority && <Label name="intake-mapping:story-priority" class={`chip pri-chip pri-${story.priority}`}>{translate(`pri.name.${story.priority}`) as string}</Label>}
      </header>
      <Heading name="intake-mapping:story-title" level={2} class="display">{story.name}</Heading>
      {story.release && <p class="artifact-lede"><Label name="intake-mapping:story-release" class="chip chip--muted">{story.release}</Label></p>}
      {story.surfaces && story.surfaces.length > 0 && (
        <Fragment>
          <Txt name="intake-mapping:trace-label" class="fact-label">{translate('storyTrace') as string}</Txt>
          <ul class="trace-list" {...inspectAttrs('intake-mapping:trace-list', { role: 'list' })}>
            {story.surfaces.map((sid, index) => <li key={index}><code class="surface-id" {...inspectAttrs('intake-mapping:surface-id', { role: 'text' })}>{sid}</code></li>)}
          </ul>
        </Fragment>
      )}
      <p class="artifact-foot">
        <artifact href={`${context.base}/artifact/map/full`} hx-get={`${context.base}/artifact/map/full`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false" {...inspectAttrs('intake-mapping:back', { role: 'action', fn: 'navigate' })}><Icon name="chevron-left" size={14} /> {translate('map.back') as string}</artifact>
      </p>
    </article>
  );
}

function CanvasArtifact({ context, translate }: { context: Ctx; translate: TFn }) {
  const artifact = (context.artifact as Artifact) ?? {};
  if (artifact.kind === 'missing') return <SH.MissingArtifact context={context} a={artifact} />;
  if (artifact.kind === 'story') return <StoryCanvas context={context} a={artifact as StoryArtifact} translate={translate} />;
  return <MapCanvas context={context} a={artifact as MapArtifact} translate={translate} />;
}

// The main panel's content: the open file, else the open artifact, else empty.
function MainContent({ context, translate }: { context: Ctx; translate: TFn }) {
  if (context.fileView) return <SH.FileView context={context} translate={translate} />;
  if (context.artifact) {
    return (
      <section class="mp-content" id="mp-content" aria-live="polite">
        <CanvasArtifact context={context} translate={translate} />
      </section>
    );
  }
  return <SH.MainEmpty translate={translate} />;
}

function Panels({ context, translate }: { context: Ctx; translate: TFn }) {
  return <SH.Panels context={context} translate={translate}><MainContent context={context} translate={translate} /></SH.Panels>;
}

// ---------- Fragment responses ----------

// Every stage interaction re-renders the whole panels block; the timeline rides
// along out-of-band since interview progress moves it too.
export function PanelsSwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return (
    <Fragment>
      <Panels context={context} translate={translate} />
      <SH.Timeline context={context} translate={translate} oob={true} />
    </Fragment>
  );
}

// Activity view switching swaps the body and refreshes head + bar out-of-band.
export function ActivitySwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return <SH.ActivitySwap context={context} translate={translate} />;
}

// A file row's response: the main panel renders the file in the server-picked mode.
export function FileSwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return <MainContent context={context} translate={translate} />;
}

// The width grip's response: the whole activity panel re-rendered at its new
// persisted size (the aside is server state now, replacing it loses nothing).
export function ActivityFrameSwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return <SH.ActivityPanel context={context} translate={translate} />;
}

// ---------- Page ----------

interface ViewProps {
  translate: TFn;
  [key: string]: unknown;
}

const MappingView: FC<ViewProps> = (context) => {
  const { translate } = context;
  return (
    <StudioIntakeShellView
      title={translate('intake.mapping.pageTitle') as string}
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

export default MappingView;
