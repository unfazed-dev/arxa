// BuildRepository — read-only access to the build fixture (run, stages,
// gates, findings, surfaces). No request context, no facade logic.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/build_model/fixture.json');

export const run = () => data().run;
export const stages = () => data().stages;
export const gates = () => data().gates;
export const surfaces = () => data().surfaces;
export const rollup = () => data().rollup;

export const findings = (severity) => {
  const all = data().findings;
  return severity && severity !== 'all'
    ? all.filter((f) => f.severity === severity)
    : all;
};

export const gate = (id) => data().gates.find((g) => g.id === id);
