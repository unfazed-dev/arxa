// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// IntakeRepository — reads one per-locale fixture (intake.<locale>.json).
// Unknown locale falls back to en — a partial translation never 500s the page.
import { readFixture } from '../../repositories/fixture_reader.js';

const data = (locale = 'en') => {
  try {
    return readFixture(`../../models/intake_model/intake.${locale}.json`);
  } catch {
    return readFixture('../../models/intake_model/intake.en.json');
  }
};

export const project = (locale = 'en') => data(locale).project;
export const releases = (locale = 'en') => data(locale).map.releases;
export const epics = (locale = 'en') => data(locale).map.epics;
export const story = (id, locale = 'en') => {
  for (const epic of data(locale).map.epics) for (const feature of epic.features) {
    const matchedStory = feature.stories.find((candidate) => candidate.id === id);
    if (matchedStory) return matchedStory;
  }
  return null;
};
export const counts = (locale = 'en') => data(locale).counts;
export const brief = (locale = 'en') => data(locale).brief;
export const moodboard = (locale = 'en') => data(locale).moodboard;
export const shot = (id, locale = 'en') => {
  for (const board of data(locale).moodboard.boards) for (const reference of board.references) {
    if (reference.shot.id === id) return { board: board, reference: reference, shot: reference.shot };
  }
  return null;
};
export const narrative = (surface, locale = 'en') => data(locale).narrative[surface] ?? [];
export const replies = (locale = 'en') => data(locale).replies;
export const replyFallback = (locale = 'en') => data(locale).replyFallback;
export const questionBanks = (locale = 'en') => data(locale).questionBanks;
// The typeform steps' prefills: personas, flows over the screen registry,
// and the design direction (adjectives / avoids / moodboard references).
export const personas = (locale = 'en') => data(locale).personas ?? [];
export const flows = (locale = 'en') => data(locale).flows ?? [];
export const direction = (locale = 'en') => data(locale).direction ?? { adjectives: [], avoids: [], references: [] };
// Live-map display data: pipeline status per story id, and the generated
// file list for the files activity view. Absent keys read as 'pending'.
export const statuses = (locale = 'en') => data(locale).statuses ?? {};
export const files = (locale = 'en') => data(locale).files ?? [];
// Initial interview state; the facade clones it into the session.
export const initialState = (locale = 'en') => data(locale).state;
