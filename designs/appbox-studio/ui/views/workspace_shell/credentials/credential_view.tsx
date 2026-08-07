// credential_view.tsx — workspace credentials surface (replaces credential_view.html).
// Lists credential groups/rows with set/unset affordances and the missing-count badge.
// Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';

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
      <span class="eyebrow">{t('creds.eyebrow') as string}</span>
      <h1 class="display">{t('creds.title') as string}</h1>
      <p class="muted">{t('creds.lede') as string}</p>
      {missing > 0 ? (
        <p class="cred-missing">
          <span class="chip type-badge tb-findings">{t('creds.missing', { count: missing }) as string}</span>
        </p>
      ) : (
        <p class="cred-missing">
          <span class="chip type-badge tb-evidence">{t('creds.allSet') as string}</span>
        </p>
      )}

      {groups.map((g) => (
        <section class="settings-section" key={g.label}>
          <h2>{g.label}</h2>
          {g.rows.map((r) => (
            <div class="cred-row" key={r.key}>
              <div class="cred-row-head">
                <span class="cred-key">{r.key}</span>
                <span class={`chip type-badge${r.kind === 'secret' ? ' tb-findings' : ' tb-evidence'}`}>{r.kindLabel}</span>
                <span class="chip chip--muted">{r.requiredLabel}</span>
                <span class={`chip${r.set ? ' is-set' : ''}`}>{r.statusLabel}</span>
                {r.url ? (
                  <a class="cred-where" href={r.url} target="_blank" rel="noopener">{t('creds.getKey') as string}</a>
                ) : null}
              </div>
              {r.note ? <p class="settings-note">{r.note}</p> : null}
              {r.set ? (
                <form method="post" action="/workspace/credentials/unset">
                  <input type="hidden" name="key" value={r.key} />
                  <button type="submit" class="ghost">{t('creds.action.remove') as string}</button>
                </form>
              ) : (
                <form class="cred-form" method="post" action="/workspace/credentials/set">
                  <input type="hidden" name="key" value={r.key} />
                  <input type="password" name="value" required autocomplete="off" aria-label={t('creds.inputAria', { key: r.key }) as string} />
                  <button type="submit">{t('creds.action.save') as string}</button>
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
