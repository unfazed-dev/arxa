// run_view.tsx — scaffold.run, the scaffold execution RECEIPT (replaces run_view.html).
// NOT a progress screen — scaffolding is a synchronous millisecond transform of an
// already-frozen structure.json. Five read states, no sixth "running" one.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import { Panels, AccountChip, type ScaffoldCtx } from '../_shared.tsx';
import Icon from '../../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface RunKit { id: string; ready?: boolean; auto?: boolean; }
interface RunWrite { kind?: string; path?: string; ready?: boolean; }
interface RunWarning { code?: string; kitId?: string; href?: string; }

interface RunViewProps extends ScaffoldCtx {
  t: TFn;
  locale?: string;
  locales?: string[];
  prefs?: { accent?: string; [key: string]: unknown };
  activeShell?: string;
  state?: string;
  isDone?: boolean;
  hasWarnings?: boolean;
  isFailed?: boolean;
  isBlocked?: boolean;
  isPre?: boolean;
  structure?: { path?: string; revision?: string; screens?: number; shells?: number };
  counts?: { kits?: number; created?: number; updated?: number; skipped?: number };
  kits?: RunKit[];
  writes?: RunWrite[];
  manifest?: { path?: string; beside?: string; sections?: string[] };
  deltas?: {
    structure?: { path?: string };
    registry?: { path?: string; added?: number; changed?: number };
  };
  warnings?: RunWarning[];
  failure?: { code?: string; path?: string; rolledBack?: boolean; wrote?: number; retryHref?: string };
  blocked?: { code?: string; href?: string };
  runHref?: string;
  backHref?: string;
}

// ---- the state banner ----
function Banner({ c, t }: { c: RunViewProps; t: TFn }) {
  const icon = c.isDone && !c.hasWarnings ? 'file-check'
    : c.hasWarnings ? 'alert-triangle'
    : c.isFailed ? 'x-octagon'
    : c.isBlocked ? 'lock'
    : 'play';
  return (
    <div class={`run-banner run-banner--${c.state}`} role="status">
      <span class="run-banner-icon"><Icon name={icon} size={18} /></span>
      <div class="run-banner-text">
        <p class="run-banner-title">{t(`scaffold.run.state.${c.state}.title`) as string}</p>
        <p class="run-banner-note">{t(`scaffold.run.state.${c.state}.note`) as string}</p>
      </div>
    </div>
  );
}

// ---- the input summary ----
function InputSummary({ c, t }: { c: RunViewProps; t: TFn }) {
  return (
    <section class="run-card run-input" aria-labelledby="run-input-h">
      <h3 class="run-card-h" id="run-input-h">{t('scaffold.run.input.heading') as string}</h3>
      <dl class="run-facts">
        <div class="run-fact">
          <dt>{t('scaffold.run.input.structure') as string}</dt>
          <dd>
            <code class="run-path">{c.structure?.path}</code>
            <span class="chip chip--sm run-frozen">
              <Icon name="lock" size={12} /> {t('scaffold.run.input.frozen', { revision: c.structure?.revision }) as string}
            </span>
          </dd>
        </div>
        <div class="run-fact">
          <dt>{t('scaffold.run.input.scope') as string}</dt>
          <dd>{t('scaffold.run.input.scopeValue', { screens: c.structure?.screens, shells: c.structure?.shells }) as string}</dd>
        </div>
        <div class="run-fact">
          <dt>{t('scaffold.run.input.kits') as string}</dt>
          <dd>{t('scaffold.run.input.kitsValue', { count: c.counts?.kits }) as string}</dd>
        </div>
      </dl>
      <ul class="run-kitset">
        {(c.kits ?? []).map((k) => (
          <li key={k.id} class={`chip run-kit${!k.ready ? ' run-kit--unready' : ''}`}>
            <span class="run-kit-name">{t(`scaffold.kit.${k.id}`) as string}</span>
            {k.auto && <span class="chip chip--sm run-kit-auto">{t('scaffold.run.kit.auto') as string}</span>}
            {!k.ready && <span class="chip chip--sm run-kit-keys">{t('scaffold.run.kit.needsKeys') as string}</span>}
          </li>
        ))}
      </ul>
    </section>
  );
}

// ---- the gate (pre) ----
function Gate({ c, t }: { c: RunViewProps; t: TFn }) {
  return (
    <section class="run-card run-gate">
      <p class="run-gate-note">{t('scaffold.run.gate.note') as string}</p>
      <div class="run-actions">
        <a class="cta-link cta-link--main" href={c.runHref}>
          <Icon name="play" size={14} /> {t('scaffold.run.gate.action') as string}
        </a>
        <a class="cta-link cta-link--ghost" href={c.backHref}>{t('scaffold.run.gate.back') as string}</a>
      </div>
    </section>
  );
}

// ---- what landed ----
function Writes({ c, t }: { c: RunViewProps; t: TFn }) {
  return (
    <section class="run-card run-writes" aria-labelledby="run-writes-h">
      <h3 class="run-card-h" id="run-writes-h">{t('scaffold.run.writes.heading') as string}</h3>
      <p class="run-counts">
        {t('scaffold.run.writes.counts', { created: c.counts?.created, updated: c.counts?.updated, skipped: c.counts?.skipped }) as string}
      </p>
      <ul class="run-filelist">
        {(c.writes ?? []).map((w, i) => (
          <li key={i} class={`run-file run-file--${w.kind}`}>
            <span class="run-file-kind">{t(`scaffold.run.writes.kind.${w.kind}`) as string}</span>
            <code class="run-path">{w.path}</code>
            {!w.ready && <span class="chip chip--sm run-kit-keys">{t('scaffold.run.kit.needsKeys') as string}</span>}
          </li>
        ))}
      </ul>
    </section>
  );
}

// ---- the manifest sidecar (D8) ----
function Sidecar({ c, t }: { c: RunViewProps; t: TFn }) {
  return (
    <section class="run-card run-sidecar" aria-labelledby="run-sidecar-h">
      <h3 class="run-card-h" id="run-sidecar-h">{t('scaffold.run.manifest.heading') as string}</h3>
      <p class="run-sidecar-line">
        <code class="run-path">{c.manifest?.path}</code>
        <span class="run-beside">{t('scaffold.run.manifest.beside', { path: c.manifest?.beside }) as string}</span>
      </p>
      <ul class="run-sections">
        {(c.manifest?.sections ?? []).map((s) => (
          <li key={s}>{t(`scaffold.run.manifest.section.${s}`) as string}</li>
        ))}
      </ul>
      <dl class="run-facts run-deltas">
        <div class="run-fact">
          <dt><code class="run-path">{c.deltas?.structure?.path}</code></dt>
          <dd>{t('scaffold.run.delta.untouched') as string}</dd>
        </div>
        <div class="run-fact">
          <dt><code class="run-path">{c.deltas?.registry?.path}</code></dt>
          <dd>{t('scaffold.run.delta.counts', { added: c.deltas?.registry?.added, changed: c.deltas?.registry?.changed }) as string}</dd>
        </div>
      </dl>
    </section>
  );
}

// ---- readiness warnings (D6 — inform only) ----
function Warnings({ c, t }: { c: RunViewProps; t: TFn }) {
  return (
    <section class="run-card run-warnings" aria-labelledby="run-warn-h">
      <h3 class="run-card-h" id="run-warn-h">{t('scaffold.run.warn.heading') as string}</h3>
      <p class="run-warn-note">{t('scaffold.run.warn.note') as string}</p>
      <ul class="run-warnlist">
        {(c.warnings ?? []).map((w, i) => (
          <li key={i} class="run-warn">
            <Icon name="alert-triangle" size={13} />
            <span>{t(`scaffold.run.warn.${w.code}`, { kit: t(`scaffold.kit.${w.kitId}`) }) as string}</span>
            <a class="bt-link" href={w.href}>{t('scaffold.run.warn.fix') as string}</a>
          </li>
        ))}
      </ul>
    </section>
  );
}

// ---- failure ----
function Failure({ c, t }: { c: RunViewProps; t: TFn }) {
  return (
    <section class="run-card run-failure" aria-labelledby="run-fail-h">
      <h3 class="run-card-h" id="run-fail-h">{t('scaffold.run.fail.heading') as string}</h3>
      <p class="run-fail-reason">{t(`scaffold.run.fail.${c.failure?.code}`) as string}</p>
      <p class="run-fail-path"><code class="run-path">{c.failure?.path}</code></p>
      {c.failure?.rolledBack && (
        <p class="run-fail-rollback">{t('scaffold.run.fail.rolledBack', { count: c.failure.wrote }) as string}</p>
      )}
      <div class="run-actions">
        <a class="cta-link cta-link--main" href={c.failure?.retryHref}>{t('scaffold.run.fail.retry') as string}</a>
        <a class="cta-link cta-link--ghost" href={c.backHref}>{t('scaffold.run.gate.back') as string}</a>
      </div>
    </section>
  );
}

// ---- blocked ----
function Blocked({ c, t }: { c: RunViewProps; t: TFn }) {
  return (
    <section class="run-card run-blocked">
      <p class="run-blocked-note">{t(`scaffold.run.blocked.${c.blocked?.code}`) as string}</p>
      <div class="run-actions">
        <a class="cta-link cta-link--main" href={c.blocked?.href}>{t('scaffold.run.blocked.action') as string}</a>
      </div>
    </section>
  );
}

// ---- main content ----
function MainContent({ c, t }: { c: RunViewProps; t: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <div class="run-body">
        <Banner c={c} t={t} />
        {c.isBlocked ? (
          <Blocked c={c} t={t} />
        ) : (
          <Fragment>
            <InputSummary c={c} t={t} />
            {c.isPre ? (
              <Gate c={c} t={t} />
            ) : c.isFailed ? (
              <Fragment>
                <Failure c={c} t={t} />
                <Writes c={c} t={t} />
              </Fragment>
            ) : (
              <Fragment>
                <Writes c={c} t={t} />
                <Sidecar c={c} t={t} />
                {c.hasWarnings && <Warnings c={c} t={t} />}
                <div class="run-actions run-next">
                  <a class="cta-link cta-link--main" href="/build">{t('scaffold.run.next.build') as string}</a>
                </div>
              </Fragment>
            )}
          </Fragment>
        )}
      </div>
    </section>
  );
}

// ---- panels ----
function renderPanels(c: RunViewProps) {
  return <Panels c={c} t={c.t}>{MainContent({ c, t: c.t })}</Panels>;
}

// ---- Fragment response ----
export function PanelsSwap(c: RunViewProps) {
  return renderPanels(c);
}

// ---- Page ----
const RunView: FC<RunViewProps> = (props) => (
  <MainShellView
    title={props.t('scaffold.run.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'scaffold'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop shell-main-scaffold-run"
    headerExtra={<AccountChip c={props} t={props.t} />}
    surface={
      <Fragment>
        <link rel="stylesheet" href="/assets/css/scaffold-run.css" />
        {renderPanels(props)}
      </Fragment>
    }
    t={props.t}
  />
);

export default RunView;
