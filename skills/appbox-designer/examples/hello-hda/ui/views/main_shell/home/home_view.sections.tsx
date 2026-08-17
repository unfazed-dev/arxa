// home_view.sections.tsx — the home body, defined once and composed by all
// three factor variants (studio-v2 sections pattern: sibling file so the
// variants never import back from the base view — acyclic and colocated).
// Authored entirely through the library widgets: every string and interactive
// element resolves to its own data-el (W7).
import type { FC } from 'hono/jsx';
import { Heading, Txt, Label, ActionButton, CtaLink } from '../../../widgets/hello_ui_widgets/widgets.tsx';
import { ListRow, FormField, IslandsDemo } from '../../../widgets/hello_home_widgets/widgets.tsx';
import Icon from '../../../../runtime/icon.tsx';

type TranslateFn = (key: string, vars?: Record<string, unknown>) => unknown;

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

export interface HomeBodyProps {
  translate: TranslateFn;
  rows?: ListRowData[];
  demoCount?: number;
  accent?: string;
  /** The ladder rung this copy renders into — suffixes shared ids. */
  rung?: string;
}

export const HomeBody: FC<HomeBodyProps> = ({
  translate,
  rows = [],
  demoCount,
  accent = 'blueviolet',
  rung,
}) => (
  <>
    <Heading level={1} name="home:title">{translate('home.title') as string}</Heading>
    <Txt name="home:tagline">{translate('home.tagline') as string}</Txt>

    <section class="list-section">
      <Heading level={2} name="home:greetings" class="list-section__header">
        {translate('home.greetingsHeader') as string}
      </Heading>
      <div class="list-section__card">
        {rows.map((row) => (
          <ListRow key={row.id} row={row}></ListRow>
        ))}
      </div>
    </section>
    <Txt name="home:item-count" class="muted">
      {translate('itemCount', { count: demoCount }) as string}
    </Txt>

    <p>
      <CtaLink href="/timer" name="home:to-timer">
        {translate('home.toTimer') as string} <Icon name="arrow-right" size={16} />
      </CtaLink>
    </p>

    <form hx-post="/prefs/accent" hx-swap="none">
      <FormField
        rung={rung}
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
      <ActionButton type="submit" name="home:accent-apply">
        {translate('accent.apply') as string}
      </ActionButton>
    </form>
    <Txt name="home:accent-current">
      {translate('accent.current') as string}:{' '}
      <span class="swatch"></span>{' '}
      <Label name="home:accent-hex" class="mono">{accent}</Label>
    </Txt>

    <IslandsDemo rung={rung} translate={translate} />
  </>
);

export default HomeBody;
