#!/usr/bin/env node
// Build a Tauri updater `latest.json` from a built bundle + its .sig file.
//
// Endpoint layout (D21 — channel-aware, static JSON):
//   {BASE_URL}/desktop/{channel}/{target}/{arch}/latest.json
//   channels: stable | beta
//
// Manifest contract (Tauri v2 updater "Static JSON File" format):
//   {
//     "version":  "<semver, no leading v>",
//     "notes":    "<release notes>",
//     "pub_date": "<RFC 3339 timestamp>",
//     "platforms": {
//       "<target>-<arch>": { "signature": "<contents of the .sig file>",
//                             "url": "<https url of the bundle archive>" }
//     }
//   }
//
// Hosting (D21 resolved): manifests live on the public arxa-releases repo's
// main branch, served via raw.githubusercontent.com; bundle archives are
// GitHub Release assets, so their full URL is passed with --url. Override the
// manifest base with ARXA_UPDATE_BASE_URL — see desktop/README.md "Release CI".
//
// Usage:
//   node make-update-manifest.mjs --bundle <path/to/Arxa Studio.app.tar.gz> \
//     [--sig <path>] [--version 0.1.0] [--channel stable] \
//     [--target darwin] [--arch aarch64] [--notes "..."] \
//     [--url <https bundle download url>] [--out latest.json]
//   node make-update-manifest.mjs --check <latest.json>   # validate only

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { basename, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const BASE_URL =
  process.env.ARXA_UPDATE_BASE_URL ??
  "https://raw.githubusercontent.com/unfazed-dev/arxa-releases/main";

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k.startsWith("--")) args[k.slice(2)] = argv[i + 1], i++;
  }
  return args;
}

function fail(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

export function validateManifest(m) {
  const errs = [];
  if (typeof m.version !== "string" || !/^\d+\.\d+\.\d+/.test(m.version) || m.version.startsWith("v"))
    errs.push("version must be semver without a leading v");
  if (typeof m.pub_date !== "string" || Number.isNaN(Date.parse(m.pub_date)))
    errs.push("pub_date must be a valid RFC 3339 timestamp");
  if (typeof m.notes !== "string") errs.push("notes must be a string");
  if (!m.platforms || typeof m.platforms !== "object" || !Object.keys(m.platforms).length)
    errs.push("platforms must be a non-empty object");
  else
    for (const [key, p] of Object.entries(m.platforms)) {
      if (!/^[a-z]+-[a-z0-9_]+$/.test(key)) errs.push(`platform key ${key} not <target>-<arch>`);
      if (typeof p.signature !== "string" || !p.signature.trim())
        errs.push(`${key}: signature missing (contents of the .sig file)`);
      if (typeof p.url !== "string" || !p.url.startsWith("https://"))
        errs.push(`${key}: url must be https`);
    }
  return errs;
}

const args = parseArgs(process.argv.slice(2));

if (args.check) {
  const m = JSON.parse(readFileSync(args.check, "utf8"));
  const errs = validateManifest(m);
  if (errs.length) fail(errs.join("; "));
  console.log(`${args.check}: valid updater manifest (${Object.keys(m.platforms).join(", ")})`);
  process.exit(0);
}

if (!args.bundle) fail("--bundle <path to .app.tar.gz / installer archive> is required (or --check <file>)");
if (!existsSync(args.bundle)) fail(`bundle not found: ${args.bundle}`);
const sigPath = args.sig ?? `${args.bundle}.sig`;
if (!existsSync(sigPath)) fail(`signature not found: ${sigPath} (build with bundle.createUpdaterArtifacts and TAURI_SIGNING_PRIVATE_KEY set)`);

const version =
  args.version ??
  JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../src-tauri/tauri.conf.json"), "utf8")).version;
const channel = args.channel ?? "stable";
if (!["stable", "beta"].includes(channel)) fail(`channel must be stable or beta, got ${channel}`);
const target = args.target ?? "darwin";
const arch = args.arch ?? "aarch64";

const manifest = {
  version,
  notes: args.notes ?? `Arxa Studio ${version} (${channel})`,
  pub_date: new Date().toISOString(),
  platforms: {
    [`${target}-${arch}`]: {
      signature: readFileSync(sigPath, "utf8").trim(),
      url: args.url ?? `${BASE_URL}/desktop/${channel}/artifacts/${version}/${encodeURIComponent(basename(args.bundle))}`,
    },
  },
};

const errs = validateManifest(manifest);
if (errs.length) fail(`self-check failed: ${errs.join("; ")}`);

const out = args.out ?? "latest.json";
writeFileSync(out, JSON.stringify(manifest, null, 2) + "\n");
console.log(`wrote ${out} for ${target}-${arch} ${version} on ${channel} (upload alongside the bundle; serve at ${BASE_URL}/desktop/${channel}/${target}/${arch}/latest.json)`);
