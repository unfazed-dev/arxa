// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ScaffoldRepository — reads one per-locale fixture (scaffold.<locale>.json).
// Unknown locale falls back to en — a partial translation never 500s the page.
import { readFixture, writeProjectFixture } from './fixture_reader.js';

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

// D8: the picker-confirmed selection persists as a kit-manifest.json sidecar
// BESIDE the project's frozen structure.json (design/), so `appbox emit
// scaffold` consumes `resolved` verbatim. Writes go through the one confined
// channel (POST /__project_write), like every other studio edit.
export const writeKitManifest = (manifest) =>
  writeProjectFixture('design/kit-manifest.json', manifest);
