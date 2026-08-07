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

export interface L10n {
  catalogs: Record<string, Record<string, string>>;
  locales: string[];
  createT(opts?: { locale?: string; level?: string }): (key: string, vars?: Record<string, unknown>) => string;
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
  render(c: Context, viewRef: string, ctx?: Record<string, unknown>, status?: number): Response | Promise<Response>;
  form(c: Context): Promise<Record<string, unknown>>;
  session(c: Context): SessionData | null;
  prefs(c: Context): Prefs;
  locale(c: Context): string;
  t(c: Context): (key: string, vars?: Record<string, unknown>) => string;
  setPrefs(c: Context, patch: Partial<Prefs>): void;
  timers: Timers;
  sse: Sse;
  noContent(c: Context): Response;
  stopPolling(c: Context): Response;
  refresh(c: Context): Response;
  location(c: Context, url: string): Response;
}
