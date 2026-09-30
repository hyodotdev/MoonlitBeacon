import assert from 'node:assert/strict';
import test from 'node:test';

import { DEFAULT_STEPS, STEPS, parseSteps, summarizeOutput } from './muse-judge.mjs';

test('every default step exists, and the cheap ones run before the long batches', () => {
  for (const name of DEFAULT_STEPS) assert.ok(name in STEPS, name);
  assert.ok(DEFAULT_STEPS.indexOf('checks') < DEFAULT_STEPS.indexOf('tests'));
  assert.ok(DEFAULT_STEPS.indexOf('tests') < DEFAULT_STEPS.indexOf('nat'));
  assert.ok(DEFAULT_STEPS.indexOf('nat') < DEFAULT_STEPS.indexOf('gauntlet'));
});

test('steps are chosen by name, and an unknown name is refused', () => {
  assert.deepEqual(parseSteps(undefined), DEFAULT_STEPS);
  assert.deepEqual(parseSteps('nat, gauntlet'), ['nat', 'gauntlet']);
  assert.throws(() => parseSteps('nat,speed'), /unknown step.*speed/);
});

test('the bot batches run the same commands the briefs name', () => {
  const nat = STEPS.nat.commands[0].join(' ');
  assert.match(nat, /play_bot\.tscn -- tag=judge_nat runs=12 seed=5 speed=3 loops=1$/);
  const gauntlet = STEPS.gauntlet.commands[0].join(' ');
  assert.match(gauntlet, /gauntlet=1 guardians=0,1,2,3,4,5 starts=2,6,12 runs=18 seed=11 speed=3$/);
  assert.ok(STEPS.nat.report.endsWith('judge_nat.json') && STEPS.gauntlet.report.endsWith('judge_gaunt.json'));
});

test('the store fingerprint step is expected to fail after a change under apps/game', () => {
  assert.equal(STEPS.store.expectFailure, true);
});

test('output is summarized by its failure-looking lines and its tail', () => {
  const output = ['ok one', 'ERROR: broken thing', 'Traceback (most recent call last):', '', 'fine', 'not ok 3 - x', 'last line'].join('\n');
  const summary = summarizeOutput(output, 2);
  assert.equal(summary.failureLines, 3);
  assert.deepEqual(summary.tail, ['not ok 3 - x', 'last line']);
  assert.equal(summarizeOutput('all good\nfine').failureLines, 0);
});
