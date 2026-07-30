// BuildRepository — reads one per-locale fixture (run.<locale>.json). Unknown
// locale falls back to en — a partial translation never 500s the page.
import { readFixture } from './fixture_reader.js';

const data = (locale = 'en') => {
  try {
    return readFixture(`../../models/build_model/run.${locale}.json`);
  } catch {
    return readFixture('../../models/build_model/run.en.json');
  }
};

export const run = (locale = 'en') => data(locale).run;
export const stages = (locale = 'en') => data(locale).stages;
export const stage = (id, locale = 'en') => data(locale).stages.find((s) => s.id === id);
export const humanGates = (locale = 'en') => data(locale).humanGates;
export const findingsByGate = (locale = 'en') => data(locale).findingsByGate;
export const evidence = (locale = 'en') => data(locale).evidence;
export const chart = (locale = 'en') => data(locale).chart;
export const narrative = (locale = 'en') => data(locale).narrative;
export const replies = (locale = 'en') => data(locale).replies;
export const replyFallback = (locale = 'en') => data(locale).replyFallback;
export const counts = (locale = 'en') => data(locale).counts;
// Seeded rail-view data — the real git wiring is a later stage.
export const commits = (locale = 'en') => data(locale).commits;
export const files = (locale = 'en') => data(locale).files;
