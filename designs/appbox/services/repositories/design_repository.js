// DesignRepository — read-only access to the generated design fixture.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/design_model/run.json');

export const run = () => data().run;
export const line = () => data().line;
export const screens = () => data().screens;
export const screen = (id) => data().screens.find((s) => s.id === id);
export const epics = () => data().epics;
export const counts = () => data().counts;
export const manifest = () => data().manifest;
export const trace = () => data().trace;
export const traceability = () => data().traceability;
export const drift = () => data().drift;
export const chatThreads = () => data().chatThreads;
export const checkpoints = () => data().checkpoints;
export const chatReplies = () => data().chatReplies;
export const chatFallback = () => data().chatFallback;
export const protoReplies = () => data().protoReplies;
export const protoFallback = () => data().protoFallback;
