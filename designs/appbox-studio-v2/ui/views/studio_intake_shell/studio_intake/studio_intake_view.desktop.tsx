/// This is the user interface for studio_intake at the expanded rung.
///
/// Role: the interview at desktop width — the v1 question vocabulary
/// restructured from a horizontal carousel into a vertical thread (the
/// registry's interview_thread), with the asset upload as a right-hand
/// rail. Mode cards lead the thread; answered turns render as q-cards.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [v1 interview thread look carries over] — VISUAL PARITY LAW
///
/// Relationships: mounted by studio_intake_view.tsx; composes
/// widgets/interview_thread.tsx + widgets/asset_upload_dropzone.tsx.
///
/// History: git log --follow -- ui/views/studio_intake_shell/studio_intake/studio_intake_view.desktop.tsx

import type { FC } from 'hono/jsx';
import { InterviewThread } from '../../../widgets/studio_intake_widgets/widgets.tsx';
import { AssetUploadDropzone } from '../../../widgets/studio_intake_widgets/widgets.tsx';

export interface InterviewMode {
  id: string;
  name: string;
  desc: string;
}

export interface InterviewTurn {
  id: string;
  question: string;
  answer?: string;
  state: 'answered' | 'skipped' | 'current';
}

export interface UploadAsset {
  id: string;
  name: string;
  kind: string;
  size: string;
}

export interface IntakeProps {
  translate: (key: string, vars?: Record<string, unknown>) => unknown;
  title: string;
  subtitle: string;
  modes: InterviewMode[];
  turns: InterviewTurn[];
  currentQuestion: string;
  answerLabel: string;
  answerPlaceholder: string;
  skipLabel: string;
  assetTitle: string;
  assetHint: string;
  assetButton: string;
  assets: UploadAsset[];
  locale?: string;
  activeShell: string;
  [key: string]: unknown;
}

const StudioIntakeViewDesktop: FC<IntakeProps> = (props) => (
  <main
    class="intake-stage intake-stage--desktop"
    data-inspect-surface="studio_intake"
    data-inspect-role="section"
    data-inspect-style="v1 q-card vocabulary as a vertical thread, upload rail on the right"
    data-inspect-fn="runs the intake interview that produces intake/registry.json"
    data-inspect-motion="reveal"
  >
    <div class="intake-main">
      <h1
        class="display"
        data-inspect-role="heading"
        data-inspect-style="surface heading over the thread"
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
    </div>
    <aside class="intake-rail">
      <AssetUploadDropzone
        title={props.assetTitle}
        hint={props.assetHint}
        button={props.assetButton}
        assets={props.assets}
      />
    </aside>
  </main>
);

export default StudioIntakeViewDesktop;
