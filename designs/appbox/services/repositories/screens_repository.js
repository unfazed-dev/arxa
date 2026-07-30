// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
// ScreensRepository — reads the surface registry. The registry IS the
// screens model (app-architecture contract); repositories are the DB-swap seam.
import { readFixture } from './fixture_reader.js';

const data = () => readFixture('../../models/screens_model/registry.json');

export const all = () => data();

const byShellGroup = (members) =>
  [...new Set(members.map((m) => m.shell))].map((shell) => ({
    shell,
    surfaces: members.filter((m) => m.shell === shell),
  }));

export const byShell = () => {
  const shells = data().filter((e) => e.id.endsWith('.shell'));
  // No shell entries: one implicit shell grouping every surface by shell.
  if (!shells.length) return [{ id: 'main.shell', label: 'Main Shell', shells: byShellGroup(data()) }];
  return shells.map((sh) => {
    const prefix = sh.surface.replace(/_view$/, '_');
    const members = data().filter(
      (e) => e.id !== sh.id && e.surface && e.surface.startsWith(prefix),
    );
    return { ...sh, shells: byShellGroup(members) };
  });
};
