// GreetingFacade — composes repositories into view-ready context.
// ViewModels talk to facades, never to repositories or fixtures directly.
import * as greetings from '../repositories/greeting_repository.js';

export const homeContext = () => {
  const all = greetings.all();
  return {
    // rows: greetings projected onto the shared list-row component's shape
    rows: all.map((g) => ({ id: g.id, title: g.text, icon: 'message-circle' })),
    count: all.length,
  };
};
