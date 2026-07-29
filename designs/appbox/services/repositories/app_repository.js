// AppRepository — read-only access to the generated app-shell fixture.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/app_model/app.json');

export const account = () => data().account;
export const tagline = () => data().tagline;
export const auth = () => data().auth;
export const projects = () => data().projects;
export const gates = () => data().gates;
export const stats = () => data().stats;
export const pairing = () => data().pairing;
export const wizard = () => data().wizard;
export const counts = () => data().counts;
