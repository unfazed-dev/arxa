// worker_shim.js — the Hono-equivalent shim. Ports lib/helpers.mjs +
// lib/l10n.mjs + lib/state.mjs + lib/timers.mjs semantics into the browser
// worker tab. Viewmodels call handler(c, h) and cannot tell the difference
// from Hono.
//
// Dart pre-populates (before __boot):
//   globalThis.__renderBundleUrl  blob:      esbuild-bundled TSX render module
//   globalThis.__templates  {path: src}      .html partials (project surfaces)
//   globalThis.__fixtures   {absUrl: txt} every models/**/*.json (fs_shim keys)
//   globalThis.__arb        {locale: {key: val}}  l10n/*.arb parsed
//   globalThis.__icons      {name: rawSvg}        lucide icons referenced
(function () {
  'use strict';
  let renderModule = null; // { render(viewRef, ctx) } — set by __boot
  let routesTable = [];

  // ── l10n (port of lib/l10n.mjs) ───────────────────────────────────────
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  // hono/jsx raw(): marks a string as pre-escaped so JSX rendering does not
  // double-escape it. The t() function pre-escapes via interpolate(), so its
  // return values must carry isEscaped = true.
  function raw(s) {
    const r = new String(s);
    r.isEscaped = true;
    return r;
  }

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
        if (hit !== undefined) return raw(hit);
      }
      return raw(key);
    };
  }
  const locales = Object.keys(globalThis.__arb || {}).sort((a, b) =>
    (a === 'en' ? -1 : b === 'en' ? 1 : a.localeCompare(b)));

  // ── TSX rendering ─────────────────────────────────────────────────────
  // The bundled render module exports render(viewRef, ctx) which returns a
  // hono/jsx JSXNode. String() converts it to an HTML string.
  function templatesRender(viewRef, ctx) {
    return String(renderModule.render(viewRef, ctx));
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
    for (const pair of body.split('&')) { const i = pair.indexOf('='); if (i > -1) { const k = decodeURIComponent(pair.slice(0, i).replace(/\+/g, ' ')); const v = decodeURIComponent(pair.slice(i + 1).replace(/\+/g, ' ')); if (k in out) out[k] = [].concat(out[k], v); else out[k] = v; } }
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
        const t = createT(c.get('locale') || 'en', prefs.jargon);
        // If ctx.partial is a string file path (e.g. 'ui/project/home.html'),
        // pre-render it through the TSX render module so the component receives
        // ready-made content instead of a raw path string. This replaces the
        // old nunjucks {% include partial %} dynamic-include pattern.
        if (typeof ctx.partial === 'string' && ctx.partial) {
          const partialCtx = Object.assign({ prefs, locale: c.get('locale') || 'en', locales, t }, ctx);
          partialCtx.c = partialCtx;
          try {
            const rendered = String(renderModule.render(ctx.partial, partialCtx));
            ctx.partial = raw(rendered);
          } catch (e) {
            // Partial not in registry or render error — leave as-is (falls back
            // to the generic placeholder in screen_stub_view.tsx).
          }
        }
        const bag = Object.assign({ prefs, locale: c.get('locale') || 'en', locales, t }, ctx);
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
    // Import the TSX render module from the blob URL Dart injected.
    renderModule = await import(globalThis.__renderBundleUrl);
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
