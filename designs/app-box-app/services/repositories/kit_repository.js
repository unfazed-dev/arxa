// KitRepository — reads one fixture. Repositories are the DB-swap
// seam: a real backend replaces the body of this file and nothing above
// it changes.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/kit_model/kit_fixtures.json');

export const kits = () => data().kits;
export const total = () => data().total;
export const wired = () => data().wired;
