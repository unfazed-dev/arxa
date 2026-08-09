// picker_view.tsx — scaffold.picker, the kit picker (replaces picker_view.html).
// Every kit on this grid is here for a reason, legible before you touch anything.
// Three independent axes (provenance / maturity / readiness) each get their own chip.
// No client-side JS: mutations are form posts or hx-get, the whole grid swaps as one.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import { Panels, AccountChip, type ScaffoldCtx } from '../_shared.tsx';
import { CtaLink, inspectAttrs, Label, Heading, Txt } from '../../../../common/widgets/primitives.tsx';
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
  translate: TFn;
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
function ProvChip({ k, translate }: { k: Kit; translate: TFn }) {
  const title = k.provenance === 'inferred'
    ? translate('scaffold.picker.prov.inferred.why', { screen: k.evidenceScreen }) as string
    : k.provenance === 'declared'
      ? translate('scaffold.picker.prov.declared.why') as string
      : translate('scaffold.picker.prov.requested.why') as string;
  return (
    <span class={`chip prov-chip prov-${k.provenance}`} title={title} {...inspectAttrs('scaffold.picker:prov-chip', { role: 'label' })}>
      <Icon name={k.provenance === 'inferred' ? 'sparkles' : k.provenance === 'declared' ? 'file-check' : 'hand'} size={13} />
      {' '}{translate(`scaffold.picker.prov.${k.provenance}`) as string}
      {k.confidence && <Fragment> <Label name="scaffold.picker:prov-conf" class="prov-conf">{translate(`scaffold.picker.prov.confidence.${k.confidence}`) as string}</Label></Fragment>}
    </span>
  );
}

// ---- axis 2: maturity ----
function MaturityChip({ k, translate }: { k: Kit; translate: TFn }) {
  return (
    <span
      class={`chip chip--sm kit-maturity kit-maturity--${k.phase.replace('/', '-')}`}
      title={k.maturityAxis?.native ? translate('scaffold.picker.maturity.note') as string : ''}
      {...inspectAttrs('scaffold.picker:maturity-chip', { role: 'label' })}
    >
      <Icon name={k.maturityAxis?.native ? 'smartphone' : 'package'} size={13} />
      {' '}{translate(`scaffold.picker.maturity.${k.phase === 'n/a' ? 'na' : k.phase}`) as string}
    </span>
  );
}

// ---- axis 3: readiness (D6 — inform only, never a gate) ----
function ReadinessChip({ k, translate }: { k: Kit; translate: TFn }) {
  if (k.readinessAxis?.ready) return null;
  return (
    <span
      class={`chip chip--sm kit-readiness kit-readiness--${k.readinessAxis?.state}`}
      title={translate('scaffold.picker.readiness.informOnly') as string}
      {...inspectAttrs('scaffold.picker:readiness-chip', { role: 'label' })}
    >
      <Icon name="key-round" size={13} />
      {' '}{translate('scaffold.picker.readiness.missingCount', { count: k.readinessAxis?.count }) as string}
    </span>
  );
}

// ---- the kit card ----
function KitCard({ c, k, translate }: { c: PickerViewProps; k: Kit; translate: TFn }) {
  return (
    <article
      class={`artifact kit-card${k.selected ? ' is-on' : ''}${k.auto ? ' is-auto' : ''}${k.locked ? ' is-locked' : ''}`}
      id={`kit-${k.id}`}
    >
      <header class="artifact-head kit-head">
        <Heading name="scaffold.picker:kit-name" level={3} class="kit-name">{k.id}</Heading>
        <code class="kit-pkg" {...inspectAttrs('scaffold.picker:kit-pkg', { role: 'text' })}>{k.package}</code>
      </header>

      <div class="kit-axes">
        <ProvChip k={k} translate={translate} />
        <MaturityChip k={k} translate={translate} />
        <ReadinessChip k={k} translate={translate} />
      </div>

      {k.provenance === 'declared' && k.declaredBy?.length ? (
        <Txt name="scaffold.picker:kit-why-declared" class="kit-why">
          <Icon name="link" size={13} /> {translate('scaffold.picker.confirm.declared', { screens: k.declaredBy.join(', ') }) as string}
        </Txt>
      ) : k.provenance === 'inferred' ? (
        <Txt name="scaffold.picker:kit-why-inferred" class="kit-why">
          <Icon name="sparkles" size={13} /> {translate('scaffold.picker.prov.inferred.why', { screen: k.evidenceScreen }) as string}
        </Txt>
      ) : null}

      {!k.readinessAxis?.ready && (
        <p class="kit-keys">
          <Label name="scaffold.picker:keys-note" class="muted">{translate('scaffold.picker.readiness.informOnly') as string}</Label>
          {' '}
          <CtaLink href={k.credentialsHref ?? '#'} label={translate('scaffold.picker.readiness.add') as string} glyph="chevron-right" variant="" size={13} />
        </p>
      )}

      <footer class="kit-foot" {...inspectAttrs('scaffold.picker:kit-foot', { role: 'group' })}>
        {k.essential ? (
          <span class="chip chip--muted" {...inspectAttrs('scaffold.picker:essential-badge', { role: 'label' })}><Icon name="lock" size={13} /> {translate('scaffold.picker.essential') as string}</span>
        ) : k.auto ? (
          <span class="chip chip--muted" title={translate('scaffold.picker.auto.why', { kits: (k.requiredBy ?? []).join(', ') }) as string} {...inspectAttrs('scaffold.picker:auto-badge', { role: 'label' })}>
            <Icon name="git-merge" size={13} /> {translate('scaffold.picker.auto') as string}
          </span>
        ) : c.gated ? (
          <span class="chip chip--muted" {...inspectAttrs('scaffold.picker:gated-badge', { role: 'label' })}><Icon name="eye" size={13} /> {translate('scaffold.picker.gated.badge') as string}</span>
        ) : k.selected ? (
          <form method="post" action={`${c.base}/remove`} hx-post={`${c.base}/remove`} hx-target="#picker-grid" hx-swap="outerHTML">
            <input type="hidden" name="kit" value={k.id} {...inspectAttrs('scaffold.picker:remove-input', { role: 'input' })} />
            <button type="submit" class="cta-ghost kit-toggle is-on" {...inspectAttrs('scaffold.picker:remove', { role: 'action' })}>
              <Icon name="check" size={14} /> {translate('scaffold.picker.added') as string}
            </button>
          </form>
        ) : (
          <form method="post" action={`${c.base}/add`} hx-post={`${c.base}/add`} hx-target="#picker-grid" hx-swap="outerHTML">
            <input type="hidden" name="kit" value={k.id} {...inspectAttrs('scaffold.picker:add-input', { role: 'input' })} />
            <button type="submit" class="cta-ghost kit-toggle" {...inspectAttrs('scaffold.picker:add', { role: 'action' })}>
              <Icon name="plus" size={14} /> {translate('scaffold.picker.add') as string}
            </button>
          </form>
        )}
      </footer>
    </article>
  );
}

// ---- D5 notice: auto-pulled kits ----
function AutoNotice({ c, translate }: { c: PickerViewProps; translate: TFn }) {
  if (!c.autoNotice?.length) return null;
  return (
    <aside class="picker-notice picker-notice--auto">
      <h4 class="fact-label" {...inspectAttrs('scaffold.picker:auto-notice-title', { role: 'heading' })}><Icon name="git-merge" size={14} /> {translate('scaffold.picker.autoNotice.title') as string}</h4>
      <Txt name="scaffold.picker:auto-notice-body">{translate('scaffold.picker.autoNotice.body') as string}</Txt>
      <Txt name="scaffold.picker:auto-notice-kits" class="notice-kits">
        {c.autoNotice.map((k) => <a key={k.id} class="chip chip--accent" href={`#kit-${k.id}`} {...inspectAttrs('scaffold.picker:auto-notice-kit', { role: 'action' })}>{k.id}</a>)}
      </Txt>
    </aside>
  );
}

// ---- D2: remove-with-forced-fallback confirm ----
function RemoveConfirm({ c, translate }: { c: PickerViewProps; translate: TFn }) {
  if (!c.confirm) return null;
  const cf = c.confirm;
  return (
    <aside class="picker-confirm" role="alertdialog" aria-labelledby="confirm-title">
      <h3 class="display" id="confirm-title" {...inspectAttrs('scaffold.picker:confirm-title', { role: 'heading' })}>{translate('scaffold.picker.confirm.title', { kit: cf.kit.id }) as string}</h3>
      {cf.blockedBy?.length ? (
        <Fragment>
          <Txt name="scaffold.picker:confirm-blocked" class="confirm-blocked">
            <Icon name="circle-alert" size={14} /> {translate('scaffold.picker.confirm.blocked', { kits: cf.blockedBy.join(', ') }) as string}
          </Txt>
          <form method="post" action={cf.cancelHref} hx-post={cf.cancelHref} hx-target="#picker-grid" hx-swap="outerHTML">
            <button type="submit" class="cta-ghost" {...inspectAttrs('scaffold.picker:confirm-cancel', { role: 'action' })}>
              <Icon name="chevron-left" size={14} /> {translate('scaffold.picker.confirm.cancel') as string}
            </button>
          </form>
        </Fragment>
      ) : (
        <Fragment>
          {cf.screens?.length ? (
            <Txt name="scaffold.picker:confirm-screens">{translate('scaffold.picker.confirm.declared', { screens: cf.screens.join(', ') }) as string}</Txt>
          ) : null}
          {cf.forcesFallback && (
            <Txt name="scaffold.picker:confirm-fallback" class="confirm-fallback">
              <Icon name="shield" size={14} /> {translate('scaffold.picker.confirm.fallback') as string}
            </Txt>
          )}
          <div class="confirm-actions">
            <form method="post" action={cf.confirmHref} hx-post={cf.confirmHref} hx-target="#panels" hx-swap="outerMorph">
              <button type="submit" class="cta-ghost is-destructive" {...inspectAttrs('scaffold.picker:confirm-yes', { role: 'action' })}>{translate('scaffold.picker.confirm.yes') as string}</button>
            </form>
            <form method="post" action={cf.cancelHref} hx-post={cf.cancelHref} hx-target="#picker-grid" hx-swap="outerHTML">
              <button type="submit" class="cta-ghost" {...inspectAttrs('scaffold.picker:confirm-cancel-alt', { role: 'action' })}>{translate('scaffold.picker.confirm.cancel') as string}</button>
            </form>
          </div>
        </Fragment>
      )}
    </aside>
  );
}

// ---- signed-out / not-entitled ----
function GatedNotice({ c, translate }: { c: PickerViewProps; translate: TFn }) {
  const k = `scaffold.picker.gated.${c.gatedReason || 'notEntitled'}`;
  return (
    <aside class="picker-notice picker-notice--gated" data-gated={c.gatedReason}>
      <h4 class="fact-label" {...inspectAttrs('scaffold.picker:gated-title', { role: 'heading' })}><Icon name="lock" size={14} /> {translate(`${k}.title`) as string}</h4>
      <Txt name="scaffold.picker:gated-body">{translate(`${k}.body`) as string}</Txt>
      <CtaLink href={c.entitlement?.ctaHref ?? '#'} label={translate(`${k}.cta`) as string} glyph="chevron-right" variant="main" />
    </aside>
  );
}

// ---- D8: the kit-manifest.json receipt ----
function ManifestPanel({ c, translate }: { c: PickerViewProps; translate: TFn }) {
  return (
    <section class="picker-manifest">
      <h4 class="fact-label" {...inspectAttrs('scaffold.picker:manifest-title', { role: 'heading' })}><Icon name="file-json" size={14} /> {translate('scaffold.picker.manifest.title') as string}</h4>
      <Txt name="scaffold.picker:manifest-lede" class="muted">{translate('scaffold.picker.manifest.lede') as string}</Txt>
      <dl class="manifest-facts">
        <dt {...inspectAttrs('scaffold.picker:manifest-resolved-label', { role: 'label' })}>{translate('scaffold.picker.manifest.resolved') as string}</dt>
        <dd {...inspectAttrs('scaffold.picker:manifest-resolved', { role: 'group' })}>
          {(c.manifest?.resolved ?? []).map((r) => (
            <Label name="scaffold.picker:resolved-kit" class={`chip chip--sm${r.auto ? ' chip--muted' : ''}`} key={r.id}>{r.id}</Label>
          ))}
        </dd>
        {c.manifest?.wishlist?.length ? (
          <Fragment>
            <dt {...inspectAttrs('scaffold.picker:manifest-wishlist-label', { role: 'label' })}>{translate('scaffold.picker.manifest.wishlist') as string}</dt>
            <dd {...inspectAttrs('scaffold.picker:manifest-wishlist', { role: 'group' })}>{c.manifest.wishlist.map((w) => <Label name="scaffold.picker:wishlist-kit" class="chip chip--sm chip--muted" key={w}>{w}</Label>)}</dd>
          </Fragment>
        ) : null}
        {c.manifest?.todos?.length ? (
          <Fragment>
            <dt {...inspectAttrs('scaffold.picker:manifest-todos-label', { role: 'label' })}>{translate('scaffold.picker.manifest.todos') as string}</dt>
            <dd {...inspectAttrs('scaffold.picker:manifest-todos', { role: 'group' })}>{c.manifest.todos.map((td) => <Label name="scaffold.picker:todo-kit" class="chip chip--sm kit-readiness kit-readiness--missing-keys" key={td.id}>{td.id}</Label>)}</dd>
          </Fragment>
        ) : null}
      </dl>
    </section>
  );
}

// ---- the grid: one swappable fragment ----
function PickerGrid({ c, translate }: { c: PickerViewProps; translate: TFn }) {
  return (
    <div class="picker-grid" id="picker-grid" {...inspectAttrs('scaffold.picker:grid', { role: 'group' })}>
      {c.loading ? (
        <p class="picker-loading" aria-busy="true" {...inspectAttrs('scaffold.picker:loading', { role: 'text' })}><Icon name="loader" size={16} /> {translate('scaffold.picker.loading') as string}</p>
      ) : c.error ? (
        <aside class="picker-notice picker-notice--error" role="alert">
          <h4 class="fact-label" {...inspectAttrs('scaffold.picker:error-title', { role: 'heading' })}><Icon name="circle-alert" size={14} /> {translate('scaffold.picker.error.title') as string}</h4>
          <Txt name="scaffold.picker:error-body">{translate('scaffold.picker.error.body') as string}</Txt>
          <CtaLink href={c.error.retryHref ?? '#'} label={translate('scaffold.picker.error.retry') as string} glyph="refresh-cw" variant="main" />
        </aside>
      ) : (
        <Fragment>
          {c.state === 'empty' && (
            <aside class="picker-notice">
              <h4 class="fact-label" {...inspectAttrs('scaffold.picker:empty-title', { role: 'heading' })}>{translate('scaffold.picker.empty.title') as string}</h4>
              <Txt name="scaffold.picker:empty-body">{translate('scaffold.picker.empty.body') as string}</Txt>
            </aside>
          )}
          <AutoNotice c={c} translate={translate} />
          <RemoveConfirm c={c} translate={translate} />
          {(c.groups ?? []).map((g) => (
            <section class="kit-group" id={`group-${g.id}`} key={g.id}>
              <h3 class="fact-label kit-group-head" {...inspectAttrs('scaffold.picker:group-head', { role: 'heading' })}>
                {g.label}
                <Label name="scaffold.picker:group-count" class="chip chip--sm chip--muted">{translate('scaffold.picker.groupCount', { selected: g.selectedCount, count: g.count }) as string}</Label>
              </h3>
              <div class="kit-cards" {...inspectAttrs('scaffold.picker:kit-cards', { role: 'group' })}>
                {g.kits.map((k) => <KitCard key={k.id} c={c} k={k} translate={translate} />)}
              </div>
            </section>
          ))}
        </Fragment>
      )}
    </div>
  );
}

// ---- the stage ----
function MainContent({ c, translate }: { c: PickerViewProps; translate: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <div class="picker-stage">
        <header class="picker-head">
          <Heading name="scaffold.picker:page-title" level={1} class="display">{translate('scaffold.picker.pageTitle') as string}</Heading>
          <Txt name="scaffold.picker:lede" class="artifact-lede">{translate('scaffold.picker.lede') as string}</Txt>
          <p class="picker-counts">
            <Label name="scaffold.picker:selected-count" class="chip chip--accent">{translate('scaffold.picker.selectedCount', { selected: c.counts?.selected, total: c.counts?.total }) as string}</Label>
            <Label name="scaffold.picker:summary" class="chip chip--muted">{translate('scaffold.picker.summary', { declared: c.counts?.declared, inferred: c.counts?.inferred, requested: c.counts?.requested }) as string}</Label>
            {c.counts?.auto ? <Label name="scaffold.picker:auto-count" class="chip chip--muted">{translate('scaffold.picker.autoCount', { count: c.counts.auto }) as string}</Label> : null}
            {c.counts?.unready ? <Label name="scaffold.picker:unready-count" class="chip chip--sm kit-readiness kit-readiness--missing-keys">{translate('scaffold.picker.unreadyCount', { count: c.counts.unready }) as string}</Label> : null}
          </p>
        </header>

        {c.gated && <GatedNotice c={c} translate={translate} />}
        <PickerGrid c={c} translate={translate} />
        <ManifestPanel c={c} translate={translate} />

        <footer class="picker-foot" {...inspectAttrs('scaffold.picker:foot', { role: 'group' })}>
          {c.canContinue ? (
            <CtaLink href={c.continueHref ?? '#'} label={translate('scaffold.picker.continue') as string} glyph="chevron-right" variant="main" />
          ) : (
            <span class="cta-main is-disabled" aria-disabled="true" {...inspectAttrs('scaffold.picker:continue-blocked', { role: 'action' })}>{translate('scaffold.picker.continue.blocked') as string}</span>
          )}
        </footer>
      </div>
    </section>
  );
}

// ---- panels (fills the shell's main panel via children) ----
function renderPanels(c: PickerViewProps) {
  return <Panels c={c} translate={c.translate}>{MainContent({ c, translate: c.translate })}</Panels>;
}

// ---- Fragment responses ----
export function PanelsSwap(c: PickerViewProps) {
  return renderPanels(c);
}

export function GridSwap(c: PickerViewProps) {
  return PickerGrid({ c, translate: c.translate });
}

// ---- Page ----
const PickerView: FC<PickerViewProps> = (props) => (
  <MainShellView
    title={props.translate('scaffold.picker.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'scaffold'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop shell-main-picker"
    headerExtra={<AccountChip c={props} translate={props.translate} />}
    surface={
      <Fragment>
        <link rel="stylesheet" href="/assets/css/scaffold-picker.css" />
        {renderPanels(props)}
      </Fragment>
    }
    translate={props.translate}
  />
);

export default PickerView;
