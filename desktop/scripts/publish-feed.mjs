#!/usr/bin/env node
// Publish a Tauri updater manifest (and optionally its bundle archive) to the
// R2 feed bucket — D6: R2 primary + GitHub raw fallback.
//
// Object layout mirrors the endpoint template in tauri.conf.json so the R2
// URL can become the FIRST endpoint once the bucket is live (see
// docs/ci/release-ops.md#r2-feed for the flip checklist):
//   <bucket>/desktop/<channel>/<target>/<arch>/latest.json   (max-age=300)
//   <bucket>/desktop/<channel>/artifacts/<version>/<bundle>  (immutable —
//     versioned filenames can never change content, D6)
//
// Wrangler is invoked through `npx -y wrangler@latest` (nothing pinned here),
// with --remote so it hits the real bucket, not wrangler's local simulator.
//
// Usage:
//   node publish-feed.mjs --manifest staging/latest.json --channel stable \
//     [--target darwin] [--arch aarch64] [--bucket arxa-releases] \
//     [--bundle staging/Arxa-Studio-1.2.3-....app.tar.gz] \
//     [--base https://pub-<id>.r2.dev] [--dry-run]
//
// --target/--arch: explicit path segments (preferred — the workflow passes
// them). Otherwise derived from the manifest's single platform key (e.g.
// "darwin-aarch64") by splitting at the FIRST hyphen, and only when both
// halves are [a-z0-9_]+ — keys like a hypothetical "appimage-linux-x86_64"
// would mis-split, so ambiguity is an error, not a guess.
// --base: public https base used to print the resulting feed URL (the r2.dev
// hostname is only knowable after bucket creation; R2_PUBLIC_BASE_URL works
// too). Without it we still print the r2:// object path.
// --dry-run: print the wrangler commands without running anything.

import { spawnSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { basename } from "node:path";

const MANIFEST_CACHE_CONTROL = "public, max-age=300"; // D6: feed staleness budget
const BUNDLE_CACHE_CONTROL = "public, max-age=31536000, immutable"; // D6

const BOOL_FLAGS = new Set(["dry-run", "help"]);

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    let k = argv[i];
    if (k === "-h") k = "--help";
    if (k.startsWith("--")) {
      if (BOOL_FLAGS.has(k.slice(2))) args[k.slice(2)] = true;
      else {
        args[k.slice(2)] = argv[i + 1];
        i++;
      }
    }
  }
  return args;
}

function fail(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

function shellQuote(a) {
  return /[^\w@:./=-]/.test(a) ? `'${a.replace(/'/g, `'\\''`)}'` : a;
}

// Split a platform key ("darwin-aarch64") into target/arch. Null when the
// split is ambiguous (see header note) — callers turn that into an error.
function splitPlatformKey(key) {
  const idx = key.indexOf("-");
  if (idx < 1) return null;
  const target = key.slice(0, idx);
  const arch = key.slice(idx + 1);
  if (!/^[a-z0-9_]+$/.test(target) || !/^[a-z0-9_]+$/.test(arch)) return null;
  return { target, arch };
}

function runWrangler(args, dryRun) {
  const cmd = ["npx", "-y", "wrangler@latest", ...args];
  const printable = cmd.map(shellQuote).join(" ");
  if (dryRun) {
    console.log(`[dry-run] ${printable}`);
    return;
  }
  const res = spawnSync(cmd[0], cmd.slice(1), { stdio: "inherit" });
  if (res.error) fail(`could not spawn npx: ${res.error.message}`);
  if (res.status !== 0) fail(`wrangler exited ${res.status}: ${printable}`);
}

const args = parseArgs(process.argv.slice(2));
if (args.help) {
  console.log("see usage header: node desktop/scripts/publish-feed.mjs --help");
  process.exit(0);
}

if (!args.manifest) fail("--manifest <latest.json> is required");
if (!existsSync(args.manifest)) fail(`manifest not found: ${args.manifest}`);
if (!args.channel) fail("--channel (stable|beta) is required");
const channel = args.channel;
if (!["stable", "beta"].includes(channel)) fail(`channel must be stable or beta, got ${channel}`);

const manifest = JSON.parse(readFileSync(args.manifest, "utf8"));
const platformKeys = Object.keys(manifest.platforms ?? {});
if (!platformKeys.length) fail(`manifest has no platforms object: ${args.manifest}`);

// Resolve <target>/<arch> path segments: explicit flags win, then an
// unambiguous single platform key, else a hard error.
let target = args.target;
let arch = args.arch;
if (!target || !arch) {
  if (platformKeys.length > 1)
    fail(`manifest carries multiple platform keys (${platformKeys.join(", ")}) — pass --target/--arch explicitly`);
  const split = splitPlatformKey(platformKeys[0]);
  if (!split)
    fail(
      `cannot split platform key ${platformKeys[0]} into target/arch unambiguously — pass --target and --arch explicitly`,
    );
  target = target ?? split.target;
  arch = arch ?? split.arch;
}

const bucket = args.bucket ?? "arxa-releases";
const manifestKey = `${bucket}/desktop/${channel}/${target}/${arch}/latest.json`;
const base = args.base ?? process.env.R2_PUBLIC_BASE_URL;

if (!args["dry-run"] && !process.env.CLOUDFLARE_API_TOKEN)
  fail("CLOUDFLARE_API_TOKEN is not set — wrangler needs it for r2 --remote operations");

console.log(`publishing ${args.manifest} -> r2://${manifestKey}`);
runWrangler(
  [
    "r2",
    "object",
    "put",
    manifestKey,
    "--file",
    args.manifest,
    "--content-type",
    "application/json",
    "--cache-control",
    MANIFEST_CACHE_CONTROL,
    "--remote",
  ],
  args["dry-run"],
);

if (args.bundle) {
  if (!existsSync(args.bundle)) fail(`bundle not found: ${args.bundle}`);
  if (typeof manifest.version !== "string" || !manifest.version)
    fail("manifest has no version string — needed for the artifacts/ path");
  // Versioned filename => immutable content (D6): long cache, no revalidation.
  const bundleKey = `${bucket}/desktop/${channel}/artifacts/${manifest.version}/${basename(args.bundle)}`;
  console.log(`publishing ${args.bundle} -> r2://${bundleKey}`);
  runWrangler(
    [
      "r2",
      "object",
      "put",
      bundleKey,
      "--file",
      args.bundle,
      "--cache-control",
      BUNDLE_CACHE_CONTROL,
      "--remote",
    ],
    args["dry-run"],
  );
}

const feedUrl = base
  ? `${base.replace(/\/$/, "")}/desktop/${channel}/${target}/${arch}/latest.json`
  : `r2://${manifestKey}`;
console.log(`feed: ${feedUrl}`);
