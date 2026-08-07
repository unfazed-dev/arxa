// picker_view.tsx — scaffold.picker, the kit picker (replaces picker_view.html).
// Every kit on this grid is here for a reason, legible before you touch anything.
// Three independent axes (provenance / maturity / readiness) each get their own chip.
// No client-side JS: mutations are form posts or hx-get, the whole grid swaps as one.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import { Panels, AccountChip, type ScaffoldCtx } from '../_shared.tsx';
import { CtaLink } from '../../../../common/widgets/primitives.tsx';
import Icon from '../../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Kit {
  id: string;
  package?: string;
  provenance: string;
  confidence?: string;
  evidenceScreen?: string;
  declaredBy?: string[];
  phase: string;
  maturityAxis: { native?: boolean };
  readinessAxis: { ready?: boolean; state?: string; count?: number };
  selected?: boolean;
  auto?: boolean;
  locked?: boolean;
  essential?: boolean;
  requiredBy?: string[];
  credentialsHref?: string;
}

interface KitGroup {
  id: string;
  label: string;
  selectedCount?: number;
  count?: number;
  kits: Kit[];
}

interface ManifestItem { id: string; auto?: boolean; }

interface ConfirmState {
  kit: { id: string };
  blockedBy?: string[];
  screens?: string[];
  forcesFallback?: boolean;
  confirmHref: string;
  cancelHref: string;
}

interface PickerViewProps extends ScaffoldCtx {
  t: TFn;
  locale?: string;
  locales?: string[];
  prefs?: { accent?: string; [key: string]: unknown };
  activeShell?: string;
  base?: string;
  gated?: boolean;
  gatedReason?: string;
  counts?: { selected?: number; total?: number; declared?: number; inferred?: number; requested?: number; auto?: number; unready?: number };
  groups?: KitGroup[];
  loading?: boolean;
  error?: { retryHref?: string };
  state?: string;
  autoNotice?: { id: string }[];
  confirm?: ConfirmState;
  manifest?: { resolved?: ManifestItem[]; wishlist?: string[]; todos?: { id: string }[] };
  canContinue?: boolean;
  continueHref?: string;
  entitlement?: { ctaHref?: string; signedIn?: boolean; entitled?: boolean; accountHref?: string; plan?: string };
}

// ---- axis 1: provenance (D4) ----
function ProvChip({ k, t }: { k: Kit; t: TFn }) {
  const title = k.provenance === 'inferred'
    ? t('scaffold.picker.prov.inferred.why', { screen: k.evidenceScreen }) as string
    : k.provenance === 'declared'
      ? t('scaffold.picker.prov.declared.why') as string
      : t('scaffold.picker.prov.requested.why') as string;
  return (
    <span class={`chip prov-chip prov-${k.provenance}`} title={title}>
      <Icon name={k.provenance === 'inferred' ? 'sparkles' : k.provenance === 'declared' ? 'file-check' : 'hand'} size={13} />
      {' '}{t(`scaffold.picker.prov.${k.provenance}`) as string}
      {k.confidence && <Fragment> <span class="prov-conf">{t(`scaffold.picker.prov.confidence.${k.confidence}`) as string}</span></Fragment>}
    </span>
  );
}

// ---- axis 2: maturity ----
function MaturityChip({ k, t }: { k: Kit; t: TFn }) {
  return (
    <span
      class={`chip chip--sm kit-maturity kit-maturity--${k.phase.replace('/', '-')}`}
      title={k.maturityAxis?.native ? t('scaffold.picker.maturity.note') as string : ''}
    >
      <Icon name={k.maturityAxis?.native ? 'smartphone' : 'package'} size={13} />
      {' '}{t(`scaffold.picker.maturity.${k.phase === 'n/a' ? 'na' : k.phase}`) as string}
    </span>
  );
}

// ---- axis 3: readiness (D6 — inform only, never a gate) ----
function ReadinessChip({ k, t }: { k: Kit; t: TFn }) {
  if (k.readinessAxis?.ready) return null;
  return (
    <span
      class={`chip chip--sm kit-readiness kit-readiness--${k.readinessAxis?.state}`}
      title={t('scaffold.picker.readiness.informOnly') as string}
    >
      <Icon name="key-round" size={13} />
      {' '}{t('scaffold.picker.readiness.missingCount', { count: k.readinessAxis?.count }) as string}
    </span>
  );
}

// ---- the kit card ----
function KitCard({ c, k, t }: { c: PickerViewProps; k: Kit; t: TFn }) {
  return (
    <article
      class={`artifact kit-card${k.selected ? ' is-on' : ''}${k.auto ? ' is-auto' : ''}${k.locked ? ' is-locked' : ''}`}
      id={`kit-${k.id}`}
    >
      <header class="artifact-head kit-head">
        <h3 class="kit-name">{k.id}</h3>
        <code class="kit-pkg">{k.package}</code>
      </header>

      <div class="kit-axes">
        <ProvChip k={k} t={t} />
        <MaturityChip k={k} t={t} />
        <ReadinessChip k={k} t={t} />
      </div>

      {k.provenance === 'declared' && k.declaredBy?.length ? (
        <p class="kit-why">
          <Icon name="link" size={13} /> {t('scaffold.picker.confirm.declared', { screens: k.declaredBy.join(', ') }) as string}
        </p>
      ) : k.provenance === 'inferred' ? (
        <p class="kit-why">
          <Icon name="sparkles" size={13} /> {t('scaffold.picker.prov.inferred.why', { screen: k.evidenceScreen }) as string}
        </p>
      ) : null}

      {!k.readinessAxis?.ready && (
        <p class="kit-keys">
          <span class="muted">{t('scaffold.picker.readiness.informOnly') as string}</span>
          {' '}
          <CtaLink href={k.credentialsHref ?? '#'} label={t('scaffold.picker.readiness.add') as string} glyph="chevron-right" variant="" size={13} />
        </p>
      )}

      <footer class="kit-foot">
        {k.essential ? (
          <span class="chip chip--muted"><Icon name="lock" size={13} /> {t('scaffold.picker.essential') as string}</span>
        ) : k.auto ? (
          <span class="chip chip--muted" title={t('scaffold.picker.auto.why', { kits: (k.requiredBy ?? []).join(', ') }) as string}>
            <Icon name="git-merge" size={13} /> {t('scaffold.picker.auto') as string}
          </span>
        ) : c.gated ? (
          <span class="chip chip--muted"><Icon name="eye" size={13} /> {t('scaffold.picker.gated.badge') as string}</span>
        ) : k.selected ? (
          <form method="post" action={`${c.base}/remove`} hx-post={`${c.base}/remove`} hx-target="#picker-grid" hx-swap="outerHTML">
            <input type="hidden" name="kit" value={k.id} />
            <button type="submit" class="cta-ghost kit-toggle is-on">
              <Icon name="check" size={14} /> {t('scaffold.picker.added') as string}
            </button>
          </form>
        ) : (
          <form method="post" action={`${c.base}/add`} hx-post={`${c.base}/add`} hx-target="#picker-grid" hx-swap="outerHTML">
            <input type="hidden" name="kit" value={k.id} />
            <button type="submit" class="cta-ghost kit-toggle">
              <Icon name="plus" size={14} /> {t('scaffold.picker.add') as string}
            </button>
          </form>
        )}
      </footer>
    </article>
  );
}

// ---- D5 notice: auto-pulled kits ----
function AutoNotice({ c, t }: { c: PickerViewProps; t: TFn }) {
  if (!c.autoNotice?.length) return null;
  return (
    <aside class="picker-notice picker-notice--auto">
      <h4 class="fact-label"><Icon name="git-merge" size={14} /> {t('scaffold.picker.autoNotice.title') as string}</h4>
      <p>{t('scaffold.picker.autoNotice.body') as string}</p>
      <p class="notice-kits">
        {c.autoNotice.map((k) => <a key={k.id} class="chip chip--accent" href={`#kit-${k.id}`}>{k.id}</a>)}
      </p>
    </aside>
  );
}

// ---- D2: remove-with-forced-fallback confirm ----
function RemoveConfirm({ c, t }: { c: PickerViewProps; t: TFn }) {
  if (!c.confirm) return null;
  const cf = c.confirm;
  return (
    <aside class="picker-confirm" role="alertdialog" aria-labelledby="confirm-title">
      <h3 class="display" id="confirm-title">{t('scaffold.picker.confirm.title', { kit: cf.kit.id }) as string}</h3>
      {cf.blockedBy?.length ? (
        <Fragment>
          <p class="confirm-blocked">
            <Icon name="circle-alert" size={14} /> {t('scaffold.picker.confirm.blocked', { kits: cf.blockedBy.join(', ') }) as string}
          </p>
          <form method="post" action={cf.cancelHref} hx-post={cf.cancelHref} hx-target="#picker-grid" hx-swap="outerHTML">
            <button type="submit" class="cta-ghost">
              <Icon name="chevron-left" size={14} /> {t('scaffold.picker.confirm.cancel') as string}
            </button>
          </form>
        </Fragment>
      ) : (
        <Fragment>
          {cf.screens?.length ? (
            <p>{t('scaffold.picker.confirm.declared', { screens: cf.screens.join(', ') }) as string}</p>
          ) : null}
          {cf.forcesFallback && (
            <p class="confirm-fallback">
              <Icon name="shield" size={14} /> {t('scaffold.picker.confirm.fallback') as string}
            </p>
          )}
          <div class="confirm-actions">
            <form method="post" action={cf.confirmHref} hx-post={cf.confirmHref} hx-target="#panels" hx-swap="morph:outerHTML">
              <button type="submit" class="cta-ghost is-destructive">{t('scaffold.picker.confirm.yes') as string}</button>
            </form>
            <form method="post" action={cf.cancelHref} hx-post={cf.cancelHref} hx-target="#picker-grid" hx-swap="outerHTML">
              <button type="submit" class="cta-ghost">{t('scaffold.picker.confirm.cancel') as string}</button>
            </form>
          </div>
        </Fragment>
      )}
    </aside>
  );
}

// ---- signed-out / not-entitled ----
function GatedNotice({ c, t }: { c: PickerViewProps; t: TFn }) {
  const k = `scaffold.picker.gated.${c.gatedReason || 'notEntitled'}`;
  return (
    <aside class="picker-notice picker-notice--gated" data-gated={c.gatedReason}>
      <h4 class="fact-label"><Icon name="lock" size={14} /> {t(`${k}.title`) as string}</h4>
      <p>{t(`${k}.body`) as string}</p>
      <CtaLink href={c.entitlement?.ctaHref ?? '#'} label={t(`${k}.cta`) as string} glyph="chevron-right" variant="main" />
    </aside>
  );
}

// ---- D8: the kit-manifest.json receipt ----
function ManifestPanel({ c, t }: { c: PickerViewProps; t: TFn }) {
  return (
    <section class="picker-manifest">
      <h4 class="fact-label"><Icon name="file-json" size={14} /> {t('scaffold.picker.manifest.title') as string}</h4>
      <p class="muted">{t('scaffold.picker.manifest.lede') as string}</p>
      <dl class="manifest-facts">
        <dt>{t('scaffold.picker.manifest.resolved') as string}</dt>
        <dd>
          {(c.manifest?.resolved ?? []).map((r) => (
            <span class={`chip chip--sm${r.auto ? ' chip--muted' : ''}`} key={r.id}>{r.id}</span>
          ))}
        </dd>
        {c.manifest?.wishlist?.length ? (
          <Fragment>
            <dt>{t('scaffold.picker.manifest.wishlist') as string}</dt>
            <dd>{c.manifest.wishlist.map((w) => <span class="chip chip--sm chip--muted" key={w}>{w}</span>)}</dd>
          </Fragment>
        ) : null}
        {c.manifest?.todos?.length ? (
          <Fragment>
            <dt>{t('scaffold.picker.manifest.todos') as string}</dt>
            <dd>{c.manifest.todos.map((td) => <span class="chip chip--sm kit-readiness kit-readiness--missing-keys" key={td.id}>{td.id}</span>)}</dd>
          </Fragment>
        ) : null}
      </dl>
    </section>
  );
}

// ---- the grid: one swappable fragment ----
function PickerGrid({ c, t }: { c: PickerViewProps; t: TFn }) {
  return (
    <div class="picker-grid" id="picker-grid">
      {c.loading ? (
        <p class="picker-loading" aria-busy="true"><Icon name="loader" size={16} /> {t('scaffold.picker.loading') as string}</p>
      ) : c.error ? (
        <aside class="picker-notice picker-notice--error" role="alert">
          <h4 class="fact-label"><Icon name="circle-alert" size={14} /> {t('scaffold.picker.error.title') as string}</h4>
          <p>{t('scaffold.picker.error.body') as string}</p>
          <CtaLink href={c.error.retryHref ?? '#'} label={t('scaffold.picker.error.retry') as string} glyph="refresh-cw" variant="main" />
        </aside>
      ) : (
        <Fragment>
          {c.state === 'empty' && (
            <aside class="picker-notice">
              <h4 class="fact-label">{t('scaffold.picker.empty.title') as string}</h4>
              <p>{t('scaffold.picker.empty.body') as string}</p>
            </aside>
          )}
          <AutoNotice c={c} t={t} />
          <RemoveConfirm c={c} t={t} />
          {(c.groups ?? []).map((g) => (
            <section class="kit-group" id={`group-${g.id}`} key={g.id}>
              <h3 class="fact-label kit-group-head">
                {g.label}
                <span class="chip chip--sm chip--muted">{t('scaffold.picker.groupCount', { selected: g.selectedCount, count: g.count }) as string}</span>
              </h3>
              <div class="kit-cards">
                {g.kits.map((k) => <KitCard key={k.id} c={c} k={k} t={t} />)}
              </div>
            </section>
          ))}
        </Fragment>
      )}
    </div>
  );
}

// ---- the stage ----
function MainContent({ c, t }: { c: PickerViewProps; t: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <div class="picker-stage">
        <header class="picker-head">
          <h1 class="display">{t('scaffold.picker.pageTitle') as string}</h1>
          <p class="artifact-lede">{t('scaffold.picker.lede') as string}</p>
          <p class="picker-counts">
            <span class="chip chip--accent">{t('scaffold.picker.selectedCount', { selected: c.counts?.selected, total: c.counts?.total }) as string}</span>
            <span class="chip chip--muted">{t('scaffold.picker.summary', { declared: c.counts?.declared, inferred: c.counts?.inferred, requested: c.counts?.requested }) as string}</span>
            {c.counts?.auto ? <span class="chip chip--muted">{t('scaffold.picker.autoCount', { count: c.counts.auto }) as string}</span> : null}
            {c.counts?.unready ? <span class="chip chip--sm kit-readiness kit-readiness--missing-keys">{t('scaffold.picker.unreadyCount', { count: c.counts.unready }) as string}</span> : null}
          </p>
        </header>

        {c.gated && <GatedNotice c={c} t={t} />}
        <PickerGrid c={c} t={t} />
        <ManifestPanel c={c} t={t} />

        <footer class="picker-foot">
          {c.canContinue ? (
            <CtaLink href={c.continueHref ?? '#'} label={t('scaffold.picker.continue') as string} glyph="chevron-right" variant="main" />
          ) : (
            <span class="cta-main is-disabled" aria-disabled="true">{t('scaffold.picker.continue.blocked') as string}</span>
          )}
        </footer>
      </div>
    </section>
  );
}

// ---- panels (fills the shell's main panel via children) ----
function renderPanels(c: PickerViewProps) {
  return <Panels c={c} t={c.t}>{MainContent({ c, t: c.t })}</Panels>;
}

// ---- Fragment responses ----
export function PanelsSwap(c: PickerViewProps) {
  return renderPanels(c);
}

export function GridSwap(c: PickerViewProps) {
  return PickerGrid({ c, t: c.t });
}

// ---- Page ----
const PickerView: FC<PickerViewProps> = (props) => (
  <MainShellView
    title={props.t('scaffold.picker.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'scaffold'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop shell-main-picker"
    headerExtra={<AccountChip c={props} t={props.t} />}
    surface={
      <Fragment>
        <link rel="stylesheet" href="/assets/css/scaffold-picker.css" />
        {renderPanels(props)}
      </Fragment>
    }
    t={props.t}
  />
);

export default PickerView;
