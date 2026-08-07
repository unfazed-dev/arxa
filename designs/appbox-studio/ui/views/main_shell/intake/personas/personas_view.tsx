// personas_view.tsx — the personas intake step (replaces personas_view.html).
// Default export PersonasView: wraps MainShellView → Base. Named fragment
// exports (PanelsSwap / ActivitySwap / FileSwap / ActivityFrameSwap) dispatch
// the htmx fragment routes registered in personas_viewmodel.js.
import { Fragment, type FC } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import * as SH from '../_shared.tsx';
import type { Ctx, Step } from '../_shared.tsx';
import Icon from '../../../../../runtime/icon.tsx';

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
      <h3 class="fact-label"><Icon name={iconName} size={14} /> {label}</h3>
      <ul class="trace-list">
        {entries.map((e, i) => <li key={i}>{e}</li>)}
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
        <span class="chip chip--muted"><Icon name="user" size={14} /> {t('intake.personas.proficiency') as string}: {t(`intake.personas.prof.${item.proficiency}`) as string}</span>
        {item.edited && <span class="chip chip--muted">{t('intake.item.edited') as string}</span>}
      </header>
      <h2 class="display">{item.name}</h2>
      <p class="artifact-lede">{item.role}</p>
      {item.accessibility && (
        <p class="persona-a11y"><span class="fact-label"><Icon name="accessibility" size={14} /> {t('intake.personas.accessibility') as string}</span> {item.accessibility}</p>
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
      <input type="hidden" name="item" value={item.id} />
      <label class="fact-label" for="pf-name">{t('intake.form.name') as string}</label>
      <input type="text" id="pf-name" name="name" value={item.name} />
      <label class="fact-label" for="pf-role">{t('intake.form.role') as string}</label>
      <input type="text" id="pf-role" name="role" value={item.role} />
      <label class="fact-label" for="pf-goals">{t('intake.form.goals') as string}</label>
      <textarea id="pf-goals" name="goals" rows={item.goals?.length || 2}>{(item.goals ?? []).join('\n')}</textarea>
      <label class="fact-label" for="pf-frustrations">{t('intake.form.frustrations') as string}</label>
      <textarea id="pf-frustrations" name="frustrations" rows={item.frustrations?.length || 2}>{(item.frustrations ?? []).join('\n')}</textarea>
      <label class="fact-label" for="pf-contexts">{t('intake.form.contexts') as string}</label>
      <textarea id="pf-contexts" name="contexts" rows={item.contexts?.length || 2}>{(item.contexts ?? []).join('\n')}</textarea>
      <button type="submit" class="cta-main">{t('intake.form.save') as string} <Icon name="check" size={14} /></button>
    </form>
  );
}

// The closed step: every persona compact, re-openable via itemActions.
function PersonasSummary({ c, t }: { c: Ctx; t: TFn }) {
  const step = (c.step as Step) ?? {};
  return (
    <div class="step-summary">
      <h2 class="display">{t('intake.step.allConfirmed', { total: step.total }) as string}</h2>
      {(step.items ?? []).map((item, i) => {
        const persona = item as unknown as PersonaItem;
        return (
          <div key={i} class={`q-card is-${persona.state}`}>
            <p class="q-text">{persona.name} <span class="muted">— {persona.role}</span> {persona.edited && <span class="chip chip--muted">{t('intake.item.edited') as string}</span>}</p>
            <p class="q-answer">
              <SH.ProvChip p={persona.provenance} t={t} />
              <span class="chip chip--muted"><Icon name="target" size={14} /> {(persona.goals ?? []).length} {t('intake.personas.goals') as string}</span>
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
