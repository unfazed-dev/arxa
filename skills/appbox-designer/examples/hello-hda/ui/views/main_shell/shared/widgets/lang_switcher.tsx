// lang_switcher.tsx — language switching (replaces _lang_switcher.html).
// Plain anchors to /prefs/lang; renders nothing for single-locale artifacts.
import type { FC } from 'hono/jsx';

interface LangSwitcherProps {
  locales: string[];
  locale: string;
  translate: (key: string) => unknown;
}

const LangSwitcher: FC<LangSwitcherProps> = ({ locales, locale, translate }) => {
  if (!locales || locales.length <= 1) return null;
  return (
    <nav class="lang-switcher" aria-label={translate('lang.label') as string}>
      {locales.map((localeTag) => (
        <a
          class="lang-switcher__link"
          href={`/prefs/lang?lang=${localeTag}`}
          aria-current={localeTag === locale ? 'true' : undefined}
        >
          {translate(`lang.name.${localeTag}`) as string}
        </a>
      ))}
    </nav>
  );
};

export default LangSwitcher;
