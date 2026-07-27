// ChatFacade — the transcript.
import * as chat from '../repositories/chat_repository.js';

export const transcript = () => ({ messages: chat.messages() });
