/// This is the user interface for studio_auth.
///
/// Role: auth surface view — the credentials card. Composes the three
/// DERIVED factor variants inside the auth shell. The card markup is
/// identical at every rung (v1 parity: one auth-card, CSS frames it), so
/// the variants frame rather than restate it.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Seeded sign-in: any input signs in; ?state= swaps headline/lede] — v1 auth contract
/// 3. [Inspect triple + annotation quad on every emitted element] — Q-v2-5
///
/// Relationships: studio_auth_viewmodel.js -> this -> the three
/// *_view.<factor>.tsx variants, wrapped by studio_auth_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth/studio_auth_view.tsx

import type { FC } from 'hono/jsx';
import Shell from '../studio_auth_shell_view.tsx';
import Desktop from './studio_auth_view.desktop.tsx';
import Tablet from './studio_auth_view.tablet.tsx';
import Mobile from './studio_auth_view.mobile.tsx';
import type { AuthProps } from './studio_auth_view.desktop.tsx';

const StudioAuthView: FC<AuthProps & { brand: string; tagline: string; locale?: string }> = (props) => (
  <Shell brand={props.brand} tagline={props.tagline} locale={props.locale}>
    <div data-inspect-view="studio_auth_view">
      <div class="rung rung--desktop"><Desktop {...props} /></div>
      <div class="rung rung--tablet"><Tablet {...props} /></div>
      <div class="rung rung--mobile"><Mobile {...props} /></div>
    </div>
  </Shell>
);

export default StudioAuthView;
