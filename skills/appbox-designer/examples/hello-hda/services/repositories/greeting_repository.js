// GreetingRepository — reads one per-locale fixture. Repositories are the
// DB-swap seam: a real backend replaces the body of this file and nothing
// above it changes. Unknown locale falls back to en — a partial translation
// never 500s the page.
import { readFixture } from './fixture_reader.js';

/** @param {string} locale */
const data = (locale) =>
  /** @type {{ greetings: Array<{ id: string, text: string }> }} */
  (readFixture(`../../models/greeting_model/greeting_fixtures.${locale}.json`));

/** @param {string} [locale] */
export const all = (locale = 'en') => {
  try {
    return data(locale).greetings;
  } catch {
    return data('en').greetings;
  }
};
/** @param {string} id @param {string} [locale] */
export const byId = (id, locale = 'en') => all(locale).find((/** @type {{ id: string, text: string }} */ g) => g.id === id);
