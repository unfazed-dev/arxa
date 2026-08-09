// config_view.tsx — workspace config surface (replaces config_view.html).
// Target toggles, default-locale radios, credential-group summary, and the
// theme/accent/jargon pref rows. Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';

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
  translate: TFn;
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
    translate,
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
      <Label name="workspace-config:eyebrow" class="eyebrow">{translate('cfg.eyebrow') as string}</Label>
      <Heading name="workspace-config:title" level={1} class="display">{translate('cfg.title') as string}</Heading>
      <Txt name="workspace-config:lede" class="muted">{translate('cfg.lede') as string}</Txt>

      <section class="settings-section">
        <Heading name="workspace-config:app-h" level={2}>{translate('cfg.section.app') as string}</Heading>
        <Txt name="workspace-config:app-note" class="settings-note">{translate('cfg.appNote') as string}</Txt>
        <form method="post" action="/workspace/config/set">
          <div class="cred-row">
            <div class="cred-row-head">
              <Label name="workspace-config:targets-label" class="cred-key">{translate('cfg.targets') as string}</Label>
              {targets.map((tg) => (
                <label class={`chip${tg.on ? ' is-set' : ''}`} key={tg.id} {...inspectAttrs('workspace-config:target', { role: 'label' })}>
                  <input type="checkbox" name={`target_${tg.id}`} checked={!!tg.on} {...inspectAttrs('workspace-config:target-input', { role: 'input' })} /> {tg.label}
                </label>
              ))}
            </div>
          </div>
          <div class="cred-row">
            <div class="cred-row-head">
              <Label name="workspace-config:locale-label" class="cred-key">{translate('cfg.defaultLocale') as string}</Label>
              {locales.map((lc) => (
                <label class={`chip${lc.on ? ' is-set' : ''}`} key={lc.id} {...inspectAttrs('workspace-config:locale', { role: 'label' })}>
                  <input type="radio" name="defaultLocale" value={lc.id} checked={!!lc.on} {...inspectAttrs('workspace-config:locale-input', { role: 'input' })} /> {lc.label}
                </label>
              ))}
              <button type="submit" {...inspectAttrs('workspace-config:save-app', { role: 'action' })}>{translate('cfg.action.save') as string}</button>
            </div>
          </div>
        </form>
      </section>

      <section class="settings-section">
        <Heading name="workspace-config:creds-h" level={2}>{translate('cfg.section.creds') as string}</Heading>
        {credMissing > 0 ? (
          <p class="cred-missing">
            <Label name="workspace-config:creds-missing" class="chip type-badge tb-findings">{translate('creds.missing', { count: credMissing }) as string}</Label>
          </p>
        ) : (
          <p class="cred-missing">
            <Label name="workspace-config:creds-allset" class="chip type-badge tb-evidence">{translate('creds.allSet') as string}</Label>
          </p>
        )}
        {credGroups.map((g) => (
          <div class="cred-row" key={g.label}>
            <div class="cred-row-head">
              <Label name="workspace-config:cred-group" class="cred-key">{g.label}</Label>
              <Label name="workspace-config:cred-set" class={`chip${g.missing === 0 ? ' is-set' : ''}`}>
                {translate('cfg.creds.setOf', { set: g.set, total: g.total }) as string}
              </Label>
              {g.missing > 0 ? (
                <Label name="workspace-config:cred-missing" class="chip type-badge tb-findings">{translate('cfg.creds.missing', { count: g.missing }) as string}</Label>
              ) : null}
              <a class="cred-where" href="/workspace/credentials" {...inspectAttrs('workspace-config:cred-manage', { role: 'action' })}>{translate('cfg.creds.manage') as string}</a>
            </div>
          </div>
        ))}
      </section>

      <section class="settings-section">
        <Heading name="workspace-config:prefs-h" level={2}>{translate('cfg.section.prefs') as string}</Heading>
        <div class="cred-row">
          <div class="cred-row-head">
            <Label name="workspace-config:theme-label" class="cred-key">{translate('cfg.prefs.theme') as string}</Label>
            <Label name="workspace-config:theme-value" class="chip is-set">{translate(`cfg.theme.${prefs?.theme}`) as string}</Label>
            <form method="post" action="/prefs/theme">
              <button type="submit" class="ghost" {...inspectAttrs('workspace-config:theme-toggle', { role: 'action' })}>{translate('cfg.action.toggle') as string}</button>
            </form>
          </div>
        </div>
        <div class="cred-row">
          <div class="cred-row-head">
            <Label name="workspace-config:accent-label" class="cred-key">{translate('cfg.prefs.accent') as string}</Label>
            {accents.map((a) => (
              <form method="post" action="/prefs/accent" key={a.id}>
                <button type="submit" name="accent" value={a.id} class={`chip${a.on ? ' is-set' : ''}`} {...inspectAttrs('workspace-config:accent', { role: 'action' })}>{a.label}</button>
              </form>
            ))}
          </div>
        </div>
        <div class="cred-row">
          <div class="cred-row-head">
            <Label name="workspace-config:jargon-label" class="cred-key">{translate('cfg.prefs.jargon') as string}</Label>
            {jargons.map((j) => (
              <form method="post" action="/prefs/jargon" key={j.id}>
                <button type="submit" name="jargon" value={j.id} class={`chip${j.on ? ' is-set' : ''}`} {...inspectAttrs('workspace-config:jargon', { role: 'action' })}>{j.label}</button>
              </form>
            ))}
          </div>
        </div>
      </section>
    </Fragment>
  );

  return (
    <WorkspaceShellView
      translate={translate}
      title={translate('cfg.pageTitle') as string}
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
