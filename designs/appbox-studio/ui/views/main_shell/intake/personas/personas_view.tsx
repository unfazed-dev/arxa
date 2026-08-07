// personas_view.tsx — the personas intake step (replaces personas_view.html).
// Default export PersonasView: wraps MainShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in personas_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx, Step } from '../_shared.tsx';
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
function PersonaList({ iconName, label, entries, t }: { iconName: string; label: string; entries?: string[]; t: TFn }) {
  if (!entries || entries.length === 0) return null;
  return (
    <section class="persona-list">
      <h3 class="fact-label" {...inspectAttrs('intake-personas:list-label', { role: 'heading' })}><Icon name={iconName} size={14} /> {label}</h3>
      <ul class="trace-list" {...inspectAttrs('intake-personas:trace-list', { role: 'list' })}>
        {entries.map((e, i) => <li key={i} {...inspectAttrs('intake-personas:trace-entry', { role: 'list row' })}>{e}</li>)}
      </ul>
    </section>
  );
}

// The current persona, large: provenance, name, role, proficiency, the three
// lists — the prefill to confirm or correct.
function PersonaCard({ c, item, t }: { c: Ctx; item: PersonaItem; t: TFn }) {
  return (
    <article class={`artifact persona-card is-${item.state}`}>
      <header class="artifact-head">
        <SH.ProvChip p={item.provenance} t={t} />
        <span class="chip chip--muted" {...inspectAttrs('intake-personas:proficiency', { role: 'label' })}><Icon name="user" size={14} /> {t('intake.personas.proficiency') as string}: {t(`intake.personas.prof.${item.proficiency}`) as string}</span>
        {item.edited && <span class="chip chip--muted" {...inspectAttrs('intake-personas:card-edited', { role: 'label' })}>{t('intake.item.edited') as string}</span>}
      </header>
      <Heading name="intake-personas:name" level={2} class="display">{item.name}</Heading>
      <Txt name="intake-personas:role" class="artifact-lede">{item.role}</Txt>
      {item.accessibility && (
        <p class="persona-a11y"><span class="fact-label" {...inspectAttrs('intake-personas:a11y-label', { role: 'label' })}><Icon name="accessibility" size={14} /> {t('intake.personas.accessibility') as string}</span> {item.accessibility}</p>
      )}
      <PersonaList iconName="target" label={t('intake.personas.goals') as string} entries={item.goals} t={t} />
      <PersonaList iconName="circle-alert" label={t('intake.personas.frustrations') as string} entries={item.frustrations} t={t} />
      <PersonaList iconName="map-pin" label={t('intake.personas.contexts') as string} entries={item.contexts} t={t} />
    </article>
  );
}

// The correction form: same fields as the card, one-per-line textareas; saving
// confirms the item with the corrected fields.
function CorrectionForm({ c, item, t }: { c: Ctx; item: PersonaItem; t: TFn }) {
  return (
    <form class="persona-form" method="post" action={`${c.base}/save`} hx-post={`${c.base}/save`} hx-target="#panels" hx-swap="outerMorph">
      <input type="hidden" name="item" value={item.id} {...inspectAttrs('intake-personas:item-id', { role: 'input' })} />
      <label class="fact-label" for="pf-name" {...inspectAttrs('intake-personas:field-name-label', { role: 'label' })}>{t('intake.form.name') as string}</label>
      <input type="text" id="pf-name" name="name" value={item.name} {...inspectAttrs('intake-personas:field-name', { role: 'input' })} />
      <label class="fact-label" for="pf-role" {...inspectAttrs('intake-personas:field-role-label', { role: 'label' })}>{t('intake.form.role') as string}</label>
      <input type="text" id="pf-role" name="role" value={item.role} {...inspectAttrs('intake-personas:field-role', { role: 'input' })} />
      <label class="fact-label" for="pf-goals" {...inspectAttrs('intake-personas:field-goals-label', { role: 'label' })}>{t('intake.form.goals') as string}</label>
      <textarea id="pf-goals" name="goals" rows={item.goals?.length || 2} {...inspectAttrs('intake-personas:field-goals', { role: 'input' })}>{(item.goals ?? []).join('\n')}</textarea>
      <label class="fact-label" for="pf-frustrations" {...inspectAttrs('intake-personas:field-frustrations-label', { role: 'label' })}>{t('intake.form.frustrations') as string}</label>
      <textarea id="pf-frustrations" name="frustrations" rows={item.frustrations?.length || 2} {...inspectAttrs('intake-personas:field-frustrations', { role: 'input' })}>{(item.frustrations ?? []).join('\n')}</textarea>
      <label class="fact-label" for="pf-contexts" {...inspectAttrs('intake-personas:field-contexts-label', { role: 'label' })}>{t('intake.form.contexts') as string}</label>
      <textarea id="pf-contexts" name="contexts" rows={item.contexts?.length || 2} {...inspectAttrs('intake-personas:field-contexts', { role: 'input' })}>{(item.contexts ?? []).join('\n')}</textarea>
      <button type="submit" class="cta-main" {...inspectAttrs('intake-personas:save', { role: 'action', fn: 'submit' })}>{t('intake.form.save') as string} <Icon name="check" size={14} /></button>
    </form>
  );
}

// The closed step: every persona compact, re-openable via itemActions.
function PersonasSummary({ c, t }: { c: Ctx; t: TFn }) {
  const step = (c.step as Step) ?? {};
  return (
    <div class="step-summary">
      <Heading name="intake-personas:summary-title" level={2} class="display">{t('intake.step.allConfirmed', { total: step.total }) as string}</Heading>
      {(step.items ?? []).map((item, i) => {
        const persona = item as unknown as PersonaItem;
        return (
          <div key={i} class={`q-card is-${persona.state}`}>
            <p class="q-text" {...inspectAttrs('intake-personas:summary-card-text', { role: 'text' })}>{persona.name} <Label name="intake-personas:summary-card-role" class="muted">— {persona.role}</Label> {persona.edited && <span class="chip chip--muted" {...inspectAttrs('intake-personas:summary-card-edited', { role: 'label' })}>{t('intake.item.edited') as string}</span>}</p>
            <p class="q-answer">
              <SH.ProvChip p={persona.provenance} t={t} />
              <span class="chip chip--muted" {...inspectAttrs('intake-personas:summary-card-goals', { role: 'label' })}><Icon name="target" size={14} /> {(persona.goals ?? []).length} {t('intake.personas.goals') as string}</span>
            </p>
            <SH.ItemActions c={c} item={item} t={t} />
          </div>
        );
      })}
    </div>
  );
}

// The main panel's content: the open file, else the step stage.
function MainContent({ c, t }: { c: Ctx; t: TFn }) {
  if (c.fileView) return <SH.FileView c={c} t={t} />;
  const step = (c.step as Step) ?? {};
  return (
    <SH.StepStage c={c} t={t}>
      {step.complete ? (
        <PersonasSummary c={c} t={t} />
      ) : (
        (step.items ?? []).map((item, i) => {
          const persona = item as unknown as PersonaItem;
          if (persona.state === 'current' || persona.state === 'editing') {
            return (
              <Fragment key={String(i)}>
                <PersonaCard c={c} item={persona} t={t} />
                {persona.state === 'editing' && <CorrectionForm c={c} item={persona} t={t} />}
                <SH.ItemActions c={c} item={item} t={t} />
              </Fragment>
            );
          }
          return null;
        })
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

const PersonasView: FC<ViewProps> = (c) => {
  const { t } = c;
  return (
    <MainShellView
      title={t('intake.personas.pageTitle') as string}
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

export default PersonasView;
