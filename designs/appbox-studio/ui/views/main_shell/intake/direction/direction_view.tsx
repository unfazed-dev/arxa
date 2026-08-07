// direction_view.tsx — the direction intake step (replaces direction_view.html).
// Three groups (adjectives / avoids / references), one card per panel. Default
// export DirectionView: wraps MainShellView → Base. Named fragment exports
// dispatch the htmx routes registered in direction_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx, StepItem } from '../_shared.tsx';
import { inspectAttrs, Label } from '../../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// Prefill values as chips, each with its provenance; avoids carry the ban mark.
function ValueChips({ item, t }: { item: StepItem; t: TFn }) {
  return (
    <span class="value-chips" {...inspectAttrs('intake-direction:value-chips', { role: 'group' })}>
      {(item.values ?? []).map((v, i) => (
        <span key={i} class={`chip value-chip${item.id === 'avoids' ? ' avoid-chip' : ''}`} {...inspectAttrs('intake-direction:value-chip', { role: 'label' })}>
          {item.id === 'avoids' ? <Fragment><Icon name="ban" size={12} /> </Fragment> : null}
          {v.value} <SH.ProvChip p={v.provenance} t={t} />
        </span>
      ))}
    </span>
  );
}

// The references group: one row per moodboard pull.
function ReferenceRows({ item, t }: { item: StepItem; t: TFn }) {
  return (
    <div class="ref-list" {...inspectAttrs('intake-direction:ref-list', { role: 'group' })}>
      {(item.values ?? []).map((v, i) => (
        <div key={i} class="ref-row">
          <Label name="intake-direction:ref-board" class="chip chip--muted">{v.board}</Label>
          <Label name="intake-direction:ref-note" class="ref-note">{v.note}</Label>
          <a class="ref-link" href="/intake/moodboard" {...inspectAttrs('intake-direction:ref-link', { role: 'action', fn: 'navigate' })}>
            <Icon name="image" size={14} /> {t('intake.direction.fromBoard', { board: v.board }) as string}
          </a>
        </div>
      ))}
    </div>
  );
}

// The correction form (adjectives / avoids only): one value per line.
function ValuesForm({ c, item, t }: { c: Ctx; item: StepItem; t: TFn }) {
  return (
    <form class="values-form" method="post" action={`${c.base}/save`}
          hx-post={`${c.base}/save`} hx-target="#panels" hx-swap="outerMorph">
      <input type="hidden" name="item" value={item.id} {...inspectAttrs('intake-direction:form-item', { role: 'input' })} />
      <label class="fact-label" for={`values-${item.id}`} {...inspectAttrs('intake-direction:values-label', { role: 'label' })}>{t('intake.form.values') as string}</label>
      <textarea id={`values-${item.id}`} name="values" rows={6} {...inspectAttrs('intake-direction:values-input', { role: 'input' })}>{(item.values ?? []).map((v) => v.value ?? '').join('\n')}</textarea>
      <button type="submit" class="cta-main" {...inspectAttrs('intake-direction:save', { role: 'action', fn: 'submit' })}>{t('intake.form.save') as string} <Icon name="check" size={14} /></button>
    </form>
  );
}

// The current/editing group, large — the typeform's one thing per panel.
function GroupCard({ c, item, t }: { c: Ctx; item: StepItem; t: TFn }) {
  const icon = item.id === 'adjectives' ? 'sparkles' : item.id === 'avoids' ? 'ban' : 'image';
  return (
    <div class={`q-card group-card is-${item.state ?? ''}`}>
      <h2 class="display"><Icon name={icon} size={20} /> {t(`intake.direction.group.${item.id}`) as string}</h2>
      {item.id === 'references' ? <ReferenceRows item={item} t={t} /> : <ValueChips item={item} t={t} />}
      {item.state === 'editing' && item.id !== 'references' ? <ValuesForm c={c} item={item} t={t} /> : null}
      <SH.ItemActions c={c} item={item} t={t} />
    </div>
  );
}

// All confirmed: a compact summary of the three groups, each re-openable.
function StepSummary({ c, t }: { c: Ctx; t: TFn }) {
  const step = c.step;
  return (
    <div class="step-summary">
      <h2 class="display"><Icon name="compass" size={20} /> {t('intake.step.allConfirmed', { total: step?.total }) as string}</h2>
      {(step?.items ?? []).map((item) => (
        <div key={item.id} class={`q-card is-${item.state ?? ''}`}>
          <p class="q-text" {...inspectAttrs('intake-direction:summary-text', { role: 'text' })}>{t(`intake.direction.group.${item.id}`) as string} {item.edited ? <Label name="intake-direction:edited-mark" class="chip chip--muted">{t('intake.item.edited') as string}</Label> : null}</p>
          {item.id === 'references' ? (
            <span class="value-chips" {...inspectAttrs('intake-direction:summary-chips', { role: 'group' })}>{(item.values ?? []).map((v, i) => <Label name="intake-direction:summary-board" class="chip chip--muted" key={i}>{v.board}</Label>)}</span>
          ) : (
            <ValueChips item={item} t={t} />
          )}
          <SH.ItemActions c={c} item={item} t={t} />
        </div>
      ))}
    </div>
  );
}

// The main panel's content: the open file, else the direction stage.
function MainContent({ c, t }: { c: Ctx; t: TFn }) {
  if (c.fileView) return <SH.FileView c={c} t={t} />;
  return (
    <SH.StepStage c={c} t={t}>
      {c.step?.complete ? (
        <StepSummary c={c} t={t} />
      ) : (
        (c.step?.items ?? [])
          .filter((item) => item.state === 'current' || item.state === 'editing')
          .map((item) => <GroupCard key={item.id} c={c} item={item} t={t} />)
      )}
    </SH.StepStage>
  );
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

const DirectionView: FC<ViewProps> = (c) => {
  const { t } = c;
  return (
    <MainShellView
      title={t('intake.direction.pageTitle') as string}
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

export default DirectionView;
