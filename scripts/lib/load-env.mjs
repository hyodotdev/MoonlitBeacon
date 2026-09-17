/** Read the repo-root `.env` and fill `process.env`.
 *
 *     import './lib/load-env.mjs';   // top of every entry script
 *
 * The point is that `pnpm android:build` picks up signing, IAP, and App
 * Store values without sourcing `scripts/secrets.sh` in every shell.
 *
 * **Existing values are left alone.** Precedence is
 *
 *     live environment  >  .env  >  each script's Keychain / default-path fallback
 *
 * That order keeps CI safe. CI has no `.env` (it is gitignored); secrets
 * arrive as environment variables. If the file overwrote the environment,
 * a stale local value would quietly change CI results. That class of bug
 * is hard to diagnose after the fact.
 *
 * `.env` holds the Android keystore password. **This secret cannot be
 * rotated** — a leak lets someone sign updates as this app, and losing it
 * means we cannot ship updates. Warn if the file mode is not 600.
 *
 * Never print values. Names only.
 */

import { readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ENV_PATH = fileURLToPath(new URL('../../.env', import.meta.url));

/** Parse one `KEY=value` line. Return `null` if the line is not a pair. */
function parseLine(line) {
  const trimmed = line.trim();
  if (trimmed === '' || trimmed.startsWith('#')) return null;
  // Also accept `export FOO=bar` — people paste shell lines as-is.
  const body = trimmed.startsWith('export ') ? trimmed.slice(7).trim() : trimmed;
  const split = body.indexOf('=');
  if (split <= 0) return null;
  const name = body.slice(0, split).trim();
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) return null;
  let value = body.slice(split + 1).trim();
  const quote = value[0];
  if ((quote === '"' || quote === "'") && value.endsWith(quote) && value.length > 1) {
    value = value.slice(1, -1);
  } else {
    // Strip a trailing comment only when the value is unquoted. Do not
    // cut a `#` that belongs to the value.
    const comment = value.indexOf(' #');
    if (comment >= 0) value = value.slice(0, comment).trimEnd();
  }
  return [name, value];
}

/** Read `.env` and fill names that are still empty. Return filled names. */
export function loadEnv({ path = ENV_PATH, env = process.env } = {}) {
  let text = '';
  try {
    text = readFileSync(path, 'utf8');
  } catch {
    return [];                       // missing is fine. CI and new machines look like this.
  }

  try {
    const mode = statSync(path).mode & 0o777;
    if (mode !== 0o600) {
      process.stderr.write(
        `.env mode is ${mode.toString(8)}. It holds a keystore password, so `
        + '`chmod 600 .env` is recommended\n');
    }
  } catch {
    // Failing to read the mode does not stop loading.
  }

  const filled = [];
  for (const line of text.split('\n')) {
    const pair = parseLine(line);
    if (pair === null) continue;
    const [name, value] = pair;
    if (env[name] !== undefined && env[name] !== '') continue;
    if (value === '') continue;      // empty means "not filled yet"
    env[name] = value;
    filled.push(name);
  }
  return filled;
}

loadEnv();
