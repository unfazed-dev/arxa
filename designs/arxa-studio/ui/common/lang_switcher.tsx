// lang_switcher.tsx — language switching partial (replaces _lang_switcher.html).
// Plain anchors to the runtime's built-in /prefs/lang route (ADR-0004 prefs
// recipe): boosted requests get h.setPrefs + HX-Refresh; plain navigation gets a
// 302 back. No custom JS, no form — a GET is enough because the cookie is the
// state. Renders nothing for a single-locale artifact.
//
//   import LangSwitcher from './lang_switcher.tsx';
//   <LangSwitcher locales={locales} locale={locale} t={t} />
//
// Reads `locales` and `locale` from the context bag (merged into every render
// by the runtime), so no viewmodel wiring is needed.
import type { FC } from 'hono/jsx';
import { inspectAttrs } from './widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface LangSwitcherProps {
  locales?: string[];
  locale?: string;
  translate: TFn;
}

const LangSwitcher: FC<LangSwitcherProps> = ({ locales, locale, translate }) => {
  if (!locales || locales.length <= 1) return null;
  return (
    <nav class="lang-switcher" aria-label={translate('lang.label') as string} {...inspectAttrs('lang-switcher:nav', { role: 'nav' })}>
      {locales.map((localeOption) => (
        <a
          class="lang-switcher__link"
          href={`/prefs/lang?lang=${localeOption}`}
          aria-current={localeOption === locale ? 'true' : undefined}
          {...inspectAttrs('lang-switcher:locale', { role: 'action' })}
        >
          {translate(`lang.name.${localeOption}`) as string}
        </a>
      ))}
    </nav>
  );
};

export default LangSwitcher;
