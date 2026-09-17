import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';

const KEYCHAIN_SERVICE = 'dev.openiap.kit.moonlitbeacon';
const KEYCHAIN_ACCOUNT = 'MoonlitBeacon Mobile';
const GENERATED_HEADER =
  '; Generated for a store export. This file must remain untracked.\n';
const PUBLISHABLE_KEY = /^openiap-kit_pk_[A-Za-z0-9_-]{32,}$/;

export function iapKitConfigPaths(root) {
  return {
    config: join(root, 'apps/game/iapkit.cfg'),
    directStage: join(root, 'builds/.iapkit.cfg-direct-stage'),
  };
}

export function validateIapKitPublishableKey(rawKey) {
  const key = typeof rawKey === 'string' ? rawKey.trim() : '';
  if (key.startsWith('openiap-kit_sk_')) {
    throw new Error(
      'IAPKit secret key (sk) must not go in the app. Use a publishable key (pk).',
    );
  }
  if (!PUBLISHABLE_KEY.test(key)) {
    throw new Error(
      'IAPKit publishable key is invalid. Check the openiap-kit_pk_ format.',
    );
  }
  return key;
}

export function resolveIapKitPublishableKey({
  env = process.env,
  platform = process.platform,
  spawn = spawnSync,
} = {}) {
  const envKey = typeof env.IAPKIT_API_KEY === 'string'
    ? env.IAPKIT_API_KEY.trim()
    : '';
  if (envKey) return validateIapKitPublishableKey(envKey);

  if (platform !== 'darwin') {
    throw new Error(
      'IAPKit publishable key is missing. Set the IAPKIT_API_KEY environment variable.',
    );
  }

  const keychainEnv = {};
  for (const name of [
    'HOME',
    'LANG',
    'LC_ALL',
    'LOGNAME',
    'PATH',
    'SECURITYSESSIONID',
    'TMPDIR',
    'USER',
  ]) {
    if (typeof env[name] === 'string') keychainEnv[name] = env[name];
  }
  const result = spawn(
    '/usr/bin/security',
    [
      'find-generic-password',
      '-s',
      KEYCHAIN_SERVICE,
      '-a',
      KEYCHAIN_ACCOUNT,
      '-w',
    ],
    {
      encoding: 'utf8',
      env: keychainEnv,
      killSignal: 'SIGTERM',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 10_000,
    },
  );
  if (result.status !== 0) {
    throw new Error(
      'IAPKit publishable key was not found in the environment or macOS Keychain.',
    );
  }
  return validateIapKitPublishableKey(result.stdout);
}

export function cleanupStaleGeneratedIapKitConfig(root) {
  const { config } = iapKitConfigPaths(root);
  return cleanupGeneratedIapKitConfigFile(config);
}

export function cleanupGeneratedIapKitConfigFile(path) {
  if (!existsSync(path)) return false;
  if (!readFileSync(path, 'utf8').startsWith(GENERATED_HEADER)) return false;
  rmSync(path, { force: true });
  return true;
}

export function recoverDirectIapKitConfig(root) {
  const { config, directStage } = iapKitConfigPaths(root);
  if (!existsSync(directStage)) return false;
  if (existsSync(config)) {
    throw new Error('IAPKit config source and direct-distribution staging path both exist');
  }
  renameSync(directStage, config);
  return true;
}

export function stageIapKitConfigForDirect(root) {
  const { config, directStage } = iapKitConfigPaths(root);
  if (!existsSync(config)) return false;
  if (existsSync(directStage)) {
    throw new Error('IAPKit direct-distribution staged config already exists');
  }
  mkdirSync(dirname(directStage), { recursive: true });
  renameSync(config, directStage);
  return true;
}

export function restoreIapKitConfigAfterDirect(root) {
  return recoverDirectIapKitConfig(root);
}

export function stageIapKitConfigForStore(root, options = {}) {
  const { config, directStage } = iapKitConfigPaths(root);
  if (existsSync(config) || existsSync(directStage)) {
    throw new Error(
      'IAPKit config staging file already exists. Confirm the other export finished.',
    );
  }
  const key = resolveIapKitPublishableKey(options);
  mkdirSync(dirname(config), { recursive: true });
  try {
    writeFileSync(
      config,
      `${GENERATED_HEADER}[iapkit]\napi_key="${key}"\n`,
      {
        encoding: 'utf8',
        flag: 'wx',
        mode: 0o600,
      },
    );
  } catch (error) {
    rmSync(config, { force: true });
    throw error;
  }
  return config;
}

export function removeStagedIapKitConfig(root) {
  const { config } = iapKitConfigPaths(root);
  rmSync(config, { force: true });
}
