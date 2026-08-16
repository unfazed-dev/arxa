// brief_view.tsx — the brief intake step (replaces brief_view.html).
// Default export BriefView: wraps StudioIntakeShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in brief_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import { Heading, inspectAttrs, Label, Txt } from '../../../widgets/common/studio_primitives/widgets.tsx';
import Icon from '../../../../runtime/icon.tsx';
import StudioIntakeShellView from '../studio_intake_shell_view.tsx';
import * as SH from '../shared.tsx';
import type { Ctx, MissingArtifactA } from '../shared.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// --- brief artifact shapes ---
interface Surface { id: string; label?: string; priority?: string; release?: string; }
interface BriefDoc { title?: string; surfaces?: Surface[]; surfaceNote?: string; }
interface MapRelease { name?: string; stories?: number; description?: string; }
interface MapStory { name?: string; priority?: string; release?: string; }
interface MapFeature { name?: string; stories?: MapStory[]; }
interface MapEpic { name?: string; features?: MapFeature[]; storyCount?: number; }
interface Artifact {
  kind?: string;
  brief?: BriefDoc;
  lede?: string;
  mapMissing?: MissingArtifactA;
  releases?: MapRelease[];
  epics?: MapEpic[];
  surfaces?: Surface[];
  headline?: string;
}

// The surface inventory table — standalone artifact and the brief's last
// section. `priority` and `release` are additive story-mapper columns a
// project whose story-mapper has not run lacks; guarded, not defaulted.
function Inventory({ surfaces, translate }: { surfaces: Surface[]; translate: TFn }) {
  return (
    <table class="inv-table">
      <thead>
        <tr><th {...inspectAttrs('intake-brief:inv-id', { role: 'label' })}>{translate('inv.id') as string}</th><th {...inspectAttrs('intake-brief:inv-label', { role: 'label' })}>{translate('inv.label') as string}</th><th {...inspectAttrs('intake-brief:inv-priority', { role: 'label' })}>{translate('inv.priority') as string}</th><th {...inspectAttrs('intake-brief:inv-release', { role: 'label' })}>{translate('inv.release') as string}</th></tr>
      </thead>
      <tbody {...inspectAttrs('intake-brief:inv-body', { role: 'group' })}>
        {surfaces.map((surface) => (
          <tr key={surface.id}>
            <td {...inspectAttrs('intake-brief:inv-cell-id', { role: 'text' })}><code class="surface-id" {...inspectAttrs('intake-brief:surface-id', { role: 'text' })}>{surface.id}</code></td>
            <td {...inspectAttrs('intake-brief:inv-cell-label', { role: 'text' })}>{surface.label}</td>
            <td {...inspectAttrs('intake-brief:inv-cell-priority', { role: 'text' })}>{surface.priority ? <Label name="intake-brief:pri-chip" class={`chip pri-chip pri-${surface.priority}`}>{translate(`pri.name.${surface.priority}`) as string}</Label> : <Label name="intake-brief:pri-unset" class="muted">{translate('inv.unset') as string}</Label>}</td>
            <td {...inspectAttrs('intake-brief:inv-cell-release', { role: 'text' })}>{surface.release ? <Label name="intake-brief:rel-chip" class="chip chip--muted">{surface.release}</Label> : <Label name="intake-brief:rel-unset" class="muted">{translate('inv.unset') as string}</Label>}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// The whole brief, rendered as the generated document.
function DocCanvas({ context, a: artifact, translate }: { context: Ctx; a: Artifact; translate: TFn }) {
  return (
    <article class="artifact doc-artifact">
      <header class="artifact-head">
        <Label name="intake-brief:eyebrow" class="eyebrow">{translate('brief.eyebrow') as string}</Label>
        {(context.approval as { stale?: boolean } | undefined)?.stale ? <Label name="intake-brief:stale-badge" class="rv-badge rv-warn">{translate('badge.stale') as string}</Label> : null}
        <Label name="intake-brief:surfaces-traced" class="chip chip--muted">{translate('brief.surfacesTraced', { count: artifact.brief?.surfaces?.length ?? 0 }) as string}</Label>
      </header>
      <Heading name="intake-brief:title" level={2} class="display">{artifact.brief?.title}</Heading>
      <Txt name="intake-brief:lede" class="artifact-lede">{artifact.lede}</Txt>
      {artifact.mapMissing ? (
        <SH.MissingArtifact context={context} a={artifact.mapMissing} />
      ) : (
        <Fragment>
          <section class="doc-section">
            <Heading name="intake-brief:releases-h" level={3}>{translate('brief.releasesH') as string}</Heading>
            {(artifact.releases ?? []).map((release, index) => (
              <div key={index} class="doc-release">
                <span class="doc-release-name" {...inspectAttrs('intake-brief:release-name', { role: 'label' })}>{release.name} <Label name="intake-brief:release-stories" class="chip chip--muted">{translate('map.storiesCount', { count: release.stories }) as string}</Label></span>
                <Txt name="intake-brief:release-desc" class="muted">{release.description}</Txt>
              </div>
            ))}
          </section>

          <section class="doc-section">
            <Heading name="intake-brief:must-h" level={3}>{translate('brief.mustH') as string}</Heading>
            {(artifact.epics ?? []).map((epic, index) => (
              <details key={index} class="doc-epic">
                <summary {...inspectAttrs('intake-brief:epic-summary', { role: 'label' })}>{epic.name} <span class="muted" {...inspectAttrs('intake-brief:epic-counts', { role: 'label' })}>· {translate('map.featuresCount', { count: epic.features?.length ?? 0 }) as string} · {translate('map.storiesCount', { count: epic.storyCount }) as string}</span></summary>
                <div class="doc-epic-body" {...inspectAttrs('intake-brief:epic-body', { role: 'group' })}>
                  {(epic.features ?? []).map((feature, featureIndex) => (
                    <div key={featureIndex} class="doc-feature">
                      <Label name="intake-brief:feature-name" class="map-feature-name">{feature.name}</Label>
                      <ul class="doc-stories" {...inspectAttrs('intake-brief:stories-list', { role: 'list' })}>
                        {(feature.stories ?? []).map((story, storyIndex) => (
                          <li key={storyIndex} {...inspectAttrs('intake-brief:story-item', { role: 'list row' })}>
                            {story.priority ? <Label name="intake-brief:story-pri" class={`chip pri-chip pri-${story.priority}`}>{translate(`pri.name.${story.priority}`) as string}</Label> : null}
                            <Label name="intake-brief:story-name" class="doc-story-text">{story.name}</Label>
                            {story.release ? <Label name="intake-brief:story-rel" class="chip chip--muted">{story.release}</Label> : null}
                          </li>
                        ))}
                      </ul>
                    </div>
                  ))}
                </div>
              </details>
            ))}
          </section>
        </Fragment>
      )}

      <section class="doc-section">
        <Heading name="intake-brief:surfaces-h" level={3}>{translate('brief.surfacesH') as string}</Heading>
        <Txt name="intake-brief:surface-note" class="muted">{artifact.brief?.surfaceNote}</Txt>
        <Inventory surfaces={artifact.brief?.surfaces ?? []} translate={translate} />
      </section>
    </article>
  );
}

// The inventory on its own — the table the designer consumes.
function SurfacesCanvas({ context, a: artifact, translate }: { context: Ctx; a: Artifact; translate: TFn }) {
  return (
    <article class="artifact surfaces-artifact">
      <header class="artifact-head">
        <Label name="intake-brief:surfaces-eyebrow" class="eyebrow">{translate('surfaces.eyebrow') as string}</Label>
        <Label name="intake-brief:surfaces-count" class="chip chip--muted">{translate('surfaces.count', { count: artifact.surfaces?.length ?? 0 }) as string}</Label>
      </header>
      <Heading name="intake-brief:surfaces-title" level={2} class="display">{artifact.headline}</Heading>
      <Txt name="intake-brief:surfaces-lede" class="artifact-lede">{artifact.lede}</Txt>
      <Inventory surfaces={artifact.surfaces ?? []} translate={translate} />
      <p class="artifact-foot">
        <artifact href={`${context.base}/artifact/doc/full`}
           hx-get={`${context.base}/artifact/doc/full`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
           {...inspectAttrs('intake-brief:back-link', { role: 'action', fn: 'navigate' })}>
          <Icon name="chevron-left" size={14} /> {translate('brief.back') as string}
        </artifact>
      </p>
    </article>
  );
}

function CanvasArtifact({ context, translate }: { context: Ctx; translate: TFn }) {
  const artifact = context.artifact as Artifact | undefined;
  if (!artifact) return null;
  if (artifact.kind === 'missing') return <SH.MissingArtifact context={context} a={artifact as unknown as MissingArtifactA} />;
  if (artifact.kind === 'surfaces') return <SurfacesCanvas context={context} a={artifact} translate={translate} />;
  return <DocCanvas context={context} a={artifact} translate={translate} />;
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

// A file row's response: the main panel renders the file in the server-chosen mode.
export function FileSwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return <MainContent context={context} translate={translate} />;
}

// The width grip's response: the whole activity panel re-rendered at its new persisted size.
export function ActivityFrameSwap({ context, translate }: { context: Ctx; translate: TFn }) {
  return <SH.ActivityPanel context={context} translate={translate} />;
}

// ---------- Page ----------

interface ViewProps {
  translate: TFn;
  [key: string]: unknown;
}

const BriefView: FC<ViewProps> = (context) => {
  const { translate } = context;
  return (
    <StudioIntakeShellView
      title={translate('intake.brief.pageTitle') as string}
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

export default BriefView;
