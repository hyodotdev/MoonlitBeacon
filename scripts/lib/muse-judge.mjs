// The director's acceptance battery, run inside the implementer's copy of the repo. It only runs the same
// commands every brief names and keeps their output, so the director compares numbers it reproduced itself and
// not the numbers in a report. It decides nothing: the pass or fail of a criterion is the director's reading.

/** One step: what it runs (in the copy), how long it may take, and how to read its output. */
export const STEPS = {
  checks: {
    label: 'quick checks',
    commands: [
      ['pnpm', 'game:check'],
      ['pnpm', 'check:scripts'],
      ['pnpm', 'check:hygiene'],
      ['pnpm', 'check:locale'],
      ['pnpm', 'check:skills'],
    ],
    timeoutSeconds: 1200,
  },
  tests: {
    label: 'all game tests',
    commands: [['pnpm', 'test:game']],
    timeoutSeconds: 2700,
  },
  nat: {
    label: 'natural first loops (12 runs)',
    commands: [
      ['node', 'scripts/godot-run.mjs', '--timeout', '3300', 'res://tools/play_bot.tscn', '--', 'tag=judge_nat', 'runs=12', 'seed=5', 'speed=3', 'loops=1'],
    ],
    report: 'builds/play/judge_nat.json',
    timeoutSeconds: 3600,
  },
  gauntlet: {
    label: 'guardian gauntlet (18 fights)',
    commands: [
      ['node', 'scripts/godot-run.mjs', '--timeout', '3300', 'res://tools/play_bot.tscn', '--', 'tag=judge_gaunt', 'gauntlet=1', 'guardians=0,1,2,3,4,5', 'starts=2,6,12', 'runs=18', 'seed=11', 'speed=3'],
    ],
    report: 'builds/play/judge_gaunt.json',
    timeoutSeconds: 3600,
  },
  perf: {
    label: 'late-game node budget',
    commands: [['node', 'scripts/godot-run.mjs', '--timeout', '600', 'res://tests/test_late_game_performance.tscn']],
    timeoutSeconds: 700,
  },
  store: {
    label: 'store screenshot fingerprint (red is expected after any change under apps/game)',
    commands: [['pnpm', 'check:store-screenshots']],
    timeoutSeconds: 600,
    expectFailure: true,
  },
};

/** The order they run in when none is named: cheap first, long batches last. */
export const DEFAULT_STEPS = ['checks', 'perf', 'tests', 'nat', 'gauntlet', 'store'];

export function parseSteps(text) {
  if (text === undefined || text === '') return DEFAULT_STEPS;
  const names = text.split(',').map((name) => name.trim()).filter(Boolean);
  const unknown = names.filter((name) => !(name in STEPS));
  if (unknown.length > 0) throw new Error(`unknown step(s): ${unknown.join(', ')} (known: ${Object.keys(STEPS).join(', ')})`);
  return names;
}

const FAILURE_LINE = /(^|\s)(FAIL|ERROR|Traceback|not ok)\b/;

/** What to say about a step's output without reading all of it: how many lines look like failures, and the last few lines. */
export function summarizeOutput(output, tailLines = 6) {
  const lines = output.split('\n');
  const failures = lines.filter((line) => FAILURE_LINE.test(line));
  return {
    failureLines: failures.length,
    firstFailures: failures.slice(0, 5),
    tail: lines.filter((line) => line.trim() !== '').slice(-tailLines),
  };
}
