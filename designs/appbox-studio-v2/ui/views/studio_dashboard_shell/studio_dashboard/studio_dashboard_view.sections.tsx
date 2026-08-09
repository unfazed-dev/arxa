// Role: shared section components for the dashboard surface — the
//   greeting/pairing head, the needs-you gates strip, the LIVE project grid,
//   the analytics trio, and the new-project wizard. Composed identically by
//   all three studio_dashboard_view.<factor>.tsx variants so each section's
//   markup lives once per section, not once per rung.
//   Sections that own an aria-labelledby/label-for id pair (GatesSection,
//   ProjectsSection, StatsSection, WizardSection) take a `rung` prop and
//   suffix the id with it. The rung CSS (assets/css/app.css .rung rules)
//   keeps all three rungs in the DOM at once — only display:none/block
//   toggles which one is visible — so a bare id shared across the tripled
//   copies would collide three times and the label/heading reference would
//   be ambiguous. Suffixing keeps every rung's aria-labelledby and
//   label[for] pointing at a real, unique target instead of stripping the
//   id and leaving two of three copies with a dangling reference.
// Requirements: Q-v2-3.
// Relationships: composed by studio_dashboard_view.tsx (unused directly —
//   the shell mount and its props are untouched) and by the three
//   studio_dashboard_view.<factor>.tsx variants, in the same order at every
//   rung.
// History: extracted from studio_dashboard_view.tsx to give the dashboard
//   surface the same DERIVED factor-variant structure as studio_startup.
//   Sibling file (not inlined in the root view) so the root can still
//   import the three variants without the variants importing back from the
//   root — see studio_dashboard_view.tsx History for the deviation note.
import type { FC } from 'hono/jsx';
import Icon from '../../../../runtime/icon.tsx';
import { CtaLink, inspectAttrs, Label, Heading, Txt } from '../../../widgets/common/studio_primitives/primitives.tsx';
import { Wrap } from '../../../common/modal.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

export type Rung = 'desktop' | 'tablet' | 'mobile';

export interface Gate {
  id: string;
  stage: string;
  waiting?: string;
  gate?: string;
  project?: string;
  summary?: string;
}

export interface ProjectCard {
  id: string;
  name: string;
  targets?: string[];
  stage: string;
  detail?: string;
  current?: boolean;
}

export interface StatBar {
  label: string;
  value: string | number;
  height: number;
}
export interface Stat {
  label: string;
  total: string | number;
  unit: string;
  bars: StatBar[];
}
export interface Stats {
  [key: string]: Stat;
}

export interface PairingModal {
  qr: string[];
  code?: string;
  expiresLabel?: string;
  fingerprint?: string;
}

export interface Wizard {
  prompt?: string;
  targets?: string[];
  note?: string;
}

export const STAT_KEYS = ['runs', 'stageTime', 'gateLatency'];

// Shape every studio_dashboard_view.<factor>.tsx variant takes — one prop
// bag, same fields at every rung, so the three variants stay drop-in
// interchangeable the way studio_startup's StartupProps is.
export interface DashboardSurfaceProps {
  t: TFn;
  accountName?: string;
  gateCount: number;
  projectCount: number;
  pairingModal: PairingModal;
  gates: Gate[];
  projects: ProjectCard[];
  stats: Stats;
  wizard: Wizard;
}

export interface GreetingHeadProps {
  t: TFn;
  accountName?: string;
  gateCount: number;
  projectCount: number;
  pairingModal: PairingModal;
}

export const GreetingHead: FC<GreetingHeadProps> = ({ t, accountName, gateCount, projectCount, pairingModal }) => (
  <>
    <Label name="app-dashboard:eyebrow" class="eyebrow">{t('dash.eyebrow') as string}</Label>
    <div class="dash-head">
      <div>
        <Heading name="app-dashboard:greeting" level={1} class="display">{t('dash.greeting', { name: accountName }) as string}</Heading>
        <Txt name="app-dashboard:greeting-sub" class="muted">
          {t('dash.gatesNeedYou', { count: gateCount }) as string} ·{' '}
          {t('dash.projectsTailnet', { count: projectCount }) as string}
        </Txt>
      </div>
      {/* Pair-a-device entry point — declarative modal: pure <details>, no JS. */}
      <Wrap
        trigger={t('pair.title') as string}
        closeLabel={t('pair.closeLabel') as string}
        cardClass="pair-modal"
        t={t}
      >
        <Heading name="app-dashboard:pair-title" level={2}>{t('pair.title') as string}</Heading>
        <Txt name="app-dashboard:pair-lede" class="muted">{t('pair.lede') as string}</Txt>
        <div
          class="qr"
          role="img"
          aria-label={t('pair.qrAria') as string}
          style={`--qr-n: ${pairingModal.qr.length}`}
          {...inspectAttrs('app-dashboard:qr', { role: 'group' })}
        >
          {pairingModal.qr.map((row: string, ri: number) => [...row].map((cell, ci) => (
            <span key={`${ri}-${ci}`} class={`qr-c${cell === '1' ? ' on' : ''}`}></span>
          )))}
        </div>
        <p class="pair-code"><code {...inspectAttrs('app-dashboard:pair-code', { role: 'text' })}>{pairingModal.code}</code></p>
        <p class="pair-expiry"><Icon name="timer" size={14} /><Label name="app-dashboard:pair-expiry">{pairingModal.expiresLabel}</Label></p>
        <p class="pair-fingerprint muted"><code {...inspectAttrs('app-dashboard:pair-fingerprint', { role: 'text' })}>{pairingModal.fingerprint}</code></p>
      </Wrap>
    </div>
  </>
);

export interface GatesSectionProps {
  t: TFn;
  gates: Gate[];
  rung: Rung;
}

export const GatesSection: FC<GatesSectionProps> = ({ t, gates, rung }) => {
  const headingId = `needs-h--${rung}`;
  return (
    /* Needs-you strip — pending human gates, quick actions seeded. */
    <section class="dash-section" aria-labelledby={headingId}>
      <Heading name="app-dashboard:needs-h" level={2} id={headingId}>{t('dash.needsYouH') as string}</Heading>
      {gates.length ? (
        <div class="gates-strip" role="list" {...inspectAttrs('app-dashboard:gates-strip', { role: 'group' })}>
          {gates.map((g) => (
            <article class="gate-card" role="listitem" key={g.id}>
              <div class="gate-card-head">
                <Label name="app-dashboard:gate-stage" class={`chip gate-stage gate-stage-${g.stage}`}>
                  {t(`stage.name.${g.stage}`) as string}
                </Label>
                <Label name="app-dashboard:gate-waiting" class="gate-waiting">{g.waiting}</Label>
              </div>
              <Heading name="app-dashboard:gate-name" level={3}>{g.gate}</Heading>
              <Txt name="app-dashboard:gate-project" class="gate-project">{g.project}</Txt>
              <Txt name="app-dashboard:gate-summary" class="gate-summary muted">{g.summary}</Txt>
              <form class="gate-actions" method="post" action="/dashboard/gates/decide">
                <input type="hidden" name="gate" value={g.id} {...inspectAttrs('app-dashboard:gate-input', { role: 'input' })} />
                <button type="submit" name="decision" value="approve" {...inspectAttrs('app-dashboard:gate-approve', { role: 'action' })}>
                  <Icon name="check" size={16} />{t('action.approve') as string}
                </button>
                <button type="submit" name="decision" value="reject" class="ghost" {...inspectAttrs('app-dashboard:gate-reject', { role: 'action' })}>
                  <Icon name="x" size={16} />{t('action.reject') as string}
                </button>
              </form>
            </article>
          ))}
        </div>
      ) : (
        <Txt name="app-dashboard:gates-empty" class="dash-empty muted">{t('dash.gatesEmpty') as string}</Txt>
      )}
    </section>
  );
};

export interface ProjectsSectionProps {
  t: TFn;
  projects: ProjectCard[];
  rung: Rung;
}

export const ProjectsSection: FC<ProjectsSectionProps> = ({ t, projects, rung }) => {
  const headingId = `proj-h--${rung}`;
  return (
    /* Project grid — LIVE: one card per real project in ~/.appbox/projects. */
    <section class="dash-section" aria-labelledby={headingId}>
      <Heading name="app-dashboard:proj-h" level={2} id={headingId}>{t('dash.projectsH') as string}</Heading>
      {projects.length ? (
        <div class="proj-grid" {...inspectAttrs('app-dashboard:proj-grid', { role: 'group' })}>
          {projects.map((p) => (
            <article class={`proj-card${p.current ? ' is-current' : ''}`} key={p.id}>
              <div class="proj-card-head">
                <Heading name="app-dashboard:proj-name" level={3}>{p.name}</Heading>
                <Label name="app-dashboard:proj-stage" class={`chip proj-stage proj-stage-${p.stage}`}>
                  {t(`dash.stage.${p.stage}`) as string}
                </Label>
              </div>
              <Txt name="app-dashboard:proj-targets" class="proj-targets">
                {(p.targets ?? []).map((tgt) => (
                  <Label name="app-dashboard:proj-target" class="chip chip--muted" key={tgt}>{tgt}</Label>
                ))}
                {p.current && <Label name="app-dashboard:proj-current" class="chip proj-current">{t('dash.current') as string}</Label>}
              </Txt>
              <div class="proj-card-foot">
                <Label name="app-dashboard:proj-saved" class="proj-saved muted">{p.detail}</Label>
                {!p.current && (
                  <form method="post" action="/dashboard/projects/use">
                    <input type="hidden" name="project" value={p.id} {...inspectAttrs('app-dashboard:proj-use-input', { role: 'input' })} />
                    <button type="submit" class="ghost" {...inspectAttrs('app-dashboard:proj-use', { role: 'action' })}>{t('dash.useProject') as string}</button>
                  </form>
                )}
                <CtaLink href="/intake" label={t('dash.open') as string} size={16} />
              </div>
            </article>
          ))}
        </div>
      ) : (
        <Txt name="app-dashboard:projects-empty" class="dash-empty muted">{t('dash.projectsEmpty') as string}</Txt>
      )}
    </section>
  );
};

export interface StatsSectionProps {
  t: TFn;
  stats: Stats;
  rung: Rung;
}

export const StatsSection: FC<StatsSectionProps> = ({ t, stats, rung }) => {
  const headingId = `stats-h--${rung}`;
  return (
    /* Analytics trio — CSS bar charts, no JS. */
    <section class="dash-section" aria-labelledby={headingId}>
      <Heading name="app-dashboard:stats-h" level={2} id={headingId}>{t('dash.thisWeek') as string}</Heading>
      <div class="stat-trio" {...inspectAttrs('app-dashboard:stat-trio', { role: 'group' })}>
        {STAT_KEYS.map((key) => {
          const s = stats[key];
          if (!s) return null;
          const barsAria = s.bars.map((b) => `${b.label} ${b.value}`).join(', ');
          return (
            <article class="stat-card" key={key}>
              <Txt name="app-dashboard:stat-label" class="stat-label muted">{s.label}</Txt>
              <Txt name="app-dashboard:stat-total" class="stat-total">{s.total} <Label name="app-dashboard:stat-unit" class="stat-unit">{s.unit}</Label></Txt>
              <div class="bars" role="img" aria-label={`${s.label}: ${barsAria}`} {...inspectAttrs('app-dashboard:bars', { role: 'group' })}>
                {s.bars.map((b, bi) => (
                  <span
                    key={bi}
                    class="bar"
                    style={`--h: ${b.height}%`}
                    title={`${b.label}: ${b.value}`}
                  ></span>
                ))}
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
};

export interface WizardSectionProps {
  t: TFn;
  wizard: Wizard;
  rung: Rung;
}

export const WizardSection: FC<WizardSectionProps> = ({ t, wizard, rung }) => {
  const headingId = `wizard-h--${rung}`;
  const nameInputId = `wizard-name--${rung}`;
  return (
    /* New project — a GenUI wizard in chat style. */
    <section class="dash-section" aria-labelledby={headingId}>
      <Heading name="app-dashboard:wizard-h" level={2} id={headingId}>{t('action.newProject') as string}</Heading>
      <div class="wizard">
        <Txt name="app-dashboard:wizard-agent" class="wizard-agent">{wizard.prompt}</Txt>
        <form class="wizard-form" method="post" action="/dashboard/projects">
          <label class="auth-label" for={nameInputId} {...inspectAttrs('app-dashboard:wizard-name-label', { role: 'label' })}>{t('wizard.nameLabel') as string}</label>
          <input
            id={nameInputId}
            type="text"
            name="name"
            placeholder={t('wizard.namePlaceholder') as string}
            autocomplete="off"
            {...inspectAttrs('app-dashboard:wizard-name-input', { role: 'input' })}
          />
          <fieldset class="wizard-targets">
            <legend class="auth-label" {...inspectAttrs('app-dashboard:wizard-targets-label', { role: 'label' })}>{t('wizard.targets') as string}</legend>
            {(wizard.targets ?? []).map((tgt) => (
              <label class="wizard-chip" key={tgt}>
                <input type="checkbox" name="targets" value={tgt} checked={tgt === 'web'} {...inspectAttrs('app-dashboard:wizard-target-input', { role: 'input' })} />
                <Label name="app-dashboard:wizard-target" class="chip chip--lg chip--muted">{tgt}</Label>
              </label>
            ))}
          </fieldset>
          <div class="wizard-foot">
            <Txt name="app-dashboard:wizard-note" class="wizard-note muted">{wizard.note}</Txt>
            <button type="submit" {...inspectAttrs('app-dashboard:wizard-create', { role: 'action' })}><Icon name="plus" size={16} />{t('wizard.create') as string}</button>
          </div>
        </form>
      </div>
    </section>
  );
};
