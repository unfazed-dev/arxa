// GreetingFacade — composes repositories into view-ready context.
// ViewModels talk to facades, never to repositories or fixtures directly.
// The locale comes from the request (h.locale(c)); the facade picks the
// per-locale fixture.
import * as greetings from '../repositories/greeting_repository.js';

export const homeContext = (locale = 'en') => {
  const all = greetings.all(locale);
  return {
    // rows: greetings projected onto the shared list-row component's shape
    rows: all.map((g) => ({ id: g.id, title: g.text, icon: 'message-circle' })),
    count: all.length,
  };
};
