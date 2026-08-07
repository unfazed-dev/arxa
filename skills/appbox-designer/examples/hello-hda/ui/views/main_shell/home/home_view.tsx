// home_view.tsx — home page (replaces home_view.html).
// Default export HomePage: wraps MainShell → Base.
import type { FC } from 'hono/jsx';
import MainShell from '../main_shell_view.tsx';
import ListRow from '../shared/widgets/list_row.tsx';
import FormField from '../shared/widgets/form_field.tsx';
import Icon from '../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

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
  t: TFn;
  rail?: unknown;
  rows?: ListRowData[];
  demoCount?: number;
  prefs?: { accent?: string; [key: string]: unknown };
  [key: string]: unknown;
}

const HomePage: FC<HomePageProps> = ({ t, locale, locales = [], rail, rows = [], demoCount, prefs }) => {
  const accent = prefs?.accent ?? 'blueviolet';
  return (
    <MainShell
      title={t('home.pageTitle') as string}
      locale={locale}
      accent={accent}
      locales={locales}
      t={t}
      rail={rail as { brand?: string; drawer?: boolean; items: NavItem[] }}
    >
      <h1>{t('home.title') as string}</h1>
      <p>{t('home.tagline') as string}</p>

      <section class="list-section">
        <h2 class="list-section__header">{t('home.greetingsHeader') as string}</h2>
        <div class="list-section__card">
          {rows.map((row) => (
            <ListRow row={row} />
          ))}
        </div>
      </section>
      <p class="muted">{t('itemCount', { count: demoCount }) as string}</p>

      <p>
        <a class="btn" href="/timer">
          {t('home.toTimer') as string} <Icon name="arrow-right" size={16} />
        </a>
      </p>

      <form hx-post="/prefs/accent" hx-swap="none">
        <FormField
          field={{
            name: 'accent',
            label: t('accent.label') as string,
            value: accent,
            options: [
              { value: 'blueviolet', label: t('accent.option.iris') as string },
              { value: 'teal', label: t('accent.option.lagoon') as string },
              { value: 'tomato', label: t('accent.option.signal') as string },
            ],
          }}
        />
        <button class="btn" type="submit">
          {t('accent.apply') as string}
        </button>
      </form>
      <p>
        {t('accent.current') as string}: <span class="swatch"></span> <code>{accent}</code>
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
