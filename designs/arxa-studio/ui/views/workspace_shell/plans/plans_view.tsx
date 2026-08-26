// plans_view.tsx — workspace plans surface (replaces plans_view.html).
// Pricing + account/entitlement state with the seeded mock checkout. Three
// entitlement lenses (signedOut / free / entitled); the checkout card mirrors
// kit/payments one-for-one. Extends the workspace shell.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import WorkspaceShellView from '../workspace_shell_view.tsx';
import { CtaLink, inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';
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
  translate: TFn;
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
    translate,
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
      <Label name="workspace-plans:eyebrow" class="eyebrow">{translate('plans.eyebrow') as string}</Label>
      <Heading name="workspace-plans:title" level={1} class="display">{translate('plans.title') as string}</Heading>
      <Txt name="workspace-plans:lede" class="muted">{translate('plans.lede') as string}</Txt>

      {signedOut ? (
        <aside class="plans-notice" data-lens="signedOut">
          <h4 class="fact-label" {...inspectAttrs('workspace-plans:signed-out-title', { role: 'heading' })}>
            <Icon name="lock" size={14} /> {translate('plans.signedOut.title') as string}
          </h4>
          <Txt name="workspace-plans:signed-out-body">{translate('plans.signedOut.body') as string}</Txt>
          <CtaLink href={signInHref} label={translate('plans.signedOut.cta') as string} glyph="chevron-right" variant="main" />
        </aside>
      ) : null}

      <section class="settings-section">
        <Heading name="workspace-plans:plans-h" level={2}>{translate('plans.plansH') as string}</Heading>
        <div class="plan-grid" {...inspectAttrs('workspace-plans:grid', { role: 'group' })}>
          {plans.map((plan) => (
            <article class={`plan-card${plan.current ? ' is-current' : ''}`} key={plan.name}>
              <header class="plan-head">
                <Heading name="workspace-plans:plan-name" level={3} class="plan-name">{plan.name}</Heading>
                {plan.current ? (
                  <span class="chip chip--accent" {...inspectAttrs('workspace-plans:current-chip', { role: 'label' })}>
                    <Icon name="badge-check" size={13} /> {translate('plans.current') as string}
                  </span>
                ) : null}
              </header>
              <Txt name="workspace-plans:plan-price" class="plan-price">{plan.priceLabel}</Txt>
              <Txt name="workspace-plans:plan-blurb" class="muted">{plan.blurb}</Txt>
              <plan class="plan-seats" {...inspectAttrs('workspace-plans:plan-seats', { role: 'text' })}>
                <Icon name="laptop" size={13} /> {plan.seatsLabel}
              </plan>
              <ul class="plan-features" {...inspectAttrs('workspace-plans:features', { role: 'group' })}>
                {plan.features.map((feature, index) => (
                  <li key={index} {...inspectAttrs('workspace-plans:feature', { role: 'list row' })}>
                    <Icon name="check" size={13} /> {feature}
                  </li>
                ))}
              </ul>
              {plan.upgradeable ? (
                <a class="cta-main plan-upgrade" href="#plans-checkout" {...inspectAttrs('workspace-plans:upgrade', { role: 'action' })}>{translate('plans.upgrade', { plan: plan.name }) as string}</a>
              ) : null}
            </article>
          ))}
        </div>
      </section>

      {entitled ? (
        <section class="settings-section">
          <Heading name="workspace-plans:account-h" level={2}>{translate('plans.accountH') as string}</Heading>
          <div class="plan-account">
            <p>
              <span class="chip chip--accent" {...inspectAttrs('workspace-plans:plan-name-chip', { role: 'label' })}>
                <Icon name="badge-check" size={13} /> {translate(`plans.plan.${currentPlan}.name`) as string}
              </span>
              <span class="chip chip--muted" {...inspectAttrs('workspace-plans:seats-chip', { role: 'label' })}>
                <Icon name="laptop" size={13} /> {translate('plans.seats.used', { used: machineSeats?.used, total: machineSeats?.total }) as string}
              </span>
            </p>
            <form method="post" action="/workspace/plans/signout">
              <button type="submit" class="ghost" {...inspectAttrs('workspace-plans:sign-out', { role: 'action' })}>
                <Icon name="log-out" size={14} /> {translate('plans.signOut') as string}
              </button>
            </form>
          </div>
        </section>
      ) : null}

      {checkout ? (
        <section class="settings-section" id="plans-checkout">
          <Heading name="workspace-plans:checkout-h" level={2}>{translate('plans.checkoutH') as string}</Heading>
          <Txt name="workspace-plans:checkout-seeded" class="settings-note">{translate('plans.checkout.seeded') as string}</Txt>
          <p class="checkout-summary" {...inspectAttrs('workspace-plans:checkout-summary', { role: 'text' })}>
            <Icon name="credit-card" size={14} /> {translate('plans.checkout.summary', { amount: checkout.amountLabel }) as string}
          </p>

          <div class="checkout-outcomes" role="group" aria-label={translate('plans.checkout.outcomesAria') as string} {...inspectAttrs('workspace-plans:outcomes', { role: 'group' })}>
            {checkout.outcomes.map((outcome) => (
              <form method="post" action="/workspace/plans/checkout/attempt" key={outcome.id}>
                <button
                  type="submit"
                  name="outcome"
                  value={outcome.id}
                  class={`chip${outcome.active ? ' chip--accent' : ' chip--muted'}`}
                  {...inspectAttrs('workspace-plans:outcome', { role: 'action' })}
                  title={outcome.profile ? `${outcome.profile} -> ${outcome.result}` : outcome.result}
                >
                  {outcome.label}
                </button>
              </form>
            ))}
          </div>

          {active ? (
            <aside class={`plans-notice checkout-result checkout-result--${active.id}`} role="status">
              <h4 class="fact-label" {...inspectAttrs('workspace-plans:checkout-result-title', { role: 'heading' })}>
                <Icon name={outcomeIcon} size={14} /> {active.title}
              </h4>
              <Txt name="workspace-plans:checkout-kit" class="checkout-kit">
                {active.profile ? (
                  <Fragment>
                    {active.profile} <Icon name="arrow-right" size={12} />{' '}
                  </Fragment>
                ) : null}
                {active.result}
              </Txt>
              <Txt name="workspace-plans:checkout-body">{active.body}</Txt>
              {active.id === 'succeed' ? (
                <form method="post" action="/workspace/plans/checkout/apply">
                  <button type="submit" class="cta-main" {...inspectAttrs('workspace-plans:apply', { role: 'action' })}>{active.applyLabel}</button>
                </form>
              ) : active.id === 'decline' || active.id === 'timeout' ? (
                <form method="post" action="/workspace/plans/checkout/attempt">
                  <button type="submit" name="outcome" value="succeed" class="cta-main" {...inspectAttrs('workspace-plans:retry', { role: 'action' })}>
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
      translate={translate}
      title={translate('plans.pageTitle') as string}
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
