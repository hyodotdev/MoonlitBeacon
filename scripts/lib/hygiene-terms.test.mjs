import assert from 'node:assert/strict';
import test from 'node:test';

import { containsForbiddenPhaseTerm } from './hygiene-terms.mjs';

test('flags the forbidden lesson-step token regardless of case or separators', () => {
  assert.equal(containsForbiddenPhaseTerm('Phase 3'), true);
  assert.equal(containsForbiddenPhaseTerm('phase-03'), true);
  assert.equal(containsForbiddenPhaseTerm('.mb-phase-table'), true);
});

test('does not treat longer technical terms such as broadphase as that lesson-step token', () => {
  assert.equal(containsForbiddenPhaseTerm('_diagnostic_broadphase_checks'), false);
  assert.equal(containsForbiddenPhaseTerm('multiphase filter'), false);
});
