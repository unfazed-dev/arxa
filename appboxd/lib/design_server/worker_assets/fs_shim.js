// node:fs shim for the worker. fixture_reader.js does
//   readFileSync(new URL(relFromThisFile, import.meta.url), 'utf8')
// In the browser import.meta.url is an http:// URL, so the key is the
// absolute served URL of the fixture. Dart pre-fetches every models/**/*.json
// into globalThis.__fixtures before __boot. Sync lookup — no async I/O.
export function readFileSync(path, _enc) {
  const k = String(path);
  const v = globalThis.__fixtures[k];
  if (v === undefined) throw new Error('fs_shim: not prefetched: ' + k);
  return v;
}
export function existsSync(path) {
  return globalThis.__fixtures[String(path)] !== undefined;
}
