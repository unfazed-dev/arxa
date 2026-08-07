// brief_view.tsx — the brief intake step (replaces brief_view.html).
// Default export BriefView: wraps MainShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in brief_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import { Heading, inspectAttrs, Label, Txt } from '../../../../common/widgets/primitives.tsx';
import Icon from '../../../../../runtime/icon.tsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx, MissingArtifactA } from '../_shared.tsx';

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
function Inventory({ surfaces, t }: { surfaces: Surface[]; t: TFn }) {
  return (
    <table class="inv-table">
      <thead>
        <tr><th {...inspectAttrs('intake-brief:inv-id', { role: 'label' })}>{t('inv.id') as string}</th><th {...inspectAttrs('intake-brief:inv-label', { role: 'label' })}>{t('inv.label') as string}</th><th {...inspectAttrs('intake-brief:inv-priority', { role: 'label' })}>{t('inv.priority') as string}</th><th {...inspectAttrs('intake-brief:inv-release', { role: 'label' })}>{t('inv.release') as string}</th></tr>
      </thead>
      <tbody {...inspectAttrs('intake-brief:inv-body', { role: 'group' })}>
        {surfaces.map((s) => (
          <tr key={s.id}>
            <td {...inspectAttrs('intake-brief:inv-cell-id', { role: 'text' })}><code class="surface-id" {...inspectAttrs('intake-brief:surface-id', { role: 'text' })}>{s.id}</code></td>
            <td {...inspectAttrs('intake-brief:inv-cell-label', { role: 'text' })}>{s.label}</td>
            <td {...inspectAttrs('intake-brief:inv-cell-priority', { role: 'text' })}>{s.priority ? <Label name="intake-brief:pri-chip" class={`chip pri-chip pri-${s.priority}`}>{t(`pri.name.${s.priority}`) as string}</Label> : <Label name="intake-brief:pri-unset" class="muted">{t('inv.unset') as string}</Label>}</td>
            <td {...inspectAttrs('intake-brief:inv-cell-release', { role: 'text' })}>{s.release ? <Label name="intake-brief:rel-chip" class="chip chip--muted">{s.release}</Label> : <Label name="intake-brief:rel-unset" class="muted">{t('inv.unset') as string}</Label>}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// The whole brief, rendered as the generated document.
function DocCanvas({ c, a, t }: { c: Ctx; a: Artifact; t: TFn }) {
  return (
    <article class="artifact doc-artifact">
      <header class="artifact-head">
        <Label name="intake-brief:eyebrow" class="eyebrow">{t('brief.eyebrow') as string}</Label>
        {(c.approval as { stale?: boolean } | undefined)?.stale ? <Label name="intake-brief:stale-badge" class="rv-badge rv-warn">{t('badge.stale') as string}</Label> : null}
        <Label name="intake-brief:surfaces-traced" class="chip chip--muted">{t('brief.surfacesTraced', { count: a.brief?.surfaces?.length ?? 0 }) as string}</Label>
      </header>
      <Heading name="intake-brief:title" level={2} class="display">{a.brief?.title}</Heading>
      <Txt name="intake-brief:lede" class="artifact-lede">{a.lede}</Txt>
      {a.mapMissing ? (
        <SH.MissingArtifact c={c} a={a.mapMissing} />
      ) : (
        <Fragment>
          <section class="doc-section">
            <Heading name="intake-brief:releases-h" level={3}>{t('brief.releasesH') as string}</Heading>
            {(a.releases ?? []).map((r, i) => (
              <div key={i} class="doc-release">
                <span class="doc-release-name" {...inspectAttrs('intake-brief:release-name', { role: 'label' })}>{r.name} <Label name="intake-brief:release-stories" class="chip chip--muted">{t('map.storiesCount', { count: r.stories }) as string}</Label></span>
                <Txt name="intake-brief:release-desc" class="muted">{r.description}</Txt>
              </div>
            ))}
          </section>

          <section class="doc-section">
            <Heading name="intake-brief:must-h" level={3}>{t('brief.mustH') as string}</Heading>
            {(a.epics ?? []).map((e, i) => (
              <details key={i} class="doc-epic">
                <summary {...inspectAttrs('intake-brief:epic-summary', { role: 'label' })}>{e.name} <span class="muted" {...inspectAttrs('intake-brief:epic-counts', { role: 'label' })}>· {t('map.featuresCount', { count: e.features?.length ?? 0 }) as string} · {t('map.storiesCount', { count: e.storyCount }) as string}</span></summary>
                <div class="doc-epic-body" {...inspectAttrs('intake-brief:epic-body', { role: 'group' })}>
                  {(e.features ?? []).map((f, j) => (
                    <div key={j} class="doc-feature">
                      <Label name="intake-brief:feature-name" class="map-feature-name">{f.name}</Label>
                      <ul class="doc-stories" {...inspectAttrs('intake-brief:stories-list', { role: 'list' })}>
                        {(f.stories ?? []).map((s, k) => (
                          <li key={k} {...inspectAttrs('intake-brief:story-item', { role: 'list row' })}>
                            {s.priority ? <Label name="intake-brief:story-pri" class={`chip pri-chip pri-${s.priority}`}>{t(`pri.name.${s.priority}`) as string}</Label> : null}
                            <Label name="intake-brief:story-name" class="doc-story-text">{s.name}</Label>
                            {s.release ? <Label name="intake-brief:story-rel" class="chip chip--muted">{s.release}</Label> : null}
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
        <Heading name="intake-brief:surfaces-h" level={3}>{t('brief.surfacesH') as string}</Heading>
        <Txt name="intake-brief:surface-note" class="muted">{a.brief?.surfaceNote}</Txt>
        <Inventory surfaces={a.brief?.surfaces ?? []} t={t} />
      </section>
    </article>
  );
}

// The inventory on its own — the table the designer consumes.
function SurfacesCanvas({ c, a, t }: { c: Ctx; a: Artifact; t: TFn }) {
  return (
    <article class="artifact surfaces-artifact">
      <header class="artifact-head">
        <Label name="intake-brief:surfaces-eyebrow" class="eyebrow">{t('surfaces.eyebrow') as string}</Label>
        <Label name="intake-brief:surfaces-count" class="chip chip--muted">{t('surfaces.count', { count: a.surfaces?.length ?? 0 }) as string}</Label>
      </header>
      <Heading name="intake-brief:surfaces-title" level={2} class="display">{a.headline}</Heading>
      <Txt name="intake-brief:surfaces-lede" class="artifact-lede">{a.lede}</Txt>
      <Inventory surfaces={a.surfaces ?? []} t={t} />
      <p class="artifact-foot">
        <a href={`${c.base}/artifact/doc/full`}
           hx-get={`${c.base}/artifact/doc/full`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
           {...inspectAttrs('intake-brief:back-link', { role: 'action', fn: 'navigate' })}>
          <Icon name="chevron-left" size={14} /> {t('brief.back') as string}
        </a>
      </p>
    </article>
  );
}

function CanvasArtifact({ c, t }: { c: Ctx; t: TFn }) {
  const a = c.artifact as Artifact | undefined;
  if (!a) return null;
  if (a.kind === 'missing') return <SH.MissingArtifact c={c} a={a as unknown as MissingArtifactA} />;
  if (a.kind === 'surfaces') return <SurfacesCanvas c={c} a={a} t={t} />;
  return <DocCanvas c={c} a={a} t={t} />;
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

// A file row's response: the main panel renders the file in the server-chosen mode.
export function FileSwap({ c, t }: { c: Ctx; t: TFn }) {
  return <MainContent c={c} t={t} />;
}

// The width grip's response: the whole activity panel re-rendered at its new persisted size.
export function ActivityFrameSwap({ c, t }: { c: Ctx; t: TFn }) {
  return <SH.ActivityPanel c={c} t={t} />;
}

// ---------- Page ----------

interface ViewProps {
  t: TFn;
  [key: string]: unknown;
}

const BriefView: FC<ViewProps> = (c) => {
  const { t } = c;
  return (
    <MainShellView
      title={t('intake.brief.pageTitle') as string}
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

export default BriefView;
