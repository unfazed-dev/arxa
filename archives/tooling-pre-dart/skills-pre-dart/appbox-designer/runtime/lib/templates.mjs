import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import nunjucks from 'nunjucks';

// Vendored Lucide set (vendor/fetch.mjs), resolved against the RUNTIME dir —
// not the artifact — so every artifact shares the one copy.
const iconsDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'vendor', 'lucide', 'icons');
const iconCache = new Map(); // name → raw svg | null (null = unknown, warned once)
const NAME_RE = /^[a-z0-9-]+$/;

const esc = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function placeholder(size, cls) {
  console.warn(`[icon] placeholder rendered`);
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false"${cls ? ` class="${esc(cls)}"` : ''}><rect x="3" y="3" width="18" height="18" rx="3" stroke-dasharray="4 3"/></svg>`;
}

// {{ icon('arrow-left') }} / {{ icon('arrow-left', {size: 20, cls: 'x', label: 'Back'}) }}
// Decorative by default; opts.label makes it an accessible img. Unknown or
// invalid name → dashed-square placeholder + server-side warning.
function icon(name, opts = {}) {
  const size = opts.size ?? 24;
  if (typeof name !== 'string' || !NAME_RE.test(name)) {
    console.warn(`[icon] rejected name ${JSON.stringify(String(name))} (want ${NAME_RE})`);
    return new nunjucks.runtime.SafeString(placeholder(size, opts.cls));
  }
  let raw = iconCache.get(name);
  if (raw === undefined) {
    try {
      raw = readFileSync(path.join(iconsDir, name + '.svg'), 'utf8');
    } catch {
      raw = null;
      console.warn(`[icon] unknown icon '${name}' (vendor/lucide/icons/${name}.svg missing)`);
    }
    iconCache.set(name, raw);
  }
  if (raw === null) return new nunjucks.runtime.SafeString(placeholder(size, opts.cls));

  const openTag = raw.match(/<svg[^>]*>/)[0];
  let open = openTag
    .replace(/\s+class="[^"]*"/, '')
    .replace(/\s+width="[^"]*"/, '')
    .replace(/\s+height="[^"]*"/, '');
  if (opts.strokeWidth != null) {
    open = open.replace(/stroke-width="[^"]*"/, `stroke-width="${Number(opts.strokeWidth)}"`);
  }
  open = open.replace(
    /<svg/,
    `<svg width="${size}" height="${size}"` +
      (opts.cls ? ` class="${esc(opts.cls)}"` : '') +
      (opts.label ? ` role="img" aria-label="${esc(opts.label)}"` : ' aria-hidden="true" focusable="false"'),
  );
  const head = raw.slice(0, raw.indexOf(openTag)); // @license comment — keep it attached
  let out = head + open + raw.slice(raw.indexOf(openTag) + openTag.length);
  if (opts.label) out = out.replace(/(<svg[^>]*>)/, `$1<title>${esc(opts.label)}</title>`);
  return new nunjucks.runtime.SafeString(out);
}

// Templates render in two modes (ADR-0003):
//   'ui/views/.../home_view.html'        → full page
//   'ui/views/.../home_view.html#rows'   → Named Fragment: the `rows` macro in that file
// Macros take one argument: the context bag `c` (pages pass `c`; see helpers.render).
export function createTemplates(artifactDir, l10n) {
  const env = new nunjucks.Environment(
    new nunjucks.FileSystemLoader(artifactDir, { watch: false, noCache: false }),
    { autoescape: true, throwOnUndefined: false },
  );
  env.addGlobal('icon', icon);
  // Default; rebound per render below. `t` must be a real global (not a context
  // key) because Named Fragment macros imported into a renderString see only
  // `c` + globals. Rebinding is safe: renders are synchronous and Node is
  // single-threaded, so no two requests interleave between bind and render.
  env.addGlobal('t', l10n ? l10n.createT({}) : (s) => s);

  return {
    render(viewRef, ctx) {
      if (l10n) env.addGlobal('t', l10n.createT({ locale: ctx.locale, level: ctx.prefs?.jargon }));
      const hash = viewRef.indexOf('#');
      if (hash === -1) return env.render(viewRef, ctx);
      const file = viewRef.slice(0, hash);
      const macro = viewRef.slice(hash + 1);
      return env.renderString(`{% import "${file}" as f %}{{ f.${macro}(c) }}`, ctx);
    },
  };
}
