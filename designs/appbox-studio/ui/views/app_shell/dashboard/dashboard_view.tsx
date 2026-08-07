// dashboard_view.tsx — the studio home (replaces dashboard_view.html).
// Extends main_shell_view: mounts the main panel and fills it with the
// needs-you strip (gates), the LIVE project grid (~/.appbox/projects), an
// analytics trio, and a new-project wizard. shell-main-col hands the
// region height to the panel so .mp-content is the scroller.
import type { FC } from 'hono/jsx';
import MainShellView from '../../main_shell/main_shell_view.tsx';
import Icon from '../../../../runtime/icon.tsx';
import { CtaLink } from '../../../common/widgets/primitives.tsx';
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

            <span class="eyebrow">{t('dash.eyebrow') as string}</span>
            <div class="dash-head">
              <div>
                <h1 class="display">{t('dash.greeting', { name: account.name }) as string}</h1>
                <p class="muted">
                  {t('dash.gatesNeedYou', { count: gateCount }) as string} ·{' '}
                  {t('dash.projectsTailnet', { count: projects.length }) as string}
                </p>
              </div>
              {/* Pair-a-device entry point — declarative modal: pure <details>, no JS. */}
              <Wrap
                trigger={t('pair.title') as string}
                closeLabel={t('pair.closeLabel') as string}
                cardClass="pair-modal"
                t={t}
              >
                <h2>{t('pair.title') as string}</h2>
                <p class="muted">{t('pair.lede') as string}</p>
                <div
                  class="qr"
                  role="img"
                  aria-label={t('pair.qrAria') as string}
                  style={`--qr-n: ${pairingModal.qr.length}`}
                >
                  {pairingModal.qr.map((row: string, ri: number) => [...row].map((cell, ci) => (
                    <span key={`${ri}-${ci}`} class={`qr-c${cell === '1' ? ' on' : ''}`}></span>
                  )))}
                </div>
                <p class="pair-code"><code>{pairingModal.code}</code></p>
                <p class="pair-expiry"><Icon name="timer" size={14} /><span>{pairingModal.expiresLabel}</span></p>
                <p class="pair-fingerprint muted"><code>{pairingModal.fingerprint}</code></p>
              </Wrap>
            </div>

            {/* Needs-you strip — pending human gates, quick actions seeded. */}
            <section class="dash-section" aria-labelledby="needs-h">
              <h2 id="needs-h">{t('dash.needsYouH') as string}</h2>
              {gates.length ? (
                <div class="gates-strip" role="list">
                  {gates.map((g) => (
                    <article class="gate-card" role="listitem" key={g.id}>
                      <div class="gate-card-head">
                        <span class={`chip gate-stage gate-stage-${g.stage}`}>
                          {t(`stage.name.${g.stage}`) as string}
                        </span>
                        <span class="gate-waiting">{g.waiting}</span>
                      </div>
                      <h3>{g.gate}</h3>
                      <p class="gate-project">{g.project}</p>
                      <p class="gate-summary muted">{g.summary}</p>
                      <form class="gate-actions" method="post" action="/dashboard/gates/decide">
                        <input type="hidden" name="gate" value={g.id} />
                        <button type="submit" name="decision" value="approve">
                          <Icon name="check" size={16} />{t('action.approve') as string}
                        </button>
                        <button type="submit" name="decision" value="reject" class="ghost">
                          <Icon name="x" size={16} />{t('action.reject') as string}
                        </button>
                      </form>
                    </article>
                  ))}
                </div>
              ) : (
                <p class="dash-empty muted">{t('dash.gatesEmpty') as string}</p>
              )}
            </section>

            {/* Project grid — LIVE: one card per real project in ~/.appbox/projects. */}
            <section class="dash-section" aria-labelledby="proj-h">
              <h2 id="proj-h">{t('dash.projectsH') as string}</h2>
              {projects.length ? (
                <div class="proj-grid">
                  {projects.map((p) => (
                    <article class={`proj-card${p.current ? ' is-current' : ''}`} key={p.id}>
                      <div class="proj-card-head">
                        <h3>{p.name}</h3>
                        <span class={`chip proj-stage proj-stage-${p.stage}`}>
                          {t(`dash.stage.${p.stage}`) as string}
                        </span>
                      </div>
                      <p class="proj-targets">
                        {(p.targets ?? []).map((tgt) => (
                          <span class="chip chip--muted" key={tgt}>{tgt}</span>
                        ))}
                        {p.current && <span class="chip proj-current">{t('dash.current') as string}</span>}
                      </p>
                      <div class="proj-card-foot">
                        <span class="proj-saved muted">{p.detail}</span>
                        {!p.current && (
                          <form method="post" action="/dashboard/projects/use">
                            <input type="hidden" name="project" value={p.id} />
                            <button type="submit" class="ghost">{t('dash.useProject') as string}</button>
                          </form>
                        )}
                        <CtaLink href="/intake" label={t('dash.open') as string} size={16} />
                      </div>
                    </article>
                  ))}
                </div>
              ) : (
                <p class="dash-empty muted">{t('dash.projectsEmpty') as string}</p>
              )}
            </section>

            {/* Analytics trio — CSS bar charts, no JS. */}
            <section class="dash-section" aria-labelledby="stats-h">
              <h2 id="stats-h">{t('dash.thisWeek') as string}</h2>
              <div class="stat-trio">
                {STAT_KEYS.map((key) => {
                  const s = stats[key];
                  if (!s) return null;
                  const barsAria = s.bars.map((b) => `${b.label} ${b.value}`).join(', ');
                  return (
                    <article class="stat-card" key={key}>
                      <p class="stat-label muted">{s.label}</p>
                      <p class="stat-total">{s.total} <span class="stat-unit">{s.unit}</span></p>
                      <div class="bars" role="img" aria-label={`${s.label}: ${barsAria}`}>
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
              <h2 id="wizard-h">{t('action.newProject') as string}</h2>
              <div class="wizard">
                <p class="wizard-agent">{wizard.prompt}</p>
                <form class="wizard-form" method="post" action="/dashboard/projects">
                  <label class="auth-label" for="wizard-name">{t('wizard.nameLabel') as string}</label>
                  <input
                    id="wizard-name"
                    type="text"
                    name="name"
                    placeholder={t('wizard.namePlaceholder') as string}
                    autocomplete="off"
                  />
                  <fieldset class="wizard-targets">
                    <legend class="auth-label">{t('wizard.targets') as string}</legend>
                    {(wizard.targets ?? []).map((tgt) => (
                      <label class="wizard-chip" key={tgt}>
                        <input type="checkbox" name="targets" value={tgt} checked={tgt === 'web'} />
                        <span class="chip chip--lg chip--muted">{tgt}</span>
                      </label>
                    ))}
                  </fieldset>
                  <div class="wizard-foot">
                    <p class="wizard-note muted">{wizard.note}</p>
                    <button type="submit"><Icon name="plus" size={16} />{t('wizard.create') as string}</button>
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
