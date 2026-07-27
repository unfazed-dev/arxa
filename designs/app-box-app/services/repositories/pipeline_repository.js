// PipelineRepository — reads one fixture. Repositories are the DB-swap
// seam: a real backend replaces the body of this file and nothing above
// it changes.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/pipeline_model/pipeline_fixtures.json');

export const stages = () => data().stages;
export const log = () => data().log;
export const findings = () => data().findings;
export const release = () => data().release;
