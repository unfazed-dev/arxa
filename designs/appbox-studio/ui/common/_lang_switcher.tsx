// _lang_switcher.tsx — language switching partial (replaces _lang_switcher.html).
// Plain anchors to the runtime's built-in /prefs/lang route (ADR-0004 prefs
// recipe): boosted requests get h.setPrefs + HX-Refresh; plain navigation gets a
// 302 back. No custom JS, no form — a GET is enough because the cookie is the
// state. Renders nothing for a single-locale artifact.
//
//   import LangSwitcher from './_lang_switcher.tsx';
//   <LangSwitcher locales={locales} locale={locale} t={t} />
//
// Reads `locales` and `locale` from the context bag (merged into every render
// by the runtime), so no viewmodel wiring is needed.
import type { FC } from 'hono/jsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface LangSwitcherProps {
  locales?: string[];
  locale?: string;
  t: TFn;
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
