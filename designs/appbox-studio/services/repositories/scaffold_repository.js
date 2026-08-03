// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ScaffoldRepository — reads one per-locale fixture (scaffold.<locale>.json).
// Unknown locale falls back to en — a partial translation never 500s the page.
import { readFixture } from './fixture_reader.js';

const data = (locale = 'en') => {
  try {
    return readFixture(`../../models/scaffold_model/scaffold.${locale}.json`);
  } catch {
    return readFixture('../../models/scaffold_model/scaffold.en.json');
  }
};

export const kits = (locale = 'en') => data(locale).kits;
export const groups = (locale = 'en') => data(locale).groups;
export const counts = (locale = 'en') => data(locale).counts;
export const manifest = (locale = 'en') => data(locale).manifest;
export const entitlement = (locale = 'en') => data(locale).entitlement;
export const essentials = (locale = 'en') => data(locale).essentials;
export const states = (locale = 'en') => data(locale).states;
