// credential_view.tsx — workspace credentials surface (replaces credential_view.html).
// Lists credential groups/rows with set/unset affordances and the missing-count badge.
// Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface CredRow {
  key: string;
  kind: string;
  kindLabel: string;
  requiredLabel: string;
  set?: boolean;
  statusLabel: string;
  url?: string;
  note?: string;
}

interface CredGroup {
  label: string;
  rows: CredRow[];
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

interface CredentialViewProps {
  t: TFn;
  locale?: string;
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  missing?: number;
  groups?: CredGroup[];
  [key: string]: unknown;
}

const CredentialView: FC<CredentialViewProps> = (props) => {
  const {
    t,
    locale,
    activeShell,
    prefs,
    project,
    missing = 0,
    groups = [],
  } = props;

  const surface = (
    <Fragment>
      <Label name="workspace-credentials:eyebrow" class="eyebrow">{t('creds.eyebrow') as string}</Label>
      <Heading name="workspace-credentials:title" level={1} class="display">{t('creds.title') as string}</Heading>
      <Txt name="workspace-credentials:lede" class="muted">{t('creds.lede') as string}</Txt>
      {missing > 0 ? (
        <p class="cred-missing">
          <Label name="workspace-credentials:missing" class="chip type-badge tb-findings">{t('creds.missing', { count: missing }) as string}</Label>
        </p>
      ) : (
        <p class="cred-missing">
          <Label name="workspace-credentials:all-set" class="chip type-badge tb-evidence">{t('creds.allSet') as string}</Label>
        </p>
      )}

      {groups.map((g) => (
        <section class="settings-section" key={g.label}>
          <Heading name="workspace-credentials:group" level={2}>{g.label}</Heading>
          {g.rows.map((r) => (
            <div class="cred-row" key={r.key}>
              <div class="cred-row-head">
                <Label name="workspace-credentials:key" class="cred-key">{r.key}</Label>
                <Label name="workspace-credentials:kind" class={`chip type-badge${r.kind === 'secret' ? ' tb-findings' : ' tb-evidence'}`}>{r.kindLabel}</Label>
                <Label name="workspace-credentials:required" class="chip chip--muted">{r.requiredLabel}</Label>
                <Label name="workspace-credentials:status" class={`chip${r.set ? ' is-set' : ''}`}>{r.statusLabel}</Label>
                {r.url ? (
                  <a class="cred-where" href={r.url} target="_blank" rel="noopener" {...inspectAttrs('workspace-credentials:get-key', { role: 'action' })}>{t('creds.getKey') as string}</a>
                ) : null}
              </div>
              {r.note ? <Txt name="workspace-credentials:note" class="settings-note">{r.note}</Txt> : null}
              {r.set ? (
                <form method="post" action="/workspace/credentials/unset">
                  <input type="hidden" name="key" value={r.key} {...inspectAttrs('workspace-credentials:unset-key', { role: 'input' })} />
                  <button type="submit" class="ghost" {...inspectAttrs('workspace-credentials:unset', { role: 'action' })}>{t('creds.action.remove') as string}</button>
                </form>
              ) : (
                <form class="cred-form" method="post" action="/workspace/credentials/set">
                  <input type="hidden" name="key" value={r.key} {...inspectAttrs('workspace-credentials:set-key', { role: 'input' })} />
                  <input type="password" name="value" required autocomplete="off" aria-label={t('creds.inputAria', { key: r.key }) as string} {...inspectAttrs('workspace-credentials:set-value', { role: 'input' })} />
                  <button type="submit" {...inspectAttrs('workspace-credentials:save', { role: 'action' })}>{t('creds.action.save') as string}</button>
                </form>
              )}
            </div>
          ))}
        </section>
      ))}
    </Fragment>
  );

  return (
    <WorkspaceShellView
      t={t}
      title={t('creds.pageTitle') as string}
      locale={locale}
      activeShell={activeShell}
      prefs={prefs}
      project={project}
      headExtra={<link rel="stylesheet" href="/assets/css/credential.css" />}
      surface={surface}
    />
  );
};

export default CredentialView;
