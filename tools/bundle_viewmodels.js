#!/usr/bin/env node
// tools/bundle_viewmodels.js -- app_box prototype runtime bundler (plan 09 step 9.3).
//
// A frozen design's viewmodels are ES modules; embedded JS engines resolve
// modules poorly. This bundler walks the import graph rooted at a design's
// app.routes.js and emits a SINGLE IIFE the engine can evaluate with one
// `evaluate()` call. The viewmodels, services, models and templates are NOT
// restructured -- their bodies are preserved verbatim; only `import`/`export`
// syntax is lowered to a require()/module.exports shim, and Node's `fs`
// (used by services/repositories/fixture_reader.js) is bridged to a host
// function so the readFixture contract is unchanged (step 9.4).
//
//   node tools/bundle_viewmodels.js <design-dir|design-name> [--out PATH]
//
// Output defaults to <designDir>/_bundle/artifact.bundle.js. The shipped app
// looks for the bundle there; if absent it errors with the command to run.
//
// This is a build step that runs at FREEZE time, where Node is legitimately
// present (plan 09 scope note). It adds no shipped dependency.
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { builtinModules } from 'node:module';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const DESIGNS = path.join(ROOT, 'designs');

function die(msg, code = 1) {
  console.error(msg);
  process.exit(code);
}

function resolveDesign(target) {
  const candidates = [path.resolve(target), path.resolve(DESIGNS, target)];
  for (const c of candidates) if (existsSync(path.join(c, 'app.routes.js'))) return c;
  const tried = [...new Set(candidates)].map((c) => `  ${c}`).join('\n');
  die(`no design at "${target}" -- every candidate lacked app.routes.js:\n${tried}`, 66);
}

// ES module spec resolution. Handles the patterns this artifact uses: relative
// ('./x', '../x') and the virtual 'node:fs'. Bare specs / other builtins fail
// loudly rather than ship a half-bundle.
function resolveSpec(spec, importerDir) {
  if (spec === 'node:fs') return { virtual: 'node:fs' };
  if (spec.startsWith('.')) {
    const full = path.resolve(importerDir, spec);
    if (existsSync(full)) return { real: full };
    for (const ext of ['.js', '.mjs']) if (existsSync(full + ext)) return { real: full + ext };
    die(`cannot resolve "${spec}" from ${importerDir}`, 65);
  }
  if (builtinModules.includes(spec.replace(/^node:/, ''))) {
    die(`bundle needs a shim for Node builtin "${spec}" -- add it before shipping`, 65);
  }
  die(`bare spec "${spec}" is not supported (only relative + node:fs)`, 65);
}

// Lower import/export to require()/module.exports, preserving the body verbatim.
function transformModule(src, modRelPath) {
  const lines = src.split('\n');
  const out = [];
  const exported = []; // {local} names to assign to module.exports at the tail

  for (const line of lines) {
    let m;
    // import * as ns from '...'
    if ((m = line.match(/^(\s*)import\s+\*\s+as\s+(\w+)\s+from\s+(['"])([^'"]+)\3\s*;?\s*$/))) {
      out.push(`${m[1]}const ${m[2]} = __req(${JSON.stringify(m[4])});`);
      continue;
    }
    // import { a, b } from '...'  (no aliases used by this artifact)
    if ((m = line.match(/^(\s*)import\s+\{([^}]*)\}\s+from\s+(['"])([^'"]+)\3\s*;?\s*$/))) {
      const names = m[2].split(',').map((s) => s.trim()).filter(Boolean);
      out.push(`${m[1]}const { ${names.join(', ')} } = __req(${JSON.stringify(m[4])});`);
      continue;
    }
    // import name from '...'  (default import — routes tables use this)
    if ((m = line.match(/^(\s*)import\s+(\w+)\s+from\s+(['"])([^'"]+)\3\s*;?\s*$/))) {
      out.push(`${m[1]}const ${m[2]} = __req(${JSON.stringify(m[4])}).default;`);
      continue;
    }
    // import '...' (side-effect import)
    if ((m = line.match(/^(\s*)import\s+(['"])([^'"]+)\2\s*;?\s*$/))) {
      out.push(`${m[1]}__req(${JSON.stringify(m[3])});`);
      continue;
    }
    // export default E   ->  const __default = E   (E may be a multi-line array)
    if ((m = line.match(/^(\s*)export\s+default\s+/))) {
      out.push(`${m[1]}const __default = ${line.slice(m[0].length)}`);
      exported.push('__default');
      continue;
    }
    // export const X | export function f | export let/var -- strip the
    // `export ` keyword, keep the declaration intact, track the bound name.
    if ((m = line.match(/^(\s*)export\s+(const|let|var|function)\s+(\w+)/))) {
      exported.push(m[3]);
      out.push(line.replace(/^(\s*)export\s+/, '$1'));
      continue;
    }
    // import.meta.url -> file URL relative to artifact root; host swaps
    // __ARTIFACT__ for the runtime design dir at read time.
    if (line.includes('import.meta.url')) {
      out.push(
        line.replace(/import\.meta\.url/g, JSON.stringify('file://__ARTIFACT__/' + modRelPath.split(path.sep).join('/'))),
      );
      continue;
    }
    out.push(line);
  }

  const tail = exported.map((n) => `\n__exports.${n === '__default' ? 'default' : n} = ${n};`).join('');
  return out.join('\n') + tail;
}

function shimFor(name) {
  if (name === 'node:fs') {
    // readFileSync is the only symbol the artifact uses. The host __readFileSync
    // resolves against the runtime design dir and returns the file string.
    return `__exports.readFileSync = function (p, enc) {
  return globalThis.__readFileSync(typeof p === 'string' ? p : (p && p.href) || String(p));
};`;
  }
  die(`no shim for ${name}`, 65);
}

function bundle(designDir) {
  const modules = new Map();  // realPath -> {key, body}
  const virtuals = new Map(); // name -> body
  const resolveMap = {};      // `${importerKey}\n${spec}` -> targetKey
  const queue = [];
  const entryKey = 'app.routes.js';

  function visit(abs, key) {
    if (modules.has(abs)) return;
    const src = readFileSync(abs, 'utf8');
    const modRelPath = key.split(path.sep).join('/');
    modules.set(abs, { key, body: transformModule(src, modRelPath) });

    const importerDir = path.dirname(abs);
    const re = /import\s+(?:\*\s+as\s+\w+|\{[^}]*\}|\w+|['"])\s*(?:from\s+)?(['"])([^'"]+)\1/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      const spec = m[2];
      const r = resolveSpec(spec, importerDir);
      if (r.virtual) {
        resolveMap[`${key}\n${spec}`] = '__virtual__:' + r.virtual;
        virtuals.set(r.virtual, shimFor(r.virtual));
        continue;
      }
      const targetKey = path.relative(designDir, r.real).split(path.sep).join('/');
      resolveMap[`${key}\n${spec}`] = targetKey;
      queue.push({ abs: r.real, key: targetKey });
    }
  }

  queue.push({ abs: path.join(designDir, entryKey), key: entryKey });
  while (queue.length) {
    const { abs, key } = queue.shift();
    visit(abs, key);
  }
  return { modules, virtuals, resolveMap, entryKey };
}

// JSC has no URL global; the artifact's fixture_reader uses new URL(rel, base).
const URL_POLYFILL = `var URL = (function () {
  function normJoin(baseDir, rel) {
    var parts = (baseDir + '/' + rel).split('/');
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] === '' || parts[i] === '.') continue;
      if (parts[i] === '..') { if (out.length) out.pop(); continue; }
      out.push(parts[i]);
    }
    return out.join('/');
  }
  function URL(rel, base) {
    if (base && base.indexOf('file://') === 0) {
      var b = base.slice(7);
      var dir = b.slice(0, b.lastIndexOf('/'));
      this.href = 'file://' + normJoin(dir, rel);
    } else {
      this.href = rel;
    }
  }
  URL.prototype.toString = function () { return this.href; };
  return URL;
})();
`;

function emit(graph) {
  const { modules, virtuals, resolveMap, entryKey } = graph;

  const factories = [];
  for (const [, info] of modules) {
    factories.push(
      `__modules[${JSON.stringify(info.key)}] = function (__exports, __req) {\n${info.body}\n};`,
    );
  }
  for (const [name, body] of virtuals) {
    factories.push(
      `__modules[${JSON.stringify('__virtual__:' + name)}] = function (__exports, __req) {\n${body}\n};`,
    );
  }

  const mapEntries = Object.entries(resolveMap)
    .map(([k, v]) => `${JSON.stringify(k)}: ${JSON.stringify(v)}`)
    .join(',\n    ');

  return `// AUTO-GENERATED by tools/bundle_viewmodels.js (plan 09 step 9.3). Do not edit.
// The frozen design's viewmodels bundled into one IIFE the embedded JS engine
// evaluates once. Viewmodel bodies are preserved verbatim; only import/export
// is lowered and Node's fs is bridged to the host (readFixture unchanged).
(function (globalThis) {
${URL_POLYFILL}
  var __modules = {};
  var __cache = {};
  var __resolveMap = {
    ${mapEntries}
  };
  function __resolve(importerKey, spec) {
    var k = __resolveMap[importerKey + '\\n' + spec];
    if (!k) throw new Error('module not resolved: ' + spec + ' (from ' + importerKey + ')');
    return k;
  }
  function __load(key) {
    if (__cache[key]) return __cache[key].exports;
    var factory = __modules[key];
    if (!factory) throw new Error('module factory missing: ' + key);
    var mod = { exports: {} };
    __cache[key] = mod;
    factory.call(mod.exports, mod.exports, function (spec) { return __load(__resolve(key, spec)); });
    return mod.exports;
  }
${factories.join('\n')}
  globalThis.__artifact = __load(${JSON.stringify(entryKey)});
})(globalThis);
`;
}

function main() {
  const args = process.argv.slice(2);
  if (!args.length || args[0] === '--help') {
    console.error('Usage: node tools/bundle_viewmodels.js <design-dir|name> [--out PATH]');
    process.exit(!args.length ? 64 : 0);
  }
  const target = args.find((a) => !a.startsWith('--'));
  const outIdx = args.indexOf('--out');
  const designDir = resolveDesign(target);
  const graph = bundle(designDir);
  const code = emit(graph);
  const outDir =
    outIdx >= 0 && args[outIdx + 1] ? path.resolve(args[outIdx + 1]) : path.join(designDir, '_bundle');
  mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, 'artifact.bundle.js');
  writeFileSync(outFile, code, 'utf8');
  console.log(`bundled ${graph.modules.size} module(s) -> ${path.relative(ROOT, outFile)}`);
}

main();
