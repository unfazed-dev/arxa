#!/usr/bin/env node
/* Read a gate's --out file and print one line.
 *
 * Exists because the three gates return three different shapes through
 * `appbox lens eval`: a bare object, a {value:...} wrapper, and a
 * double-encoded JSON *string*. Hand-rolled readers misread the last one as
 * "0 checks" and printed a green line for a gate whose results were never
 * looked at — the same false-green shape as the stale-read incident.
 *
 * Rules enforced here:
 *   - a missing file is a FAILURE, never "no news is good news"
 *   - an unparseable file is a FAILURE
 *   - zero assertions is a FAILURE (a gate that checked nothing is not a pass)
 * Exit 1 on any of those or on real fails, so `&&` chains stop.
 */
const fs = require("fs");
const [, , file, label] = process.argv;

if (!file || !fs.existsSync(file)) {
  console.log(`${(label || file || "?").padEnd(26)} NO OUTPUT — gate threw or never ran = FAILURE`);
  process.exit(1);
}

let d;
try {
  d = JSON.parse(fs.readFileSync(file, "utf8"));
  // unwrap {value:...}, then unwrap a double-encoded JSON string, repeatedly
  for (let i = 0; i < 4; i++) {
    if (d && typeof d === "object" && "value" in d && Object.keys(d).length <= 2) d = d.value;
    else if (typeof d === "string") d = JSON.parse(d);
    else break;
  }
} catch (e) {
  console.log(`${(label || file).padEnd(26)} UNPARSEABLE (${e.message}) = FAILURE`);
  process.exit(1);
}

/* `fails` is an array in two gates and a COUNT in the contrast gate. Treating a
   number as an array gives .length === undefined, which reads as green — the
   same false-green shape this reader exists to stop. Normalise both. */
const rawFails = d.fails;
const failCount = typeof rawFails === "number" ? rawFails : (rawFails || []).length;
const failLines =
  typeof rawFails === "number"
    ? (Array.isArray(d.bad) ? d.bad.map((b) => (Array.isArray(b) ? b.join(": ") : String(b))) : [])
    : (rawFails || []).map(String);
// how many assertions actually ran, by whichever name the gate uses
const n = d.checked ?? d.count ?? d.total ?? (d.pass !== undefined ? null : 0);
const notes = d.notes || [];

if (n === 0) {
  console.log(`${(label || file).padEnd(26)} 0 ASSERTIONS RAN = FAILURE (vacuous gate)`);
  process.exit(1);
}

const green = failCount === 0;
const count = n === null ? "" : `${n} checks, `;
console.log(
  `${(label || file).padEnd(26)} ${green ? "PASS" : "FAIL"}  (${count}${failCount} fails)` +
    (green ? "" : "\n" + failLines.map((f) => `      ✗ ${f}`).join("\n")) +
    (notes.length ? "\n" + notes.map((x) => `      · ${x}`).join("\n") : "")
);
process.exit(green ? 0 : 1);
