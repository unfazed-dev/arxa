/// This is the user interface for studio_intake at the compact rung.
///
/// Role: the interview at mobile width — single column; the upload
/// section collapses into a closed `<details>` so the thread owns the
/// first screen; the composer stays pinned to the bottom of the scroll.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: mounted by studio_intake_view.tsx; composes
/// widgets/interview_thread.tsx + widgets/asset_upload_dropzone.tsx.
///
/// History: git log --follow -- ui/views/studio_intake_shell/studio_intake/studio_intake_view.mobile.tsx

import type { FC } from 'hono/jsx';
import { InterviewThread, AssetUploadDropzone } from '../../../widgets/studio_intake_widgets/widgets.tsx';
import type { IntakeProps } from './studio_intake_view.desktop.tsx';

const StudioIntakeViewMobile: FC<IntakeProps> = (props) => (
  <main
    class="intake-stage intake-stage--mobile"
    data-inspect-surface="studio_intake"
    data-inspect-role="section"
    data-inspect-style="single column, upload collapsed into a closed details"
    data-inspect-fn="runs the intake interview that produces intake/registry.json"
    data-inspect-motion="reveal"
  >
    <h1
      class="display display--sm"
      data-inspect-role="heading"
      data-inspect-style="compact heading sized for the phone width"
      data-inspect-fn="names the stage the interview fronts"
      data-inspect-motion="none"
    >
      {props.title}
    </h1>
    <details
      class="intake-upload-details"
      data-inspect-role="section"
      data-inspect-style="closed disclosure holding the upload section"
      data-inspect-fn="keeps the thread first on a phone; opens for uploads"
      data-inspect-motion="reveal"
    >
      <summary class="intake-upload-summary">{props.assetTitle}</summary>
      <AssetUploadDropzone
        title={props.assetTitle}
        hint={props.assetHint}
        button={props.assetButton}
        assets={props.assets}
        compact
      />
    </details>
    <InterviewThread
      modes={props.modes}
      turns={props.turns}
      currentQuestion={props.currentQuestion}
      answerLabel={props.answerLabel}
      answerPlaceholder={props.answerPlaceholder}
      skipLabel={props.skipLabel}
      stacked
    />
  </main>
);

export default StudioIntakeViewMobile;
