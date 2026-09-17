import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { agentSkillSyncProblems, syncAgentSkills } from './agent-skill-sync.mjs';

function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-agent-skills-'));
  const source = join(root, '.claude/skills/example');
  const target = join(root, '.agents/skills/example');
  mkdirSync(join(source, 'references'), { recursive: true });
  mkdirSync(join(target, 'references'), { recursive: true });
  writeFileSync(join(source, 'SKILL.md'), 'same skill\n');
  writeFileSync(join(source, 'references/check.md'), 'same reference\n');
  writeFileSync(join(target, 'SKILL.md'), 'same skill\n');
  writeFileSync(join(target, 'references/check.md'), 'same reference\n');
  return { root, source, target };
}

test('byte-identical Claude/Codex skill trees pass', (t) => {
  const { root } = fixture();
  t.after(() => rmSync(root, { recursive: true, force: true }));
  assert.deepEqual(agentSkillSyncProblems(root), []);
});

test('missing, changed, and Codex-only files are rejected', (t) => {
  const { root, source, target } = fixture();
  t.after(() => rmSync(root, { recursive: true, force: true }));
  writeFileSync(join(target, 'SKILL.md'), 'drifted skill\n');
  rmSync(join(target, 'references/check.md'));
  writeFileSync(join(target, 'codex-only.md'), 'orphan\n');

  const problems = agentSkillSyncProblems(root);
  assert.equal(problems.length, 3);
  assert.ok(problems.some((problem) => problem.includes('byte-identical')));
  assert.ok(problems.some((problem) => problem.includes('missing Codex copy')));
  assert.ok(problems.some((problem) => problem.includes('no matching')));
  assert.equal(agentSkillSyncProblems(root).length, 3);
  assert.equal(source.endsWith('.claude/skills/example'), true);
});

test('write mode replaces the Codex mirror with the complete source tree', (t) => {
  const { root, source, target } = fixture();
  t.after(() => rmSync(root, { recursive: true, force: true }));
  writeFileSync(join(source, 'new.md'), 'new source file\n');
  writeFileSync(join(target, 'codex-only.md'), 'remove me\n');

  syncAgentSkills(root);

  assert.deepEqual(agentSkillSyncProblems(root), []);
});

test('non-regular entries are reported without reading a fabricated path', (t) => {
  const { root, source, target } = fixture();
  t.after(() => rmSync(root, { recursive: true, force: true }));
  symlinkSync('missing-target', join(source, 'link.md'));
  symlinkSync('missing-target', join(target, 'link.md'));

  const problems = agentSkillSyncProblems(root);
  assert.equal(problems.length, 2);
  assert.ok(problems.every((problem) => problem.includes('regular file')));

  syncAgentSkills(root);
  assert.equal(agentSkillSyncProblems(root).length, 2);
});
