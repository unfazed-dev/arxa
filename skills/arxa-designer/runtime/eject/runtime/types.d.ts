// runtime/types.d.ts — runtime type surface.
// Imported by JSDoc annotations across runtime/*.js and artifact viewmodels.

import type { Context } from 'hono';

export type { Context };
export type Next = () => Promise<Response | void>;

export interface Prefs {
  lang?: string;
  theme?: string;
  accent?: string;
  jargon?: string;
  [key: string]: unknown;
}

export interface SessionData {
  id: string;
  data: Record<string, unknown>;
}

export type Translate = (key: string, vars?: Record<string, unknown>) => unknown;

export interface L10n {
  catalogs: Record<string, Record<string, string>>;
  locales: string[];
  createT(opts?: { locale?: string; level?: string }): (key: string, vars?: Record<string, unknown>) => string;
  createTranslator(opts?: { locale?: string; level?: string }): (key: string, vars?: Record<string, unknown>) => string;
}

export interface Timers {
  start(id: string, seconds: number): void;
  extend(id: string, seconds: number): void;
  remaining(id: string): number | null;
  stop(id: string): void;
}

export interface Sse {
  publishPatch(channel: string, html: string): void;
  publishEvent(channel: string, eventName: string, html?: string): void;
}

export interface Helpers {
  render(context: Context, viewRef: string, ctx?: Record<string, unknown>, status?: number): Response | Promise<Response>;
  form(context: Context): Promise<Record<string, unknown>>;
  session(context: Context): SessionData | null;
  prefs(context: Context): Prefs;
  locale(context: Context): string;
  translate(context: Context): (key: string, vars?: Record<string, unknown>) => string;
  setPrefs(context: Context, patch: Partial<Prefs>): void;
  timers: Timers;
  sse: Sse;
  noContent(context: Context): Response;
  stopPolling(context: Context): Response;
  refresh(context: Context): Response;
  location(context: Context, url: string): Response;
}
