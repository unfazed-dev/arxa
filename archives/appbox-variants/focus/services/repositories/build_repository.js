// BuildRepository — read-only access to the generated run fixture.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/build_model/run.json');

export const run = () => data().run;
export const stages = () => data().stages;
export const humanGates = () => data().humanGates;
export const findings = () => data().findings;
export const chart = () => data().chart;
export const counts = () => data().counts;
