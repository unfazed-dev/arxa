// lang_switcher.tsx — language switching (replaces _lang_switcher.html).
// Plain anchors to /prefs/lang; renders nothing for single-locale artifacts.
import type { FC } from 'hono/jsx';

interface LangSwitcherProps {
  locales: string[];
  locale: string;
  t: (key: string) => unknown;
}

const LangSwitcher: FC<LangSwitcherProps> = ({ locales, locale, t }) => {
  if (!locales || locales.length <= 1) return null;
  return (
    <nav class="lang-switcher" aria-label={t('lang.label') as string}>
      {locales.map((l) => (
        <a
          class="lang-switcher__link"
          href={`/prefs/lang?lang=${l}`}
          aria-current={l === locale ? 'true' : undefined}
        >
          {t(`lang.name.${l}`) as string}
        </a>
      ))}
    </nav>
  );
};

export default LangSwitcher;
