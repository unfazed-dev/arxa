// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ScaffoldRunRepository — reads one per-locale fixture (scaffold_run.<locale>.json).
// Unknown locale falls back to en — a partial translation never 500s the page.
//
// Deliberately separate from scaffold_repository: the picker's model answers
// "which kits could be chosen", this one answers "what did a run produce".
// A receipt reads its own recorded snapshot rather than re-querying the
// picker, so a later edit to the kit catalogue cannot retroactively rewrite
// the history of a run that already happened.
import { readFixture } from './fixture_reader.js';

const data = (locale = 'en') => {
  try {
    return readFixture(`../../models/scaffold_run_model/scaffold_run.${locale}.json`);
  } catch {
    return readFixture('../../models/scaffold_run_model/scaffold_run.en.json');
  }
};

export const structure = (locale = 'en') => data(locale).structure;
export const manifest = (locale = 'en') => data(locale).manifest;
export const kits = (locale = 'en') => data(locale).kits;
export const writes = (locale = 'en') => data(locale).writes;
export const deltas = (locale = 'en') => data(locale).deltas;
export const warnings = (locale = 'en') => data(locale).warnings;
export const states = (locale = 'en') => data(locale).states;
export const counts = (locale = 'en') => data(locale).counts;
export const unready = (locale = 'en') => data(locale).unready;
