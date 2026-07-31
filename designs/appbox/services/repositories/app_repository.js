// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// AppRepository — reads one per-locale fixture (app.<locale>.json). Unknown
// locale falls back to en — a partial translation never 500s the page.
import { readFixture } from './fixture_reader.js';

const data = (locale = 'en') => {
  try {
    return readFixture(`../../models/app_model/app.${locale}.json`);
  } catch {
    return readFixture('../../models/app_model/app.en.json');
  }
};

export const account = (locale = 'en') => data(locale).account;
export const tagline = (locale = 'en') => data(locale).tagline;
export const auth = (locale = 'en') => data(locale).auth;
export const projects = (locale = 'en') => data(locale).projects;
export const gates = (locale = 'en') => data(locale).gates;
export const stats = (locale = 'en') => data(locale).stats;
export const pairing = (locale = 'en') => data(locale).pairing;
export const wizard = (locale = 'en') => data(locale).wizard;
export const counts = (locale = 'en') => data(locale).counts;
