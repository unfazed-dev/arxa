// composedFrom: tabs + form-field (no single kind realises it — the
//   inspector is a tabbed property sheet, F4 resolution).
// Role: the inspector panel — the selected tile's properties as tabs of
//   labelled fields. Tabs are radio inputs + CSS (zero client JS,
//   ADR-0002); the first tab renders checked. The folded variant (tablet/
//   mobile) wraps each tab in a closed disclosure instead.
// Requirements: Q-v2-3, Q-v2-5, ADR-0002.
// Relationships: composed by all three studio_design_view.<factor>.tsx
//   variants.
// History: created for studio v2; property-sheet vocabulary from v1
//   inspector_pane.tsx per the VISUAL PARITY LAW.
import type { FC } from 'hono/jsx';

export interface InspectorField {
  id: string;
  label: string;
  value: string;
}

export interface InspectorTab {
  id: string;
  label: string;
  fields: InspectorField[];
}

export interface InspectorPanelProps {
  title: string;
  tabs: InspectorTab[];
  folded?: boolean;
}

const InspectorPanel: FC<InspectorPanelProps> = ({ title, tabs, folded }) => (
  <section
    class={folded ? 'inspector inspector--folded' : 'inspector'}
    aria-labelledby="inspector-h"
    data-inspect-widget="inspector_panel"
    data-inspect-role="section"
    data-inspect-style="v1 property sheet: tab strip over labelled fields"
    data-inspect-fn="edits the selected tile's properties"
    data-inspect-motion="none"
  >
    <h2
      id="inspector-h"
      class="inspector-title"
      data-inspect-role="heading"
      data-inspect-style="small section heading"
      data-inspect-fn="names the inspector"
      data-inspect-motion="none"
    >
      {title}
    </h2>
    {folded ? (
      tabs.map((tab) => (
        <details key={tab.id} class="inspector-tab-details">
          <summary>{tab.label}</summary>
          <dl class="inspector-fields">
            {tab.fields.map((field) => (
              <div key={field.id} class="inspector-field">
                <dt>{field.label}</dt>
                <dd>{field.value}</dd>
              </div>
            ))}
          </dl>
        </details>
      ))
    ) : (
      <div class="inspector-tabs" role="tablist">
        {tabs.map((tab, index) => (
          <div key={tab.id} class="inspector-tab" data-inspect-role="section" data-inspect-style={'radio-selected tab: ' + tab.label} data-inspect-fn={'shows the ' + tab.label + ' properties'} data-inspect-motion="none">
            <input
              type="radio"
              id={'insp-tab-' + tab.id}
              name="insp-tabs"
              defaultChecked={index === 0}
              data-inspect-role="tab"
              data-inspect-style="native radio driving the CSS tab selection"
              data-inspect-fn={'opens the ' + tab.label + ' tab'}
              data-inspect-motion="none"
            />
            <label for={'insp-tab-' + tab.id}>{tab.label}</label>
            <dl class="inspector-fields">
              {tab.fields.map((field) => (
                <div key={field.id} class="inspector-field">
                  <dt>{field.label}</dt>
                  <dd>{field.value}</dd>
                </div>
              ))}
            </dl>
          </div>
        ))}
      </div>
    )}
  </section>
);

export default InspectorPanel;
