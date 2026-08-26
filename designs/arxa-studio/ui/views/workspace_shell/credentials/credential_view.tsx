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
  translate: TFn;
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
    translate,
    locale,
    activeShell,
    prefs,
    project,
    missing = 0,
    groups = [],
  } = props;

  const surface = (
    <Fragment>
      <Label name="workspace-credentials:eyebrow" class="eyebrow">{translate('creds.eyebrow') as string}</Label>
      <Heading name="workspace-credentials:title" level={1} class="display">{translate('creds.title') as string}</Heading>
      <Txt name="workspace-credentials:lede" class="muted">{translate('creds.lede') as string}</Txt>
      {missing > 0 ? (
        <p class="cred-missing">
          <Label name="workspace-credentials:missing" class="chip type-badge tb-findings">{translate('creds.missing', { count: missing }) as string}</Label>
        </p>
      ) : (
        <p class="cred-missing">
          <Label name="workspace-credentials:all-set" class="chip type-badge tb-evidence">{translate('creds.allSet') as string}</Label>
        </p>
      )}

      {groups.map((group) => (
        <section class="settings-section" key={group.label}>
          <Heading name="workspace-credentials:group" level={2}>{group.label}</Heading>
          {group.rows.map((row) => (
            <div class="cred-row" key={row.key}>
              <div class="cred-row-head">
                <Label name="workspace-credentials:key" class="cred-key">{row.key}</Label>
                <Label name="workspace-credentials:kind" class={`chip type-badge${row.kind === 'secret' ? ' tb-findings' : ' tb-evidence'}`}>{row.kindLabel}</Label>
                <Label name="workspace-credentials:required" class="chip chip--muted">{row.requiredLabel}</Label>
                <Label name="workspace-credentials:status" class={`chip${row.set ? ' is-set' : ''}`}>{row.statusLabel}</Label>
                {row.url ? (
                  <a class="cred-where" href={row.url} target="_blank" rel="noopener" {...inspectAttrs('workspace-credentials:get-key', { role: 'action' })}>{translate('creds.getKey') as string}</a>
                ) : null}
              </div>
              {row.note ? <Txt name="workspace-credentials:note" class="settings-note">{row.note}</Txt> : null}
              {row.set ? (
                <form method="post" action="/workspace/credentials/unset">
                  <input type="hidden" name="key" value={row.key} {...inspectAttrs('workspace-credentials:unset-key', { role: 'input' })} />
                  <button type="submit" class="ghost" {...inspectAttrs('workspace-credentials:unset', { role: 'action' })}>{translate('creds.action.remove') as string}</button>
                </form>
              ) : (
                <form class="cred-form" method="post" action="/workspace/credentials/set">
                  <input type="hidden" name="key" value={row.key} {...inspectAttrs('workspace-credentials:set-key', { role: 'input' })} />
                  <input type="password" name="value" required autocomplete="off" aria-label={translate('creds.inputAria', { key: row.key }) as string} {...inspectAttrs('workspace-credentials:set-value', { role: 'input' })} />
                  <button type="submit" {...inspectAttrs('workspace-credentials:save', { role: 'action' })}>{translate('creds.action.save') as string}</button>
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
      translate={translate}
      title={translate('creds.pageTitle') as string}
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
