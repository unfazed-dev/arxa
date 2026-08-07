// config_view.tsx — workspace config surface (replaces config_view.html).
// Target toggles, default-locale radios, credential-group summary, and the
// theme/accent/jargon pref rows. Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Toggle {
  id: string;
  label: string;
  on?: boolean;
}

interface CredGroup {
  label: string;
  missing: number;
  set: number;
  total: number;
}

interface Prefs {
  theme?: string;
  accent?: string;
  [key: string]: unknown;
}

interface Project {
  name?: string;
  savedLabel?: string;
}

interface ConfigViewProps {
  t: TFn;
  locale?: string;
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  targets?: Toggle[];
  locales?: Toggle[];
  credMissing?: number;
  credGroups?: CredGroup[];
  accents?: Toggle[];
  jargons?: Toggle[];
  [key: string]: unknown;
}

const ConfigView: FC<ConfigViewProps> = (props) => {
  const {
    t,
    locale,
    activeShell,
    prefs,
    project,
    targets = [],
    locales = [],
    credMissing = 0,
    credGroups = [],
    accents = [],
    jargons = [],
  } = props;

  const surface = (
    <Fragment>
      <span class="eyebrow">{t('cfg.eyebrow') as string}</span>
      <h1 class="display">{t('cfg.title') as string}</h1>
      <p class="muted">{t('cfg.lede') as string}</p>

      <section class="settings-section">
        <h2>{t('cfg.section.app') as string}</h2>
        <p class="settings-note">{t('cfg.appNote') as string}</p>
        <form method="post" action="/workspace/config/set">
          <div class="cred-row">
            <div class="cred-row-head">
              <span class="cred-key">{t('cfg.targets') as string}</span>
              {targets.map((tg) => (
                <label class={`chip${tg.on ? ' is-set' : ''}`} key={tg.id}>
                  <input type="checkbox" name={`target_${tg.id}`} checked={!!tg.on} /> {tg.label}
                </label>
              ))}
            </div>
          </div>
          <div class="cred-row">
            <div class="cred-row-head">
              <span class="cred-key">{t('cfg.defaultLocale') as string}</span>
              {locales.map((lc) => (
                <label class={`chip${lc.on ? ' is-set' : ''}`} key={lc.id}>
                  <input type="radio" name="defaultLocale" value={lc.id} checked={!!lc.on} /> {lc.label}
                </label>
              ))}
              <button type="submit">{t('cfg.action.save') as string}</button>
            </div>
          </div>
        </form>
      </section>

      <section class="settings-section">
        <h2>{t('cfg.section.creds') as string}</h2>
        {credMissing > 0 ? (
          <p class="cred-missing">
            <span class="chip type-badge tb-findings">{t('creds.missing', { count: credMissing }) as string}</span>
          </p>
        ) : (
          <p class="cred-missing">
            <span class="chip type-badge tb-evidence">{t('creds.allSet') as string}</span>
          </p>
        )}
        {credGroups.map((g) => (
          <div class="cred-row" key={g.label}>
            <div class="cred-row-head">
              <span class="cred-key">{g.label}</span>
              <span class={`chip${g.missing === 0 ? ' is-set' : ''}`}>
                {t('cfg.creds.setOf', { set: g.set, total: g.total }) as string}
              </span>
              {g.missing > 0 ? (
                <span class="chip type-badge tb-findings">{t('cfg.creds.missing', { count: g.missing }) as string}</span>
              ) : null}
              <a class="cred-where" href="/workspace/credentials">{t('cfg.creds.manage') as string}</a>
            </div>
          </div>
        ))}
      </section>

      <section class="settings-section">
        <h2>{t('cfg.section.prefs') as string}</h2>
        <div class="cred-row">
          <div class="cred-row-head">
            <span class="cred-key">{t('cfg.prefs.theme') as string}</span>
            <span class="chip is-set">{t(`cfg.theme.${prefs?.theme}`) as string}</span>
            <form method="post" action="/prefs/theme">
              <button type="submit" class="ghost">{t('cfg.action.toggle') as string}</button>
            </form>
          </div>
        </div>
        <div class="cred-row">
          <div class="cred-row-head">
            <span class="cred-key">{t('cfg.prefs.accent') as string}</span>
            {accents.map((a) => (
              <form method="post" action="/prefs/accent" key={a.id}>
                <button type="submit" name="accent" value={a.id} class={`chip${a.on ? ' is-set' : ''}`}>{a.label}</button>
              </form>
            ))}
          </div>
        </div>
        <div class="cred-row">
          <div class="cred-row-head">
            <span class="cred-key">{t('cfg.prefs.jargon') as string}</span>
            {jargons.map((j) => (
              <form method="post" action="/prefs/jargon" key={j.id}>
                <button type="submit" name="jargon" value={j.id} class={`chip${j.on ? ' is-set' : ''}`}>{j.label}</button>
              </form>
            ))}
          </div>
        </div>
      </section>
    </Fragment>
  );

  return (
    <WorkspaceShellView
      t={t}
      title={t('cfg.pageTitle') as string}
      locale={locale}
      activeShell={activeShell}
      prefs={prefs}
      project={project}
      headExtra={<link rel="stylesheet" href="/assets/css/credential.css" />}
      surface={surface}
    />
  );
};

export default ConfigView;
