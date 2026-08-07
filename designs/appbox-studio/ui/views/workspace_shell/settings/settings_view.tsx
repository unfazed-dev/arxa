// settings_view.tsx — workspace settings surface (replaces settings_view.html).
// Appearance (theme/accent/font), language switcher, jargon level, and the
// credentials/config entry links. Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';
import LangSwitcher from '../../../common/_lang_switcher.tsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';

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
      <Label name="workspace-settings:eyebrow" class="eyebrow">{t('settings.eyebrow') as string}</Label>
      <Heading name="workspace-settings:title" level={1} class="display">{t('settings.title') as string}</Heading>
      <Txt name="workspace-settings:lede" class="muted">{t('settings.lede') as string}</Txt>

      <section class="settings-section">
        <Heading name="workspace-settings:appearance-h" level={2}>{t('settings.appearanceH') as string}</Heading>
        <Txt name="workspace-settings:appearance-note" class="settings-note">{t('settings.appearanceNote') as string}</Txt>
        <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
          <button type="submit" {...inspectAttrs('workspace-settings:theme-toggle', { role: 'action' })}>
            <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={15} />{' '}
            {theme === 'dark' ? (t('settings.themeTo.light') as string) : (t('settings.themeTo.dark') as string)}
          </button>
        </form>
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:accent-h" level={2}>{t('settings.accentH') as string}</Heading>
        <Txt name="workspace-settings:accent-note" class="settings-note">{t('settings.accentNote') as string}</Txt>
        <form class="swatch-row" method="post" action="/prefs/accent" hx-post="/prefs/accent" hx-swap="none" {...inspectAttrs('workspace-settings:accent-form', { role: 'group' })}>
          {accents.map((s) => (
            <button
              type="submit"
              name="accent"
              value={s.id}
              class={`swatch${s.id === accent ? ' is-active' : ''}`}
              key={s.id}
              {...inspectAttrs('workspace-settings:accent', { role: 'action' })}
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
        <Heading name="workspace-settings:font-h" level={2}>{t('settings.fontH') as string}</Heading>
        <Txt name="workspace-settings:font-note" class="settings-note">{t('settings.fontNote') as string}</Txt>
        <form class="swatch-row" method="post" action="/prefs/font" hx-post="/prefs/font" hx-swap="none" {...inspectAttrs('workspace-settings:font-form', { role: 'group' })}>
          {fonts.map((f) => (
            <button
              type="submit"
              name="font"
              value={f.id}
              class={`swatch${f.id === font ? ' is-active' : ''}`}
              style={`font-family: ${f.stack}`}
              key={f.id}
              {...inspectAttrs('workspace-settings:font', { role: 'action' })}
            >
              {f.label}
              {f.id === font ? (<Fragment>{' '}<Icon name="check" size={13} /></Fragment>) : null}
            </button>
          ))}
        </form>
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:language-h" level={2}>{t('settings.languageH') as string}</Heading>
        <Txt name="workspace-settings:language-note" class="settings-note">{t('settings.languageNote') as string}</Txt>
        <LangSwitcher locales={locales} locale={locale} t={t} />
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:jargon-h" level={2}>{t('settings.jargonH') as string}</Heading>
        <Txt name="workspace-settings:jargon-note" class="settings-note">{t('settings.jargonNote') as string}</Txt>
        <div class="level-row" {...inspectAttrs('workspace-settings:level-row', { role: 'group' })}>
          {levels.map((l) => (
            <form method="post" action="/prefs/jargon" hx-post="/prefs/jargon" hx-swap="none" key={l.id}>
              <button
                type="submit"
                name="jargon"
                value={l.id}
                class={`level-card${l.id === jargon ? ' is-active' : ''}`}
                {...inspectAttrs('workspace-settings:jargon', { role: 'action' })}
              >
                <span class="level-name" {...inspectAttrs('workspace-settings:level-name', { role: 'text' })}>
                  {l.label}
                  {l.id === jargon ? (<Fragment>{' '}<Icon name="check" size={14} /></Fragment>) : null}
                </span>
                <Label name="workspace-settings:level-example" class="level-example">&ldquo;{l.example}&rdquo;</Label>
              </button>
            </form>
          ))}
        </div>
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:credentials-h" level={2}>{t('settings.credentialsH') as string}</Heading>
        <Txt name="workspace-settings:credentials-note" class="settings-note">{t('settings.credentialsNote') as string}</Txt>
        <a class="ghost" href="/workspace/credentials" {...inspectAttrs('workspace-settings:credentials-link', { role: 'action' })}>
          {t('settings.credentialsH') as string} <Icon name="arrow-right" size={14} />
        </a>
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:config-h" level={2}>{t('settings.configH') as string}</Heading>
        <Txt name="workspace-settings:config-note" class="settings-note">{t('settings.configNote') as string}</Txt>
        <a class="ghost" href="/workspace/config" {...inspectAttrs('workspace-settings:config-link', { role: 'action' })}>
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
