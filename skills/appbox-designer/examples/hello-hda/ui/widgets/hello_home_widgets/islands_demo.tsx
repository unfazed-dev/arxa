// islands_demo.tsx — the interactive-island teaching block. The whole unit
// (trigger button, hidden panel, island state script) is a widget so surfaces
// compose it as one vocabulary element; raw markup lives in the library,
// where W7 does not scan.
//
// rung suffixes the aria-controls/id pair — the three factor variants each
// mount one demo and a bare id would collide (same law as form_field).
import type { FC } from 'hono/jsx';

interface IslandsDemoProps {
  rung?: string;
  translate: (key: string, vars?: Record<string, unknown>) => unknown;
}

const IslandsDemo: FC<IslandsDemoProps> = ({ rung, translate }) => {
  const scope = rung ? `--${rung}` : '';
  return (
    <div data-arxa-id="ui-widgets-hello_home_widgets-islands_demo-e1" hx-island="toggle" hx-island-when="interaction">
      <button data-arxa-id="ui-widgets-hello_home_widgets-islands_demo-e2" class="btn" data-island-btn="" aria-expanded="false" aria-controls={`island-panel${scope}`} id={`island-btn${scope}`}>
        {translate('home.islands.toggle') as string}
      </button>
      <div data-arxa-id="ui-widgets-hello_home_widgets-islands_demo-e3" data-island-panel="" id={`island-panel${scope}`} hidden={true}>
        <p data-arxa-id="ui-widgets-hello_home_widgets-islands_demo-e4" class="muted">
          {translate('home.islands.copy') as string}
        </p>
      </div>
      <script data-arxa-id="ui-widgets-hello_home_widgets-islands_demo-e5"
        type="application/json"
        data-island-state="toggle"
        dangerouslySetInnerHTML={{ __html: '{"open":false}' }}
      />
    </div>
  );
};

export { IslandsDemo };
