// IntakeRepository — read-only access to the generated intake fixture.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/intake_model/intake.json');

export const project = () => data().project;
export const releases = () => data().map.releases;
export const epics = () => data().map.epics;
export const story = (id) => {
  for (const e of data().map.epics) for (const f of e.features) {
    const s = f.stories.find((x) => x.id === id);
    if (s) return s;
  }
  return null;
};
export const counts = () => data().counts;
export const brief = () => data().brief;
export const moodboard = () => data().moodboard;
export const shot = (id) => {
  for (const b of data().moodboard.boards) for (const r of b.references) {
    if (r.shot.id === id) return { board: b, reference: r, shot: r.shot };
  }
  return null;
};
export const narrative = (surface) => data().narrative[surface] ?? [];
export const replies = () => data().replies;
export const replyFallback = () => data().replyFallback;
export const questionBanks = () => data().questionBanks;
// Live-map display data: pipeline status per story id, and the generated
// file list for the files rail view. Absent keys read as 'pending'.
export const statuses = () => data().statuses ?? {};
export const files = () => data().files ?? [];
// Initial interview state; the facade clones it into the session.
export const initialState = () => data().state;
