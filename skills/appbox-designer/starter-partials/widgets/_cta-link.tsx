// _cta-link.tsx — navigational CTA link (replaces _cta-link.html).
// Zero JavaScript. The *go somewhere* counterpart of the action row's *do
// something* buttons: icon + label with a trailing affordance glyph — card
// footers, "view on canvas", artifact cross-links.
//
//   import { CtaLink } from '../../common/widgets/_cta-link.tsx';
//   <CtaLink cta={{ href: `/projects/${p.id}`, label: 'Open' }} />
//
// cta = {
//   href, label,
//   icon?,       // trailing glyph: default chevron-right (arrow-up-right
//                // when external); pass icon: false for a bare text link
//   external?,   // target="_blank" rel="noopener"
//   hx?          // fragment nav: { get?, target, swap?, pushUrl? };
//                // get defaults to href, swap to "outerHTML"
// }
//
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (block: .cta-link).
// Flutter: AppBoxKitListTile trailing chevron / AppBoxKitNativeButton(link).
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface CtaLinkProps {
  cta: {
    href: string;
    label: string;
    icon?: string | false;
    external?: boolean;
    hx?: {
      get?: string;
      target: string;
      swap?: string;
      pushUrl?: boolean;
    };
  };
}

export const CtaLink: FC<CtaLinkProps> = ({ cta }) => {
  const showIcon = cta.icon !== false;
  const iconName =
    typeof cta.icon === 'string'
      ? cta.icon
      : cta.external
        ? 'arrow-up-right'
        : 'chevron-right';
  return (
    <a
      class="cta-link"
      href={cta.href}
      hx-get={cta.hx ? (cta.hx.get ?? cta.href) : undefined}
      hx-target={cta.hx?.target}
      hx-swap={cta.hx ? (cta.hx.swap ?? 'outerHTML') : undefined}
      hx-push-url={cta.hx ? (cta.hx.pushUrl ? 'true' : 'false') : undefined}
      target={cta.external ? '_blank' : undefined}
      rel={cta.external ? 'noopener' : undefined}
    >
      <span>{cta.label}</span>
      {showIcon && <Icon name={iconName} size={16} />}
    </a>
  );
};
