// GreetingRepository — reads one per-locale fixture. Repositories are the
// DB-swap seam: a real backend replaces the body of this file and nothing
// above it changes. Unknown locale falls back to en — a partial translation
// never 500s the page.
import { readFixture } from './fixture_reader.js';

const data = (locale) =>
  readFixture(`../../models/greeting_model/greeting_fixtures.${locale}.json`);

export const all = (locale = 'en') => {
  try {
    return data(locale).greetings;
  } catch {
    return data('en').greetings;
  }
};
export const byId = (id, locale = 'en') => all(locale).find((g) => g.id === id);
