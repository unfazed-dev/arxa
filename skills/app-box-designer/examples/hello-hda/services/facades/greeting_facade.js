// GreetingFacade — composes repositories into view-ready context.
// ViewModels talk to facades, never to repositories or fixtures directly.
import * as greetings from '../repositories/greeting_repository.js';

export const homeContext = () => ({
  greetings: greetings.all(),
  count: greetings.all().length,
});
