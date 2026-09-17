import assert from 'node:assert/strict';
import test from 'node:test';
import {
  resolveAndroidReleaseSigning,
} from './android-release-signing.mjs';

const TEST_PATH = '/secure/moonlit-beacon-upload.jks';
const SECURE_FILE = {
  isFile: () => true,
  isSymbolicLink: () => false,
  mode: 0o600,
};

test('uses explicit release signing environment variables as-is', () => {
  let spawned = false;
  const resolved = resolveAndroidReleaseSigning({
    env: {
      GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: ' secret ',
      GODOT_ANDROID_KEYSTORE_RELEASE_PATH: ` ${TEST_PATH} `,
      GODOT_ANDROID_KEYSTORE_RELEASE_USER: ' upload ',
    },
    exists: (path) => path === TEST_PATH,
    lstat: () => SECURE_FILE,
    platform: 'linux',
    spawn: () => {
      spawned = true;
      return { status: 1 };
    },
  });

  assert.deepEqual(resolved, {
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: ' secret ',
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH: TEST_PATH,
    GODOT_ANDROID_KEYSTORE_RELEASE_USER: 'upload',
  });
  assert.equal(spawned, false);
});

test('on macOS uses the default path outside the repo and Keychain', () => {
  const resolved = resolveAndroidReleaseSigning({
    env: {
      HOME: '/Users/test',
      IAPKIT_API_KEY: 'must-not-leak',
      MOONLIT_ASC_KEY_ID: 'must-not-leak',
      PATH: '/usr/bin',
    },
    exists: (path) => path === (
      '/Users/test/Library/Application Support/MoonlitBeacon/signing/'
      + 'moonlit-beacon-upload.jks'
    ),
    home: '/Users/test',
    lstat: () => SECURE_FILE,
    platform: 'darwin',
    spawn: (command, args, options) => {
      assert.equal(command, '/usr/bin/security');
      assert.deepEqual(args, [
        'find-generic-password',
        '-s',
        'dev.moonlitbeacon.android-signing',
        '-a',
        'moonlitbeacon-upload',
        '-w',
      ]);
      assert.equal(
        options.env.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD,
        undefined,
      );
      assert.equal(options.env.IAPKIT_API_KEY, undefined);
      assert.equal(options.env.MOONLIT_ASC_KEY_ID, undefined);
      assert.equal(options.env.HOME, '/Users/test');
      return { status: 0, stdout: 'keychain-secret\n' };
    },
  });

  assert.equal(
    resolved.GODOT_ANDROID_KEYSTORE_RELEASE_PATH,
    '/Users/test/Library/Application Support/MoonlitBeacon/signing/'
      + 'moonlit-beacon-upload.jks',
  );
  assert.equal(
    resolved.GODOT_ANDROID_KEYSTORE_RELEASE_USER,
    'moonlitbeacon-upload',
  );
  assert.equal(
    resolved.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD,
    'keychain-secret',
  );
});

test('rejects a missing keystore or password without leaking the secret', () => {
  assert.throws(
    () => resolveAndroidReleaseSigning({
      env: {
        GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: 'should-not-appear',
        GODOT_ANDROID_KEYSTORE_RELEASE_PATH: TEST_PATH,
      },
      exists: () => false,
      lstat: () => SECURE_FILE,
      platform: 'linux',
    }),
    (error) => error.message.includes('keystore')
      && !error.message.includes('should-not-appear'),
  );

  assert.throws(
    () => resolveAndroidReleaseSigning({
      env: { GODOT_ANDROID_KEYSTORE_RELEASE_PATH: TEST_PATH },
      exists: () => true,
      lstat: () => SECURE_FILE,
      platform: 'linux',
    }),
    /password/,
  );
});

test('allows only a mode-600 regular file outside the repository', () => {
  const env = {
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: 'secret',
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH: TEST_PATH,
    GODOT_ANDROID_KEYSTORE_RELEASE_USER: 'upload',
  };
  assert.throws(
    () => resolveAndroidReleaseSigning({
      env,
      exists: () => true,
      lstat: () => ({ ...SECURE_FILE, mode: 0o644 }),
      platform: 'linux',
    }),
    /mode must be 600/,
  );
  assert.throws(
    () => resolveAndroidReleaseSigning({
      env,
      exists: () => true,
      lstat: () => SECURE_FILE,
      platform: 'linux',
      realpath: (path) => (
        path === TEST_PATH ? '/repo/secrets/upload.jks' : path
      ),
      root: '/repo',
    }),
    /outside the repository/,
  );
});
