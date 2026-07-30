// DesignRepository — reads one per-locale fixture (run.<locale>.json).
// Unknown locale falls back to en — a partial translation never 500s the page.
import { readFixture } from './fixture_reader.js';

const data = (locale = 'en') => {
  try {
    return readFixture(`../../models/design_model/run.${locale}.json`);
  } catch {
    return readFixture('../../models/design_model/run.en.json');
  }
};

export const run = (locale = 'en') => data(locale).run;
export const line = (locale = 'en') => data(locale).line;
export const screens = (locale = 'en') => data(locale).screens;
export const screen = (id, locale = 'en') => data(locale).screens.find((s) => s.id === id);
export const epics = (locale = 'en') => data(locale).epics;
export const counts = (locale = 'en') => data(locale).counts;
export const draft = (locale = 'en') => data(locale).draft;
export const approval = (locale = 'en') => data(locale).approval;
export const noContext = (locale = 'en') => data(locale).noContext;
export const artifacts = (locale = 'en') => data(locale).artifacts;
export const files = (locale = 'en') => data(locale).files;
export const manifest = (locale = 'en') => data(locale).manifest;
export const trace = (locale = 'en') => data(locale).trace;
export const traceability = (locale = 'en') => data(locale).traceability;
export const drift = (locale = 'en') => data(locale).drift;
export const designThread = (locale = 'en') => data(locale).designThread;
export const checkpoints = (locale = 'en') => data(locale).checkpoints;
export const chatReplies = (locale = 'en') => data(locale).chatReplies;
export const chatFallback = (locale = 'en') => data(locale).chatFallback;
