/// This is the user interface for studio_intake at the medium rung.
///
/// Role: the interview at tablet width — the upload rail folds under
/// the thread as a full-width section; the thread keeps the desktop
/// q-card vocabulary at this width.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: mounted by studio_intake_view.tsx; composes
/// widgets/interview_thread.tsx + widgets/asset_upload_dropzone.tsx.
///
/// History: git log --follow -- ui/views/studio_intake_shell/studio_intake/studio_intake_view.tablet.tsx

import type { FC } from 'hono/jsx';
import { InterviewThread, AssetUploadDropzone } from '../../../widgets/studio_intake_widgets/widgets.tsx';
import type { IntakeProps } from './studio_intake_view.desktop.tsx';

const StudioIntakeViewTablet: FC<IntakeProps> = (props) => (
  <main
    class="intake-stage intake-stage--tablet"
    data-inspect-surface="studio_intake"
    data-inspect-role="section"
    data-inspect-style="thread over full-width upload section"
    data-inspect-fn="runs the intake interview that produces intake/registry.json"
    data-inspect-motion="reveal"
  >
    <h1
      class="display display--md"
      data-inspect-role="heading"
      data-inspect-style="surface heading, one step smaller than desktop"
      data-inspect-fn="names the stage the interview fronts"
      data-inspect-motion="none"
    >
      {props.title}
    </h1>
    <p
      class="muted intake-lede"
      data-inspect-role="text"
      data-inspect-style="one quiet line under the heading"
      data-inspect-fn="says what the interview produces"
      data-inspect-motion="none"
    >
      {props.subtitle}
    </p>
    <InterviewThread
      modes={props.modes}
      turns={props.turns}
      currentQuestion={props.currentQuestion}
      answerLabel={props.answerLabel}
      answerPlaceholder={props.answerPlaceholder}
      skipLabel={props.skipLabel}
    />
    <AssetUploadDropzone
      title={props.assetTitle}
      hint={props.assetHint}
      button={props.assetButton}
      assets={props.assets}
    />
  </main>
);

export default StudioIntakeViewTablet;
