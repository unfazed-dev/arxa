// plans_view.tsx — workspace plans surface (replaces plans_view.html).
// Pricing + account/entitlement state with the seeded mock checkout. Three
// entitlement lenses (signedOut / free / entitled); the checkout card mirrors
// kit/payments one-for-one. Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';
import { CtaLink } from '../../../common/widgets/primitives.tsx';
import Icon from '../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Plan {
  name: string;
  current?: boolean;
  priceLabel: string;
  blurb: string;
  seatsLabel: string;
  features: string[];
  upgradeable?: boolean;
}

interface MachineSeats {
  used: number;
  total: number;
}

interface CheckoutOutcome {
  id: string;
  label: string;
  active?: boolean;
  profile?: string;
  result?: string;
}

interface CheckoutActive {
  id: string;
  title: string;
  profile?: string;
  result: string;
  body: string;
  applyLabel?: string;
  retryLabel?: string;
}

interface Checkout {
  amountLabel: string;
  outcomes: CheckoutOutcome[];
  active?: CheckoutActive;
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

interface PlansViewProps {
  t: TFn;
  locale?: string;
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  signedOut?: boolean;
  signInHref?: string;
  plans?: Plan[];
  entitled?: boolean;
  currentPlan?: string;
  machineSeats?: MachineSeats;
  checkout?: Checkout;
  [key: string]: unknown;
}

const PlansView: FC<PlansViewProps> = (props) => {
  const {
    t,
    locale,
    activeShell,
    prefs,
    project,
    signedOut = false,
    signInHref = '',
    plans = [],
    entitled = false,
    currentPlan = '',
    machineSeats,
    checkout,
  } = props;

  const active = checkout?.active;
  const outcomeIcon = active
    ? active.id === 'succeed'
      ? 'check'
      : active.id === 'timeout'
        ? 'timer'
        : active.id === 'error' || active.id === 'decline'
          ? 'circle-alert'
          : 'x-circle'
    : 'x-circle';

  const surface = (
    <Fragment>
      <span class="eyebrow">{t('plans.eyebrow') as string}</span>
      <h1 class="display">{t('plans.title') as string}</h1>
      <p class="muted">{t('plans.lede') as string}</p>

      {signedOut ? (
        <aside class="plans-notice" data-lens="signedOut">
          <h4 class="fact-label">
            <Icon name="lock" size={14} /> {t('plans.signedOut.title') as string}
          </h4>
          <p>{t('plans.signedOut.body') as string}</p>
          <CtaLink href={signInHref} label={t('plans.signedOut.cta') as string} glyph="chevron-right" variant="main" />
        </aside>
      ) : null}

      <section class="settings-section">
        <h2>{t('plans.plansH') as string}</h2>
        <div class="plan-grid">
          {plans.map((p) => (
            <article class={`plan-card${p.current ? ' is-current' : ''}`} key={p.name}>
              <header class="plan-head">
                <h3 class="plan-name">{p.name}</h3>
                {p.current ? (
                  <span class="chip chip--accent">
                    <Icon name="badge-check" size={13} /> {t('plans.current') as string}
                  </span>
                ) : null}
              </header>
              <p class="plan-price">{p.priceLabel}</p>
              <p class="muted">{p.blurb}</p>
              <p class="plan-seats">
                <Icon name="laptop" size={13} /> {p.seatsLabel}
              </p>
              <ul class="plan-features">
                {p.features.map((f, i) => (
                  <li key={i}>
                    <Icon name="check" size={13} /> {f}
                  </li>
                ))}
              </ul>
              {p.upgradeable ? (
                <a class="cta-main plan-upgrade" href="#plans-checkout">{t('plans.upgrade', { plan: p.name }) as string}</a>
              ) : null}
            </article>
          ))}
        </div>
      </section>

      {entitled ? (
        <section class="settings-section">
          <h2>{t('plans.accountH') as string}</h2>
          <div class="plan-account">
            <p>
              <span class="chip chip--accent">
                <Icon name="badge-check" size={13} /> {t(`plans.plan.${currentPlan}.name`) as string}
              </span>
              <span class="chip chip--muted">
                <Icon name="laptop" size={13} /> {t('plans.seats.used', { used: machineSeats?.used, total: machineSeats?.total }) as string}
              </span>
            </p>
            <form method="post" action="/workspace/plans/signout">
              <button type="submit" class="ghost">
                <Icon name="log-out" size={14} /> {t('plans.signOut') as string}
              </button>
            </form>
          </div>
        </section>
      ) : null}

      {checkout ? (
        <section class="settings-section" id="plans-checkout">
          <h2>{t('plans.checkoutH') as string}</h2>
          <p class="settings-note">{t('plans.checkout.seeded') as string}</p>
          <p class="checkout-summary">
            <Icon name="credit-card" size={14} /> {t('plans.checkout.summary', { amount: checkout.amountLabel }) as string}
          </p>

          <div class="checkout-outcomes" role="group" aria-label={t('plans.checkout.outcomesAria') as string}>
            {checkout.outcomes.map((o) => (
              <form method="post" action="/workspace/plans/checkout/attempt" key={o.id}>
                <button
                  type="submit"
                  name="outcome"
                  value={o.id}
                  class={`chip${o.active ? ' chip--accent' : ' chip--muted'}`}
                  title={o.profile ? `${o.profile} -> ${o.result}` : o.result}
                >
                  {o.label}
                </button>
              </form>
            ))}
          </div>

          {active ? (
            <aside class={`plans-notice checkout-result checkout-result--${active.id}`} role="status">
              <h4 class="fact-label">
                <Icon name={outcomeIcon} size={14} /> {active.title}
              </h4>
              <p class="checkout-kit">
                {active.profile ? (
                  <Fragment>
                    {active.profile} <Icon name="arrow-right" size={12} />{' '}
                  </Fragment>
                ) : null}
                {active.result}
              </p>
              <p>{active.body}</p>
              {active.id === 'succeed' ? (
                <form method="post" action="/workspace/plans/checkout/apply">
                  <button type="submit" class="cta-main">{active.applyLabel}</button>
                </form>
              ) : active.id === 'decline' || active.id === 'timeout' ? (
                <form method="post" action="/workspace/plans/checkout/attempt">
                  <button type="submit" name="outcome" value="succeed" class="cta-main">
                    <Icon name="refresh-cw" size={14} /> {active.retryLabel}
                  </button>
                </form>
              ) : null}
            </aside>
          ) : null}
        </section>
      ) : null}
    </Fragment>
  );

  return (
    <WorkspaceShellView
      t={t}
      title={t('plans.pageTitle') as string}
      locale={locale}
      activeShell={activeShell}
      prefs={prefs}
      project={project}
      headExtra={<link rel="stylesheet" href="/assets/css/plans.css" />}
      surface={surface}
    />
  );
};

export default PlansView;
