// Which implementer runs, and with what model: one file, `scripts/muse.config.json`.
//
// Everything else in the repo (AGENTS.md, the commands, the skills, the standing orders) says
// "the implementer" and points here, so switching to another model is one edit and the rest
// follows. `pnpm muse who` prints what is configured, `pnpm muse models` lists what the CLI
// offers, `pnpm muse doctor` checks the two agree, and `check-hygiene` fails when a document
// hardcodes a model id instead of pointing here.

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const CONFIG_FILE = 'scripts/muse.config.json';

/** The model family the implementer CLI names its models after. A file that mentions an id of this shape
 * (other than the config) is out of date the day the model changes. */
export const MODEL_FAMILY_PATTERN = /\bmuse-spark-[0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?/g;

const EFFORTS = ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra'];
const MODEL_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{1,80}$/;
const COMMAND = /^[A-Za-z0-9][A-Za-z0-9._-]{0,40}$/;

export function parseConfig(text) {
  let raw;
  try {
    raw = JSON.parse(text);
  } catch (error) {
    return { config: null, problems: [`${CONFIG_FILE}: not valid JSON (${error.message})`] };
  }
  const problems = configProblems(raw);
  if (problems.length > 0) return { config: null, problems };
  const { implementer } = raw;
  return {
    config: {
      name: implementer.name,
      command: implementer.command,
      model: implementer.model,
      reasoningEffort: implementer.reasoningEffort,
      timeoutMinutes: raw.timeoutMinutes ?? 300,
    },
    problems: [],
  };
}

export function configProblems(raw) {
  const problems = [];
  const implementer = raw?.implementer;
  if (implementer === null || typeof implementer !== 'object') {
    return [`${CONFIG_FILE}: "implementer" object is missing`];
  }
  if (typeof implementer.name !== 'string' || implementer.name.trim() === '') {
    problems.push(`${CONFIG_FILE}: implementer.name must be a non-empty string`);
  }
  if (typeof implementer.command !== 'string' || !COMMAND.test(implementer.command)) {
    problems.push(`${CONFIG_FILE}: implementer.command must be a bare command name such as "muse"`);
  }
  if (typeof implementer.model !== 'string' || !MODEL_ID.test(implementer.model)) {
    problems.push(`${CONFIG_FILE}: implementer.model must be a model id`);
  }
  if (!EFFORTS.includes(implementer.reasoningEffort)) {
    problems.push(`${CONFIG_FILE}: implementer.reasoningEffort must be one of ${EFFORTS.join(', ')}`);
  }
  const minutes = raw.timeoutMinutes;
  if (minutes !== undefined && (!Number.isInteger(minutes) || minutes < 5 || minutes > 1440)) {
    problems.push(`${CONFIG_FILE}: timeoutMinutes must be a whole number from 5 to 1440`);
  }
  return problems;
}

export function loadConfig(repoRoot = REPO_ROOT) {
  const path = join(repoRoot, CONFIG_FILE);
  if (!existsSync(path)) return { config: null, problems: [`${CONFIG_FILE}: missing`] };
  return parseConfig(readFileSync(path, 'utf8'));
}

/** "Muse (model-id, max effort)": the one line commits and reports use to say who wrote a change. */
export function whoLine(config) {
  return `${config.name} (${config.model}, ${config.reasoningEffort} effort)`;
}

/** The catalog the CLI keeps of the models it can run. Absent (a fresh machine, CI) is not an error. */
export function readCatalog(home = homedir()) {
  const dir = join(home, '.local', 'share', 'muse', 'model-catalog');
  if (!existsSync(dir)) return [];
  const rows = [];
  for (const name of readdirSync(dir).sort()) {
    if (!name.endsWith('.json')) continue;
    try {
      const document = JSON.parse(readFileSync(join(dir, name), 'utf8'));
      for (const row of document.rows ?? []) {
        if (typeof row.model_id !== 'string') continue;
        rows.push({
          id: row.model_id,
          released: row.release_date ?? '',
          current: row.is_current === true,
          efforts: (row.reasoning_effort_variants ?? []).map((variant) => variant.tier),
          note: row.description ?? '',
        });
      }
    } catch {
      // A half-written catalog is treated as no catalog; `doctor` says so.
    }
  }
  return rows;
}

/** Problems between the config and what the CLI offers. Empty when the catalog is unavailable. */
export function catalogProblems(config, rows) {
  if (rows.length === 0) return [];
  const row = rows.find((candidate) => candidate.id === config.model);
  if (row === undefined) {
    const known = rows.map((candidate) => candidate.id).join(', ');
    return [`${CONFIG_FILE}: model "${config.model}" is not in the CLI's catalog (${known})`];
  }
  if (row.efforts.length > 0 && !row.efforts.includes(config.reasoningEffort)) {
    return [
      `${CONFIG_FILE}: "${config.model}" does not offer "${config.reasoningEffort}" effort `
      + `(it offers ${row.efforts.join(', ')})`,
    ];
  }
  return [];
}

/**
 * Tracked files that name a model id of the implementer's family. Only the config may: everywhere else says
 * "the implementer" and points at the config, so changing the model is one edit.
 * `files` is `[{ path, text }]`; the config file itself and `exempt` paths are skipped.
 */
export function modelMentions(files, exempt = []) {
  const found = [];
  for (const { path, text } of files) {
    if (path === CONFIG_FILE || exempt.includes(path)) continue;
    text.split('\n').forEach((line, index) => {
      for (const match of line.matchAll(MODEL_FAMILY_PATTERN)) {
        found.push(`${path}:${index + 1}: names the model "${match[0]}" — say "the implementer" and point to ${CONFIG_FILE}`);
      }
    });
  }
  return found;
}
