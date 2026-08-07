// icon.tsx — <Icon> component: replaces the `icon()` global.
// Reads Lucide SVGs from the vendor directory (node) or preload (workers),
// modifies the <svg> tag (sets width/height, adds class, adjusts
// stroke-width, adds aria attributes), and returns the raw HTML.
//
// Same SVG modification logic as makeIcon() in templates.js.
// Returns raw() so the SVG injects without a wrapping element — byte-identical
// to the original {{ icon(...) }} output.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { raw } from 'hono/utils/html';
import type { FC } from 'hono/jsx';

interface IconProps {
  name: string;
  size?: number;
  cls?: string;
  label?: string;
  strokeWidth?: number;
}

// Vendored Lucide icons — resolved relative to this module. In the ejected tree
// that is runtime/vendor/lucide/icons. On Workers there is no fs: the cloudflare
// eject bundles icons into preload.js (node/vercel emit a stub, preload = null).
// Lazy: workerd leaves import.meta.url undefined, so computing this at module
// load would kill the Worker even though the fs path is never used there.
let iconsDir: string | null = null;
function iconsDirPath(): string {
  return (iconsDir ??= path.join(path.dirname(fileURLToPath(import.meta.url)), 'vendor', 'lucide', 'icons'));
}
const NAME_RE = /^[a-z0-9-]+$/;
const cache = new Map<string, string | null>();

// @ts-ignore — runtime/preload.js is generated at eject time
const { preload } = await import('./preload.js');
const preloadIcons: Record<string, string> | null = preload?.iconSvg ?? null;

const esc = (s: string) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function placeholder(size: number, cls?: string): string {
  console.warn(`[icon] placeholder rendered`);
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false"${cls ? ` class="${esc(cls)}"` : ''}><rect x="3" y="3" width="18" height="18" rx="3" stroke-dasharray="4 3"/></svg>`;
}

function loadIcon(name: string): string | null {
  let raw_ = cache.get(name);
  if (raw_ !== undefined) return raw_;
  if (preloadIcons) {
    raw_ = preloadIcons[name] ?? null;
  } else {
    try {
      raw_ = readFileSync(path.join(iconsDirPath(), name + '.svg'), 'utf8');
    } catch {
      raw_ = null;
    }
  }
  if (raw_ === null) console.warn(`[icon] unknown icon '${name}'`);
  cache.set(name, raw_);
  return raw_;
}

const Icon: FC<IconProps> = ({ name, size = 24, cls, label, strokeWidth }) => {
  if (typeof name !== 'string' || !NAME_RE.test(name)) {
    console.warn(`[icon] rejected name ${JSON.stringify(String(name))} (want ${NAME_RE})`);
    return raw(placeholder(size, cls));
  }

  const rawSvg = loadIcon(name);
  if (rawSvg === null) return raw(placeholder(size, cls));

  const openTag = rawSvg.match(/<svg[^>]*>/)![0];
  let open = openTag
    .replace(/\s+class="[^"]*"/, '')
    .replace(/\s+width="[^"]*"/, '')
    .replace(/\s+height="[^"]*"/, '');
  if (strokeWidth != null) {
    open = open.replace(/stroke-width="[^"]*"/, `stroke-width="${Number(strokeWidth)}"`);
  }
  open = open.replace(
    /<svg/,
    `<svg width="${size}" height="${size}"` +
      (cls ? ` class="${esc(cls)}"` : '') +
      (label ? ` role="img" aria-label="${esc(label)}"` : ' aria-hidden="true" focusable="false"'),
  );
  const head = rawSvg.slice(0, rawSvg.indexOf(openTag)); // @license comment — keep it attached
  let out = head + open + rawSvg.slice(rawSvg.indexOf(openTag) + openTag.length);
  if (label) out = out.replace(/(<svg[^>]*>)/, `$1<title>${esc(label)}</title>`);

  return raw(out);
};

export default Icon;
