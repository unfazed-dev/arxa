// ProjectFacade — composes repositories into view-ready context.
import * as projects from '../repositories/project_repository.js';

// The seed stores platform IDENTIFIERS, because that is what the pipeline
// reads. Presentation names belong here, not in the seed and not in the view.
const PLATFORM = { ios: 'iOS', android: 'Android', macos: 'macOS',
                   windows: 'Windows', linux: 'Linux', web: 'Web', pwa: 'PWA' };

export const list = () => {
  const all = projects.projects().map((p) => ({
    ...p, platforms: p.targets.map((t) => PLATFORM[t] || t).join(', '),
  }));
  return { projects: all, count: all.length };
};
