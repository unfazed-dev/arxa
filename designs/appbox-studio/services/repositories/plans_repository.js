// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// PlansRepository — reads one per-locale fixture (plans.<locale>.json).
// Unknown locale falls back to en — a partial translation never 500s the page.
import { readFixture } from './fixture_reader.js';

const data = (locale = 'en') => {
  try {
    return readFixture(`../../models/plans_model/plans.${locale}.json`);
  } catch {
    return readFixture('../../models/plans_model/plans.en.json');
  }
};

export const account = (locale = 'en') => data(locale).account;
export const plans = (locale = 'en') => data(locale).plans;
export const checkout = (locale = 'en') => data(locale).checkout;
