// dashboard_view.tsx — the studio home (replaces dashboard_view.html).
// Extends main_shell_view: mounts the main panel and fills it with the
// needs-you strip (gates), the LIVE project grid (~/.appbox/projects), an
// analytics trio, and a new-project wizard. shell-main-col hands the
// region height to the panel so .mp-content is the scroller.
import type { FC } from 'hono/jsx';
import MainShellView from '../../main_shell/main_shell_view.tsx';
import Icon from '../../../../runtime/icon.tsx';
import { CtaLink, inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';
import { Open } from '../../../common/widgets/main_panel.tsx';
import { Wrap } from '../../../common/modal.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Gate {
  id: string;
  stage: string;
  waiting?: string;
  gate?: string;
  project?: string;
  summary?: string;
}

interface ProjectCard {
  id: string;
  name: string;
  targets?: string[];
  stage: string;
  detail?: string;
  current?: boolean;
}

interface StatBar {
  label: string;
  value: string | number;
  height: number;
}
interface Stat {
  label: string;
  total: string | number;
  unit: string;
  bars: StatBar[];
}
interface Stats {
  [key: string]: Stat;
}

interface PairingModal {
  qr: string[];
  code?: string;
  expiresLabel?: string;
  fingerprint?: string;
}

interface Wizard {
  prompt?: string;
  targets?: string[];
  note?: string;
}

interface Prefs {
  accent?: string;
  theme?: string;
  [key: string]: unknown;
}

interface DashboardViewProps {
  t: TFn;
  locale?: string;
  activeShell: string;
  prefs?: Prefs;
  account?: { name?: string; email?: string;[key: string]: unknown };
  gates?: Gate[];
  gateCount?: number;
  projects?: ProjectCard[];
  stats?: Stats;
  pairingModal?: PairingModal;
  wizard?: Wizard;
  project?: { name?: string; savedLabel?: string;[key: string]: unknown };
  [key: string]: unknown;
}

const STAT_KEYS = ['runs', 'stageTime', 'gateLatency'];

const DashboardView: FC<DashboardViewProps> = (props) => {
  const {
    t,
    locale,
    activeShell,
    prefs,
    account = {},
    gates = [],
    gateCount = 0,
    projects = [],
    stats = {},
    pairingModal = { qr: [] },
    wizard = {},
    project,
  } = props;

  return (
    <MainShellView
      t={t}
      title={t('dash.pageTitle') as string}
      locale={locale}
      activeShell={activeShell}
      prefs={prefs}
      project={project}
      mainClass="shell-main-col"
      surface={
        <Open>
          <section class="mp-content">

            <Label name="app-dashboard:eyebrow" class="eyebrow">{t('dash.eyebrow') as string}</Label>
            <div class="dash-head">
              <div>
                <Heading name="app-dashboard:greeting" level={1} class="display">{t('dash.greeting', { name: account.name }) as string}</Heading>
                <Txt name="app-dashboard:greeting-sub" class="muted">
                  {t('dash.gatesNeedYou', { count: gateCount }) as string} ·{' '}
                  {t('dash.projectsTailnet', { count: projects.length }) as string}
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

            {/* Needs-you strip — pending human gates, quick actions seeded. */}
            <section class="dash-section" aria-labelledby="needs-h">
              <Heading name="app-dashboard:needs-h" level={2} id="needs-h">{t('dash.needsYouH') as string}</Heading>
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

            {/* Project grid — LIVE: one card per real project in ~/.appbox/projects. */}
            <section class="dash-section" aria-labelledby="proj-h">
              <Heading name="app-dashboard:proj-h" level={2} id="proj-h">{t('dash.projectsH') as string}</Heading>
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

            {/* Analytics trio — CSS bar charts, no JS. */}
            <section class="dash-section" aria-labelledby="stats-h">
              <Heading name="app-dashboard:stats-h" level={2} id="stats-h">{t('dash.thisWeek') as string}</Heading>
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

            {/* New project — a GenUI wizard in chat style. */}
            <section class="dash-section" aria-labelledby="wizard-h">
              <Heading name="app-dashboard:wizard-h" level={2} id="wizard-h">{t('action.newProject') as string}</Heading>
              <div class="wizard">
                <Txt name="app-dashboard:wizard-agent" class="wizard-agent">{wizard.prompt}</Txt>
                <form class="wizard-form" method="post" action="/dashboard/projects">
                  <label class="auth-label" for="wizard-name" {...inspectAttrs('app-dashboard:wizard-name-label', { role: 'label' })}>{t('wizard.nameLabel') as string}</label>
                  <input
                    id="wizard-name"
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

          </section>
        </Open>
      }
    />
  );
};

export default DashboardView;
