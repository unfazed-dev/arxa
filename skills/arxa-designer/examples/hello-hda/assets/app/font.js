/* font.js — the font plane's applier (palette.js's shape, grilled
   2026-09-13). Owns html[data-font-<role>] per role, the ONE Google Fonts
   css2 <link> (rebuilt from the active choices' css2 segments — families
   load BY NAME from the CDN, the designer's no-binaries law), localStorage
   memory, the ?font=<role>:<id> receipt, the arxa:font broadcast, and (in
   deployed STATIC mode) the remote settle + the font ear. PUBLISHING is
   never its job — the dial owns that. The public font ear piggybacks
   palette.js's ONE Realtime channel via the arxa:axes-row DOM event
   (the LEAST-CHANNEL law): no second connection per tab. */
(function () {
  'use strict';
  var root = document.documentElement;
  var manifestCache = null;   // boot snapshot; refetched when unknown ids arrive

  function loadManifest(force) {
    if (manifestCache && !force) return Promise.resolve(manifestCache);
    if (!window.fetch) return Promise.resolve(null);
    return fetch('/fonts.json' + (force ? '?_=' + Date.now() : ''))
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (m) {
        if (!m || !m.roles) return manifestCache;
        manifestCache = m;
        return m;
      })
      .catch(function () { return manifestCache; });
  }

  function roleOf(m, id) {
    if (!m || !m.roles) return null;
    for (var i = 0; i < m.roles.length; i++) {
      if (m.roles[i].id === id) return m.roles[i];
    }
    return null;
  }
  function choiceOf(role, id) {
    if (!role || !role.choices) return null;
    for (var i = 0; i < role.choices.length; i++) {
      if (role.choices[i].id === id) return role.choices[i];
    }
    return null;
  }
  function valid(roleId, id) {
    return !!choiceOf(roleOf(manifestCache, roleId), id);
  }

  // The ONE css2 link: the artifact's frame ships it (families by name);
  // font.js takes it over and rebuilds its href from the ACTIVE choices.
  // Identical active set -> identical href -> no refetch.
  function css2Link() {
    var links = document.querySelectorAll(
      'link[href*="fonts.googleapis.com/css2"]');
    return links.length ? links[links.length - 1] : null;
  }
  function rebuildCss2(picks) {
    var segs = [];
    (manifestCache && manifestCache.roles ? manifestCache.roles : [])
      .forEach(function (role) {
        var c = choiceOf(role, picks[role.id]);
        if (c && c.css2 && segs.indexOf(c.css2) < 0) segs.push(c.css2);
      });
    if (!segs.length) return;
    var href = 'https://fonts.googleapis.com/css2?' + segs.join('&') +
      '&display=swap';
    var link = css2Link();
    if (link) {
      if (link.getAttribute('href') !== href) link.setAttribute('href', href);
    } else {
      link = document.createElement('link');
      link.rel = 'stylesheet';
      link.setAttribute('data-arxa-fonts', '1');
      link.href = href;
      document.head.appendChild(link);
    }
  }

  function dressSheets(picks) {
    // Ensure every active choice's token-override sheet is linked (the
    // serve seam injects declared sheets; a mid-session ingest from the
    // dial needs its sheet linked client-side).
    (manifestCache && manifestCache.roles ? manifestCache.roles : [])
      .forEach(function (role) {
        var c = choiceOf(role, picks[role.id]);
        if (!c || !c.sheet) return;
        if (!document.querySelector('link[href="' + c.sheet + '"]')) {
          var l = document.createElement('link');
          l.rel = 'stylesheet';
          l.setAttribute('data-font-sheet', role.id + '-' + c.id);
          l.href = c.sheet;
          document.head.appendChild(l);
        }
      });
  }

  function current() {
    var picks = {};
    (manifestCache && manifestCache.roles ? manifestCache.roles : [])
      .forEach(function (role) {
        var v = root.getAttribute('data-font-' + role.id);
        if (v) picks[role.id] = v;
      });
    return picks;
  }

  function apply(picks, opts) {
    opts = opts || {};
    var next = {};
    (manifestCache && manifestCache.roles ? manifestCache.roles : [])
      .forEach(function (role) {
        var v = picks[role.id];
        next[role.id] = valid(role.id, v) ? v :
          ((manifestCache.default || {})[role.id] ||
            (role.choices[0] && role.choices[0].id));
      });
    Object.keys(next).forEach(function (roleId) {
      root.setAttribute('data-font-' + roleId, next[roleId]);
      if (opts.remember) {
        try { localStorage.setItem('arxa.font.' + roleId, next[roleId]); } catch (e) {}
      }
    });
    dressSheets(next);
    rebuildCss2(next);
    try {
      document.dispatchEvent(new CustomEvent('arxa:font', { detail: next }));
    } catch (e) {}
    return next;
  }

  function set(roleId, id) {
    // dress first (a palette BORN mid-session refetches the manifest);
    // an unknown id after the refetch is ignored, never a guess.
    var go = function () {
      if (!valid(roleId, id)) return;
      var picks = current();
      picks[roleId] = id;
      apply(picks, { remember: true });
    };
    if (manifestCache && valid(roleId, id) === false && manifestCache) {
      loadManifest(true).then(go);
    } else {
      loadManifest(false).then(go);
    }
  }

  window.__arxaFont = {
    get: function (roleId) {
      return root.getAttribute('data-font-' + roleId) ||
        ((manifestCache && manifestCache.default || {})[roleId]) || '';
    },
    set: set,   // dresses first, then flips; publishing stays the dial's job
    apply: apply
  };

  // ── boot ────────────────────────────────────────────────────────────
  // Pre-paint memory (static fallback only — the serve-time attribute is
  // authoritative and overwrites), then the ?font= receipt, then the
  // remote settle. Never in parallel with the dial: its SSE frames drive
  // __arxaFont.set directly.
  var q = null;
  try { q = new URLSearchParams(window.location.search).get('font'); } catch (e) {}
  var receipt = {};
  if (q) {
    q.split(',').forEach(function (part) {
      var seg = part.split(':');
      if (seg.length === 2) receipt[seg[0].trim()] = seg[1].trim();
    });
  }
  loadManifest(false).then(function () {
    if (!manifestCache) return;
    var picks = {};
    manifestCache.roles.forEach(function (role) {
      var stored = null;
      try { stored = localStorage.getItem('arxa.font.' + role.id); } catch (e) {}
      picks[role.id] = (receipt[role.id] && valid(role.id, receipt[role.id]))
        ? receipt[role.id]
        : (root.getAttribute('data-font-' + role.id) ||
          (stored && valid(role.id, stored) ? stored :
            (manifestCache.default || {})[role.id]));
    });
    apply(picks);

    // Deployed static mode: settle onto the published picks when this
    // build can dress them (the dressable law — ADDENDUM 18's font twin:
    // a publish ahead of its deploy silently renders base) and never over
    // an explicit ?font= receipt.
    var cfg = window.__ARXA_FONT__ || null;
    var hasReceipt = Object.keys(receipt).length > 0;
    function settlePublished(fontCell) {
      if (!fontCell || typeof fontCell !== 'object') return;
      var cur = current();
      var wants = false;
      Object.keys(fontCell).forEach(function (roleId) {
        if (valid(roleId, fontCell[roleId]) && cur[roleId] !== fontCell[roleId]) {
          wants = true;
        }
      });
      if (!wants) return;
      var picks2 = {};
      Object.keys(cur).forEach(function (r) { picks2[r] = cur[r]; });
      Object.keys(fontCell).forEach(function (r) { picks2[r] = fontCell[r]; });
      apply(picks2, { remember: true });
    }
    if (cfg && cfg.remote && cfg.remote.url && cfg.remote.anonKey && !hasReceipt) {
      fetch(cfg.remote.url, {
        headers: { apikey: cfg.remote.anonKey, Authorization: 'Bearer ' + cfg.remote.anonKey }
      }).then(function (r) { return r.ok ? r.json() : null; }).then(function (rows) {
        if (rows && rows[0]) settlePublished(rows[0].font);
      }).catch(function () {});
    }
    // The font ear: piggybacks palette.js's ONE Realtime channel — the
    // arxa:axes-row DOM event carries the whole row (font cell included).
    if (cfg && cfg.remote) {
      document.addEventListener('arxa:axes-row', function (e) {
        if (hasReceipt) return; // the receipt law
        settlePublished(e.detail && e.detail.font);
      });
      document.addEventListener('visibilitychange', function () {
        if (document.hidden || document._arxaDial || hasReceipt) return;
        fetch(cfg.remote.url, {
          headers: { apikey: cfg.remote.anonKey, Authorization: 'Bearer ' + cfg.remote.anonKey }
        }).then(function (r) { return r.ok ? r.json() : null; }).then(function (rows) {
          if (rows && rows[0]) settlePublished(rows[0].font);
        }).catch(function () {});
      });
    }
  });
})();
