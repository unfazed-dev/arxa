// palette.js — the palette plane runtime (VERIFY ADDENDUM 17/18). Owns the
// data-palette attribute on <html>, the meta theme-color swap, the
// per-visitor memory (localStorage), the ?palette= URL override, and the
// 'arxa:palette' broadcast that cursor.js / howitworks.js recolor on.
//
// Application plane only — PUBLICATION is the Arxa Dial's job (axes store).
// Boot precedence law (ADDENDUM 17, after the dial workstream's coherence
// flag): a server-RENDERED data-palette attribute is authoritative — the
// axes store already spoke (design server serve-time, or the value baked
// into the deployed worker); local memory only applies when nothing was
// rendered (bare/file usage). In deployed STATIC mode (config.remote
// baked) memory may pre-paint — the remote fetch of the published pick
// then settles everyone: a guest's switch publishes for everyone (Q10).
//
// ADDENDUM 18 — dressing: a palette is DRESSED when its override sheet is
// linked AND its tokens.css block is live. The serve seams (design server
// + deployed worker) wire both for every palette declared at page load;
// the boot manifest marks those dressed. A palette BORN mid-session (a
// Coolors paste in another tab, or the dial's own ingest seconds ago) is
// not in the boot snapshot: set() hot-dresses it — refetch the manifest,
// inject the sheet, append the tokens block as a <style> — and only then
// flips the attribute. Never settle onto an id this page cannot dress.
(function () {
  var KEY = 'arxa:palette';
  var root = document.documentElement;
  var meta = null;
  // No-FOUC fallback only — the manifest (line ~56) overwrites this map
  // once fetched. Kept in sync with the seeded five (ADDENDUM 19 curation);
  // retired ids must leave this map or a stale localStorage id would paint
  // a dead palette's theme-color during the boot window.
  var themeColors = { marine: '#007EA7', 'c-6f58c9': '#7e78d2', 'c-2e1f27': '#854d27', 'c-8e518d': '#c86fc9', 'c-293f14': '#386c0b' };
  var manifestCache = null;   // boot snapshot; refetched when an unknown id arrives
  var dressed = {};           // id -> true once sheet + tokens are live

  function valid(name) {
    return typeof name === 'string' && /^[a-z0-9][a-z0-9-]{0,40}$/.test(name);
  }

  function apply(name, opts) {
    if (!valid(name)) return;
    root.setAttribute('data-palette', name);
    if (!meta) meta = document.querySelector('meta[name="theme-color"]');
    if (meta && themeColors[name]) meta.setAttribute('content', themeColors[name]);
    if (!opts || opts.remember !== false) {
      try { localStorage.setItem(KEY, name); } catch (e) {}
    }
    window.dispatchEvent(new CustomEvent('arxa:palette', { detail: { palette: name } }));
  }

  function loadManifest(force) {
    if (manifestCache && !force) return Promise.resolve(manifestCache);
    if (!window.fetch) return Promise.resolve(null);
    return fetch('/palettes.json' + (force ? '?_=' + Date.now() : ''))
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (m) {
        if (!m || !m.palettes) return manifestCache;
        manifestCache = m;
        for (var i = 0; i < m.palettes.length; i++) {
          var p = m.palettes[i];
          if (p && valid(p.id) && p.themeColor) themeColors[p.id] = p.themeColor;
        }
        return m;
      })
      .catch(function () { return manifestCache; });
  }

  function manifestEntry(m, id) {
    if (!m || !m.palettes) return null;
    for (var i = 0; i < m.palettes.length; i++) {
      if (m.palettes[i] && m.palettes[i].id === id) return m.palettes[i];
    }
    return null;
  }

  // Inject the entry's override sheet (dedup by href) and, when the loaded
  // tokens.css predates the palette, append its var block as a <style>.
  // done() fires once, after the sheet loads (or a 2s cap — never block).
  function dress(id, entry, done) {
    var finished = false;
    function finish() {
      if (finished) return;
      finished = true;
      dressed[id] = true;
      done();
    }
    var pending = 0;
    function step() { if (--pending <= 0) finish(); }
    setTimeout(finish, 2000); // the cap: a stuck sheet must not hold the flip

    if (entry && entry.sheet && !document.querySelector('link[href="' + entry.sheet + '"]')) {
      pending++;
      var link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = entry.sheet;
      link.setAttribute('data-palette-sheet', id);
      var stepped = false;
      var once = function () { if (!stepped) { stepped = true; step(); } };
      link.onload = once;
      link.onerror = once;
      document.head.appendChild(link);
    }
    if (window.fetch && !document.querySelector('style[data-palette-tokens="' + id + '"]')) {
      pending++;
      fetch('/ui/styles/common/tokens.css?_=' + Date.now())
        .then(function (r) { return r.ok ? r.text() : ''; })
        .then(function (css) {
          var m = css.match(new RegExp('\\[data-palette="' + id + '"\\]\\s*\\{[^}]*\\}'));
          if (m) {
            var st = document.createElement('style');
            st.setAttribute('data-palette-tokens', id);
            st.textContent = m[0];
            document.head.appendChild(st);
          }
        })
        .catch(function () {})
        .then(step);
    }
    if (pending === 0) finish();
  }

  // set() — the dial's entry point: dress first, then flip. Unknown ids
  // (born mid-session) force one manifest refetch before concluding.
  function set(name) {
    if (!valid(name)) return;
    if (dressed[name]) return apply(name);
    loadManifest(false).then(function (m) {
      var entry = manifestEntry(m, name);
      if (!entry) {
        return loadManifest(true).then(function (m2) {
          dress(name, manifestEntry(m2, name), function () { apply(name); });
        });
      }
      dress(name, entry, function () { apply(name); });
    });
  }

  function boot() {
    var q = new URLSearchParams(window.location.search).get('palette');
    var stored = null;
    try { stored = localStorage.getItem(KEY); } catch (e) {}
    var cfg = window.__ARXA_PALETTE__ || null;
    var rendered = root.getAttribute('data-palette');
    var initial;
    // An explicit ?palette= is the URL receipt (the dial's preview link):
    // the remote settle below must never stomp it (ADDENDUM 18).
    var urlOverride = !!(q && valid(q));
    if (cfg && cfg.remote) {
      // static channel: ?palette= > memory > rendered/baked > baked default
      initial = (q && valid(q) && q) ||
        (stored && valid(stored) && stored) ||
        (rendered && valid(rendered) && rendered) ||
        (valid(cfg.published) && cfg.published) ||
        'marine';
    } else {
      // rendered attribute is the store speaking; memory is the fallback
      initial = (q && valid(q) && q) ||
        (rendered && valid(rendered) && rendered) ||
        (stored && valid(stored) && stored) ||
        'marine';
    }
    apply(initial, { remember: true });

    if (!window.fetch) return;
    loadManifest(false).then(function (m) {
      if (!m) return;
      // The boot snapshot is dressed BY LAW: the serve seams wired every
      // declared sheet (ADDENDUM 18) and tokens.css ships its var blocks.
      // The safety net below re-injects any sheet a serving path skipped.
      for (var i = 0; i < m.palettes.length; i++) {
        var p = m.palettes[i];
        if (p && valid(p.id)) dressed[p.id] = true;
        if (p && valid(p.id) && p.sheet && !document.querySelector('link[href="' + p.sheet + '"]')) {
          var link = document.createElement('link');
          link.rel = 'stylesheet';
          link.href = p.sheet;
          link.setAttribute('data-palette-sheet', p.id);
          document.head.appendChild(link);
        }
      }
      var cur = root.getAttribute('data-palette');
      if (meta && cur && themeColors[cur]) meta.setAttribute('content', themeColors[cur]);

      // Deployed static mode: the published pick lives in the shared store.
      // Settle onto it only when this build can dress it (a publish ahead
      // of its deploy otherwise silently renders base — ADDENDUM 18) and
      // never over an explicit ?palette= receipt.
      if (cfg && cfg.remote && cfg.remote.url && cfg.remote.anonKey) {
        fetch(cfg.remote.url, {
          headers: { apikey: cfg.remote.anonKey, Authorization: 'Bearer ' + cfg.remote.anonKey }
        }).then(function (r) { return r.ok ? r.json() : null; }).then(function (rows) {
          if (urlOverride) return;
          var published = rows && rows[0] && rows[0].palette;
          if (!valid(published) || published === root.getAttribute('data-palette')) return;
          if (!dressed[published]) return;
          apply(published, { remember: true });
        }).catch(function () {});
      }
    });
  }

  window.__arxaPalette = {
    get: function () { return root.getAttribute('data-palette') || 'marine'; },
    set: set, // dresses first, then flips; publishing stays the dial's job
    apply: apply
  };
  // ── the public palette ear (header law) ────────────────────────────
  // Deployed static mode only: the baked remote config carries the
  // project origin, the anon key, and the design id (parsed from the
  // axes REST URL the worker constructs). Local design-time returns —
  // the dial's SSE frames cover those tabs.
  function listen() {
    var cfg = window.__ARXA_PALETTE__ || null;
    if (!cfg || !cfg.remote || !cfg.remote.url || !cfg.remote.anonKey) return;
    if (!window.fetch) return;
    var dm = /design_id=eq\.([0-9a-f-]{36})/.exec(cfg.remote.url);
    if (!dm) return;
    var designId = dm[1];
    var origin = null;
    try { origin = new URL(cfg.remote.url).origin; } catch (e) { return; }
    var q0 = new URLSearchParams(window.location.search).get('palette');
    var receipt = !!(q0 && valid(q0));
    var client = null, channel = null, failures = 0, timer = null, loading = null;

    function applyPublished(id) {
      // The receipt law + the dressable law (ADDENDUM 18): never stomp a
      // ?palette= link, never settle onto an id this build cannot dress.
      if (receipt || !valid(id)) return;
      if (id === root.getAttribute('data-palette')) return;
      loadManifest(false).then(function (m) {
        if (!dressed[id] && !manifestEntry(m, id)) return; // ahead of deploy
        set(id);
      });
    }
    function resync() {
      fetch(cfg.remote.url, {
        headers: { apikey: cfg.remote.anonKey, Authorization: 'Bearer ' + cfg.remote.anonKey }
      }).then(function (r) { return r.ok ? r.json() : null; }).then(function (rows) {
        if (rows && rows[0]) applyPublished(rows[0].palette);
      }).catch(function () {});
    }
    function ensureClient(cb) {
      if (window.supabase && window.supabase.createClient) {
        cb(window.supabase.createClient(origin, cfg.remote.anonKey));
        return;
      }
      if (loading) return; // one load attempt; a miss degrades to loads
      loading = document.createElement('script');
      loading.src = '/assets/vendor/supabase-js.min.js';
      loading.onload = function () {
        var lib = window.supabase;
        loading = null;
        if (lib && lib.createClient) cb(lib.createClient(origin, cfg.remote.anonKey));
      };
      loading.onerror = function () { loading = null; };
      document.head.appendChild(loading);
    }
    function teardown() {
      if (!channel) return;
      try { if (client) client.removeChannel(channel); else channel.unsubscribe(); } catch (e) {}
      channel = null;
    }
    function subscribe() {
      if (document.hidden || document._arxaDial || channel) return;
      ensureClient(function (c) {
        if (!c || document.hidden || document._arxaDial || channel) return;
        client = c;
        channel = c.channel('arxa-palette-' + designId)
          .on('postgres_changes', {
            event: '*', schema: 'public', table: 'arxa_dial_axes',
            filter: 'design_id=eq.' + designId
          }, function (payload) {
            failures = 0;
            var id = payload && payload.new && payload.new.palette;
            if (id) applyPublished(id); else resync(); // DELETE — read truth
          })
          .subscribe(function (status) {
            if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
              teardown();
              if (failures < 5 && !document.hidden) {
                timer = setTimeout(subscribe,
                  [2000, 5000, 15000, 60000, 60000][Math.min(failures, 4)]);
                failures++;
              }
            }
          });
      });
    }
    document.addEventListener('visibilitychange', function () {
      clearTimeout(timer);
      if (document.hidden) {
        teardown(); // the socket-pool law: hidden tabs hold nothing
      } else if (!document._arxaDial) {
        failures = 0;
        resync();
        subscribe();
      }
    });
    window.addEventListener('pagehide', teardown);
    // The dial stamps synchronously at </body>; 1.5s lets it win the
    // stand-down check and the boot settle win the race.
    setTimeout(subscribe, 1500);
  }

  boot();
  listen();
})();
