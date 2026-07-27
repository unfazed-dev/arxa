// GreetingRepository — reads one fixture. Repositories are the DB-swap seam:
// a real backend replaces the body of this file and nothing above it changes.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/greeting_model/greeting_fixtures.json');

export const all = () => data().greetings;
export const byId = (id) => data().greetings.find((g) => g.id === id);
