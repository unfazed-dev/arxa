// home_view.tsx — home page (replaces home_view.html).
// Default export HomePage: wraps MainShell → Base.
import type { FC } from 'hono/jsx';
import MainShell from '../main_shell_view.tsx';
import ListRow from './widgets/list_row.tsx';
import FormField from './widgets/form_field.tsx';
import Icon from '../../../../runtime/icon.tsx';

type TranslateFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface NavItem {
  id: string;
  label: string;
  icon?: string;
  href: string;
  current?: boolean;
}

interface ListRowData {
  id: string;
  title: string;
  subtitle?: string;
  detail?: string;
  icon?: string;
  href?: string;
  chevron?: boolean;
  oob?: boolean;
}

interface HomePageProps {
  locale?: string;
  locales?: string[];
  translate: TranslateFn;
  rail?: unknown;
  rows?: ListRowData[];
  demoCount?: number;
  prefs?: { accent?: string; [key: string]: unknown };
  [key: string]: unknown;
}

const HomePage: FC<HomePageProps> = ({ translate, locale, locales = [], rail, rows = [], demoCount, prefs }) => {
  const accent = prefs?.accent ?? 'blueviolet';
  return (
    <MainShell
      title={translate('home.pageTitle') as string}
      locale={locale}
      accent={accent}
      locales={locales}
      translate={translate}
      rail={rail as { brand?: string; drawer?: boolean; items: NavItem[] }}
    >
      <h1>{translate('home.title') as string}</h1>
      <p>{translate('home.tagline') as string}</p>

      <section class="list-section">
        <h2 class="list-section__header">{translate('home.greetingsHeader') as string}</h2>
        <div class="list-section__card">
          {rows.map((row) => (
            <ListRow row={row} />
          ))}
        </div>
      </section>
      <p class="muted">{translate('itemCount', { count: demoCount }) as string}</p>

      <p>
        <a class="btn" href="/timer">
          {translate('home.toTimer') as string} <Icon name="arrow-right" size={16} />
        </a>
      </p>

      <form hx-post="/prefs/accent" hx-swap="none">
        <FormField
          field={{
            name: 'accent',
            label: translate('accent.label') as string,
            value: accent,
            options: [
              { value: 'blueviolet', label: translate('accent.option.iris') as string },
              { value: 'teal', label: translate('accent.option.lagoon') as string },
              { value: 'tomato', label: translate('accent.option.signal') as string },
            ],
          }}
        />
        <button class="btn" type="submit">
          {translate('accent.apply') as string}
        </button>
      </form>
      <p>
        {translate('accent.current') as string}: <span class="swatch"></span> <code>{accent}</code>
      </p>

      <div hx-island="toggle" hx-island-when="interaction">
        <button class="btn" data-island-btn="" aria-expanded="false">
          Details
        </button>
        <div data-island-panel="" hidden={true}>
          <p class="muted">
            Islands load zero JS until their condition fires. This content was hidden by the server;
            the toggle island revealed it after first interaction — no framework boot, no hydration.
          </p>
        </div>
        <script
          type="application/json"
          data-island-state="toggle"
          dangerouslySetInnerHTML={{ __html: '{"open":false}' }}
        />
      </div>
    </MainShell>
  );
};

export default HomePage;
