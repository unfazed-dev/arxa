// worker.js — Cloudflare Workers entry point for the ejected arxa-designer
// artifact.
//
//   npx wrangler dev     # local dev (http://localhost:8787)
//   npx wrangler deploy  # production
//
// Static assets (/assets/*, /assets/vendor/*) are served by the [assets]
// binding in wrangler.toml. The binding's directory root is ./assets, so the
// fetch export strips the /assets prefix before delegating to env.ASSETS.
// Templates, l10n catalogs, and fixtures are pre-bundled into
// runtime/preload.js at eject time (Workers have no filesystem).
//
// One-way eject: this tree is yours. arxa will never re-import it — but
// YOU maintain both trees: the design tree stays the source of truth, and
// every app/widget/style change is mirrored here identically (see the
// productionize doc's dual-tree law before editing).
import { createArtifactApp } from './runtime/router.js';
import { preload } from './runtime/preload.js';
import routes from './app.routes.js';

// ── palette plane + deployed dial (VERIFY ADDENDUM 17, grilled Q7-Q10) ───
// Baked at eject time (null for artifacts without palettes.json — the whole
// block inerts): the palette manifest; the static Supabase channel carrying
// the PUBLISHABLE key only (RLS: read + insert-only; palette publishes go
// through the publish_palette RPC, which checks the share-link/author
// capability in SQL); the published palette as of the eject (live updates
// reach visitors through palette.js's remote fetch + the dial's Realtime).
const ARXA_PALETTES = null; // EJECT-PATCH: palettes.json object
const ARXA_DIAL_STATIC = null; // EJECT-PATCH: {artifact,url,anonKey,designId,published,font,authorSha256}
// The font plane (grilled 2026-09-13): baked at eject time when the
// artifact declares fonts.json (null otherwise — the whole plane inerts).
// Shape: {version, default: {role: choice}, roles: [{id, name, token,
// choices: [{id, family, category, css2, stack, seeded, sheet}]}]}.
const ARXA_FONTS = null; // EJECT-PATCH: fonts.json object

async function arxaSha256Hex(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// ── live sync (operator, 2026-09-13: "in sync and live at all times") ──
// The bake is the floor, the row is the truth. Ingested choices and new
// publishes land on the axes row immediately; each request resolves
// against a 5s snapshot of (font picks, font manifest) read with the
// publishable key (RLS: read-only - the same channel palette.js uses).
// A fetch failure falls back to the bake, so a Supabase outage serves
// the last eject, never an error page. One in-flight fetch per window
// per isolate - the design server's own axes cache runs the same law.
let _liveAt = 0;
let _livePromise = null;
function arxaLiveFontState() {
  if (!ARXA_FONTS || !ARXA_DIAL_STATIC) return Promise.resolve(null);
  const now = Date.now();
  if (now - _liveAt >= 5000) {
    _liveAt = now;
    _livePromise = fetch(
      ARXA_DIAL_STATIC.url + '/rest/v1/arxa_dial_axes?design_id=eq.'
        + ARXA_DIAL_STATIC.designId + '&select=font,font_manifest',
      { headers: { apikey: ARXA_DIAL_STATIC.anonKey, Authorization: 'Bearer ' + ARXA_DIAL_STATIC.anonKey } },
    )
      .then((r) => (r.ok ? r.json() : null))
      .then((rows) => (Array.isArray(rows) && rows[0] ? rows[0] : null))
      .catch(() => null);
  }
  return _livePromise;
}

// The merged manifest: baked roles + the row manifest's additions.
// Choices dedupe by id (the bake wins - seeded truth); roles stay
// fixed, ingestion only ever adds choices to declared roles.
function arxaMergeFonts(baked, liveManifest) {
  if (!liveManifest || !Array.isArray(liveManifest.roles)) return baked;
  const byId = {};
  liveManifest.roles.forEach((r) => { if (r && r.id) byId[r.id] = r; });
  const roles = baked.roles.map((role) => {
    const twin = byId[role.id];
    if (!twin || !Array.isArray(twin.choices)) return role;
    const known = new Set(role.choices.map((c) => c.id));
    const extra = twin.choices.filter((c) => c && c.id && c.sheet && !known.has(c.id));
    return extra.length ? { ...role, choices: [...role.choices, ...extra] } : role;
  });
  return { ...baked, roles };
}

// The font picks for one request (grilled 2026-09-13; live-sync law):
// per-role resolve - ?font= receipt > live published cell > baked cell >
// manifest default. Shared by the stamping pass (applyFontPlane) and the
// dial config (applyPalettePlane) so both speak the same truth.
function resolveFontPicks(url, fonts, published) {
  const receipt = {};
  (url.searchParams.get('font') || '').split(',').forEach((part) => {
    const seg = part.split(':');
    if (seg.length === 2) receipt[seg[0].trim()] = seg[1].trim();
  });
  const active = {};
  fonts.roles.forEach((role) => {
    const declared = (id) => role.choices.some((c) => c.id === id);
    active[role.id] = declared(receipt[role.id]) ? receipt[role.id]
      : declared(published[role.id]) ? published[role.id]
      : fonts.default[role.id];
  });
  return { active, published };
}


// Post-processes one response for the palette plane: serves /palettes.json,
// stamps the serve-time data-palette (?palette= > baked published >
// manifest default), injects palette.js's static channel, and — only when
// the URL carries a dial credential — injects the dial config + island.
// No credential = no dial on the public site (Q9).
async function applyPalettePlane(request, response) {
  if (!ARXA_PALETTES) return response;
  const url = new URL(request.url);
  if (url.pathname === '/palettes.json') {
    return Response.json(ARXA_PALETTES);
  }
  const type = response.headers.get('content-type') || '';
  if (!type.includes('text/html')) return response;
  let html = await response.text();
  const ids = ARXA_PALETTES.palettes.map((p) => p.id);
  const q = url.searchParams.get('palette');
  const published = ids.includes(ARXA_DIAL_STATIC && ARXA_DIAL_STATIC.published)
    ? ARXA_DIAL_STATIC.published
    : ARXA_PALETTES.default;
  const active = q && ids.includes(q) ? q : published;
  html = html.replace(/<html\b[^>]*>/, (tag) =>
    tag.replace(/\s+data-palette="[^"]*"/, '').replace(/>$/, ' data-palette="' + active + '">'));
  // Wire every declared override sheet (ADDENDUM 18): the baked HTML links
  // the seeded sheets only — a pasted palette's sheet shipped on disk but
  // was never <link>ed, so its tokens flipped while the override rules
  // stayed base (the "mixed palette" report). Dedup by href.
  const sheetLinks = ARXA_PALETTES.palettes
    .filter((p) => p.sheet && !html.includes('href="' + p.sheet + '"'))
    .map((p) => '<link rel="stylesheet" href="' + p.sheet + '" data-palette-sheet="' + p.id + '">')
    .join('');
  if (sheetLinks) html = html.replace('</head>', sheetLinks + '</head>');
  const activeEntry = ARXA_PALETTES.palettes.find((p) => p.id === active);
  if (activeEntry && activeEntry.themeColor) {
    html = html.replace(/(<meta[^>]*name="theme-color"[^>]*content=")[^"]*(")/, '$1' + activeEntry.themeColor + '$2');
  }
  const injects = [];
  if (ARXA_DIAL_STATIC) {
    injects.push('<script>window.__ARXA_PALETTE__=' + JSON.stringify({
      published: active,
      remote: {
        url: ARXA_DIAL_STATIC.url + '/rest/v1/arxa_dial_axes?design_id=eq.' + ARXA_DIAL_STATIC.designId + '&select=palette',
        anonKey: ARXA_DIAL_STATIC.anonKey,
      },
    }) + '</' + 'script>');
  }
  // ?dial= rides a share link (the island validates it against the store);
  // ?dial-author= is verified HERE against the baked SHA-256 — a wrong
  // token gets no dial at all, exactly like no token (Q9).
  const dialToken = url.searchParams.get('dial');
  const authorToken = url.searchParams.get('dial-author');
  let dialMode = null;
  if (ARXA_DIAL_STATIC && authorToken) {
    if ((await arxaSha256Hex(authorToken)) === ARXA_DIAL_STATIC.authorSha256) dialMode = 'author';
  } else if (ARXA_DIAL_STATIC && dialToken) {
    dialMode = 'guest';
  }
  if (dialMode) {
    const cfg = {
      v: 1,
      artifact: ARXA_DIAL_STATIC.artifact,
      store: 'supabase',
      mode: dialMode,
      static: { url: ARXA_DIAL_STATIC.url, anonKey: ARXA_DIAL_STATIC.anonKey, designId: ARXA_DIAL_STATIC.designId },
      axes: {
        styles: [],
        themes: [],
        palettes: ARXA_PALETTES.palettes,
        active: { palette: active },
        published: { palette: published },
        // The font plane (grilled 2026-09-13): the deployed dial picks
        // per-role from the baked manifest; publishing rides publish_font.
        // The font plane (grilled 2026-09-13; live-sync law): the dial
        // picks per-role from the MERGED manifest; publishing rides
        // publish_font. Awaiting the live state here keeps the cfg's
        // active/published in phase with the stamping pass.
        ...(ARXA_FONTS ? await (async () => {
          const live = await arxaLiveFontState();
          const fonts = arxaMergeFonts(ARXA_FONTS, live && live.font_manifest);
          const f = resolveFontPicks(url, fonts,
            (live && live.font) || (ARXA_DIAL_STATIC && ARXA_DIAL_STATIC.font) || {});
          return { fonts, active: { palette: active, font: f.active }, published: { palette: published, font: f.published } };
        })() : {}),
      },
    };
    // The publish_palette RPC checks BOTH capabilities in SQL — the guest
    // share link or the design's author token — so either way the dial's
    // credential rides cfg.token (never echoed back by the worker).
    if (dialToken) cfg.token = dialToken;
    if (dialMode === 'author') cfg.token = authorToken;
    injects.push('<script type="application/json" id="arxa-dial-config">' + JSON.stringify(cfg) + '</script>');
    // supabase-js rides first: the island's static driver (Q8) builds its
    // PostgREST + Realtime client from window.supabase.
    injects.push('<script src="/assets/vendor/supabase-js.min.js"></script>');
    injects.push('<script src="/assets/vendor/arxa-dial.js"></script>');
  }
  if (!injects.length) return new Response(html, response);
  html = html.replace('</body>', injects.join('') + '</body>');
  return new Response(html, response);
}

// Post-processes one response for the font plane (grilled 2026-09-13;
// live-sync law 2026-09-13): serves the MERGED /fonts.json (bake + row
// manifest), stamps serve-time data-font-<role> per role (?font= receipt
// > live published cell > baked cell > manifest default), wires the
// token-override sheets (missing ones are synthesized in the fetch
// handler), and injects font.js's static channel. Runs AFTER the palette
// plane; a null ARXA_FONTS passes straight through.
async function applyFontPlane(request, response) {
  if (!ARXA_FONTS) return response;
  const url = new URL(request.url);
  const live = await arxaLiveFontState();
  const fonts = arxaMergeFonts(ARXA_FONTS, live && live.font_manifest);
  if (url.pathname === '/fonts.json') {
    return Response.json(fonts);
  }
  const type = response.headers.get('content-type') || '';
  if (!type.includes('text/html')) return response;
  let html = await response.text();
  // Resolve per role (the independence law) - the shared resolver.
  const picks = resolveFontPicks(url, fonts,
    (live && live.font) || (ARXA_DIAL_STATIC && ARXA_DIAL_STATIC.font) || {});
  const active = picks.active;
  html = html.replace(/<html\b[^>]*>/, (tag) => {
    let out = tag.replace(/\s+data-font-[a-z0-9-]+="[^"]*"/g, '');
    fonts.roles.forEach((role) => {
      out = out.replace(/>$/, ' data-font-' + role.id + '="' + active[role.id] + '">');
    });
    return out;
  });
  // Wire every declared override sheet (the ADDENDUM 18 law, font twin).
  const sheetLinks = [];
  fonts.roles.forEach((role) => {
    role.choices.forEach((c) => {
      if (c.sheet && !html.includes('href="' + c.sheet + '"')) {
        sheetLinks.push('<link rel="stylesheet" href="' + c.sheet + '" data-font-sheet="' + role.id + '-' + c.id + '">');
      }
    });
  });
  if (sheetLinks.length) html = html.replace('</head>', sheetLinks.join('') + '</head>');
  const injects = [];
  if (ARXA_DIAL_STATIC) {
    injects.push('<script>window.__ARXA_FONT__=' + JSON.stringify({
      published: active,
      remote: {
        url: ARXA_DIAL_STATIC.url + '/rest/v1/arxa_dial_axes?design_id=eq.' + ARXA_DIAL_STATIC.designId + '&select=font',
        anonKey: ARXA_DIAL_STATIC.anonKey,
      },
    }) + '</' + 'script>');
  }
  if (!injects.length) return new Response(html, response);
  html = html.replace('</body>', injects.join('') + '</body>');
  return new Response(html, response);
}

const app = await createArtifactApp('.', {
  staticSetup: null, // [assets] binding handles static on Workers
  preload,
  routes,
});

export default {
  // The eject's tsconfig runs checkJs + strict over **/*.js — the handler
  // needs JSDoc types or tsc fails with implicit-any errors.
  /**
   * @param {Request} request
   * @param {{ ASSETS: { fetch(request: Request): Promise<Response> } }} env
   * @param {any} ctx pass-through (ExecutionContext) — no workers-types lib in the eject tsconfig
   * @returns {Response | Promise<Response>}
   */
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Locale routes are literal (/fr, /fr/about) — no trailing-slash twins
    // in the route table. 308 to the canonical slash-less form.
    if (url.pathname.length > 1 && url.pathname.endsWith('/')) {
      url.pathname = url.pathname.replace(/\/+$/, '');
      return Response.redirect(url.toString(), 308);
    }

    if (url.pathname.startsWith('/assets/')) {
      url.pathname = url.pathname.slice('/assets'.length);
      const asset = await env.ASSETS.fetch(new Request(url, request));
      // Live-sync law: an ingested choice's token-override sheet exists
      // only in the row manifest - on an asset miss inside the font-sheet
      // name shape, synthesize the gate CSS the static file would carry.
      // Unknown stems still miss (404).
      if (asset.status === 404 && ARXA_FONTS &&
          /^\/styles\/fonts\/font-[a-z0-9-]+\.css$/.test(url.pathname)) {
        const live = await arxaLiveFontState();
        const fonts = arxaMergeFonts(ARXA_FONTS, live && live.font_manifest);
        const file = url.pathname.split('/').pop();
        for (const role of fonts.roles) {
          for (const c of role.choices) {
            if (c.sheet && c.sheet.split('/').pop() === file) {
              return new Response(
                '/* font choice ' + role.id + '/' + c.id + ' - synthesized from the live manifest */' + '\n'
                  + '[data-font-' + role.id + '="' + c.id + '"] {' + '\n'
                  + '  ' + role.token + ': ' + c.stack + ';' + '\n' + '}' + '\n',
                { headers: { 'content-type': 'text/css; charset=utf-8' } });
            }
          }
        }
      }
      return asset;
    }

    // Style barrels serve at /ui/styles/<owner>/ (the artifact styles law) —
    // mirrored into the [assets] root as assets/styles/ at eject time.
    if (url.pathname.startsWith('/ui/styles/')) {
      url.pathname = url.pathname.slice('/ui'.length);
      return env.ASSETS.fetch(new Request(url, request));
    }
    // /palettes.json + /fonts.json + the palette/dial injection are
    // response transforms — they run on the artifact's own answer.
    if (ARXA_PALETTES && url.pathname === '/palettes.json') {
      return applyFontPlane(request, applyPalettePlane(request, new Response('null')));
    }
    if (ARXA_FONTS && url.pathname === '/fonts.json') {
      return applyFontPlane(request, new Response('null'));
    }
    return applyFontPlane(request,
      await applyPalettePlane(request, await app.fetch(request, env, ctx)));
  },
};
