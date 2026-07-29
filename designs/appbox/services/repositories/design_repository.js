// DesignRepository — read-only access to the generated design fixture.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/design_model/run.json');

export const run = () => data().run;
export const line = () => data().line;
export const screens = () => data().screens;
export const screen = (id) => data().screens.find((s) => s.id === id);
export const epics = () => data().epics;
export const counts = () => data().counts;
export const draft = () => data().draft;
export const approval = () => data().approval;
export const noContext = () => data().noContext;
export const artifacts = () => data().artifacts;
export const files = () => data().files;
export const manifest = () => data().manifest;
export const trace = () => data().trace;
export const traceability = () => data().traceability;
export const drift = () => data().drift;
export const designThread = () => data().designThread;
export const checkpoints = () => data().checkpoints;
export const chatReplies = () => data().chatReplies;
export const chatFallback = () => data().chatFallback;
