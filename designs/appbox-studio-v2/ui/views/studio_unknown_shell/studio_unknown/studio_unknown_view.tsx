/// This is the user interface for studio_unknown.
///
/// Role: unknown surface view. Composes the three DERIVED factor variants
/// inside the unknown shell.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Ceremony shells cut over first] — Q-v2-5
///
/// Relationships: studio_unknown_viewmodel.js -> this -> the three
/// *_view.<factor>.tsx variants, wrapped by studio_unknown_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_unknown_shell/studio_unknown/studio_unknown_view.tsx

import type { FC } from 'hono/jsx';
import Shell from '../studio_unknown_shell_view.tsx';
import Desktop from './studio_unknown_view.desktop.tsx';
import Tablet from './studio_unknown_view.tablet.tsx';
import Mobile from './studio_unknown_view.mobile.tsx';
import type { UnknownProps } from './studio_unknown_view.desktop.tsx';

const StudioUnknownView: FC<UnknownProps & { pageTitle: string; locale?: string }> = (props) => (
  <Shell pageTitle={props.pageTitle} locale={props.locale}>
    <div data-inspect-view="studio_unknown_view">
      <div class="rung rung--desktop"><Desktop {...props} /></div>
      <div class="rung rung--tablet"><Tablet {...props} /></div>
      <div class="rung rung--mobile"><Mobile {...props} /></div>
    </div>
  </Shell>
);

export default StudioUnknownView;
