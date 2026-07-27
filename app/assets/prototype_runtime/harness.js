// app/assets/prototype_runtime/harness.js -- app_box embedded prototype runtime.
//
// Loaded into the JS engine (JavaScriptCore on Apple platforms via flutter_js)
// AFTER the nunjucks browser bundle and BEFORE the per-design artifact bundle.
// It provides the Hono-style `c` (request context) and `h` (helpers) that the
// designer's viewmodels expect (matching skills/app-box-designer/runtime/lib/
// helpers.mjs + state.mjs + templates.mjs), a host-backed nunjucks loader so
// templates read through the Dart bridge, and a single `__dispatch` entry the
// Dart HttpServer calls per request.
//
// Only the routing/dispatch layer lives here -- the viewmodels, services,
// models and templates are untouched and bundled separately (9.3). Fixture
// reads go through the host __readFileSync bridge (9.4); the readFixture
// contract is unchanged.
(function (globalThis) {
  'use strict';

  // Host bridges: when running under flutter_js, `sendMessage` is a global the
  // runtime registers (a synchronous JSObjectMakeFunctionWithCallback). The
  // wrappers marshal their argument as a JSON string -- the Dart side decodes
  // it and its return value is handed back synchronously. Under the Node proof
  // harness `sendMessage` is absent, so the host functions the harness injects
  // (real fs reads) stay in place.
  if (typeof globalThis.sendMessage === 'function') {
    globalThis.__readTemplate = function (name) {
      return globalThis.sendMessage('readTemplate', JSON.stringify(name));
    };
    globalThis.__readFileSync = function (p) {
      return globalThis.sendMessage('readFileSync', JSON.stringify(p));
    };
  }

  // nunjucks loader backed by the Dart host: getSource(name) reads the template
  // file through __readTemplate synchronously (JSC callFunction callback).
  function HostLoader() { this.async = false; }
  HostLoader.prototype.getSource = function (name) {
    var src = globalThis.__readTemplate(name);
    if (src == null) throw new Error('template not found: ' + name);
    return { src: src, path: name, noCache: false };
  };
  HostLoader.prototype.isRelative = function () { return false; };
  HostLoader.prototype.resolve = function (from, to) { return to; };

  var env = new nunjucks.Environment(new HostLoader(), {
    autoescape: true,
    throwOnUndefined: false,
  });

  // Templates render in two modes (matches runtime/lib/templates.mjs):
  //   'ui/.../x.html'        -> full page
  //   'ui/.../x.html#macro'   -> the named macro in that file (a fragment)
  function renderTemplate(viewRef, ctx) {
    var hash = viewRef.indexOf('#');
    if (hash === -1) return env.render(viewRef, ctx);
    var file = viewRef.slice(0, hash);
    var macro = viewRef.slice(hash + 1);
    return env.renderString('{% import "' + file + '" as f %}{{ f.' + macro + '(c) }}', ctx);
  }

  // In-memory session store keyed by kdh_sid (single-user prototype). Matches
  // runtime/lib/state.mjs: a session is { id, data } and handlers mutate .data.
  var sessions = Object.create(null);
  function uuid() {
    // JSC has no crypto.getRandomValues in flutter_js; a v4-shaped id suffices
    // for a loopback prototype (the value never reaches rendered HTML).
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
    });
  }

  function buildContext(req) {
    var cookies = req.cookies || {};
    var headers = {};
    var status = 200;
    var body = null;
    var contentType = null;
    var setCookies = [];

    var c = {
      req: {
        query: function (k) { return (req.query || {})[k]; },
        parseBody: function () { return Promise.resolve(req.body || {}); },
      },
      status: function (n) { status = n; return c; },
      header: function (k, v, opts) {
        // Vary is appended (helpers/router add it post-handler); others set.
        if (k.toLowerCase() === 'vary') {
          var cur = headers['Vary'];
          headers['Vary'] = cur ? cur + ', ' + v : v;
        } else {
          headers[k] = v;
        }
        return c;
      },
      html: function (s) { body = s; contentType = 'text/html'; return c; },
      text: function (s) { body = s; contentType = 'text/plain'; return c; },
      body: function (s) { body = s == null ? '' : s; return c; },
      set: function (k, v) { c['_' + k] = v; return c; },
      get: function (k) { return c['_' + k]; },
    };

    // Session: reuse kdh_sid if present and known, else mint one + Set-Cookie.
    var sid = cookies['kdh_sid'];
    var session;
    if (sid && sessions[sid]) {
      session = sessions[sid];
    } else {
      sid = uuid();
      session = { id: sid, data: {} };
      sessions[sid] = session;
      setCookies.push(cookieHeader('kdh_sid', sid, { path: '/', httpOnly: true, sameSite: 'Lax' }));
    }
    c.set('kdh_session', session);

    var h = {
      render: function (c, viewRef, ctx, st) {
        var bag = Object.assign({ prefs: prefsOf() }, ctx || {});
        bag.c = bag;
        c.status(st == null ? 200 : st);
        return c.html(renderTemplate(viewRef, bag));
      },
      form: function (c) { return c.req.parseBody(); },
      session: function () { return session; },
      prefs: prefsOf,
      setPrefs: function (c, patch) {
        var merged = Object.assign({}, prefsOf(), patch);
        // store on the session so it survives within this engine instance and
        // round-trips via the kdh_prefs cookie (next request carries it back).
        session._prefs = merged;
        setCookies.push(cookieHeader('kdh_prefs', JSON.stringify(merged), {
          path: '/', maxAge: 31536000, sameSite: 'Lax',
        }));
      },
      timers: globalThis.__timers || {
        start: function () {}, extend: function () {}, remaining: function () { return null; }, stop: function () {},
      },
      noContent: function (c) { c.status(204); return c.body(null); },
      stopPolling: function (c) { c.status(286); return c.body(null); },
      refresh: function (c) { c.header('HX-Refresh', 'true'); return c.body(null); },
      location: function (c, url) { c.header('HX-Location', url); return c.body(null); },
    };

    function prefsOf() {
      try { return session._prefs || JSON.parse(cookies['kdh_prefs'] || '{}'); }
      catch (e) { return {}; }
    }

    function finish() {
      var outBody = body == null ? '' : String(body);
      var outHeaders = Object.assign({}, headers);
      if (contentType && (outBody !== '' || status !== 204)) {
        outHeaders['Content-Type'] = contentType;
      }
      // router.mjs appends Vary: HX-Request after the handler runs.
      if (!outHeaders['Vary']) outHeaders['Vary'] = 'HX-Request';
      else outHeaders['Vary'] = appendUnique(outHeaders['Vary'], 'HX-Request');
      return { status: status, headers: outHeaders, body: outBody, setCookies: setCookies };
    }
    return { c: c, h: h, finish: finish };
  }

  function appendUnique(vary, val) {
    var parts = vary.split(',').map(function (s) { return s.trim(); });
    if (parts.indexOf(val) === -1) parts.push(val);
    return parts.join(', ');
  }

  function cookieHeader(name, value, opts) {
    var s = name + '=' + value;
    if (opts.path) s += '; Path=' + opts.path;
    if (opts.maxAge != null) s += '; Max-Age=' + opts.maxAge;
    if (opts.httpOnly) s += '; HttpOnly';
    if (opts.sameSite) s += '; SameSite=' + opts.sameSite;
    return s;
  }

  function matchRoute(routes, method, path) {
    for (var i = 0; i < routes.length; i++) {
      var r = routes[i];
      if (r[0] === method && r[1] === path) return r[2];
    }
    return null;
  }

  // The Dart HttpServer calls this per request. req = { method, path, query,
  // body, cookies }. The resolved response is stored on
  // globalThis.__lastDispatchResponse (sync handlers store it immediately; async
  // handlers store it from the promise's .then, and JSC drains that microtask
  // before the next evaluate() reads it). Returns '__sync__' or '__async__'.
  globalThis.__dispatch = function (req) {
    var routes = globalThis.__artifact && globalThis.__artifact.default;
    if (!routes) {
      globalThis.__lastDispatchResponse = { status: 500, headers: {}, body: 'engine not loaded', setCookies: [] };
      return '__sync__';
    }
    var handler = matchRoute(routes, req.method, req.path);
    if (!handler) {
      globalThis.__lastDispatchResponse = {
        status: 404, headers: { 'Content-Type': 'text/plain' },
        body: '404 — no route for ' + req.method + ' ' + req.path, setCookies: [],
      };
      return '__sync__';
    }
    var ctx = buildContext(req);
    try {
      var ret = handler(ctx.c, ctx.h);
      if (ret && typeof ret.then === 'function') {
        globalThis.__lastDispatchResponse = null;
        ret.then(function () { globalThis.__lastDispatchResponse = ctx.finish(); });
        return '__async__';
      }
      globalThis.__lastDispatchResponse = ctx.finish();
      return '__sync__';
    } catch (err) {
      globalThis.__lastDispatchResponse = {
        status: 500, headers: { 'Content-Type': 'text/plain' },
        body: '500 — ' + ((err && err.message) || err), setCookies: [],
      };
      return '__sync__';
    }
  };
})(globalThis);
