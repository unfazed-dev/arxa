// kind: bottom-sheet
// Role: the composer sheet — the v1 chat composer as a pinned bottom
//   sheet with the canvas sliders (zoom, grid snap) in its rail. Native
//   inputs only: textarea, range sliders, one POST trigger.
// Requirements: Q-v2-1 (manual trigger), Q-v2-5, ADR-0002.
// Relationships: composed by all three studio_design_view.<factor>.tsx
//   variants; posts to /design/compose.
// History: created for studio v2; composer classes from v1 composer.css
//   per the VISUAL PARITY LAW.
import type { FC } from 'hono/jsx';

export interface ComposerSliderPanelProps {
  title: string;
  placeholder: string;
  sendLabel: string;
  zoomLabel: string;
  gridLabel: string;
}

const ComposerSliderPanel: FC<ComposerSliderPanelProps> = ({ title, placeholder, sendLabel, zoomLabel, gridLabel }) => (
  <section
    class="composer-sheet"
    aria-labelledby="composer-h"
    data-el="bottom-sheet"
    data-inspect-widget="composer_slider_panel"
    data-inspect-role="form"
    data-inspect-style="v1 composer as a pinned bottom sheet, sliders in the side rail"
    data-inspect-fn="composes design instructions and tunes the canvas"
    data-inspect-motion="none"
  >
    <h2
      id="composer-h"
      class="sr-only"
      data-inspect-role="heading"
      data-inspect-style="screen-reader heading"
      data-inspect-fn="names the composer for assistive tech"
      data-inspect-motion="none"
    >
      {title}
    </h2>
    <form class="composer" method="post" action="/design/compose">
      <textarea
        name="instruction"
        rows={2}
        aria-label={title}
        placeholder={placeholder}
        data-el="form-field__input"
        data-inspect-role="input"
        data-inspect-style="multi-line instruction input"
        data-inspect-fn="holds the design instruction being composed"
        data-inspect-motion="none"
      ></textarea>
      <div
        class="composer-controls"
        data-inspect-role="group"
        data-inspect-style="slider rail beside the input row"
        data-inspect-fn="tunes canvas zoom and grid snap"
        data-inspect-motion="none"
      >
        <label class="slider-row">
          <span class="slider-label muted">{zoomLabel}</span>
          <input type="range" name="zoom" min={50} max={150} defaultValue={100} data-inspect-role="input" data-inspect-style="native zoom range" data-inspect-fn="scales the canvas tiles" data-inspect-motion="none" />
        </label>
        <label class="slider-row">
          <span class="slider-label muted">{gridLabel}</span>
          <input type="range" name="grid" min={0} max={24} defaultValue={8} data-inspect-role="input" data-inspect-style="native grid-snap range" data-inspect-fn="sets the canvas snap grid" data-inspect-motion="none" />
        </label>
        <button
          type="submit"
          class="btn btn--primary"
          data-el="cta-link"
          data-inspect-role="button"
          data-inspect-style="primary submit closing the sheet's row"
          data-inspect-fn="sends the instruction to the design stage"
          data-inspect-motion="pending"
        >
          {sendLabel}
        </button>
      </div>
    </form>
  </section>
);

export default ComposerSliderPanel;
