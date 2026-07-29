// BuildRepository — read-only access to the generated run fixture.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/build_model/run.json');

export const run = () => data().run;
export const stages = () => data().stages;
export const stage = (id) => data().stages.find((s) => s.id === id);
export const humanGates = () => data().humanGates;
export const findingsByGate = () => data().findingsByGate;
export const evidence = () => data().evidence;
export const chart = () => data().chart;
export const narrative = () => data().narrative;
export const replies = () => data().replies;
export const replyFallback = () => data().replyFallback;
export const counts = () => data().counts;
