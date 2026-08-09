// run_view.tsx — scaffold.run, the scaffold execution RECEIPT (replaces run_view.html).
// NOT a progress screen — scaffolding is a synchronous millisecond transform of an
// already-frozen structure.json. Five read states, no sixth "running" one.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import { Panels, AccountChip, type ScaffoldCtx } from '../shared.tsx';
import { inspectAttrs, Label, Txt } from '../../../../common/widgets/primitives.tsx';
import Icon from '../../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface RunKit { id: string; ready?: boolean; auto?: boolean; }
interface RunWrite { kind?: string; path?: string; ready?: boolean; }
interface RunWarning { code?: string; kitId?: string; href?: string; }

interface RunViewProps extends ScaffoldCtx {
  translate: TFn;
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
function Banner({ context, translate }: { context: RunViewProps; translate: TFn }) {
  const icon = context.isDone && !context.hasWarnings ? 'file-check'
    : context.hasWarnings ? 'alert-triangle'
    : context.isFailed ? 'x-octagon'
    : context.isBlocked ? 'lock'
    : 'play';
  return (
    <div class={`run-banner run-banner--${context.state}`} role="status">
      <span class="run-banner-icon"><Icon name={icon} size={18} /></span>
      <div class="run-banner-text">
        <Txt name="scaffold.run:banner-title" class="run-banner-title">{translate(`scaffold.run.state.${context.state}.title`) as string}</Txt>
        <Txt name="scaffold.run:banner-note" class="run-banner-note">{translate(`scaffold.run.state.${context.state}.note`) as string}</Txt>
      </div>
    </div>
  );
}

// ---- the input summary ----
function InputSummary({ context, translate }: { context: RunViewProps; translate: TFn }) {
  return (
    <section class="run-card run-input" aria-labelledby="run-input-h">
      <h3 class="run-card-h" id="run-input-h" {...inspectAttrs('scaffold.run:input-heading', { role: 'heading' })}>{translate('scaffold.run.input.heading') as string}</h3>
      <dl class="run-facts">
        <div class="run-fact">
          <dt {...inspectAttrs('scaffold.run:fact-structure', { role: 'label' })}>{translate('scaffold.run.input.structure') as string}</dt>
          <dd>
            <code class="run-path" {...inspectAttrs('scaffold.run:structure-path', { role: 'text' })}>{context.structure?.path}</code>
            <span class="chip chip--sm run-frozen" {...inspectAttrs('scaffold.run:structure-frozen', { role: 'label' })}>
              <Icon name="lock" size={12} /> {translate('scaffold.run.input.frozen', { revision: context.structure?.revision }) as string}
            </span>
          </dd>
        </div>
        <div class="run-fact">
          <dt {...inspectAttrs('scaffold.run:fact-scope', { role: 'label' })}>{translate('scaffold.run.input.scope') as string}</dt>
          <dd {...inspectAttrs('scaffold.run:fact-scope-value', { role: 'text' })}>{translate('scaffold.run.input.scopeValue', { screens: context.structure?.screens, shells: context.structure?.shells }) as string}</dd>
        </div>
        <div class="run-fact">
          <dt {...inspectAttrs('scaffold.run:fact-kits', { role: 'label' })}>{translate('scaffold.run.input.kits') as string}</dt>
          <dd {...inspectAttrs('scaffold.run:fact-kits-value', { role: 'text' })}>{translate('scaffold.run.input.kitsValue', { count: context.counts?.kits }) as string}</dd>
        </div>
      </dl>
      <ul class="run-kitset" {...inspectAttrs('scaffold.run:kitset', { role: 'list' })}>
        {(context.kits ?? []).map((kit) => (
          <li key={kit.id} class={`chip run-kit${!kit.ready ? ' run-kit--unready' : ''}`}>
            <Label name="scaffold.run:kit-name" class="run-kit-name">{translate(`scaffold.kit.${kit.id}`) as string}</Label>
            {kit.auto && <Label name="scaffold.run:kit-auto" class="chip chip--sm run-kit-auto">{translate('scaffold.run.kit.auto') as string}</Label>}
            {!kit.ready && <Label name="scaffold.run:kit-keys" class="chip chip--sm run-kit-keys">{translate('scaffold.run.kit.needsKeys') as string}</Label>}
          </li>
        ))}
      </ul>
    </section>
  );
}

// ---- the gate (pre) ----
function Gate({ context, translate }: { context: RunViewProps; translate: TFn }) {
  return (
    <section class="run-card run-gate">
      <Txt name="scaffold.run:gate-note" class="run-gate-note">{translate('scaffold.run.gate.note') as string}</Txt>
      <div class="run-actions">
        <a class="cta-link cta-link--main" href={context.runHref} {...inspectAttrs('scaffold.run:gate-run', { role: 'action' })}>
          <Icon name="play" size={14} /> {translate('scaffold.run.gate.action') as string}
        </a>
        <a class="cta-link cta-link--ghost" href={context.backHref} {...inspectAttrs('scaffold.run:gate-back', { role: 'action' })}>{translate('scaffold.run.gate.back') as string}</a>
      </div>
    </section>
  );
}

// ---- what landed ----
function Writes({ context, translate }: { context: RunViewProps; translate: TFn }) {
  return (
    <section class="run-card run-writes" aria-labelledby="run-writes-h">
      <h3 class="run-card-h" id="run-writes-h" {...inspectAttrs('scaffold.run:writes-heading', { role: 'heading' })}>{translate('scaffold.run.writes.heading') as string}</h3>
      <Txt name="scaffold.run:writes-counts" class="run-counts">
        {translate('scaffold.run.writes.counts', { created: context.counts?.created, updated: context.counts?.updated, skipped: context.counts?.skipped }) as string}
      </Txt>
      <ul class="run-filelist" {...inspectAttrs('scaffold.run:filelist', { role: 'list' })}>
        {(context.writes ?? []).map((write, index) => (
          <li key={index} class={`run-file run-file--${write.kind}`}>
            <Label name="scaffold.run:file-kind" class="run-file-kind">{translate(`scaffold.run.writes.kind.${write.kind}`) as string}</Label>
            <code class="run-path" {...inspectAttrs('scaffold.run:file-path', { role: 'text' })}>{write.path}</code>
            {!write.ready && <Label name="scaffold.run:file-keys" class="chip chip--sm run-kit-keys">{translate('scaffold.run.kit.needsKeys') as string}</Label>}
          </li>
        ))}
      </ul>
    </section>
  );
}

// ---- the manifest sidecar (D8) ----
function Sidecar({ context, translate }: { context: RunViewProps; translate: TFn }) {
  return (
    <section class="run-card run-sidecar" aria-labelledby="run-sidecar-h">
      <h3 class="run-card-h" id="run-sidecar-h" {...inspectAttrs('scaffold.run:sidecar-heading', { role: 'heading' })}>{translate('scaffold.run.manifest.heading') as string}</h3>
      <p class="run-sidecar-line">
        <code class="run-path" {...inspectAttrs('scaffold.run:manifest-path', { role: 'text' })}>{context.manifest?.path}</code>
        <Label name="scaffold.run:manifest-beside" class="run-beside">{translate('scaffold.run.manifest.beside', { path: context.manifest?.beside }) as string}</Label>
      </p>
      <ul class="run-sections" {...inspectAttrs('scaffold.run:sections', { role: 'list' })}>
        {(context.manifest?.sections ?? []).map((section) => (
          <li key={section} {...inspectAttrs('scaffold.run:section', { role: 'list row' })}>{translate(`scaffold.run.manifest.section.${section}`) as string}</li>
        ))}
      </ul>
      <dl class="run-facts run-deltas">
        <div class="run-fact">
          <dt><code class="run-path" {...inspectAttrs('scaffold.run:delta-structure-path', { role: 'text' })}>{context.deltas?.structure?.path}</code></dt>
          <dd {...inspectAttrs('scaffold.run:delta-untouched', { role: 'text' })}>{translate('scaffold.run.delta.untouched') as string}</dd>
        </div>
        <div class="run-fact">
          <dt><code class="run-path" {...inspectAttrs('scaffold.run:delta-registry-path', { role: 'text' })}>{context.deltas?.registry?.path}</code></dt>
          <dd {...inspectAttrs('scaffold.run:delta-counts', { role: 'text' })}>{translate('scaffold.run.delta.counts', { added: context.deltas?.registry?.added, changed: context.deltas?.registry?.changed }) as string}</dd>
        </div>
      </dl>
    </section>
  );
}

// ---- readiness warnings (D6 — inform only) ----
function Warnings({ context, translate }: { context: RunViewProps; translate: TFn }) {
  return (
    <section class="run-card run-warnings" aria-labelledby="run-warn-h">
      <h3 class="run-card-h" id="run-warn-h" {...inspectAttrs('scaffold.run:warn-heading', { role: 'heading' })}>{translate('scaffold.run.warn.heading') as string}</h3>
      <Txt name="scaffold.run:warn-note" class="run-warn-note">{translate('scaffold.run.warn.note') as string}</Txt>
      <ul class="run-warnlist" {...inspectAttrs('scaffold.run:warnlist', { role: 'list' })}>
        {(context.warnings ?? []).map((warning, index) => (
          <li key={index} class="run-warn">
            <Icon name="alert-triangle" size={13} />
            <Label name="scaffold.run:warn-text">{translate(`scaffold.run.warn.${warning.code}`, { kit: translate(`scaffold.kit.${warning.kitId}`) }) as string}</Label>
            <a class="bt-link" href={warning.href} {...inspectAttrs('scaffold.run:warn-fix', { role: 'action' })}>{translate('scaffold.run.warn.fix') as string}</a>
          </li>
        ))}
      </ul>
    </section>
  );
}

// ---- failure ----
function Failure({ context, translate }: { context: RunViewProps; translate: TFn }) {
  return (
    <section class="run-card run-failure" aria-labelledby="run-fail-h">
      <h3 class="run-card-h" id="run-fail-h" {...inspectAttrs('scaffold.run:fail-heading', { role: 'heading' })}>{translate('scaffold.run.fail.heading') as string}</h3>
      <Txt name="scaffold.run:fail-reason" class="run-fail-reason">{translate(`scaffold.run.fail.${context.failure?.code}`) as string}</Txt>
      <p class="run-fail-path"><code class="run-path" {...inspectAttrs('scaffold.run:fail-path', { role: 'text' })}>{context.failure?.path}</code></p>
      {context.failure?.rolledBack && (
        <Txt name="scaffold.run:fail-rollback" class="run-fail-rollback">{translate('scaffold.run.fail.rolledBack', { count: context.failure.wrote }) as string}</Txt>
      )}
      <div class="run-actions">
        <a class="cta-link cta-link--main" href={context.failure?.retryHref} {...inspectAttrs('scaffold.run:fail-retry', { role: 'action' })}>{translate('scaffold.run.fail.retry') as string}</a>
        <a class="cta-link cta-link--ghost" href={context.backHref} {...inspectAttrs('scaffold.run:fail-back', { role: 'action' })}>{translate('scaffold.run.gate.back') as string}</a>
      </div>
    </section>
  );
}

// ---- blocked ----
function Blocked({ context, translate }: { context: RunViewProps; translate: TFn }) {
  return (
    <section class="run-card run-blocked">
      <Txt name="scaffold.run:blocked-note" class="run-blocked-note">{translate(`scaffold.run.blocked.${context.blocked?.code}`) as string}</Txt>
      <div class="run-actions">
        <a class="cta-link cta-link--main" href={context.blocked?.href} {...inspectAttrs('scaffold.run:blocked-action', { role: 'action' })}>{translate('scaffold.run.blocked.action') as string}</a>
      </div>
    </section>
  );
}

// ---- main content ----
function MainContent({ context, translate }: { context: RunViewProps; translate: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <div class="run-body" {...inspectAttrs('scaffold.run:body', { role: 'group' })}>
        <Banner context={context} translate={translate} />
        {context.isBlocked ? (
          <Blocked context={context} translate={translate} />
        ) : (
          <Fragment>
            <InputSummary context={context} translate={translate} />
            {context.isPre ? (
              <Gate context={context} translate={translate} />
            ) : context.isFailed ? (
              <Fragment>
                <Failure context={context} translate={translate} />
                <Writes context={context} translate={translate} />
              </Fragment>
            ) : (
              <Fragment>
                <Writes context={context} translate={translate} />
                <Sidecar context={context} translate={translate} />
                {context.hasWarnings && <Warnings context={context} translate={translate} />}
                <div class="run-actions run-next">
                  <a class="cta-link cta-link--main" href="/build" {...inspectAttrs('scaffold.run:next-build', { role: 'action' })}>{translate('scaffold.run.next.build') as string}</a>
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
function renderPanels(context: RunViewProps) {
  return <Panels context={context} translate={context.translate}>{MainContent({ context, translate: context.translate })}</Panels>;
}

// ---- Fragment response ----
export function PanelsSwap(context: RunViewProps) {
  return renderPanels(context);
}

// ---- Page ----
const RunView: FC<RunViewProps> = (props) => (
  <MainShellView
    title={props.translate('scaffold.run.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'scaffold'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop shell-main-scaffold-run"
    headerExtra={<AccountChip context={props} translate={props.translate} />}
    surface={
      <Fragment>
        <link rel="stylesheet" href="/assets/css/scaffold-run.css" />
        {renderPanels(props)}
      </Fragment>
    }
    translate={props.translate}
  />
);

export default RunView;
