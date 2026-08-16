// File viewer — the main panel's render:* modes for files. Mode selection is
// 100% server-side: the file's extension picks the mode (the closed set:
// render:code/doc/image/svg/pdf/video), the files repository provides the
// body/src. Shared by the three shells' facades.
import * as filesRepo from '../repositories/files_repository.js';

const MODES = new Map(Object.entries({
  md: 'render:doc', txt: 'render:doc',
  json: 'render:code', js: 'render:code', mjs: 'render:code', css: 'render:code',
  html: 'render:code', dart: 'render:code', py: 'render:code', sh: 'render:code',
  yaml: 'render:code', yml: 'render:code', arb: 'render:code',
  png: 'render:image', jpg: 'render:image', jpeg: 'render:image', gif: 'render:image', webp: 'render:image',
  svg: 'render:svg',
  pdf: 'render:pdf',
  mp4: 'render:video', webm: 'render:video', mov: 'render:video',
}));

const extOf = (path) => {
  const base = (path ?? '').split('/').pop() ?? '';
  const dotIndex = base.lastIndexOf('.');
  return dotIndex < 1 ? '' : base.slice(dotIndex + 1).toLowerCase();
};

export const modeFor = (path) => MODES.get(extOf(path)) ?? null;

// A file row's link data; no mode or no fixture content → the row is inert.
export const fileLink = (path, base) => {
  const mode = modeFor(path);
  if (!mode || !filesRepo.read(path)) return { mode: null };
  const encodedPath = encodeURIComponent(path);
  return { mode, href: `${base}?file=${encodedPath}`, get: `${base}/file?path=${encodedPath}` };
};

// The open file's view context; unknown paths resolve to null (the main
// panel falls back to its stage default).
export const fileViewFor = (path, backHref) => {
  const mode = modeFor(path);
  const data = mode ? filesRepo.read(path) : null;
  if (!data) return null;
  return {
    path, mode,
    modeName: mode.split(':')[1],
    lang: extOf(path),
    body: data.body ?? null,
    html: data.body && mode === 'render:doc' ? mdToHtml(data.body) : null,
    src: data.src ?? null,
    backHref,
  };
};

// Minimal markdown → HTML for the fixture docs (no new deps): h1–h3,
// paragraphs, ul lists, fenced code, inline `code` and **bold**. Input is
// always escaped before any tag is emitted.
const esc = (text) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const inline = (text) => esc(text)
  .replace(/`([^`]+)`/g, '<code>$1</code>')
  .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

export function mdToHtml(md) {
  const out = [];
  let inCode = false, list = false, para = [];
  const flushPara = () => { if (para.length) { out.push(`<p>${para.map(inline).join(' ')}</p>`); para = []; } };
  const flushList = () => { if (list) { out.push('</ul>'); list = false; } };
  for (const line of md.split('\n')) {
    if (line.startsWith('```')) { flushPara(); flushList(); out.push(inCode ? '</code></pre>' : '<pre><code>'); inCode = !inCode; continue; }
    if (inCode) { out.push(esc(line) + '\n'); continue; }
    const headingMatch = line.match(/^(#{1,3})\s+(.*)/);
    if (headingMatch) { flushPara(); flushList(); out.push(`<h${headingMatch[1].length}>${inline(headingMatch[2])}</h${headingMatch[1].length}>`); continue; }
    const li = line.match(/^[-*]\s+(.*)/);
    if (li) { flushPara(); if (!list) { out.push('<ul>'); list = true; } out.push(`<li>${inline(li[1])}</li>`); continue; }
    if (!line.trim()) { flushPara(); flushList(); continue; }
    para.push(line.trim());
  }
  flushPara(); flushList();
  if (inCode) out.push('</code></pre>');
  return out.join('\n');
}
