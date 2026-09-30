import assert from 'node:assert/strict';
import test from 'node:test';

import {
  FORBIDDEN_FLAGS,
  buildExecArguments,
  childEnvironment,
  composePrompt,
  isValidTag,
  makeTag,
  summarizeEvent,
} from './muse-run.mjs';

const config = { model: 'muse-spark-9.9-test', reasoningEffort: 'max' };
const build = (extra = {}) => buildExecArguments({ config, promptFile: 'p.md', workspace: '/work', ...extra });
const valueAfter = (args, flag) => args[args.indexOf(flag) + 1];

test('a run always gets approvals, the sandbox without network, no web tools and no personal rules', () => {
  const args = build();
  assert.equal(args[0], 'exec');
  assert.equal(valueAfter(args, '--approval-mode'), 'on-request');
  assert.equal(valueAfter(args, '--approval-judge'), 'on');
  assert.equal(valueAfter(args, '--sandbox-network'), 'restricted');
  for (const flag of ['--disable-web-tools', '--no-foreign-personal-context', '--json']) {
    assert.ok(args.includes(flag), `missing ${flag}`);
  }
  assert.equal(valueAfter(args, '--workspace'), '/work');
  assert.equal(valueAfter(args, '--prompt-file'), 'p.md');
});

test('the model and effort are exactly what the config says', () => {
  const args = build();
  assert.equal(valueAfter(args, '--model'), config.model);
  assert.equal(valueAfter(args, '--reasoning-effort'), config.reasoningEffort);
  const other = buildExecArguments({ config: { model: 'muse-spark-8.8-test', reasoningEffort: 'low' }, promptFile: 'p', workspace: 'w' });
  assert.equal(valueAfter(other, '--model'), 'muse-spark-8.8-test');
  assert.equal(valueAfter(other, '--reasoning-effort'), 'low');
});

test('no combination of options can switch a safety setting off', () => {
  for (const extra of [{}, { trustWorkspace: true }, { sessionId: 'abc' }, { trustWorkspace: true, sessionId: 'abc' }]) {
    const args = build(extra);
    for (const flag of FORBIDDEN_FLAGS) assert.ok(!args.includes(flag), `${flag} present`);
    assert.notEqual(valueAfter(args, '--approval-mode'), 'never');
    assert.notEqual(valueAfter(args, '--sandbox-network'), 'enabled');
    assert.ok(!args.some((argument) => /yolo|disable-sandbox|disable-approval/.test(argument)));
  }
});

test('trusting the workspace and the session id are opt-in', () => {
  assert.ok(!build().includes('--trust-workspace'));
  assert.ok(build({ trustWorkspace: true }).includes('--trust-workspace'));
  assert.ok(!build().includes('--session-id'));
  assert.equal(valueAfter(build({ sessionId: 'abc' }), '--session-id'), 'abc');
});

test('the environment carries no token, key or password of the director', () => {
  const environment = childEnvironment({
    PATH: '/bin', HOME: '/home/a', LANG: 'en_US.UTF-8', TERM: 'xterm',
    GH_TOKEN: 'x', GITHUB_TOKEN: 'x', ANTHROPIC_API_KEY: 'x', AWS_SECRET_ACCESS_KEY: 'x',
    MOONLIT_KEYSTORE_PASSWORD: 'x', IAPKIT_API_KEY: 'x', OPENAI_API_KEY: 'x',
    MUSE_CHANNEL: 'stable', MUSE_AUTH_TOKEN: 'x',
  });
  assert.deepEqual(Object.keys(environment).sort(), ['HOME', 'LANG', 'MUSE_CHANNEL', 'PATH', 'TERM']);
  assert.equal(environment.TERM, 'dumb');
  assert.equal(environment.MUSE_CHANNEL, 'stable');
});

test('the prompt puts the facts, then the standing orders, then the brief', () => {
  const prompt = composePrompt({ standingOrders: 'ORDERS\n', brief: 'BRIEF\n', tag: 't-1', round: 2 });
  assert.ok(prompt.indexOf('ORDERS') < prompt.indexOf('BRIEF'));
  assert.ok(prompt.indexOf('Facts of this round') < prompt.indexOf('ORDERS'));
  assert.match(prompt, /round 2/);
});

test('the round says when it is cut off, so the implementer can pace itself', () => {
  const startedAt = new Date('2026-09-30T01:00:00.000Z');
  const prompt = composePrompt({
    standingOrders: 'O', brief: 'B', tag: 't', round: 1, timeoutMinutes: 300, startedAt, baseline: 'abcdef0123456789',
  });
  assert.match(prompt, /cut off after 300 minutes/);
  assert.match(prompt, /ends at 2026-09-30T06:00:00\.000Z/);
  assert.match(prompt, /abcdef012345/);
  assert.doesNotMatch(composePrompt({ standingOrders: 'O', brief: 'B', tag: 't', round: 1 }), /cut off after/);
});

test('a tag is a lowercase slug of the brief name and the time', () => {
  const tag = makeTag('notes/workflow/muse/briefs/003-Bullet Fields & More!.md', new Date(2026, 8, 30, 9, 5));
  assert.equal(tag, '20260930-0905-bullet-fields-more');
  assert.ok(isValidTag(tag));
  for (const bad of ['', 'A-b', '../x', 'a b', 'x'.repeat(90)]) assert.ok(!isValidTag(bad), bad);
});

test('an event line becomes one short line, or nothing', () => {
  assert.equal(summarizeEvent('{"type":"tool_call","payload":{"command":"pnpm test:game"}}'), 'tool_call: pnpm test:game');
  assert.equal(summarizeEvent('{"kind":"message","text":"  hello\\nworld "}'), 'message: hello world');
  assert.equal(summarizeEvent('not json'), 'not json');
  assert.equal(summarizeEvent(''), null);
  assert.equal(summarizeEvent('{}'), null);
});

test('the CLI\'s own events show what the implementer does, and its bookkeeping shows nothing', () => {
  const result = (text, extra = {}) => JSON.stringify({ payload_type: 'tool.result', payload: { text, ...extra } });
  const exec = (fields) => JSON.stringify(fields);
  assert.equal(summarizeEvent(result(exec({ command: 'pnpm test:game', description: 'Run all tests', exit_code: 0 }))),
    'run ok: Run all tests');
  assert.equal(summarizeEvent(result(exec({ command: 'false', exit_code: 3 }))), 'run exit 3: false');
  assert.equal(summarizeEvent(result(exec({ description: 'Long batch', exit_code: null }))), 'run started: Long batch');
  assert.equal(summarizeEvent(result('Read text file `/a/b/work/apps/game/x.gd`. 1|extends Node 2|...')), 'read apps/game/x.gd');
  assert.equal(summarizeEvent(result('wrote 18830 bytes to /a/b/work/apps/game/tests/t.gd')), 'write apps/game/tests/t.gd (18830 bytes)');
  assert.match(summarizeEvent(result('edited changed lines: line 54 --- original')), /^edit changed lines/);
  assert.equal(
    summarizeEvent(result('tool denied: approval aborted', { edit_facts: { path: '/a/b/work/.muse/report.md' } })),
    'DENIED: tool denied: approval aborted (.muse/report.md)',
  );
  for (const bookkeeping of ['task.lifecycle.started', 'task.stream.linked', 'runtime.command.accepted', 'session.run.linked']) {
    assert.equal(summarizeEvent(JSON.stringify({ payload_type: bookkeeping, payload: { text: 'x' } })), null, bookkeeping);
  }
});
