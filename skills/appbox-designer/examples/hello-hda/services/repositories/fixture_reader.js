// Shared fixture reader — the only file that touches models/ JSON on disk.
// Repositories build on this; the productionize DB swap happens behind them.
import { readFileSync } from 'node:fs';

const cache = new Map();

/**
 * @param {string} relFromThisFile
 * @returns {unknown}
 */
export function readFixture(relFromThisFile) {
  if (!cache.has(relFromThisFile)) {
    cache.set(relFromThisFile, JSON.parse(readFileSync(new URL(relFromThisFile, import.meta.url), 'utf8')));
  }
  return cache.get(relFromThisFile);
}
