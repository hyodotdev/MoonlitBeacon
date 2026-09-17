import assert from 'node:assert/strict';
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  cleanupGeneratedIapKitConfigFile,
  cleanupStaleGeneratedIapKitConfig,
  iapKitConfigPaths,
  removeStagedIapKitConfig,
  resolveIapKitPublishableKey,
  restoreIapKitConfigAfterDirect,
  stageIapKitConfigForDirect,
  stageIapKitConfigForStore,
  validateIapKitPublishableKey,
} from './iapkit-config.mjs';

const FAKE_PUBLISHABLE_KEY = `openiap-kit_pk_${'A'.repeat(64)}`;
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');

function withTempRoot(run) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-iapkit-'));
  try {
    mkdirSync(join(root, 'apps/game'), { recursive: true });
    run(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('prefers the environment publishable key over Keychain', () => {
  let spawned = false;
  const key = resolveIapKitPublishableKey({
    env: { IAPKIT_API_KEY: `  ${FAKE_PUBLISHABLE_KEY}\n` },
    platform: 'darwin',
    spawn: () => {
      spawned = true;
      return { status: 1 };
    },
  });
  assert.equal(key, FAKE_PUBLISHABLE_KEY);
  assert.equal(spawned, false);
});

test('does not pass key environment variables to the Keychain child on macOS', () => {
  const key = resolveIapKitPublishableKey({
    env: {
      GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: 'must-not-leak',
      HOME: '/Users/test',
      IAPKIT_API_KEY: '',
      MOONLIT_ASC_KEY_ID: 'must-not-leak',
      PATH: '/usr/bin',
    },
    platform: 'darwin',
    spawn: (command, args, options) => {
      assert.equal(command, '/usr/bin/security');
      assert.deepEqual(args, [
        'find-generic-password',
        '-s',
        'dev.openiap.kit.moonlitbeacon',
        '-a',
        'MoonlitBeacon Mobile',
        '-w',
      ]);
      assert.equal(options.env.IAPKIT_API_KEY, undefined);
      assert.equal(
        options.env.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD,
        undefined,
      );
      assert.equal(options.env.MOONLIT_ASC_KEY_ID, undefined);
      assert.equal(options.env.HOME, '/Users/test');
      assert.equal(options.killSignal, 'SIGTERM');
      return { status: 0, stdout: `${FAKE_PUBLISHABLE_KEY}\n` };
    },
  });
  assert.equal(key, FAKE_PUBLISHABLE_KEY);
});

test('rejects a secret key or invalid value without leaking the real value', () => {
  const secret = `openiap-kit_sk_${'S'.repeat(64)}`;
  assert.throws(
    () => validateIapKitPublishableKey(secret),
    (error) => error.message.includes('secret key')
      && !error.message.includes(secret),
  );
  assert.throws(
    () => validateIapKitPublishableKey('not-a-key'),
    (error) => error.message.includes('openiap-kit_pk_')
      && !error.message.includes('not-a-key'),
  );
});

test('reports a missing key clearly on platforms without Keychain', () => {
  assert.throws(
    () => resolveIapKitPublishableKey({ env: {}, platform: 'linux' }),
    /IAPKIT_API_KEY/,
  );
});

test('creates store config and deletes it completely on exit', () => {
  withTempRoot((root) => {
    const path = stageIapKitConfigForStore(root, {
      env: { IAPKIT_API_KEY: FAKE_PUBLISHABLE_KEY },
      platform: 'linux',
    });
    const contents = readFileSync(path, 'utf8');
    assert.match(contents, /^; Generated for a store export\./);
    assert.match(contents, /\[iapkit\]\n/);
    assert.match(contents, /api_key="openiap-kit_pk_/);

    removeStagedIapKitConfig(root);
    assert.equal(existsSync(path), false);
  });
});

test('direct distribution moves existing config out of the project and restores it', () => {
  withTempRoot((root) => {
    const { config, directStage } = iapKitConfigPaths(root);
    const localContents = '[iapkit]\napi_key="local-only"\n';
    writeFileSync(config, localContents);

    assert.equal(stageIapKitConfigForDirect(root), true);
    assert.equal(existsSync(config), false);
    assert.equal(existsSync(directStage), true);

    assert.equal(restoreIapKitConfigAfterDirect(root), true);
    assert.equal(readFileSync(config, 'utf8'), localContents);
    assert.equal(existsSync(directStage), false);
  });
});

test('auto-cleans only generated config from an interrupted store export', () => {
  withTempRoot((root) => {
    const { config } = iapKitConfigPaths(root);
    stageIapKitConfigForStore(root, {
      env: { IAPKIT_API_KEY: FAKE_PUBLISHABLE_KEY },
      platform: 'linux',
    });
    assert.equal(cleanupStaleGeneratedIapKitConfig(root), true);
    assert.equal(existsSync(config), false);

    writeFileSync(config, '[iapkit]\napi_key="user-owned"\n');
    assert.equal(cleanupStaleGeneratedIapKitConfig(root), false);
    assert.equal(existsSync(config), true);
  });
});

test('safely cleans only generated config copied into the Gradle template', () => {
  withTempRoot((root) => {
    const generated = stageIapKitConfigForStore(root, {
      env: { IAPKIT_API_KEY: FAKE_PUBLISHABLE_KEY },
      platform: 'linux',
    });
    const copied = join(
      root,
      'apps/game/android/build/assetPackInstallTime/src/main/assets/iapkit.cfg',
    );
    mkdirSync(dirname(copied), { recursive: true });
    writeFileSync(copied, readFileSync(generated, 'utf8'));

    assert.equal(cleanupGeneratedIapKitConfigFile(copied), true);
    assert.equal(existsSync(copied), false);

    writeFileSync(copied, '[iapkit]\napi_key="user-owned"\n');
    assert.equal(cleanupGeneratedIapKitConfigFile(copied), false);
    assert.equal(existsSync(copied), true);
  });
});

test('includes generated IAPKit config only in the store preset export', () => {
  const presets = readFileSync(
    join(REPO_ROOT, 'apps/game/export_presets.cfg'),
    'utf8',
  );
  const sections = presets.split(/\n(?=\[preset\.\d+\]\n)/);
  const androidDirect = sections.find((value) =>
    value.includes('name="Android"\n'));
  const ios = sections.find((value) => value.includes('name="iOS"\n'));
  const androidPlay = sections.find((value) =>
    value.includes('name="Android Play"\n'));

  assert.match(androidDirect, /include_filter="firebase\.cfg"/);
  assert.match(ios, /include_filter="iapkit\.cfg,firebase\.cfg"/);
  assert.match(androidPlay, /include_filter="iapkit\.cfg,firebase\.cfg"/);
});
