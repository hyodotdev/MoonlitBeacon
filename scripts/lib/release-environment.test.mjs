import assert from 'node:assert/strict';
import test from 'node:test';
import {
  credentialFreeChildEnvironment,
  RELEASE_CREDENTIAL_ENV_NAMES,
} from './release-environment.mjs';

test('strips every platform release credential from ordinary build child environments', () => {
  const source = {
    PATH: '/usr/bin',
    ...Object.fromEntries(
      RELEASE_CREDENTIAL_ENV_NAMES.map((name) => [name, `secret-${name}`]),
    ),
  };
  const child = credentialFreeChildEnvironment(source);
  assert.deepEqual(child, { PATH: '/usr/bin' });
  for (const name of RELEASE_CREDENTIAL_ENV_NAMES) {
    assert.equal(source[name], `secret-${name}`);
  }
});
