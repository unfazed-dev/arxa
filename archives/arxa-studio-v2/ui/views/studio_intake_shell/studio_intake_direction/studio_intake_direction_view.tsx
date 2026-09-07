// direction_view.tsx — the direction intake step (replaces direction_view.html).
// Three groups (adjectives / avoids / references), one card per panel. Default
// export DirectionView: wraps StudioIntakeShellView → Base. Named fragment exports
// dispatch the htmx routes registered in direction_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import Icon from '../../../../runtime/icon.tsx';
import StudioIntakeShellView from '../studio_intake_shell_view.tsx';
import * as SH from '../shared.tsx';
import type { Ctx, StepItem } from '../shared.tsx';
import { inspectAttrs, Label } from '../../../widgets/common/studio_primitives/widgets.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// Prefill values as chips, each with its provenance; avoids carry the ban mark.
function ValueChips({ item, translate }: { item: StepItem; translate: TFn }) {
  return (
    <span class="value-chips" {...inspectAttrs('intake-direction:value-chips', { role: 'group' })}>
      {(item.values ?? []).map((value, index) => (
        <span key={index} class={`chip value-chip${item.id === 'avoids' ? ' avoid-chip' : ''}`} {...inspectAttrs('intake-direction:value-chip', { role: 'label' })}>
          {item.id === 'avoids' ? <Fragment><Icon name="ban" size={12} /> </Fragment> : null}
          {value.value} <SH.ProvChip p={value.provenance} translate={translate} />
        </span>
      ))}
    </span>
  );
}

// The references group: one row per moodboard pull.
function ReferenceRows({ item, translate }: { item: StepItem; translate: TFn }) {
  return (
    <div class="ref-list" {...inspectAttrs('intake-direction:ref-list', { role: 'group' })}>
      {(item.values ?? []).map((value, index) => (
        <div key={index} class="ref-row">
          <Label name="intake-direction:ref-board" class="chip chip--muted">{value.board}</Label>
          <Label name="intake-direction:ref-note" class="ref-note">{value.note}</Label>
          <a class="ref-link" href="/intake/moodboard" {...inspectAttrs('intake-direction:ref-link', { role: 'action', fn: 'navigate' })}>
            <Icon name="image" size={14} /> {translate('intake.direction.fromBoard', { board: value.board }) as string}
          </a>
        </div>
      ))}
    </div>
  );
}

// The correction form (adjectives / avoids only): one value per line.
function ValuesForm({ context, item, translate }: { context: Ctx; item: StepItem; translate: TFn }) {
  return (
    <form class="values-form" method="post" action={`${context.base}/save`}
          hx-post={`${context.base}/save`} hx-target="#panels" hx-swap="outerMorph">
      <input type="hidden" name="item" value={item.id} {...inspectAttrs('intake-direction:form-item', { role: 'input' })} />
      <label class="fact-label" for={`values-${item.id}`} {...inspectAttrs('intake-direction:values-label', { role: 'label' })}>{translate('intake.form.values') as string}</label>
      <textarea id={`values-${item.id}`} name="values" rows={6} {...inspectAttrs('intake-direction:values-input', { role: 'input' })}>{(item.values ?? []).map((value) => value.value ?? '').join('\n')}</textarea>
      <button type="submit" class="cta-main" {...inspectAttrs('intake-direction:save', { role: 'action', fn: 'submit' })}>{translate('intake.form.save') as string} <Icon name="check" size={14} /></button>
    </form>
  );
}

// The current/editing group, large — the typeform's one thing per panel.
function GroupCard({ context, item, translate }: { context: Ctx; item: StepItem; translate: TFn }) {
  const icon = item.id === 'adjectives' ? 'sparkles' : item.id === 'avoids' ? 'ban' : 'image';
  return (
    <div class={`q-card group-card is-${item.state ?? ''}`}>
      <h2 class="display" {...inspectAttrs('intake-direction:group-title', { role: 'heading' })}><Icon name={icon} size={20} /> {translate(`intake.direction.group.${item.id}`) as string}</h2>
      {item.id === 'references' ? <ReferenceRows item={item} translate={translate} /> : <ValueChips item={item} translate={translate} />}
      {item.state === 'editing' && item.id !== 'references' ? <ValuesForm context={context} item={item} translate={translate} /> : null}
      <SH.ItemActions context={context} item={item} translate={translate} />
    </div>
  );
}

// All confirmed: a compact summary of the three groups, each re-openable.
function StepSummary({ context, translate }: { context: Ctx; translate: TFn }) {
  const step = context.step;
  return (
    <div class="step-summary">
      <h2 class="display" {...inspectAttrs('intake-direction:summary-title', { role: 'heading' })}><Icon name="compass" size={20} /> {translate('intake.step.allConfirmed', { total: step?.total }) as string}</h2>
      {(step?.items ?? []).map((item) => (
        <div key={item.id} class={`q-card is-${item.state ?? ''}`}>
          <p class="q-text" {...inspectAttrs('intake-direction:summary-text', { role: 'text' })}>{translate(`intake.direction.group.${item.id}`) as string} {item.edited ? <Label name="intake-direction:edited-mark" class="chip chip--muted">{translate('intake.item.edited') as string}</Label> : null}</p>
          {item.id === 'references' ? (
            <span class="value-chips" {...inspectAttrs('intake-direction:summary-chips', { role: 'group' })}>{(item.values ?? []).map((value, index) => <Label name="intake-direction:summary-board" class="chip chip--muted" key={index}>{value.board}</Label>)}</span>
          ) : (
            <ValueChips item={item} translate={translate} />
          )}
          <SH.ItemActions context={context} item={item} translate={translate} />
        </div>
      ))}
    </div>
  );
}

// The main panel's content: the open file, else the direction stage.
function MainContent({ context, translate }: { context: Ctx; translate: TFn }) {
  if (context.fileView) return <SH.FileView context={context} translate={translate} />;
  return (
    <SH.StepStage context={context} translate={translate}>
      {context.step?.complete ? (
        <StepSummary context={context} translate={translate} />
      ) : (
        (context.step?.items ?? [])
          .filter((item) => item.state === 'current' || item.state === 'editing')
          .map((item) => <GroupCard key={item.id} context={context} item={item} translate={translate} />)
      )}
    </SH.StepStage>
  );
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

const DirectionView: FC<ViewProps> = (context) => {
  const { translate } = context;
  return (
    <StudioIntakeShellView
      title={translate('intake.direction.pageTitle') as string}
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

export default DirectionView;
