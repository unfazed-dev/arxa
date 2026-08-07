// settings_view.tsx — workspace settings surface (replaces settings_view.html).
// Appearance (theme/accent/font), language switcher, jargon level, and the
// credentials/config entry links. Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';
import LangSwitcher from '../../../common/_lang_switcher.tsx';
import Icon from '../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Accent {
  id: string;
  dot: string;
  label: string;
}

interface Font {
  id: string;
  stack: string;
  label: string;
}

interface JargonLevel {
  id: string;
  label: string;
  example: string;
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

interface SettingsViewProps {
  t: TFn;
  locale?: string;
  locales?: string[];
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  theme?: string;
  accent?: string;
  accents?: Accent[];
  font?: string;
  fonts?: Font[];
  jargon?: string;
  levels?: JargonLevel[];
  [key: string]: unknown;
}

const SettingsView: FC<SettingsViewProps> = (props) => {
  const {
    t,
    locale,
    locales,
    activeShell,
    prefs,
    project,
    theme = 'light',
    accent = '',
    accents = [],
    font = '',
    fonts = [],
    jargon = '',
    levels = [],
  } = props;

  const surface = (
    <Fragment>
      <span class="eyebrow">{t('settings.eyebrow') as string}</span>
      <h1 class="display">{t('settings.title') as string}</h1>
      <p class="muted">{t('settings.lede') as string}</p>

      <section class="settings-section">
        <h2>{t('settings.appearanceH') as string}</h2>
        <p class="settings-note">{t('settings.appearanceNote') as string}</p>
        <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
          <button type="submit">
            <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={15} />{' '}
            {theme === 'dark' ? (t('settings.themeTo.light') as string) : (t('settings.themeTo.dark') as string)}
          </button>
        </form>
      </section>

      <section class="settings-section">
        <h2>{t('settings.accentH') as string}</h2>
        <p class="settings-note">{t('settings.accentNote') as string}</p>
        <form class="swatch-row" method="post" action="/prefs/accent" hx-post="/prefs/accent" hx-swap="none">
          {accents.map((s) => (
            <button
              type="submit"
              name="accent"
              value={s.id}
              class={`swatch${s.id === accent ? ' is-active' : ''}`}
              key={s.id}
            >
              <span class="swatch-dot" style={`--swatch: ${s.dot}`} />{s.label}
              {s.id === accent ? (<Fragment>{' '}<Icon name="check" size={13} /></Fragment>) : null}
            </button>
          ))}
        </form>
      </section>

      {/* Typeface — same shape as the accent row above (one POST, no swap: the
          pref renders as data-font on #app, outside every swap unit). Each
          button is set in the family it selects, so the row is its own specimen sheet. */}
      <section class="settings-section">
        <h2>{t('settings.fontH') as string}</h2>
        <p class="settings-note">{t('settings.fontNote') as string}</p>
        <form class="swatch-row" method="post" action="/prefs/font" hx-post="/prefs/font" hx-swap="none">
          {fonts.map((f) => (
            <button
              type="submit"
              name="font"
              value={f.id}
              class={`swatch${f.id === font ? ' is-active' : ''}`}
              style={`font-family: ${f.stack}`}
              key={f.id}
            >
              {f.label}
              {f.id === font ? (<Fragment>{' '}<Icon name="check" size={13} /></Fragment>) : null}
            </button>
          ))}
        </form>
      </section>

      <section class="settings-section">
        <h2>{t('settings.languageH') as string}</h2>
        <p class="settings-note">{t('settings.languageNote') as string}</p>
        <LangSwitcher locales={locales} locale={locale} t={t} />
      </section>

      <section class="settings-section">
        <h2>{t('settings.jargonH') as string}</h2>
        <p class="settings-note">{t('settings.jargonNote') as string}</p>
        <div class="level-row">
          {levels.map((l) => (
            <form method="post" action="/prefs/jargon" hx-post="/prefs/jargon" hx-swap="none" key={l.id}>
              <button
                type="submit"
                name="jargon"
                value={l.id}
                class={`level-card${l.id === jargon ? ' is-active' : ''}`}
              >
                <span class="level-name">
                  {l.label}
                  {l.id === jargon ? (<Fragment>{' '}<Icon name="check" size={14} /></Fragment>) : null}
                </span>
                <span class="level-example">&ldquo;{l.example}&rdquo;</span>
              </button>
            </form>
          ))}
        </div>
      </section>

      <section class="settings-section">
        <h2>{t('settings.credentialsH') as string}</h2>
        <p class="settings-note">{t('settings.credentialsNote') as string}</p>
        <a class="ghost" href="/workspace/credentials">
          {t('settings.credentialsH') as string} <Icon name="arrow-right" size={14} />
        </a>
      </section>

      <section class="settings-section">
        <h2>{t('settings.configH') as string}</h2>
        <p class="settings-note">{t('settings.configNote') as string}</p>
        <a class="ghost" href="/workspace/config">
          {t('settings.configH') as string} <Icon name="arrow-right" size={14} />
        </a>
      </section>
    </Fragment>
  );

  return (
    <WorkspaceShellView
      t={t}
      title={t('settings.pageTitle') as string}
      locale={locale}
      activeShell={activeShell}
      prefs={prefs}
      project={project}
      surface={surface}
    />
  );
};

export default SettingsView;
