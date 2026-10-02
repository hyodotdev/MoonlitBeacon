// Run the game project the way the regression runner does, so a one-off run cannot write to the developer's real
// save: a throwaway HOME and `MOONLIT_VAULT_TEST_ROOT` (without which Vault switches every hero on and results
// lie), a hard timeout (a hung Godot never returns) and an environment with no tokens in it.

import { join } from 'node:path';

const ENVIRONMENT_ALLOWED = ['PATH', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TMPDIR', 'TZ', 'GODOT_BIN'];

/**
 * `argv` is what follows `pnpm godot:isolated`. Options of the wrapper come first; everything from the first other
 * argument on goes to Godot, after `--headless --path apps/game`.
 */
export function parseGodotRun(argv) {
  const options = { timeoutSeconds: 900, windowed: false, realHome: false, importOnly: false, filterNoise: false };
  let index = 0;
  for (; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--timeout') {
      options.timeoutSeconds = Number(argv[index + 1]);
      index += 1;
    } else if (token === '--windowed') {
      options.windowed = true;
    } else if (token === '--import') {
      options.importOnly = true;
      options.realHome = true;
    } else if (token === '--filter-noise') {
      options.filterNoise = true;
    } else {
      break;
    }
  }
  if (!Number.isFinite(options.timeoutSeconds) || options.timeoutSeconds < 1) {
    throw new Error('--timeout needs a number of seconds');
  }
  return { options, godotArguments: argv.slice(index) };
}

export function buildGodotArguments({ options, godotArguments }, gameDirectory) {
  const base = options.windowed ? ['--path', gameDirectory] : ['--headless', '--path', gameDirectory];
  if (options.importOnly) return [...base, '--editor', '--quit'];
  return [...base, ...godotArguments];
}

/** The environment of the Godot process: the allowed names from `source` plus the throwaway user directory. */
export function isolatedEnvironment(source, home, { realHome = false } = {}) {
  const environment = {};
  for (const name of ENVIRONMENT_ALLOWED) {
    if (source[name] !== undefined) environment[name] = source[name];
  }
  if (realHome) {
    if (source.HOME !== undefined) environment.HOME = source.HOME;
    return environment;
  }
  environment.HOME = home;
  environment.XDG_DATA_HOME = join(home, '.local', 'share');
  environment.APPDATA = join(home, 'AppData', 'Roaming');
  environment.MOONLIT_VAULT_TEST_ROOT = home;
  return environment;
}

const NOISE = /GodotIap|Camera2D|GDScript backtrace|at: _update|\[0\] _run/;

export function isNoise(line) {
  return NOISE.test(line);
}
