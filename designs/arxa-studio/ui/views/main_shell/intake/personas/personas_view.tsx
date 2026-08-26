// personas_view.tsx — the personas intake step (replaces personas_view.html).
// Default export PersonasView: wraps MainShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in personas_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../shared.tsx';
import type { Ctx, Step } from '../shared.tsx';
import Icon from '../../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// --- personas artifact shapes ---
interface PersonaItem {
  id?: string;
  state?: string;
  name?: string;
  role?: string;
  proficiency?: string;
  provenance?: string;
  edited?: boolean;
  accessibility?: string;
  goals?: string[];
  frustrations?: string[];
  contexts?: string[];
}

// One labelled persona list (goals / frustrations / contexts).
function PersonaList({ iconName, label, entries, translate }: { iconName: string; label: string; entries?: string[]; translate: TFn }) {
  if (!entries || entries.length === 0) return null;
  return (
    <section class="persona-list">
      <h3 class="fact-label" {...inspectAttrs('intake-personas:list-label', { role: 'heading' })}><Icon name={iconName} size={14} /> {label}</h3>
      <ul class="trace-list" {...inspectAttrs('intake-personas:trace-list', { role: 'list' })}>
        {entries.map((entry, index) => <li key={index} {...inspectAttrs('intake-personas:trace-entry', { role: 'list row' })}>{entry}</li>)}
      </ul>
    </section>
  );
}

// The current persona, large: provenance, name, role, proficiency, the three
// lists — the prefill to confirm or correct.
function PersonaCard({ context, item, translate }: { context: Ctx; item: PersonaItem; translate: TFn }) {
  return (
    <article class={`artifact persona-card is-${item.state}`}>
      <header class="artifact-head">
        <SH.ProvChip p={item.provenance} translate={translate} />
        <span class="chip chip--muted" {...inspectAttrs('intake-personas:proficiency', { role: 'label' })}><Icon name="user" size={14} /> {translate('intake.personas.proficiency') as string}: {translate(`intake.personas.prof.${item.proficiency}`) as string}</span>
        {item.edited && <span class="chip chip--muted" {...inspectAttrs('intake-personas:card-edited', { role: 'label' })}>{translate('intake.item.edited') as string}</span>}
      </header>
      <Heading name="intake-personas:name" level={2} class="display">{item.name}</Heading>
      <Txt name="intake-personas:role" class="artifact-lede">{item.role}</Txt>
      {item.accessibility && (
        <p class="persona-a11y"><span class="fact-label" {...inspectAttrs('intake-personas:a11y-label', { role: 'label' })}><Icon name="accessibility" size={14} /> {translate('intake.personas.accessibility') as string}</span> {item.accessibility}</p>
      )}
      <PersonaList iconName="target" label={translate('intake.personas.goals') as string} entries={item.goals} translate={translate} />
      <PersonaList iconName="circle-alert" label={translate('intake.personas.frustrations') as string} entries={item.frustrations} translate={translate} />
      <PersonaList iconName="map-pin" label={translate('intake.personas.contexts') as string} entries={item.contexts} translate={translate} />
    </article>
  );
}

// The correction form: same fields as the card, one-per-line textareas; saving
// confirms the item with the corrected fields.
function CorrectionForm({ context, item, translate }: { context: Ctx; item: PersonaItem; translate: TFn }) {
  return (
    <form class="persona-form" method="post" action={`${context.base}/save`} hx-post={`${context.base}/save`} hx-target="#panels" hx-swap="outerMorph">
      <input type="hidden" name="item" value={item.id} {...inspectAttrs('intake-personas:item-id', { role: 'input' })} />
      <label class="fact-label" for="pf-name" {...inspectAttrs('intake-personas:field-name-label', { role: 'label' })}>{translate('intake.form.name') as string}</label>
      <input type="text" id="pf-name" name="name" value={item.name} {...inspectAttrs('intake-personas:field-name', { role: 'input' })} />
      <label class="fact-label" for="pf-role" {...inspectAttrs('intake-personas:field-role-label', { role: 'label' })}>{translate('intake.form.role') as string}</label>
      <input type="text" id="pf-role" name="role" value={item.role} {...inspectAttrs('intake-personas:field-role', { role: 'input' })} />
      <label class="fact-label" for="pf-goals" {...inspectAttrs('intake-personas:field-goals-label', { role: 'label' })}>{translate('intake.form.goals') as string}</label>
      <textarea id="pf-goals" name="goals" rows={item.goals?.length || 2} {...inspectAttrs('intake-personas:field-goals', { role: 'input' })}>{(item.goals ?? []).join('\n')}</textarea>
      <label class="fact-label" for="pf-frustrations" {...inspectAttrs('intake-personas:field-frustrations-label', { role: 'label' })}>{translate('intake.form.frustrations') as string}</label>
      <textarea id="pf-frustrations" name="frustrations" rows={item.frustrations?.length || 2} {...inspectAttrs('intake-personas:field-frustrations', { role: 'input' })}>{(item.frustrations ?? []).join('\n')}</textarea>
      <label class="fact-label" for="pf-contexts" {...inspectAttrs('intake-personas:field-contexts-label', { role: 'label' })}>{translate('intake.form.contexts') as string}</label>
      <textarea id="pf-contexts" name="contexts" rows={item.contexts?.length || 2} {...inspectAttrs('intake-personas:field-contexts', { role: 'input' })}>{(item.contexts ?? []).join('\n')}</textarea>
      <button type="submit" class="cta-main" {...inspectAttrs('intake-personas:save', { role: 'action', fn: 'submit' })}>{translate('intake.form.save') as string} <Icon name="check" size={14} /></button>
    </form>
  );
}

// The closed step: every persona compact, re-openable via itemActions.
function PersonasSummary({ context, translate }: { context: Ctx; translate: TFn }) {
  const step = (context.step as Step) ?? {};
  return (
    <div class="step-summary">
      <Heading name="intake-personas:summary-title" level={2} class="display">{translate('intake.step.allConfirmed', { total: step.total }) as string}</Heading>
      {(step.items ?? []).map((item, index) => {
        const persona = item as unknown as PersonaItem;
        return (
          <div key={index} class={`q-card is-${persona.state}`}>
            <p class="q-text" {...inspectAttrs('intake-personas:summary-card-text', { role: 'text' })}>{persona.name} <Label name="intake-personas:summary-card-role" class="muted">— {persona.role}</Label> {persona.edited && <span class="chip chip--muted" {...inspectAttrs('intake-personas:summary-card-edited', { role: 'label' })}>{translate('intake.item.edited') as string}</span>}</p>
            <p class="q-answer">
              <SH.ProvChip p={persona.provenance} translate={translate} />
              <span class="chip chip--muted" {...inspectAttrs('intake-personas:summary-card-goals', { role: 'label' })}><Icon name="target" size={14} /> {(persona.goals ?? []).length} {translate('intake.personas.goals') as string}</span>
            </p>
            <SH.ItemActions context={context} item={item} translate={translate} />
          </div>
        );
      })}
    </div>
  );
}

// The main panel's content: the open file, else the step stage.
function MainContent({ context, translate }: { context: Ctx; translate: TFn }) {
  if (context.fileView) return <SH.FileView context={context} translate={translate} />;
  const step = (context.step as Step) ?? {};
  return (
    <SH.StepStage context={context} translate={translate}>
      {step.complete ? (
        <PersonasSummary context={context} translate={translate} />
      ) : (
        (step.items ?? []).map((item, index) => {
          const persona = item as unknown as PersonaItem;
          if (persona.state === 'current' || persona.state === 'editing') {
            return (
              <Fragment key={String(index)}>
                <PersonaCard context={context} item={persona} translate={translate} />
                {persona.state === 'editing' && <CorrectionForm context={context} item={persona} translate={translate} />}
                <SH.ItemActions context={context} item={item} translate={translate} />
              </Fragment>
            );
          }
          return null;
        })
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

const PersonasView: FC<ViewProps> = (context) => {
  const { translate } = context;
  return (
    <MainShellView
      title={translate('intake.personas.pageTitle') as string}
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

export default PersonasView;
