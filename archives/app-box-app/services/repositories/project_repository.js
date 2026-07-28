// ProjectRepository — reads one fixture. Repositories are the DB-swap
// seam: a real backend replaces the body of this file and nothing above
// it changes.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/project_model/project_fixtures.json');

export const projects = () => data().projects;
