// moodboard_view.tsx — the moodboard intake step (replaces moodboard_view.html).
// Default export MoodboardView: wraps MainShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in moodboard_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx } from '../_shared.tsx';
import Icon from '../../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// --- moodboard artifact shapes ---
interface Approval { stale?: boolean; approved?: boolean; currentVersion?: number; approvedVersion?: number; }
interface Shot { id?: string; src?: string; caption?: string; }
interface BoardRef { shot?: Shot; name?: string; grade?: string; }
interface Board { title?: string; informs?: string; slice?: string; references?: BoardRef[]; }
interface GalleryArtifact { kind?: string; headline?: string; lede?: string; method?: string; boards?: Board[]; }
interface ShotReference { name?: string; grade?: string; url?: string; steal?: string; why?: string; }
interface ShotArtifact {
  kind?: string;
  board?: { title?: string };
  reference?: ShotReference;
  shot?: Shot;
  backRef?: string;
}
interface Artifact { kind?: string; [k: string]: unknown }

function GradeChip({ g, t }: { g: string; t: TFn }) {
  return (
    <span class={`grade grade-${g}`} {...inspectAttrs('intake-moodboard:grade', { role: 'label' })}>
      {g === 'hot'
        ? <Fragment><Icon name="flame" size={12} /> {t('grade.hot') as string}</Fragment>
        : <Fragment><Icon name="thermometer" size={12} /> {t('grade.warm') as string}</Fragment>}
    </span>
  );
}

// The gallery: boards as sections, shots as cards linked to the detail.
function GalleryCanvas({ c, a, t }: { c: Ctx; a: GalleryArtifact; t: TFn }) {
  const approval = (c.approval as Approval) ?? {};
  return (
    <article class="artifact gallery-artifact">
      <header class="artifact-head">
        <Label name="intake-moodboard:eyebrow" class="eyebrow">{t('mood.eyebrow') as string}</Label>
        {approval.stale && <Label name="intake-moodboard:stale-badge" class="rv-badge rv-warn">{t('badge.stale') as string}</Label>}
        <Label name="intake-moodboard:boards-count" class="chip chip--muted">{t('mood.boardsCount', { count: (a.boards ?? []).length }) as string}</Label>
      </header>
      <Heading name="intake-moodboard:headline" level={2} class="display">{a.headline}</Heading>
      <Txt name="intake-moodboard:lede" class="artifact-lede">{a.lede}</Txt>
      {a.method && <Txt name="intake-moodboard:method" class="artifact-detail muted">{a.method}</Txt>}
      {(a.boards ?? []).map((b, i) => (
        <section class="board" key={i}>
          <header class="board-head">
            <Heading name="intake-moodboard:board-title" level={3} class="board-title">{b.title}</Heading>
            <Label name="intake-moodboard:informs" class="chip chip--muted">{t('mood.informs', { epic: b.informs }) as string}</Label>
          </header>
          <Txt name="intake-moodboard:board-slice" class="board-slice muted">{b.slice}</Txt>
          <div class="shot-grid" {...inspectAttrs('intake-moodboard:shot-grid', { role: 'group' })}>
            {(b.references ?? []).map((r, j) => (
              <a key={j} class="shot-card" href={`${c.base}/artifact/shot/${r.shot?.id}`}
                 hx-get={`${c.base}/artifact/shot/${r.shot?.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
                 {...inspectAttrs('intake-moodboard:shot-card', { role: 'action', fn: 'navigate' })}>
                <img src={r.shot?.src} alt={`${r.name} — ${r.shot?.caption}`} loading="lazy" />
                <span class="shot-meta">
                  <strong {...inspectAttrs('intake-moodboard:card-name', { role: 'text' })}>{r.name}</strong>
                  <GradeChip g={r.grade ?? ''} t={t} />
                </span>
              </a>
            ))}
          </div>
        </section>
      ))}
    </article>
  );
}

// One capture, large: the shot, what to steal, why it suits appbox.
function ShotCanvas({ c, a, t }: { c: Ctx; a: ShotArtifact; t: TFn }) {
  const reference = a.reference ?? {};
  const shot = a.shot ?? {};
  return (
    <article class="artifact shot-artifact">
      <header class="artifact-head">
        <Label name="intake-moodboard:shot-eyebrow" class="eyebrow">{a.board?.title}</Label>
        <GradeChip g={reference.grade ?? ''} t={t} />
      </header>
      <Heading name="intake-moodboard:reference-name" level={2} class="display">{reference.name}</Heading>
      <p class="artifact-detail muted"><a href={reference.url} rel="noreferrer" {...inspectAttrs('intake-moodboard:reference-url', { role: 'action', fn: 'navigate' })}>{reference.url}</a></p>
      <img class="shot-full" src={shot.src} alt={`${reference.name} — ${shot.caption}`} />
      <Txt name="intake-moodboard:shot-caption" class="artifact-detail muted">{shot.caption}</Txt>
      <Txt name="intake-moodboard:steal-label" class="fact-label">{t('shotSteal') as string}</Txt>
      <Txt name="intake-moodboard:steal-detail" class="artifact-detail">{reference.steal}</Txt>
      <Txt name="intake-moodboard:why-label" class="fact-label">{t('shotWhy') as string}</Txt>
      <Txt name="intake-moodboard:why-detail" class="artifact-detail">{reference.why}</Txt>
      <p class="artifact-foot">
        <a href={`${c.base}/artifact/${a.backRef}`} hx-get={`${c.base}/artifact/${a.backRef}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false" {...inspectAttrs('intake-moodboard:back', { role: 'action', fn: 'navigate' })}><Icon name="chevron-left" size={14} /> {t('mood.back') as string}</a>
      </p>
    </article>
  );
}

function CanvasArtifact({ c, t }: { c: Ctx; t: TFn }) {
  const a = (c.artifact as Artifact) ?? {};
  if (a.kind === 'missing') return <SH.MissingArtifact c={c} a={a} />;
  if (a.kind === 'shot') return <ShotCanvas c={c} a={a as ShotArtifact} t={t} />;
  return <GalleryCanvas c={c} a={a as GalleryArtifact} t={t} />;
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

const MoodboardView: FC<ViewProps> = (c) => {
  const { t } = c;
  return (
    <MainShellView
      title={t('intake.moodboard.pageTitle') as string}
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

export default MoodboardView;
