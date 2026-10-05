#!/usr/bin/env node
// The director's handle on the implementer.
//
//   pnpm muse who                       who implements, with which model (from scripts/muse.config.json)
//   pnpm muse models                    the models the CLI offers, the configured one marked
//   pnpm muse doctor                    is everything in place to run it
//   pnpm muse run <brief.md> [--tag T]  copy the repo (no secrets), hand the brief over, wait for the report
//   pnpm muse run <brief.md> --continue <tag>   a second round in the same copy and the same session
//   pnpm muse status [tag]              runs so far, or one run in detail
//   pnpm muse log <tag> [--tail N]      what the implementer has been doing (commands, files), read from its events
//   pnpm muse report <tag>              the implementer's own report of its last round
//   pnpm muse diff <tag> [--full]       what it changed against the copy it was given
//   pnpm muse judge <tag> [--steps a,b]  run the acceptance battery in its copy (checks, perf, tests, nat, gauntlet, store)
//   pnpm muse accept <tag> [--check] [--allow <path>]   apply that change to the real tree
//   pnpm muse revert <tag>              take an accepted change back out
//   pnpm muse discard <tag>             delete the copy
//
// The rules of the workflow are in AGENTS.md and .claude/skills/muse-director/SKILL.md. Starting the
// implementer starts a second autonomous agent, so an agent tool may ask its user first or refuse; when it does,
// stop and tell the user.

import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
  appendFileSync,
  copyFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import {
  CONFIG_FILE,
  REPO_ROOT,
  catalogProblems,
  loadConfig,
  readCatalog,
  whoLine,
} from './lib/muse-config.mjs';
import { STEPS, parseSteps, summarizeOutput } from './lib/muse-judge.mjs';
import {
  buildExecArguments,
  childEnvironment,
  composePrompt,
  isValidTag,
  makeTag,
  summarizeEvent,
} from './lib/muse-run.mjs';
import {
  REPORT_FILE,
  applyPatch,
  changedFiles,
  checkPatch,
  classifyChange,
  createSnapshot,
  diffStat,
  fullDiff,
  isInside,
  writePatch,
} from './lib/muse-workspace.mjs';

const RUNS = join(REPO_ROOT, 'builds', 'muse');
const STANDING_ORDERS = join(REPO_ROOT, 'notes', 'workflow', 'muse', 'standing-orders.md');

const [command = 'help', ...rest] = process.argv.slice(2);

function parseArguments(tokens) {
  const flags = {};
  const positional = [];
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!token.startsWith('--')) {
      positional.push(token);
      continue;
    }
    const name = token.slice(2);
    const next = tokens[index + 1];
    if (['tag', 'continue', 'model', 'effort', 'round', 'allow', 'tail', 'steps'].includes(name)) {
      if (next === undefined || next.startsWith('--')) fail(`--${name} needs a value`, 2);
      (flags[name] ??= []).push(next);
      index += 1;
    } else {
      flags[name] = true;
    }
  }
  return { flags, positional };
}

function fail(message, code = 1) {
  console.error(`muse: ${message}`);
  process.exit(code);
}

function configOrDie() {
  const { config, problems } = loadConfig();
  if (config === null) fail(problems.join('\n'));
  return config;
}

const runDirectory = (tag) => join(RUNS, tag);
const workDirectory = (tag) => join(RUNS, tag, 'work');
const stateFile = (tag) => join(RUNS, tag, 'state.json');

function readState(tag) {
  if (!isValidTag(tag) || !existsSync(stateFile(tag))) fail(`no run called "${tag}" (pnpm muse status lists them)`);
  return JSON.parse(readFileSync(stateFile(tag), 'utf8'));
}

function writeState(tag, state) {
  writeFileSync(stateFile(tag), `${JSON.stringify(state, null, 2)}\n`);
}

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function overallState(state) {
  const last = state.rounds.at(-1);
  if (last === undefined) return 'empty';
  if (last.state === 'running' && !alive(last.pid)) return 'lost';
  return last.state;
}

function resolveCommand(name) {
  const found = spawnSync('sh', ['-c', `command -v ${name}`], { encoding: 'utf8', env: process.env });
  return found.status === 0 ? found.stdout.trim() : null;
}

// --- who / models / doctor ---------------------------------------------------

function who() {
  const config = configOrDie();
  const rows = readCatalog();
  const row = rows.find((candidate) => candidate.id === config.model);
  if (rest.includes('--line')) {
    console.log(whoLine(config));
    return;
  }
  console.log(`implementer  ${config.name}`);
  console.log(`model        ${config.model}`);
  console.log(`effort       ${config.reasoningEffort}`);
  console.log(`time limit   ${config.timeoutMinutes} minutes a round`);
  console.log(`configured   ${CONFIG_FILE}`);
  if (row?.note) console.log(`data use     ${row.note}`);
}

function models() {
  const config = configOrDie();
  const rows = readCatalog();
  if (rows.length === 0) fail('the CLI has no model catalog on this machine (run it once, then try again)');
  for (const row of rows) {
    const mark = row.id === config.model ? '*' : ' ';
    console.log(`${mark} ${row.id}  ${row.released}  efforts: ${row.efforts.join('/')}`);
    if (row.note) console.log(`    ${row.note}`);
  }
  console.log(`\n* is what ${CONFIG_FILE} selects. Change "model" (and "reasoningEffort") there; nothing else names a model.`);
}

function doctor() {
  const { config, problems } = loadConfig();
  const results = [];
  const check = (label, ok, detail = '') => results.push({ label, ok, detail });
  check('config parses', config !== null, problems.join('; '));
  if (config !== null) {
    const rows = readCatalog();
    const mismatch = catalogProblems(config, rows);
    check('model and effort are in the CLI catalog', mismatch.length === 0, rows.length === 0 ? 'no catalog to compare against' : mismatch.join('; '));
    const path = resolveCommand(config.command);
    check(`\`${config.command}\` is on PATH`, path !== null, path ?? 'not found');
    if (path !== null) {
      const version = spawnSync(path, ['--version'], { encoding: 'utf8', timeout: 30000 });
      check('the CLI starts', version.status === 0, (version.stdout || version.stderr || '').trim().split('\n')[0]);
    }
    check('provider sign-in is stored', existsSync(join(homedir(), '.config', 'muse', 'auth.json')), 'run the CLI\'s own login once');
  }
  check('standing orders exist', existsSync(STANDING_ORDERS), STANDING_ORDERS);
  check('git is available', spawnSync('git', ['--version']).status === 0);
  check('node is 20 or newer', Number(process.versions.node.split('.')[0]) >= 20, process.version);
  let failed = 0;
  for (const { label, ok, detail } of results) {
    if (!ok) failed += 1;
    console.log(`${ok ? 'ok ' : 'NO '} ${label}${detail ? ` — ${detail}` : ''}`);
  }
  process.exit(failed === 0 ? 0 : 1);
}

// --- run ---------------------------------------------------------------------

/** The one CLI complaint that earns a fresh session: the old session id is stale. Nothing else does, and an
 * exit code, an elapsed time or a lone word like "session" never stands in for it. */
const STALE_SESSION_ERROR = 'session already exists';

/** True only when the CLI's stderr carries the recognized stale-session error, word for word. */
function isStaleSessionError(errorsPath) {
  try {
    if (!existsSync(errorsPath)) return false;
    return readFileSync(errorsPath, 'utf8').includes(STALE_SESSION_ERROR);
  } catch {
    return false;
  }
}

/** Start the implementer once, stream a short progress line for what it does, and wait for it to end or run out of time. */
async function launch({ executable, work, config, events, errors }, args) {
  const child = spawn(executable, args, { cwd: work, env: childEnvironment(), stdio: ['ignore', 'pipe', 'pipe'] });
  const started = Date.now();
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    console.error(`\ntime limit of ${config.timeoutMinutes} minutes reached; stopping the implementer`);
    child.kill('SIGTERM');
    setTimeout(() => child.kill('SIGKILL'), 20000).unref();
  }, config.timeoutMinutes * 60 * 1000);

  let buffer = '';
  let lastPrinted = 0;
  let skipped = 0;
  child.stdout.on('data', (chunk) => {
    appendFileSync(events, chunk);
    buffer += chunk.toString('utf8');
    let newline = buffer.indexOf('\n');
    while (newline !== -1) {
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      newline = buffer.indexOf('\n');
      const summary = summarizeEvent(line);
      if (summary === null) continue;
      const now = Date.now();
      if (now - lastPrinted < 1500) {
        skipped += 1;
        continue;
      }
      lastPrinted = now;
      const minutes = String(Math.floor((now - started) / 60000)).padStart(3, ' ');
      console.log(`${minutes}m ${skipped > 0 ? `(+${skipped}) ` : ''}${summary}`);
      skipped = 0;
    }
  });
  child.stderr.on('data', (chunk) => appendFileSync(errors, chunk));

  const exitCode = await new Promise((done) => {
    child.on('error', (error) => {
      appendFileSync(errors, `${error.message}\n`);
      done(127);
    });
    child.on('close', (code, signal) => done(code ?? (signal ? 128 : 1)));
  });
  clearTimeout(timer);
  return { exitCode, timedOut, started, seconds: (Date.now() - started) / 1000 };
}

async function run() {
  const { flags, positional } = parseArguments(rest);
  const briefPath = positional[0];
  if (briefPath === undefined || !existsSync(briefPath)) fail('usage: pnpm muse run <brief.md> [--tag T | --continue T] [--dry-run]', 2);
  const config = { ...configOrDie() };
  if (flags.model) config.model = flags.model[0];
  if (flags.effort) config.reasoningEffort = flags.effort[0];
  if (flags.model || flags.effort) console.log(`(overriding ${CONFIG_FILE} for this run: ${config.model}, ${config.reasoningEffort} effort)`);
  const problems = catalogProblems(config, readCatalog());
  if (problems.length > 0) fail(problems.join('\n'));
  const executable = resolveCommand(config.command);
  if (executable === null && !flags['dry-run']) fail(`\`${config.command}\` is not on PATH (pnpm muse doctor)`);
  if (!existsSync(STANDING_ORDERS)) fail(`missing ${STANDING_ORDERS}`);

  const continuing = flags.continue?.[0];
  const tag = continuing ?? flags.tag?.[0] ?? makeTag(briefPath);
  if (!isValidTag(tag)) fail(`"${tag}" is not a usable tag (lowercase letters, digits and dashes)`, 2);
  const directory = runDirectory(tag);
  const work = workDirectory(tag);

  let state;
  if (continuing) {
    state = readState(tag);
    if (overallState(state) === 'running') fail(`${tag} is still running`);
    if (!existsSync(work)) fail(`the copy of ${tag} was discarded`);
  } else {
    if (existsSync(directory)) fail(`${tag} already exists; pick another --tag or use --continue`);
    if (flags['dry-run']) {
      console.log(`would copy the repo to ${work} and start round 1 as ${tag}`);
    } else {
      mkdirSync(directory, { recursive: true });
      console.log(`copying the repo (no secrets, no remote) to ${work} ...`);
      const started = Date.now();
      const { baseline, files } = createSnapshot({ repoRoot: REPO_ROOT, destination: work, withDependencies: !flags['no-deps'] });
      console.log(`copied ${files} files in ${((Date.now() - started) / 1000).toFixed(1)} s, baseline ${baseline.slice(0, 10)}`);
      state = {
        tag,
        createdAt: new Date().toISOString(),
        baseline,
        sessionId: randomUUID(),
        implementer: config.name,
        model: config.model,
        reasoningEffort: config.reasoningEffort,
        rounds: [],
      };
    }
  }

  const round = (state?.rounds.length ?? 0) + 1;
  const brief = readFileSync(briefPath, 'utf8');
  const prompt = composePrompt({
    standingOrders: readFileSync(STANDING_ORDERS, 'utf8'),
    brief,
    tag,
    round,
    timeoutMinutes: config.timeoutMinutes,
    baseline: state?.baseline,
  });
  const promptFile = join(directory, `prompt-${round}.md`);
  const args = buildExecArguments({
    config,
    promptFile,
    workspace: work,
    sessionId: continuing && flags['fresh-session'] ? undefined : state?.sessionId ?? randomUUID(),
    trustWorkspace: flags.trust === true,
  });

  if (flags['dry-run']) {
    console.log(`\n${config.command} ${args.join(' ')}`);
    console.log(`\nprompt: ${prompt.split('\n').length} lines, ${prompt.length} characters`);
    console.log(`environment: ${Object.keys(childEnvironment()).join(', ')}`);
    return;
  }

  writeFileSync(join(directory, `brief-${round}.md`), brief);
  writeFileSync(promptFile, prompt);
  rmSync(join(work, REPORT_FILE), { force: true });
  const record = { round, brief: briefPath, startedAt: new Date().toISOString(), finishedAt: null, exitCode: null, state: 'running', pid: process.pid };
  state.rounds.push(record);
  writeState(tag, state);

  console.log(`round ${round} of ${tag}: ${whoLine(config)}`);
  console.log(`prompt ${promptFile}`);
  const events = join(directory, `events-${round}.jsonl`);
  const errors = join(directory, `stderr-${round}.log`);
  const launched = { executable, work, config, events, errors };
  let outcome = await launch(launched, args);
  // The CLI may refuse to take an old session id again. Then the same copy gets a fresh session: it has lost the
  // conversation but not the work, and the brief of a continuation says to read the diff first. Only the recognized
  // stale-session error earns that retry; anything else (an approval or classifier refusal, an unknown failure)
  // stops after one launch, as AGENTS.md requires.
  if (continuing && !flags['fresh-session'] && !outcome.timedOut && outcome.exitCode !== 0 && isStaleSessionError(errors)) {
    console.log('\nthe CLI would not take the old session again; starting a fresh session in the same copy');
    record.sessionRetried = true;
    outcome = await launch(launched, buildExecArguments({ config, promptFile, workspace: work, trustWorkspace: flags.trust === true }));
  }
  const { exitCode, timedOut, started } = outcome;

  record.finishedAt = new Date().toISOString();
  record.exitCode = exitCode;
  record.state = timedOut ? 'timeout' : exitCode === 0 ? 'done' : 'failed';
  writeState(tag, state);

  const reportPath = join(work, REPORT_FILE);
  if (existsSync(reportPath)) copyFileSync(reportPath, join(directory, `report-${round}.md`));
  console.log(`\nround ${round} ${record.state} after ${((Date.now() - started) / 60000).toFixed(1)} minutes (exit ${exitCode})`);
  if (existsSync(reportPath)) {
    console.log('\n--- the implementer\'s report ---\n');
    console.log(readFileSync(reportPath, 'utf8'));
  } else {
    console.log(`the implementer left no ${REPORT_FILE}; read what it did with: pnpm muse log ${tag}  (raw events: ${events})`);
  }
  printChanges(tag, state);
  console.log(`\nnext: pnpm muse diff ${tag} | pnpm muse accept ${tag} --check | pnpm muse run <brief> --continue ${tag}`);
  process.exit(record.state === 'done' ? 0 : 1);
}

// --- reading a run -------------------------------------------------------------

function printChanges(tag, state) {
  const changes = changedFiles(workDirectory(tag), state.baseline);
  const counts = { A: 0, M: 0, D: 0 };
  for (const { status } of changes) counts[status] = (counts[status] ?? 0) + 1;
  console.log(`\nchanged against the copy it was given: ${counts.A} added, ${counts.M} modified, ${counts.D} deleted`);
  const flagged = changes.map((change) => ({ ...change, ...classifyChange(change.path) })).filter((change) => change.level !== 'free');
  for (const change of flagged) {
    console.log(`  ${change.level === 'protected' ? 'PROTECTED' : 'watch    '} ${change.status} ${change.path} (${change.why})`);
  }
}

function status() {
  const { positional } = parseArguments(rest);
  if (positional[0] === undefined) {
    if (!existsSync(RUNS)) return console.log('no runs yet');
    const tags = readdirSync(RUNS).filter((name) => existsSync(join(RUNS, name, 'state.json'))).sort();
    if (tags.length === 0) return console.log('no runs yet');
    for (const tag of tags) {
      const state = readState(tag);
      const last = state.rounds.at(-1);
      console.log(`${tag}  ${overallState(state)}  rounds ${state.rounds.length}  ${last?.startedAt ?? ''}`);
    }
    return undefined;
  }
  const state = readState(positional[0]);
  console.log(`${state.tag}: ${overallState(state)} — ${state.implementer}, ${state.model}, ${state.reasoningEffort} effort`);
  console.log(`baseline ${state.baseline.slice(0, 10)}, session ${state.sessionId}`);
  for (const round of state.rounds) {
    console.log(`  round ${round.round}: ${round.state}${round.exitCode === null ? '' : ` (exit ${round.exitCode})`} ${round.startedAt} → ${round.finishedAt ?? '…'}`);
  }
  const last = state.rounds.at(-1);
  if (last) {
    const events = join(runDirectory(state.tag), `events-${last.round}.jsonl`);
    if (existsSync(events)) console.log(`events: ${readFileSync(events, 'utf8').split('\n').filter(Boolean).length} lines, ${statSync(events).size} bytes`);
  }
  printChanges(state.tag, state);
  return undefined;
}

function log() {
  const { flags, positional } = parseArguments(rest);
  const tag = positional[0];
  if (tag === undefined) fail('usage: pnpm muse log <tag> [--tail N] [--round N]', 2);
  const state = readState(tag);
  const round = Number(flags.round?.[0] ?? state.rounds.length);
  const events = join(runDirectory(tag), `events-${round}.jsonl`);
  if (!existsSync(events)) fail(`no events for round ${round} of ${tag}`);
  const lines = [];
  for (const line of readFileSync(events, 'utf8').split('\n')) {
    const summary = summarizeEvent(line);
    if (summary !== null) lines.push(summary);
  }
  const tail = Number(flags.tail?.[0] ?? 40);
  console.log(`${tag} round ${round}: ${overallState(state)}, ${lines.length} things done so far`);
  for (const line of lines.slice(-tail)) console.log(`  ${line}`);
}

function report() {
  const { flags, positional } = parseArguments(rest);
  const tag = positional[0];
  if (tag === undefined) fail('usage: pnpm muse report <tag> [--round N]', 2);
  const state = readState(tag);
  const round = Number(flags.round?.[0] ?? state.rounds.length);
  const path = join(runDirectory(tag), `report-${round}.md`);
  if (!existsSync(path)) fail(`no report for round ${round} of ${tag}`);
  process.stdout.write(readFileSync(path, 'utf8'));
}

function diff() {
  const { flags, positional } = parseArguments(rest);
  const tag = positional[0];
  if (tag === undefined) fail('usage: pnpm muse diff <tag> [--full | --names]', 2);
  const state = readState(tag);
  const work = workDirectory(tag);
  if (flags.names) {
    for (const change of changedFiles(work, state.baseline)) console.log(`${change.status}\t${change.path}`);
    return;
  }
  if (flags.full) {
    if (overallState(state) === 'running') fail(`${tag} is still running; a full diff stages its copy. Read the files, or wait for the round to finish`);
    process.stdout.write(fullDiff(work, state.baseline));
    return;
  }
  process.stdout.write(diffStat(work, state.baseline));
  printChanges(tag, state);
}

async function judge() {
  const { flags, positional } = parseArguments(rest);
  const tag = positional[0];
  if (tag === undefined) fail('usage: pnpm muse judge <tag> [--steps checks,perf,tests,nat,gauntlet,store]', 2);
  const state = readState(tag);
  if (overallState(state) === 'running') fail(`${tag} is still running; judge it when the round has finished`);
  let names;
  try {
    names = parseSteps(flags.steps?.[0]);
  } catch (error) {
    fail(error.message, 2);
  }
  const work = workDirectory(tag);
  const out = join(runDirectory(tag), 'judge');
  mkdirSync(out, { recursive: true });
  const results = [];
  for (const name of names) {
    const step = STEPS[name];
    console.log(`\n== ${name}: ${step.label}`);
    const started = Date.now();
    let output = '';
    let worst = 0;
    for (const [command, ...args] of step.commands) {
      console.log(`   $ ${[command, ...args].join(' ')}`);
      const run = spawnSync(command, args, { cwd: work, env: process.env, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, timeout: step.timeoutSeconds * 1000 });
      output += `$ ${[command, ...args].join(' ')}\n${run.stdout ?? ''}${run.stderr ?? ''}\n(exit ${run.status ?? run.signal})\n\n`;
      worst = Math.max(worst, run.status === 0 ? 0 : run.status ?? 124);
    }
    writeFileSync(join(out, `${name}.log`), output);
    let report = '';
    if (step.report && existsSync(join(work, step.report))) {
      const made = spawnSync('python3', ['apps/game/tools/play_report.py', step.report], { cwd: work, encoding: 'utf8' });
      report = `${made.stdout ?? ''}${made.stderr ?? ''}`;
      writeFileSync(join(out, `${name}.report.txt`), report);
    }
    const summary = summarizeOutput(output);
    const seconds = Math.round((Date.now() - started) / 1000);
    results.push({ name, exit: worst, seconds, failureLines: summary.failureLines });
    console.log(`   ${worst === 0 ? 'exit 0' : `exit ${worst}${step.expectFailure ? ' (expected)' : ''}`} after ${seconds} s, ${summary.failureLines} failure-looking line(s), log: ${join(out, `${name}.log`)}`);
    for (const line of summary.firstFailures) console.log(`   ! ${line.slice(0, 160)}`);
    if (report !== '') console.log(report.split('\n').filter((line) => /^(hits:|  by cause|bullets:|places|guardian fights|  guardian_|soft locks|bolt peak|stuck|\d+ runs)/.test(line)).join('\n'));
    else for (const line of summary.tail.slice(-3)) console.log(`   | ${line.slice(0, 160)}`);
  }
  writeFileSync(join(out, 'summary.json'), `${JSON.stringify({ tag, at: new Date().toISOString(), results }, null, 2)}\n`);
  console.log(`\njudged ${tag}: ${results.map((row) => `${row.name}=${row.exit === 0 ? 'ok' : `exit ${row.exit}`}`).join(' ')}`);
}

function accept() {
  const { flags, positional } = parseArguments(rest);
  const tag = positional[0];
  if (tag === undefined) fail('usage: pnpm muse accept <tag> [--check] [--allow <path>]', 2);
  const state = readState(tag);
  if (overallState(state) !== 'done' && !flags.force) fail(`${tag} is ${overallState(state)}; only a finished run is accepted (--force to override)`);
  if (existsSync(join(runDirectory(tag), 'accepted.json')) && !flags.check) fail(`${tag} was accepted already (pnpm muse revert ${tag} first)`);
  const work = workDirectory(tag);
  const allowed = flags.allow ?? [];
  const changes = changedFiles(work, state.baseline);
  if (changes.length === 0) fail('nothing changed; nothing to accept');
  const blocked = changes
    .map((change) => ({ ...change, ...classifyChange(change.path) }))
    .filter((change) => change.level === 'protected' && !allowed.some((entry) => change.path === entry || change.path.startsWith(entry.endsWith('/') ? entry : `${entry}/`)));
  if (blocked.length > 0) {
    for (const change of blocked) console.error(`  PROTECTED ${change.status} ${change.path} (${change.why})`);
    fail('the change touches protected paths; review them, then pass --allow <path> for each you accept, or send it back', 3);
  }
  const patch = join(runDirectory(tag), 'changes.patch');
  writePatch(work, state.baseline, patch);
  const check = checkPatch(REPO_ROOT, patch);
  if (!check.ok) {
    console.error(check.message);
    fail('the patch does not apply to the real tree as it is now (something changed there since the copy was made)', 4);
  }
  if (flags.check) {
    console.log(`ok: ${changes.length} file(s) would apply cleanly (${patch})`);
    return;
  }
  const applied = applyPatch(REPO_ROOT, patch);
  if (!applied.ok) fail(applied.message, 4);
  writeFileSync(join(runDirectory(tag), 'accepted.json'), `${JSON.stringify({ at: new Date().toISOString(), files: changes.length }, null, 2)}\n`);
  console.log(`applied ${changes.length} file(s) to the working tree. Next: run the checks (pnpm verify) on the real tree.`);
}

function revert() {
  const { positional } = parseArguments(rest);
  const tag = positional[0];
  if (tag === undefined) fail('usage: pnpm muse revert <tag>', 2);
  const patch = join(runDirectory(tag), 'changes.patch');
  if (!existsSync(join(runDirectory(tag), 'accepted.json')) || !existsSync(patch)) fail(`${tag} was not accepted`);
  const check = spawnSync('git', ['apply', '-R', '--check', '--binary', patch], { cwd: REPO_ROOT, encoding: 'utf8' });
  if (check.status !== 0) fail(`cannot take it back cleanly: ${check.stderr}`, 4);
  const undone = spawnSync('git', ['apply', '-R', '--binary', patch], { cwd: REPO_ROOT, encoding: 'utf8' });
  if (undone.status !== 0) fail(undone.stderr, 4);
  rmSync(join(runDirectory(tag), 'accepted.json'), { force: true });
  console.log('reverted');
}

function discard() {
  const { positional } = parseArguments(rest);
  const tag = positional[0];
  if (tag === undefined) fail('usage: pnpm muse discard <tag>', 2);
  const state = readState(tag);
  if (overallState(state) === 'running') fail(`${tag} is still running`);
  const directory = runDirectory(tag);
  if (!isInside(RUNS, directory)) fail('refusing to delete outside builds/muse');
  rmSync(directory, { recursive: true, force: true });
  console.log(`deleted ${directory}`);
}

const commands = { who, models, doctor, run, status, list: status, log, report, diff, judge, accept, revert, discard };
if (command === 'help' || commands[command] === undefined) {
  // The header comment at the top of this file is the help text.
  const header = [];
  for (const line of readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1)) {
    if (!line.startsWith('//')) break;
    header.push(line.slice(3));
  }
  console.log(header.join('\n'));
  process.exit(command === 'help' ? 0 : 2);
}
await commands[command]();
