// ScreensRepository — reads the surface registry. The registry IS the
// screens model (app-architecture contract); repositories are the DB-swap seam.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/screens_model/registry.json');

export const all = () => data();

export const byShell = () => {
  const shells = data().filter((e) => e.id.endsWith('.shell'));
  return shells.map((sh) => {
    const prefix = sh.surface.replace(/_view$/, '_');
    const members = data().filter(
      (e) => e.id !== sh.id && e.surface && e.surface.startsWith(prefix),
    );
    const tabs = [...new Set(members.map((m) => m.tab))].map((tab) => ({
      tab,
      surfaces: members.filter((m) => m.tab === tab),
    }));
    return { ...sh, tabs };
  });
};
