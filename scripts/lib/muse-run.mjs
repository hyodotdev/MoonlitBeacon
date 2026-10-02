// How one run of the implementer is started: what it is told, what environment it sees, and which safety
// settings it is always given. Nothing here starts a process; `scripts/muse.mjs` does that with these values,
// so the settings can be tested.

import { basename } from 'node:path';

/** The only environment variables the implementer's process inherits. Tokens, keys and cloud credentials from
 * the director's shell are deliberately not among them. */
const ENVIRONMENT_ALLOWED = [
  'PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TMPDIR', 'TZ',
  'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'GODOT_BIN',
];
const SECRET_NAME = /(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|PRIVATE|CREDENTIAL|_KEY$|_PEM$)/i;

export function childEnvironment(source = process.env) {
  const environment = {};
  for (const name of ENVIRONMENT_ALLOWED) {
    if (source[name] !== undefined) environment[name] = source[name];
  }
  // The CLI's own settings ride on MUSE_*; a value that looks like a secret still does not pass.
  for (const [name, value] of Object.entries(source)) {
    if (name.startsWith('MUSE_') && !SECRET_NAME.test(name) && value !== undefined) environment[name] = value;
  }
  environment.TERM = 'dumb';
  return environment;
}

/** What a run may never be started with. The runner refuses to build arguments containing any of these, and the
 * tests hold it to that. */
export const FORBIDDEN_FLAGS = [
  '--yolo',
  '--disable-approval',
  '--disable-sandbox',
  '--sandbox-network=enabled',
  '--dangerously-skip-permissions',
];

/**
 * Arguments for `<command> exec`. Approvals stay on (the CLI's own judge answers what a headless run cannot),
 * the sandbox stays on with no network, the web tools are off and the director's personal rules are not loaded.
 * The prompt travels as a file so it never appears in a process listing.
 */
export function buildExecArguments({ config, promptFile, workspace, sessionId, trustWorkspace = false }) {
  const args = [
    'exec',
    '--model', config.model,
    '--reasoning-effort', config.reasoningEffort,
    '--workspace', workspace,
    '--approval-mode', 'on-request',
    '--approval-judge', 'on',
    '--sandbox-network', 'restricted',
    '--disable-web-tools',
    '--no-foreign-personal-context',
    '--json',
    '--prompt-file', promptFile,
  ];
  if (trustWorkspace) args.push('--trust-workspace');
  if (sessionId) args.push('--session-id', sessionId);
  for (const flag of FORBIDDEN_FLAGS) {
    if (args.includes(flag)) throw new Error(`refusing to start the implementer with ${flag}`);
  }
  return args;
}

/**
 * The prompt of one round: the facts of the round, the standing orders, then the director's brief. The facts let the
 * implementer pace itself: a round that runs out of time is cut off wherever it happens to be.
 */
export function composePrompt({ standingOrders, brief, tag, round, timeoutMinutes, startedAt = new Date(), baseline }) {
  const facts = [`- Round ${round} of assignment ${tag}.`];
  if (timeoutMinutes) {
    const ends = new Date(startedAt.getTime() + timeoutMinutes * 60000);
    facts.push(
      `- This round is cut off after ${timeoutMinutes} minutes: it started at ${startedAt.toISOString()} and ends at`
      + ` ${ends.toISOString()} (check \`date -u\`). Plan to have your report written by 75% of that; anything unfinished`
      + ' at the cut-off is lost, and a report that is missing is a failed round.',
    );
  }
  if (baseline) facts.push(`- Your copy's \`baseline\` commit is ${baseline.slice(0, 12)}; the director reads \`git diff baseline\`.`);
  return [
    `# Assignment ${tag}, round ${round}`,
    '',
    '## Facts of this round',
    '',
    ...facts,
    '',
    standingOrders.trim(),
    '',
    '---',
    '',
    '# The brief',
    '',
    brief.trim(),
    '',
  ].join('\n');
}

const SLUG_PART = /[^a-z0-9]+/g;

/** `20260930-0930-bullet-fields` from a brief file name and the time it was started. */
export function makeTag(briefPath, now = new Date()) {
  const stem = basename(briefPath).replace(/\.[^.]+$/, '').toLowerCase().replace(/^\d+-/, '');
  const slug = stem.replace(SLUG_PART, '-').replace(/^-|-$/g, '').slice(0, 40) || 'brief';
  const pad = (value) => String(value).padStart(2, '0');
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}`;
  return `${stamp}-${slug}`;
}

export function isValidTag(tag) {
  return /^[a-z0-9][a-z0-9-]{2,80}$/.test(tag);
}

const clip = (text, length = 140) => String(text).replace(/\s+/g, ' ').trim().slice(0, length);
const relativeToWork = (path) => String(path).replace(/^.*\/work\//, '');

/**
 * One short line for a progress display from one line of the CLI's JSONL output, or null when the line says
 * nothing a reader needs. Tolerant on purpose: the shape of the events is the CLI's, not ours. What it prints for
 * the CLI's own events is what the director watches: the commands it runs (and their exit status), the files it
 * reads, writes and edits, and anything the CLI refused.
 */
export function summarizeEvent(line) {
  let event;
  try {
    event = JSON.parse(line);
  } catch {
    return line.trim() === '' ? null : clip(line, 160);
  }
  const kind = event.payload_type ?? event.type ?? event.event ?? event.kind ?? '';
  const payload = event.payload ?? event.data ?? event;

  if (kind === 'tool.result') {
    const text = typeof payload.text === 'string' ? payload.text : '';
    const denied = payload.edit_facts?.path ? ` (${relativeToWork(payload.edit_facts.path)})` : '';
    if (text.startsWith('tool denied')) return `DENIED: ${clip(text, 80)}${denied}`;
    if (text.startsWith('{')) {
      try {
        const exec = JSON.parse(text);
        const status = exec.exit_code === null || exec.exit_code === undefined ? 'started' : exec.exit_code === 0 ? 'ok' : `exit ${exec.exit_code}`;
        return `run ${status}: ${clip(exec.description || exec.command || '')}`;
      } catch {
        // not an exec result; fall through to the text patterns
      }
    }
    const read = /^Read text file `([^`]+)`/.exec(text);
    if (read) return `read ${relativeToWork(read[1])}`;
    const wrote = /^wrote (\d+) bytes to (.+)$/.exec(text);
    if (wrote) return `write ${relativeToWork(wrote[2])} (${wrote[1]} bytes)`;
    if (text.startsWith('edited')) return `edit ${clip(text.replace(/^edited\s*/, ''), 100)}`;
    return text === '' ? null : clip(text, 100);
  }
  // The CLI's own bookkeeping (task lifecycle, run and session links) is not progress.
  if (/^(task|runtime|session)\./.test(kind)) return null;

  const detail = [payload.command, payload.tool, payload.tool_name, payload.name, payload.path, payload.text, payload.message]
    .find((value) => typeof value === 'string' && value.trim() !== '');
  if (kind === '' && detail === undefined) return null;
  return detail === undefined ? String(kind) : `${kind}: ${clip(detail)}`;
}
