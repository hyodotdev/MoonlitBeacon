import { spawnSync } from 'node:child_process';
import {
  existsSync,
  lstatSync,
  realpathSync,
} from 'node:fs';
import { homedir } from 'node:os';
import {
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';

const KEYCHAIN_SERVICE = 'dev.moonlitbeacon.android-signing';
const KEYCHAIN_ACCOUNT = 'moonlitbeacon-upload';
const DEFAULT_KEYSTORE_NAME = 'moonlit-beacon-upload.jks';

function trimmed(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function passwordValue(value) {
  return typeof value === 'string'
    ? value.replace(/\r?\n$/, '')
    : '';
}

function pathIsInside(parent, child) {
  const relation = relative(resolve(parent), resolve(child));
  return relation === ''
    || (!relation.startsWith(`..${sep}`) && relation !== '..' && !isAbsolute(relation));
}

export function resolveAndroidReleaseSigning({
  env = process.env,
  exists = existsSync,
  home = homedir(),
  lstat = lstatSync,
  platform = process.platform,
  realpath = realpathSync,
  root,
  spawn = spawnSync,
} = {}) {
  const keystorePath = trimmed(
    env.GODOT_ANDROID_KEYSTORE_RELEASE_PATH,
  ) || (
    platform === 'darwin'
      ? join(
        home,
        'Library/Application Support/MoonlitBeacon/signing',
        DEFAULT_KEYSTORE_NAME,
      )
      : ''
  );
  const alias = trimmed(
    env.GODOT_ANDROID_KEYSTORE_RELEASE_USER,
  ) || KEYCHAIN_ACCOUNT;
  let password = passwordValue(
    env.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD,
  );

  if (!keystorePath || !exists(keystorePath)) {
    throw new Error(
      'Android release keystore not found. '
      + 'Check GODOT_ANDROID_KEYSTORE_RELEASE_PATH.',
    );
  }
  if (!isAbsolute(keystorePath)) {
    throw new Error('Android release keystore path must be absolute.');
  }
  const keystoreFile = lstat(keystorePath);
  if (!keystoreFile.isFile() || keystoreFile.isSymbolicLink()) {
    throw new Error('Android release keystore must be a regular file.');
  }
  if ((keystoreFile.mode & 0o077) !== 0) {
    throw new Error('Android release keystore mode must be 600 or tighter.');
  }
  if (
    root
    && (
      pathIsInside(root, keystorePath)
      || pathIsInside(realpath(root), realpath(keystorePath))
    )
  ) {
    throw new Error('Android release keystore must live outside the repository.');
  }
  if (!alias) {
    throw new Error(
      'Android release key alias is missing. '
      + 'Check GODOT_ANDROID_KEYSTORE_RELEASE_USER.',
    );
  }

  if (!password && platform === 'darwin') {
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
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: 10_000,
      },
    );
    if (result.status === 0) password = passwordValue(result.stdout);
  }

  if (!password) {
    throw new Error(
      'Android release keystore password was not found in the environment '
      + 'or macOS Keychain.',
    );
  }

  return {
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: password,
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH: keystorePath,
    GODOT_ANDROID_KEYSTORE_RELEASE_USER: alias,
  };
}
