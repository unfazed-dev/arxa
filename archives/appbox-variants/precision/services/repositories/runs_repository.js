// RunsRepository — read-only access to the generated run fixture.
import { readFixture } from './fixture_reader.js';

const run = () => readFixture('../../models/runs_model/run.fixture.json');

export const current = () => run();
