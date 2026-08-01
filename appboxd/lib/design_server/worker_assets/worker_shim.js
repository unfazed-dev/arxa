// worker_shim.js — the Hono-equivalent shim. Ports lib/helpers.mjs +
// lib/templates.mjs + lib/l10n.mjs + lib/state.mjs + lib/timers.mjs semantics
// into the browser worker tab. Viewmodels call handler(c, h) and cannot tell
// the difference from Hono.
//
// Dart pre-populates (before __boot):
//   globalThis.__templates  {path: src}   every .html under the artifact
//   globalThis.__fixtures   {absUrl: txt} every models/**/*.json (fs_shim keys)
//   globalThis.__arb        {locale: {key: val}}  l10n/*.arb parsed
//   globalThis.__icons      {name: rawSvg}        lucide icons referenced
/* global nunjucks */
(function () {
  'use strict';
  let env = null;
  let routesTable = [];

  // ── l10n (port of lib/l10n.mjs) ───────────────────────────────────────
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  function parsePlural(str) {
    const head = String(str).match(/^\{\s*(\w+)\s*,\s*plural\s*,\s*/);
    if (!head || !str.endsWith('}')) return null;
    const options = {};
    let i = head[0].length;
    while (i < str.length - 1) {
      while (str[i] === ' ') i++;
      const kw = str.slice(i).match(/^(=\d+|zero|one|two|few|many|other)\s*\{/);
      if (!kw) return null;
      let depth = 1, j = i + kw[0].length;
      const start = j;
      while (j < str.length && depth > 0) {
        if (str[j] === '{') depth++;
        else if (str[j] === '}') depth--;
        if (depth > 0) j++;
      }
      if (depth !== 0) return null;
      options[kw[1]] = str.slice(start, j);
      i = j + 1;
    }
    return { varName: head[1], options };
  }
  const interpolate = (text, vars) =>
    text.replace(/\{(\w+)\}/g, (m, name) => (vars && name in vars ? esc(vars[name]) : m));
  const selectPlural = (locale, n) => new Intl.PluralRules(locale).select(n);
  function translate(catalog, locale, key, vars) {
    const value = catalog[key];
    if (typeof value !== 'string') return undefined;
    const plural = parsePlural(value);
    if (plural) {
      const n = Number(vars && vars[plural.varName]);
      if (Number.isNaN(n)) return value;
      const picked = plural.options['=' + n] ?? plural.options[selectPlural(locale, n)] ?? plural.options.other;
      return picked === undefined ? value : interpolate(picked, vars);
    }
    return interpolate(value, vars);
  }
  function createT(locale, level) {
    const catalogs = globalThis.__arb || {};
    const cat = catalogs[locale] || {};
    const en = catalogs.en || {};
    return function (key, vars) {
      const variants = level === 'plain' ? [key + 'Plain', key]
        : level === 'technical' ? [key + 'Technical', key] : [key];
      for (const k of variants) {
        const hit = translate(cat, locale, k, vars) || translate(en, 'en', k, vars);
        if (hit !== undefined) return new nunjucks.runtime.SafeString(hit);
      }
      return new nunjucks.runtime.SafeString(key);
    };
  }
  const locales = Object.keys(globalThis.__arb || {}).sort((a, b) =>
    (a === 'en' ? -1 : b === 'en' ? 1 : a.localeCompare(b)));

  // ── templates (port of lib/templates.mjs) ─────────────────────────────
  // Loader reads from Dart-prefetched globalThis.__templates — synchronous,
  // deterministic, no async fetch on the render path.
  const prefetchedLoader = {
    async: false,
    getSource(name) {
      const src = globalThis.__templates[name];
      if (src === undefined) throw new Error('no template prefetched: ' + name);
      return { src: src, path: name, noCache: true };
    },
  };

  const NAME_RE = /^[a-z0-9-]+$/;
  function icon(name, opts) {
    opts = opts || {};
    const size = opts.size != null ? opts.size : 24;
    const placeholder = '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false"' + (opts.cls ? ' class="' + esc(opts.cls) + '"' : '') + '><rect x="3" y="3" width="18" height="18" rx="3" stroke-dasharray="4 3"/></svg>';
    if (typeof name !== 'string' || !NAME_RE.test(name)) return new nunjucks.runtime.SafeString(placeholder);
    const raw = (globalThis.__icons || {})[name];
    if (!raw) return new nunjucks.runtime.SafeString(placeholder);
    const openTag = (raw.match(/<svg[^>]*>/) || [''])[0];
    let open = openTag.replace(/\s+class="[^"]*"/, '').replace(/\s+width="[^"]*"/, '').replace(/\s+height="[^"]*"/, '');
    if (opts.strokeWidth != null) open = open.replace(/stroke-width="[^"]*"/, 'stroke-width="' + Number(opts.strokeWidth) + '"');
    open = open.replace(/<svg/, '<svg width="' + size + '" height="' + size + '"' +
      (opts.cls ? ' class="' + esc(opts.cls) + '"' : '') +
      (opts.label ? ' role="img" aria-label="' + esc(opts.label) + '"' : ' aria-hidden="true" focusable="false"'));
    const head = raw.slice(0, raw.indexOf(openTag));
    let out = head + open + raw.slice(raw.indexOf(openTag) + openTag.length);
    if (opts.label) out = out.replace(/(<svg[^>]*>)/, '$1<title>' + esc(opts.label) + '</title>');
    return new nunjucks.runtime.SafeString(out);
  }

  function templatesRender(viewRef, ctx) {
    env.addGlobal('t', createT(ctx.locale, ctx.prefs && ctx.prefs.jargon));
    const hash = viewRef.indexOf('#');
    if (hash === -1) return env.render(viewRef, ctx);
    const file = viewRef.slice(0, hash);
    const macro = viewRef.slice(hash + 1);
    return env.renderString('{% import "' + file + '" as f %}{{ f.' + macro + '(c) }}', ctx);
  }

  // ── timers (port of lib/timers.mjs) — seeded from Dart state ──────────
  let timerStore = {};
  const timers = {
    start(id, seconds) { timerStore[id] = { deadline: Date.now() + seconds * 1000 }; },
    extend(id, seconds) { const t = timerStore[id]; if (t) t.deadline += seconds * 1000; },
    remaining(id) { const t = timerStore[id]; if (!t) return null; return Math.max(0, Math.ceil((t.deadline - Date.now()) / 1000)); },
    stop(id) { delete timerStore[id]; },
  };

  // ── request context: the fake Hono `c` ────────────────────────────────
  function parseCookies(h) {
    const c = h['cookie'] || h['Cookie'] || '';
    const out = {};
    c.split(';').forEach((p) => { const i = p.indexOf('='); if (i > -1) out[p.slice(0, i).trim()] = decodeURIComponent(p.slice(i + 1).trim()); });
    return out;
  }
  function parseQs(path) {
    const q = path.indexOf('?'); const out = {};
    if (q === -1) return out;
    for (const pair of path.slice(q + 1).split('&')) { const i = pair.indexOf('='); if (i > -1) out[decodeURIComponent(pair.slice(0, i))] = decodeURIComponent(pair.slice(i + 1)); }
    return out;
  }
  function parseForm(body) {
    const out = {};
    if (!body) return out;
    for (const pair of body.split('&')) { const i = pair.indexOf('='); if (i > -1) out[decodeURIComponent(pair.slice(0, i).replace(/\+/g, ' '))] = decodeURIComponent(pair.slice(i + 1).replace(/\+/g, ' ')); }
    return out;
  }

  function makeC(method, fullPath, headers, body, state, params) {
    const hlc = {}; for (const k in headers) hlc[k.toLowerCase()] = headers[k];
    const cookies = parseCookies(hlc);
    const qs = parseQs(fullPath);
    const pathOnly = fullPath.split('?')[0];
    const resHeaders = {};
    let status = 200;
    let resBody = null;
    const vars = {};
    const setCookies = [];
    // seed per-request state from Dart
    vars.kdh_session = state.session ? { id: state.session.id, data: Object.assign({}, state.session.data) } : null;
    vars.locale = state.locale || 'en';
    timerStore = Object.assign({}, state.timers || {});
    return {
      req: {
        method, path: pathOnly,
        param: (k) => params[k],
        query: (k) => qs[k],
        header: (k) => hlc[k.toLowerCase()],
        parseBody: async () => parseForm(body),
      },
      get: (k) => vars[k],
      set: (k, v) => { vars[k] = v; },
      status: (s) => { status = s; },
      html: (s) => { resHeaders['content-type'] = 'text/html; charset=utf-8'; resBody = s; return s; },
      text: (s, st) => { resHeaders['content-type'] = 'text/plain; charset=utf-8'; resBody = s; if (st != null) status = st; return s; },
      body: (b) => { resBody = b; return b; },
      header: (k, v, opts) => {
        const kl = k.toLowerCase();
        if (opts && opts.append) resHeaders[kl] = resHeaders[kl] ? resHeaders[kl] + ', ' + v : v;
        else resHeaders[kl] = v;
      },
      redirect: (url, st) => { resHeaders['location'] = url; status = st != null ? st : 302; },
      setCookie: (name, val, opts2) => {
        let c2 = name + '=' + encodeURIComponent(val) + '; Path=' + (opts2 && opts2.path || '/');
        if (opts2 && opts2.httpOnly) c2 += '; HttpOnly';
        if (opts2 && opts2.sameSite) c2 += '; SameSite=' + opts2.sameSite;
        if (opts2 && opts2.maxAge != null) c2 += '; Max-Age=' + opts2.maxAge;
        setCookies.push(c2);
      },
      res: { headers: { get: (k) => resHeaders[k.toLowerCase()] } },
      _collect: () => ({ status, headers: resHeaders, body: resBody, setCookies, session: vars.kdh_session, timers: timerStore, locale: vars.locale }),
      _cookies: cookies,
    };
  }

  // ── helpers (port of lib/helpers.mjs) ─────────────────────────────────
  function makeHelpers() {
    return {
      render(c, viewRef, ctx, st) {
        ctx = ctx || {};
        const prefs = c._cookies.kdh_prefs ? safeJson(c._cookies.kdh_prefs) : {};
        const bag = Object.assign({ prefs, locale: c.get('locale') || 'en', locales }, ctx);
        bag.c = bag;
        if (st != null) c.status(st);
        return c.html(templatesRender(viewRef, bag));
      },
      form: (c) => c.req.parseBody(),
      session: (c) => c.get('kdh_session'),
      prefs: (c) => c._cookies.kdh_prefs ? safeJson(c._cookies.kdh_prefs) : {},
      locale: (c) => c.get('locale') || 'en',
      t: (c) => createT(c.get('locale') || 'en', (safeJson(c._cookies.kdh_prefs || '{}')).jargon),
      setPrefs(c, patch) {
        const cur = c._cookies.kdh_prefs ? safeJson(c._cookies.kdh_prefs) : {};
        c.setCookie('kdh_prefs', JSON.stringify(Object.assign({}, cur, patch)), { path: '/', maxAge: 31536000, sameSite: 'Lax' });
      },
      timers,
      noContent: (c) => { c.status(204); return c.body(null); },
      stopPolling: (c) => { c.status(286); return c.body(null); },
      refresh: (c) => { c.header('HX-Refresh', 'true'); return c.body(null); },
      location: (c, url) => { c.header('HX-Location', url); return c.body(null); },
    };
  }
  function safeJson(s) { try { return JSON.parse(s); } catch (_) { return {}; } }

  // ── public worker API ─────────────────────────────────────────────────
  globalThis.__boot = async function (artifactBase) {
    env = new nunjucks.Environment(prefetchedLoader, { autoescape: true, throwOnUndefined: false });
    env.addGlobal('icon', icon);
    env.addGlobal('t', createT('en'));
    const mod = await import(/* @vite-ignore */ artifactBase + '/app.routes.js');
    routesTable = mod.default;
    return true;
  };
  globalThis.__routes = function () {
    return routesTable.map(function (r) { return [r[0], r[1]]; });
  };
  globalThis.__dispatch = async function (method, fullPath, headers, body, state) {
    state = state || {};
    const pathOnly = fullPath.split('?')[0];
    let entry = null; let params = {};
    for (const r of routesTable) {
      if (r[0] !== method) continue;
      const p = matchParams(r[1], pathOnly);
      if (p) { entry = r; params = p; break; }
    }
    if (!entry) return JSON.stringify({ status: 404, headers: { 'content-type': 'text/plain; charset=utf-8' }, body: '404 \u2014 no route for ' + method + ' ' + pathOnly, setCookies: [], timers: state.timers || {}, locale: state.locale || 'en' });
    const c = makeC(method, fullPath, headers || {}, body, state, params);
    const h = makeHelpers();
    try {
      await entry[2](c, h);
    } catch (err) {
      // Hono's onError: a throwing handler answers 500 — it never takes the
      // request path (or the design server) down with it.
      return JSON.stringify({ status: 500, headers: { 'content-type': 'text/plain; charset=utf-8' }, body: '500 \u2014 handler threw: ' + ((err && err.message) || err), setCookies: [], timers: state.timers || {}, locale: state.locale || 'en' });
    }
    const r = c._collect();
    return JSON.stringify(r);
  };
  // :param matcher (Hono :segments only — no wildcards in appbox routes).
  // Returns the extracted params map on match, null on mismatch.
  function matchParams(pattern, path) {
    const pp = pattern.split('/'); const ap = path.split('/');
    if (pp.length !== ap.length) return null;
    const params = {};
    for (let i = 0; i < pp.length; i++) {
      if (pp[i].startsWith(':')) { params[pp[i].slice(1)] = decodeURIComponent(ap[i]); continue; }
      if (pp[i] !== ap[i]) return null;
    }
    return params;
  }
})();
