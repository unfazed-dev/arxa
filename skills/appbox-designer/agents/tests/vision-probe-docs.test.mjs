import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

import { AGENTS_DIR } from './helpers.mjs';

const SKILL_DIR = path.resolve(AGENTS_DIR, '..');
const readSkill = (relPath) => fs.readFileSync(path.join(SKILL_DIR, relPath), 'utf8');

test('vision probe agent has a strict read-only token protocol', () => {
  const probe = readSkill('agents/vision-probe-agent.md');

  assert.match(probe, /read-only/i);
  assert.match(probe, /VISION_OK/);
  assert.match(probe, /VISION_UNSUPPORTED/);
  assert.match(probe, /colorful square with a dark X\/border/);
  assert.match(probe, /Do not read real design screenshots/);
  assert.match(probe, /one\s+exact\s+token/i);
});

test('the harness reference gates image reads behind the vision probe', () => {
  const appbox-designer = readSkill('references/harness-tools.md');

  assert.match(appbox-designer, /Vision probe/);
  assert.match(appbox-designer, /VISION_OK/);
  assert.match(appbox-designer, /per session/i);
});

test('generic verification instructions no longer require visual image input', () => {
  const systemPrompt = readSkill('system-prompt.md');
  const verifier = readSkill('agents/fork-verifier-agent.md');

  assert.match(systemPrompt, /image input is native/);
  assert.match(systemPrompt, /one-per-session vision probe/);
  assert.match(systemPrompt, /without reading it back into the model/);
  assert.match(verifier, /Skip screenshot\s+reads only when the caller explicitly says image input is unsupported/);
});

test('vision probe uses a committed PNG asset, not a hardcoded /tmp write', () => {
  const png = fs.readFileSync(path.join(SKILL_DIR, 'agents/assets/vision-probe.png'));
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  assert.ok(png.length > 0);

  const appbox-designer = readSkill('references/harness-tools.md');
  const probe = readSkill('agents/vision-probe-agent.md');

  assert.match(appbox-designer, /agents\/assets\/vision-probe\.png/);
  assert.match(probe, /agents\/assets\/vision-probe\.png/);
  assert.doesNotMatch(appbox-designer, /\/tmp\/the upstream MIT project-vision-probe\.png/);
  assert.doesNotMatch(appbox-designer, /writeFileSync/);
  assert.doesNotMatch(probe, /\/tmp\/the upstream MIT project-vision-probe\.png/);
});

test('vision probe verdict is probed once per session', () => {
  const appbox-designer = readSkill('references/harness-tools.md');

  assert.match(appbox-designer, /per session/i);
});
