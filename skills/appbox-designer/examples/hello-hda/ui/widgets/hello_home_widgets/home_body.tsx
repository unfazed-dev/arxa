// home_view.sections.tsx — the home body, defined once and composed by all
// per the sections law (ruled 2026-08-18): composition files never sit
// in ui/views; the view variants invoke this widget.
// Authored entirely through the library widgets: every element is a
// Capitalized invocation (W9) and every string and interactive element
// resolves to its own data-el (W7).
import type { FC } from 'hono/jsx';
import { Heading, Txt, Label, ActionButton, CtaLink } from '../hello_ui_widgets/widgets.tsx';
import { ListRow } from './list_row.tsx';
import { FormField } from './form_field.tsx';
import { IslandsDemo } from './islands_demo.tsx';
import { ListSection, ListCard, CtaLine, Swatch, HxForm } from './home_blocks.tsx';
import Icon from '../../../runtime/icon.tsx';

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

    <ListSection>
      <Heading level={2} name="home:greetings" class="list-section__header">
        {translate('home.greetingsHeader') as string}
      </Heading>
      <ListCard>
        {rows.map((row) => (
          <ListRow key={row.id} row={row}></ListRow>
        ))}
      </ListCard>
    </ListSection>
    <Txt name="home:item-count" class="muted">
      {translate('itemCount', { count: demoCount }) as string}
    </Txt>

    <CtaLine>
      <CtaLink href="/timer" name="home:to-timer">
        {translate('home.toTimer') as string} <Icon name="arrow-right" size={16} />
      </CtaLink>
    </CtaLine>

    <HxForm post="/prefs/accent">
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
    </HxForm>
    <Txt name="home:accent-current">
      {translate('accent.current') as string}:{' '}
      <Swatch></Swatch>{' '}
      <Label name="home:accent-hex" class="mono">{accent}</Label>
    </Txt>

    <IslandsDemo rung={rung} translate={translate} />
  </>
);

export default HomeBody;
