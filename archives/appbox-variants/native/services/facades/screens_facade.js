// ScreensFacade — composes the registry into view-ready context.
// ViewModels talk to facades, never to repositories or fixtures directly.
import * as screens from '../repositories/screens_repository.js';

export const shellIndexContext = () => ({
  shells: screens.byShell(),
  counts: {
    surfaces: screens.all().filter((e) => !e.id.endsWith('.shell')).length,
    shells: screens.all().filter((e) => e.id.endsWith('.shell')).length,
  },
});
