// The runner end to end against a stand-in for the implementer's CLI: a shell script that behaves like
// `<command> exec` (reads the prompt, changes a file in its workspace, writes a report, prints JSON events).
// Nothing here starts the real CLI, touches the network or reads the developer's checkout.

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const REAL_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SCRIPTS = [
  'scripts/muse.mjs',
  'scripts/lib/muse-config.mjs',
  'scripts/lib/muse-judge.mjs',
  'scripts/lib/muse-run.mjs',
  'scripts/lib/muse-workspace.mjs',
];

const FAKE_CLI = `#!/bin/sh
# A stand-in for \`<command> exec\`. Behaviour is chosen by FAKE_MODE in the workspace's .muse/mode file.
if [ "$1" = "--version" ]; then echo "fake 0.0.1"; exit 0; fi
workspace=""; prompt=""; session=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) workspace="$2"; shift 2;;
    --prompt-file) prompt="$2"; shift 2;;
    --session-id) session="$2"; shift 2;;
    *) shift;;
  esac
done
cd "$workspace" || exit 3
mkdir -p .muse
echo "launch session=\${session:-none}" >> .muse/launches.log
mode=$(cat .muse/mode 2>/dev/null || echo change)
if [ "$mode" = "reject-session" ] && [ -n "$session" ]; then echo "session already exists" >&2; exit 9; fi
if [ "$mode" = "refuse-launch" ] && [ -n "$session" ]; then echo "approval required: classifier refused session start" >&2; exit 5; fi
env | cut -d= -f1 | sort > .muse/env-names.txt
cp "$prompt" .muse/prompt-seen.md
echo '{"type":"session.start","payload":{"text":"hello"}}'
case "$mode" in
  change) echo "// changed by the implementer" >> apps/game/scripts/player.gd; echo 'new file' > apps/game/scripts/added.gd;;
  protected) echo "tampered" >> AGENTS.md;;
  fail) echo '{"type":"error","payload":{"message":"boom"}}'; exit 7;;
esac
echo '{"type":"tool_call","payload":{"command":"pnpm test:game"}}'
printf '# Report\\n\\nDid the thing.\\n' > IMPLEMENTER_REPORT.md
exit 0
`;

/** A tiny checkout that contains its own copy of the runner, so the runner's repo root is this checkout. */
function makeCheckout(t) {
  const root = mkdtempSync(join(tmpdir(), 'muse-cli-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const file of SCRIPTS) {
    mkdirSync(dirname(join(root, file)), { recursive: true });
    copyFileSync(join(REAL_ROOT, file), join(root, file));
  }
  writeFileSync(join(root, 'scripts/muse.config.json'), JSON.stringify({
    implementer: { name: 'Fake', command: 'fakemuse', model: 'model-under-test', reasoningEffort: 'max' },
    timeoutMinutes: 5,
  }));
  mkdirSync(join(root, 'notes/workflow/muse'), { recursive: true });
  writeFileSync(join(root, 'notes/workflow/muse/standing-orders.md'), 'STANDING ORDERS\n');
  mkdirSync(join(root, 'apps/game/scripts'), { recursive: true });
  writeFileSync(join(root, 'apps/game/scripts/player.gd'), 'extends Node\n');
  writeFileSync(join(root, 'AGENTS.md'), '# rules\n');
  writeFileSync(join(root, '.gitignore'), 'builds/\n.env\n');
  writeFileSync(join(root, '.env'), 'SECRET=1\n');
  writeFileSync(join(root, 'brief.md'), '# Brief\n\nDo the thing.\n');
  const home = join(root, 'fakehome'); // no model catalog in it, and none of the developer's settings
  mkdirSync(home);
  const bin = join(root, 'fakebin');
  mkdirSync(bin);
  writeFileSync(join(bin, 'fakemuse'), FAKE_CLI, { mode: 0o755 });
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
  git('init', '-q', '-b', 'main');
  git('config', 'user.email', 't@example.com');
  git('config', 'user.name', 't');
  git('add', '-A');
  git('commit', '-q', '-m', 'init');
  return { root, bin, home };
}

function muse(checkout, args, { mode } = {}) {
  const env = { ...process.env, HOME: checkout.home, PATH: `${checkout.bin}:${process.env.PATH}`, GH_TOKEN: 'must-not-leak', ANTHROPIC_API_KEY: 'must-not-leak' };
  const run = spawnSync(process.execPath, [join(checkout.root, 'scripts/muse.mjs'), ...args], { cwd: checkout.root, env, encoding: 'utf8' });
  return { status: run.status, out: `${run.stdout}${run.stderr}` };
}

const workOf = (checkout, tag) => join(checkout.root, 'builds', 'muse', tag, 'work');

/** Launch lines the stand-in recorded in this copy; the caller clears the log to count one round only. */
const launchesIn = (checkout, tag) => {
  const log = join(workOf(checkout, tag), '.muse/launches.log');
  if (!existsSync(log)) return [];
  return readFileSync(log, 'utf8').split('\n').filter(Boolean);
};

test('a run copies the repo without secrets, hands over the orders and the brief, and reports the change', (t) => {
  const checkout = makeCheckout(t);
  const result = muse(checkout, ['run', 'brief.md', '--tag', 'first-run', '--no-deps']);
  assert.equal(result.status, 0, result.out);
  assert.match(result.out, /--- the implementer's report ---/);
  assert.match(result.out, /Did the thing\./);
  assert.match(result.out, /1 added, 1 modified, 0 deleted/);

  const work = workOf(checkout, 'first-run');
  assert.ok(!existsSync(join(work, '.env')), 'no secret in the copy');
  const prompt = readFileSync(join(work, '.muse/prompt-seen.md'), 'utf8');
  assert.ok(prompt.indexOf('STANDING ORDERS') < prompt.indexOf('Do the thing.'));
  const names = readFileSync(join(work, '.muse/env-names.txt'), 'utf8').split('\n');
  assert.ok(!names.includes('GH_TOKEN') && !names.includes('ANTHROPIC_API_KEY'), 'no token in the implementer\'s environment');
  assert.ok(names.includes('PATH') && names.includes('HOME'));

  const state = JSON.parse(readFileSync(join(checkout.root, 'builds/muse/first-run/state.json'), 'utf8'));
  assert.equal(state.rounds.length, 1);
  assert.equal(state.rounds[0].state, 'done');
  assert.equal(state.model, 'model-under-test');
  assert.ok(existsSync(join(checkout.root, 'builds/muse/first-run/report-1.md')));
  assert.ok(existsSync(join(checkout.root, 'builds/muse/first-run/events-1.jsonl')));
});

test('accept applies the change to the real tree, refuses a second time, and revert takes it back', (t) => {
  const checkout = makeCheckout(t);
  assert.equal(muse(checkout, ['run', 'brief.md', '--tag', 'accept-run', '--no-deps']).status, 0);
  const check = muse(checkout, ['accept', 'accept-run', '--check']);
  assert.equal(check.status, 0, check.out);
  assert.equal(readFileSync(join(checkout.root, 'apps/game/scripts/player.gd'), 'utf8'), 'extends Node\n', '--check changes nothing');

  const accepted = muse(checkout, ['accept', 'accept-run']);
  assert.equal(accepted.status, 0, accepted.out);
  assert.match(readFileSync(join(checkout.root, 'apps/game/scripts/player.gd'), 'utf8'), /changed by the implementer/);
  assert.ok(existsSync(join(checkout.root, 'apps/game/scripts/added.gd')));
  assert.notEqual(muse(checkout, ['accept', 'accept-run']).status, 0, 'accepting twice is refused');

  assert.equal(muse(checkout, ['revert', 'accept-run']).status, 0);
  assert.equal(readFileSync(join(checkout.root, 'apps/game/scripts/player.gd'), 'utf8'), 'extends Node\n');
  assert.ok(!existsSync(join(checkout.root, 'apps/game/scripts/added.gd')));
});

test('a change to a protected path is refused unless it is allowed by name', (t) => {
  const checkout = makeCheckout(t);
  assert.equal(muse(checkout, ['run', 'brief.md', '--tag', 'protected-run', '--no-deps']).status, 0);
  writeFileSync(join(workOf(checkout, 'protected-run'), '.muse/mode'), 'protected');
  // A second round in the same copy, with the stand-in told to tamper with the rules.
  assert.equal(muse(checkout, ['run', 'brief.md', '--continue', 'protected-run']).status, 0);
  const refused = muse(checkout, ['accept', 'protected-run']);
  assert.equal(refused.status, 3, refused.out);
  assert.match(refused.out, /PROTECTED M AGENTS\.md/);
  assert.equal(readFileSync(join(checkout.root, 'AGENTS.md'), 'utf8'), '# rules\n');
  const allowed = muse(checkout, ['accept', 'protected-run', '--allow', 'AGENTS.md']);
  assert.equal(allowed.status, 0, allowed.out);
  assert.match(readFileSync(join(checkout.root, 'AGENTS.md'), 'utf8'), /tampered/);
});

test('a failed round is recorded as failed and cannot be accepted', (t) => {
  const checkout = makeCheckout(t);
  assert.equal(muse(checkout, ['run', 'brief.md', '--tag', 'ok-run', '--no-deps']).status, 0);
  writeFileSync(join(workOf(checkout, 'ok-run'), '.muse/mode'), 'fail');
  rmSync(join(workOf(checkout, 'ok-run'), '.muse/launches.log'), { force: true });
  const failed = muse(checkout, ['run', 'brief.md', '--continue', 'ok-run']);
  assert.equal(failed.status, 1);
  assert.doesNotMatch(failed.out, /would not take the old session again/);
  assert.equal(launchesIn(checkout, 'ok-run').length, 1, 'an unknown failure stops after one launch');
  const state = JSON.parse(readFileSync(join(checkout.root, 'builds/muse/ok-run/state.json'), 'utf8'));
  assert.equal(state.rounds.at(-1).state, 'failed');
  assert.equal(state.rounds.at(-1).exitCode, 7);
  assert.equal(state.rounds.at(-1).sessionRetried, undefined);
  assert.ok(!existsSync(join(checkout.root, 'builds/muse/ok-run/report-2.md')), 'no successful report for a failed round');
  const refused = muse(checkout, ['accept', 'ok-run']);
  assert.notEqual(refused.status, 0);
  assert.match(refused.out, /only a finished run is accepted/);
});

test('a real tree that moved on since the copy refuses the patch', (t) => {
  const checkout = makeCheckout(t);
  assert.equal(muse(checkout, ['run', 'brief.md', '--tag', 'stale-run', '--no-deps']).status, 0);
  writeFileSync(join(checkout.root, 'apps/game/scripts/player.gd'), 'extends Node2D\n# somebody else\n');
  const refused = muse(checkout, ['accept', 'stale-run']);
  assert.equal(refused.status, 4, refused.out);
});

test('discard deletes only the run, and a dry run starts nothing', (t) => {
  const checkout = makeCheckout(t);
  const dry = muse(checkout, ['run', 'brief.md', '--tag', 'dry', '--dry-run']);
  assert.equal(dry.status, 0, dry.out);
  assert.match(dry.out, /--approval-mode on-request/);
  assert.match(dry.out, /--sandbox-network restricted/);
  assert.ok(!existsSync(join(checkout.root, 'builds/muse/dry')), 'a dry run copies nothing');

  assert.equal(muse(checkout, ['run', 'brief.md', '--tag', 'gone', '--no-deps']).status, 0);
  assert.equal(muse(checkout, ['discard', 'gone']).status, 0);
  assert.ok(!existsSync(join(checkout.root, 'builds/muse/gone')));
  assert.ok(existsSync(join(checkout.root, 'apps/game/scripts/player.gd')), 'the real tree is untouched');
  assert.notEqual(muse(checkout, ['status', 'gone']).status, 0);
});

test('a missing CLI is reported before anything is copied', (t) => {
  const checkout = makeCheckout(t);
  rmSync(join(checkout.bin, 'fakemuse'));
  const result = muse(checkout, ['run', 'brief.md', '--tag', 'no-cli', '--no-deps']);
  assert.notEqual(result.status, 0);
  assert.match(result.out, /is not on PATH/);
  assert.ok(!existsSync(join(checkout.root, 'builds/muse/no-cli')));
});

test('a continuation whose old session the CLI refuses gets a fresh session in the same copy', (t) => {
  const checkout = makeCheckout(t);
  assert.equal(muse(checkout, ['run', 'brief.md', '--tag', 'retry-run', '--no-deps']).status, 0);
  writeFileSync(join(workOf(checkout, 'retry-run'), '.muse/mode'), 'reject-session');
  rmSync(join(workOf(checkout, 'retry-run'), '.muse/launches.log'), { force: true });
  const second = muse(checkout, ['run', 'brief.md', '--continue', 'retry-run']);
  assert.equal(second.status, 0, second.out);
  assert.match(second.out, /would not take the old session again/);
  const launches = launchesIn(checkout, 'retry-run');
  assert.equal(launches.length, 2, 'the stale session is tried once, then once fresh');
  assert.ok(!launches[0].endsWith('none'), 'the first launch carries the old session id');
  assert.ok(launches[1].endsWith('none'), 'the retry carries no session id');
  const state = JSON.parse(readFileSync(join(checkout.root, 'builds/muse/retry-run/state.json'), 'utf8'));
  assert.equal(state.rounds.length, 2);
  assert.equal(state.rounds[1].state, 'done');
  assert.equal(state.rounds[1].sessionRetried, true);
  assert.equal(state.rounds[0].sessionRetried, undefined);
});

test('an approval/classifier refusal stops after one launch and is never accepted', (t) => {
  const checkout = makeCheckout(t);
  assert.equal(muse(checkout, ['run', 'brief.md', '--tag', 'refusal-run', '--no-deps']).status, 0);
  // The stand-in fails only when it gets a session id; without one it would write a report and succeed, so any
  // fallback without the id would turn this failure into a success and the test would catch it.
  writeFileSync(join(workOf(checkout, 'refusal-run'), '.muse/mode'), 'refuse-launch');
  rmSync(join(workOf(checkout, 'refusal-run'), '.muse/launches.log'), { force: true });
  const second = muse(checkout, ['run', 'brief.md', '--continue', 'refusal-run']);
  assert.equal(second.status, 1, second.out);
  assert.doesNotMatch(second.out, /would not take the old session again/);
  const launches = launchesIn(checkout, 'refusal-run');
  assert.equal(launches.length, 1, 'a refusal is launched exactly once');
  assert.ok(!launches[0].endsWith('none'), 'the one launch carries the old session id');
  const errors = readFileSync(join(checkout.root, 'builds/muse/refusal-run/stderr-2.log'), 'utf8');
  assert.match(errors, /classifier refused session start/);
  assert.ok(errors.includes('session') && !errors.includes('session already exists'),
    'the refusal names a session but is not the recognized stale-session error');
  const state = JSON.parse(readFileSync(join(checkout.root, 'builds/muse/refusal-run/state.json'), 'utf8'));
  assert.equal(state.rounds.length, 2);
  assert.equal(state.rounds[1].state, 'failed');
  assert.equal(state.rounds[1].exitCode, 5);
  assert.equal(state.rounds[1].sessionRetried, undefined);
  assert.ok(!existsSync(join(workOf(checkout, 'refusal-run'), 'IMPLEMENTER_REPORT.md')), 'no report in the copy');
  assert.ok(!existsSync(join(checkout.root, 'builds/muse/refusal-run/report-2.md')), 'no successful report stored');
  const refused = muse(checkout, ['accept', 'refusal-run']);
  assert.notEqual(refused.status, 0);
  assert.match(refused.out, /only a finished run is accepted/);
});
