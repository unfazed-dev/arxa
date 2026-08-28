// settings_view.tsx — workspace settings surface (replaces settings_view.html).
// Appearance (theme/accent/font), language switcher, jargon level, and the
// credentials/config entry links. Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';
import LangSwitcher from '../../../common/lang_switcher.tsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';
import { raw } from 'hono/utils/html';

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
  translate: TFn;
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
    translate,
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
      <Label name="workspace-settings:eyebrow" class="eyebrow">{translate('settings.eyebrow') as string}</Label>
      <Heading name="workspace-settings:title" level={1} class="display">{translate('settings.title') as string}</Heading>
      <Txt name="workspace-settings:lede" class="muted">{translate('settings.lede') as string}</Txt>

      {/* General — desktop-shell actions. Server-rendered hidden: pairing
          lives in the Tauri shell (open_pairing_window), so the inline script
          reveals the section only when the page runs inside the desktop
          webview (window.__TAURI__ present). In a plain browser the section
          never appears — the studio must stay fully usable without it. */}
      <section class="settings-section" id="settings-general" hidden>
        <Heading name="workspace-settings:general-h" level={2}>{translate('settings.generalH') as string}</Heading>
        <Txt name="workspace-settings:general-note" class="settings-note">{translate('settings.generalNote') as string}</Txt>
        <button type="button" class="ghost" id="pair-device" {...inspectAttrs('workspace-settings:pair-device', { role: 'action' })}>
          {translate('settings.pairDevice') as string} <Icon name="arrow-right" size={14} />
        </button>
        {raw(`<script>(function () {
  var tauri = window.__TAURI__;
  var section = document.getElementById('settings-general');
  var btn = document.getElementById('pair-device');
  if (!tauri || !tauri.core || !section || !btn) return;
  section.hidden = false;
  btn.addEventListener('click', function () {
    tauri.core.invoke('open_pairing_window').catch(function (e) {
      console.error('pair window:', e);
    });
  });
})();</script>`)}
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:appearance-h" level={2}>{translate('settings.appearanceH') as string}</Heading>
        <Txt name="workspace-settings:appearance-note" class="settings-note">{translate('settings.appearanceNote') as string}</Txt>
        <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
          <button type="submit" {...inspectAttrs('workspace-settings:theme-toggle', { role: 'action' })}>
            <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={15} />{' '}
            {theme === 'dark' ? (translate('settings.themeTo.light') as string) : (translate('settings.themeTo.dark') as string)}
          </button>
        </form>
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:accent-h" level={2}>{translate('settings.accentH') as string}</Heading>
        <Txt name="workspace-settings:accent-note" class="settings-note">{translate('settings.accentNote') as string}</Txt>
        <form class="swatch-row" method="post" action="/prefs/accent" hx-post="/prefs/accent" hx-swap="none" {...inspectAttrs('workspace-settings:accent-form', { role: 'group' })}>
          {accents.map((swatch) => (
            <button
              type="submit"
              name="accent"
              value={swatch.id}
              class={`swatch${swatch.id === accent ? ' is-active' : ''}`}
              key={swatch.id}
              {...inspectAttrs('workspace-settings:accent', { role: 'action' })}
            >
              <span class="swatch-dot" style={`--swatch: ${swatch.dot}`} />{swatch.label}
              {swatch.id === accent ? (<Fragment>{' '}<Icon name="check" size={13} /></Fragment>) : null}
            </button>
          ))}
        </form>
      </section>

      {/* Typeface — same shape as the accent row above (one POST, no swap: the
          pref renders as data-font on #app, outside every swap unit). Each
          button is set in the family it selects, so the row is its own specimen sheet. */}
      <section class="settings-section">
        <Heading name="workspace-settings:font-h" level={2}>{translate('settings.fontH') as string}</Heading>
        <Txt name="workspace-settings:font-note" class="settings-note">{translate('settings.fontNote') as string}</Txt>
        <form class="swatch-row" method="post" action="/prefs/font" hx-post="/prefs/font" hx-swap="none" {...inspectAttrs('workspace-settings:font-form', { role: 'group' })}>
          {fonts.map((fontOption) => (
            <button
              type="submit"
              name="font"
              value={fontOption.id}
              class={`swatch${fontOption.id === font ? ' is-active' : ''}`}
              style={`font-family: ${fontOption.stack}`}
              key={fontOption.id}
              {...inspectAttrs('workspace-settings:font', { role: 'action' })}
            >
              {fontOption.label}
              {fontOption.id === font ? (<Fragment>{' '}<Icon name="check" size={13} /></Fragment>) : null}
            </button>
          ))}
        </form>
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:language-h" level={2}>{translate('settings.languageH') as string}</Heading>
        <Txt name="workspace-settings:language-note" class="settings-note">{translate('settings.languageNote') as string}</Txt>
        <LangSwitcher locales={locales} locale={locale} translate={translate} />
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:jargon-h" level={2}>{translate('settings.jargonH') as string}</Heading>
        <Txt name="workspace-settings:jargon-note" class="settings-note">{translate('settings.jargonNote') as string}</Txt>
        <div class="level-row" {...inspectAttrs('workspace-settings:level-row', { role: 'group' })}>
          {levels.map((level) => (
            <form method="post" action="/prefs/jargon" hx-post="/prefs/jargon" hx-swap="none" key={level.id}>
              <button
                type="submit"
                name="jargon"
                value={level.id}
                class={`level-card${level.id === jargon ? ' is-active' : ''}`}
                {...inspectAttrs('workspace-settings:jargon', { role: 'action' })}
              >
                <span class="level-name" {...inspectAttrs('workspace-settings:level-name', { role: 'text' })}>
                  {level.label}
                  {level.id === jargon ? (<Fragment>{' '}<Icon name="check" size={14} /></Fragment>) : null}
                </span>
                <Label name="workspace-settings:level-example" class="level-example">&ldquo;{level.example}&rdquo;</Label>
              </button>
            </form>
          ))}
        </div>
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:credentials-h" level={2}>{translate('settings.credentialsH') as string}</Heading>
        <Txt name="workspace-settings:credentials-note" class="settings-note">{translate('settings.credentialsNote') as string}</Txt>
        <a class="ghost" href="/workspace/credentials" {...inspectAttrs('workspace-settings:credentials-link', { role: 'action' })}>
          {translate('settings.credentialsH') as string} <Icon name="arrow-right" size={14} />
        </a>
      </section>

      <section class="settings-section">
        <Heading name="workspace-settings:config-h" level={2}>{translate('settings.configH') as string}</Heading>
        <Txt name="workspace-settings:config-note" class="settings-note">{translate('settings.configNote') as string}</Txt>
        <a class="ghost" href="/workspace/config" {...inspectAttrs('workspace-settings:config-link', { role: 'action' })}>
          {translate('settings.configH') as string} <Icon name="arrow-right" size={14} />
        </a>
      </section>
    </Fragment>
  );

  return (
    <WorkspaceShellView
      translate={translate}
      title={translate('settings.pageTitle') as string}
      locale={locale}
      activeShell={activeShell}
      prefs={prefs}
      project={project}
      surface={surface}
    />
  );
};

export default SettingsView;
