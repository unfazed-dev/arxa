// moodboard_view.tsx — the moodboard intake step (replaces moodboard_view.html).
// Default export MoodboardView: wraps MainShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in moodboard_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../shared.tsx';
import type { Ctx } from '../shared.tsx';
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

function GradeChip({ g: grade, translate }: { g: string; translate: TFn }) {
  return (
    <span class={`grade grade-${grade}`} {...inspectAttrs('intake-moodboard:grade', { role: 'label' })}>
      {grade === 'hot'
        ? <Fragment><Icon name="flame" size={12} /> {translate('grade.hot') as string}</Fragment>
        : <Fragment><Icon name="thermometer" size={12} /> {translate('grade.warm') as string}</Fragment>}
    </span>
  );
}

// The gallery: boards as sections, shots as cards linked to the detail.
function GalleryCanvas({ context, a: artifact, translate }: { context: Ctx; a: GalleryArtifact; translate: TFn }) {
  const approval = (context.approval as Approval) ?? {};
  return (
    <article class="artifact gallery-artifact">
      <header class="artifact-head">
        <Label name="intake-moodboard:eyebrow" class="eyebrow">{translate('mood.eyebrow') as string}</Label>
        {approval.stale && <Label name="intake-moodboard:stale-badge" class="rv-badge rv-warn">{translate('badge.stale') as string}</Label>}
        <Label name="intake-moodboard:boards-count" class="chip chip--muted">{translate('mood.boardsCount', { count: (artifact.boards ?? []).length }) as string}</Label>
      </header>
      <Heading name="intake-moodboard:headline" level={2} class="display">{artifact.headline}</Heading>
      <Txt name="intake-moodboard:lede" class="artifact-lede">{artifact.lede}</Txt>
      {artifact.method && <Txt name="intake-moodboard:method" class="artifact-detail muted">{artifact.method}</Txt>}
      {(artifact.boards ?? []).map((board, index) => (
        <section class="board" key={index}>
          <header class="board-head">
            <Heading name="intake-moodboard:board-title" level={3} class="board-title">{board.title}</Heading>
            <Label name="intake-moodboard:informs" class="chip chip--muted">{translate('mood.informs', { epic: board.informs }) as string}</Label>
          </header>
          <Txt name="intake-moodboard:board-slice" class="board-slice muted">{board.slice}</Txt>
          <div class="shot-grid" {...inspectAttrs('intake-moodboard:shot-grid', { role: 'group' })}>
            {(board.references ?? []).map((reference, referenceIndex) => (
              <artifact key={referenceIndex} class="shot-card" href={`${context.base}/artifact/shot/${reference.shot?.id}`}
                 hx-get={`${context.base}/artifact/shot/${reference.shot?.id}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false"
                 {...inspectAttrs('intake-moodboard:shot-card', { role: 'action', fn: 'navigate' })}>
                <img src={reference.shot?.src} alt={`${reference.name} — ${reference.shot?.caption}`} loading="lazy" />
                <span class="shot-meta">
                  <strong {...inspectAttrs('intake-moodboard:card-name', { role: 'text' })}>{reference.name}</strong>
                  <GradeChip g={reference.grade ?? ''} translate={translate} />
                </span>
              </artifact>
            ))}
          </div>
        </section>
      ))}
    </article>
  );
}

// One capture, large: the shot, what to steal, why it suits arxa.
function ShotCanvas({ context, a: artifact, translate }: { context: Ctx; a: ShotArtifact; translate: TFn }) {
  const reference = artifact.reference ?? {};
  const shot = artifact.shot ?? {};
  return (
    <article class="artifact shot-artifact">
      <header class="artifact-head">
        <Label name="intake-moodboard:shot-eyebrow" class="eyebrow">{artifact.board?.title}</Label>
        <GradeChip g={reference.grade ?? ''} translate={translate} />
      </header>
      <Heading name="intake-moodboard:reference-name" level={2} class="display">{reference.name}</Heading>
      <p class="artifact-detail muted"><artifact href={reference.url} rel="noreferrer" {...inspectAttrs('intake-moodboard:reference-url', { role: 'action', fn: 'navigate' })}>{reference.url}</artifact></p>
      <img class="shot-full" src={shot.src} alt={`${reference.name} — ${shot.caption}`} />
      <Txt name="intake-moodboard:shot-caption" class="artifact-detail muted">{shot.caption}</Txt>
      <Txt name="intake-moodboard:steal-label" class="fact-label">{translate('shotSteal') as string}</Txt>
      <Txt name="intake-moodboard:steal-detail" class="artifact-detail">{reference.steal}</Txt>
      <Txt name="intake-moodboard:why-label" class="fact-label">{translate('shotWhy') as string}</Txt>
      <Txt name="intake-moodboard:why-detail" class="artifact-detail">{reference.why}</Txt>
      <p class="artifact-foot">
        <artifact href={`${context.base}/artifact/${artifact.backRef}`} hx-get={`${context.base}/artifact/${artifact.backRef}`} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false" {...inspectAttrs('intake-moodboard:back', { role: 'action', fn: 'navigate' })}><Icon name="chevron-left" size={14} /> {translate('mood.back') as string}</artifact>
      </p>
    </article>
  );
}

function CanvasArtifact({ context, translate }: { context: Ctx; translate: TFn }) {
  const artifact = (context.artifact as Artifact) ?? {};
  if (artifact.kind === 'missing') return <SH.MissingArtifact context={context} a={artifact} />;
  if (artifact.kind === 'shot') return <ShotCanvas context={context} a={artifact as ShotArtifact} translate={translate} />;
  return <GalleryCanvas context={context} a={artifact as GalleryArtifact} translate={translate} />;
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

const MoodboardView: FC<ViewProps> = (context) => {
  const { translate } = context;
  return (
    <MainShellView
      title={translate('intake.moodboard.pageTitle') as string}
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

export default MoodboardView;
