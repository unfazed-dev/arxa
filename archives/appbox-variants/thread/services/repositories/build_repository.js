// BuildRepository — read-only access to the generated run fixture.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/build_model/run.json');

export const run = () => data().run;
export const stages = () => data().stages;
export const humanGates = () => data().humanGates;
export const findingsByGate = () => data().findingsByGate;
export const findings = () => data().findings;
export const filters = () => data().filters;
export const evidence = () => data().evidence;
export const counts = () => data().counts;
export const thread = () => data().thread;
export const pace = () => data().pace;
export const gateChart = () => data().gateChart;
export const artifacts = () => data().artifacts;
