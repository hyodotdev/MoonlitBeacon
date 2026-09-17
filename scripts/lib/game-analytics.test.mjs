import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  buildReport,
  parseArgs,
  parseEventText,
  renderMarkdown,
} from '../analyze-game-analytics.mjs';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const arenaSource = readFileSync(
  resolve(repository, 'apps/game/scripts/gameplay/arena.gd'), 'utf8',
);

function event(name, {
  day = '2026-08-26',
  at = '',
  sessionId = '',
  runId = '',
  properties = {},
} = {}) {
  return {
    event: name,
    clientDay: day,
    clientAt: at || `${day}T00:00:00Z`,
    sessionId,
    runId,
    appVersion: '2.1.0',
    platform: 'ios',
    locale: 'ko',
    properties,
  };
}

function fixtureEvents() {
  const cohort = { cohort_version: '2.1.0', cohort_day: '2026-08-26' };
  return [
    event('analytics_activated', { sessionId: 'activation-1', properties: cohort }),
    event('analytics_activated', { sessionId: 'activation-2', properties: cohort }),
    event('analytics_activated', { sessionId: 'activation-3', properties: cohort }),
    event('retention_checkpoint', {
      day: '2026-08-27',
      sessionId: 'return-1',
      properties: { ...cohort, day: 1 },
    }),
    event('retention_checkpoint', {
      day: '2026-08-27',
      sessionId: 'return-2',
      properties: { ...cohort, day: 1 },
    }),
    event('retention_checkpoint', {
      day: '2026-09-02',
      sessionId: 'return-3',
      properties: { ...cohort, day: 7 },
    }),
    event('app_opened', { sessionId: 'session-secret-1' }),
    event('app_opened', { sessionId: 'session-secret-2' }),
    event('app_opened', { sessionId: 'session-secret-3' }),
    event('run_started', { sessionId: 'session-secret-1', runId: 'run-secret-1' }),
    event('run_started', { sessionId: 'session-secret-2', runId: 'run-secret-2' }),
    event('run_started', { sessionId: 'session-secret-3', runId: 'run-secret-3' }),
    event('relic_chosen', {
      runId: 'run-secret-1',
      properties: {
        relic: 'moon_ring', family: 'moon_dance', stack: 1, elapsed_ms: 60000,
      },
    }),
    event('relic_chosen', {
      runId: 'run-secret-1',
      properties: {
        relic: 'moon_ring', family: 'moon_dance', stack: 2, elapsed_ms: 75000,
      },
    }),
    event('relic_chosen', {
      runId: 'run-secret-1',
      properties: {
        relic: 'moon_ripple', family: 'moon_dance', stack: 3, elapsed_ms: 90000,
      },
    }),
    event('evolution_unlocked', {
      runId: 'run-secret-1',
      properties: { family: 'moon_dance', elapsed_ms: 100000 },
    }),
    event('beacon_choice', {
      runId: 'run-secret-1',
      properties: {
        beacon: 1, terrain: 'forest', mode: 'overcharge', elapsed_ms: 110000,
      },
    }),
    event('beacon_choice', {
      runId: 'run-secret-2',
      properties: {
        beacon: 1, terrain: 'forest', mode: 'normal', elapsed_ms: 170000,
      },
    }),
    event('beacon_choice', {
      runId: 'run-secret-3',
      properties: {
        beacon: 1, terrain: 'camp', mode: 'overcharge', elapsed_ms: 90000,
      },
    }),
    event('beacon_lit', {
      runId: 'run-secret-1',
      properties: { beacon: 1, mode: 'overcharge', elapsed_ms: 120000 },
    }),
    event('beacon_lit', {
      runId: 'run-secret-2',
      properties: { beacon: 1, mode: 'normal', elapsed_ms: 180000 },
    }),
    event('overcharge_resolved', {
      runId: 'run-secret-1',
      properties: { outcome: 'success', terrain: 'forest' },
    }),
    event('overcharge_resolved', {
      runId: 'run-secret-3',
      properties: { outcome: 'defeat', terrain: 'camp' },
    }),
    event('gate_crossed', { runId: 'run-secret-1' }),
    event('guardian_started', { runId: 'run-secret-1' }),
    event('guardian_defeated', { runId: 'run-secret-1' }),
    event('cycle_decision', {
      runId: 'run-secret-1',
      properties: { choice: 'continue' },
    }),
    event('cycle_decision', {
      runId: 'run-secret-1',
      properties: { choice: 'cashout' },
    }),
    event('run_ended', {
      runId: 'run-secret-1',
      properties: { reason: 'cashout', duration_ms: 600000 },
    }),
    event('run_ended', {
      runId: 'run-secret-2',
      properties: { reason: 'title', duration_ms: 300000 },
    }),
    event('run_ended', {
      runId: 'run-secret-3',
      properties: { reason: 'defeat', duration_ms: 120000 },
    }),
  ];
}

test('reads Firestore JSON and JSONL typed values as the same events', () => {
  const document = {
    name: 'projects/test/databases/(default)/documents/analytics_events_v1/e_hidden',
    fields: {
      event: { stringValue: 'beacon_lit' },
      client_day: { stringValue: '2026-08-26' },
      client_at: { timestampValue: '2026-08-26T00:00:00Z' },
      session_id: { stringValue: 'ephemeral-session' },
      run_id: { stringValue: 'ephemeral-run' },
      app_version: { stringValue: '2.1.0' },
      platform: { stringValue: 'ios' },
      locale: { stringValue: 'ko' },
      properties: {
        mapValue: {
          fields: {
            beacon: { integerValue: '2' },
            mode: { stringValue: 'overcharge' },
          },
        },
      },
    },
  };
  const fromJson = parseEventText(JSON.stringify({ documents: [document] }));
  const fromJsonl = parseEventText(`${JSON.stringify(document)}\n${JSON.stringify(document)}\n`);
  assert.equal(fromJson.length, 1);
  assert.equal(fromJson[0].properties.beacon, 2);
  assert.equal(fromJson[0].properties.mode, 'overcharge');
  assert.equal(fromJsonl.length, 2);
});

test('run analysis includes starting gear in resonance but not as a tutorial pick', () => {
  const begin = arenaSource.indexOf('\t_analytics_begin_run()');
  const boons = arenaSource.indexOf('\t_apply_boons()', begin);
  assert.ok(begin >= 0 && boons > begin,
    'must apply hero starting gear after run_started');
  assert.match(arenaSource, /_on_relic_picked\(_relic\.take_named\(path\), false, "opening"\)/u);
  assert.match(arenaSource, /if source != "opening":\s+_analytics_tutorial_step\("relic"\)/u);
  const rules = readFileSync(resolve(repository, 'firestore.rules'), 'utf8');
  assert.match(rules, /p\.source in \['opening', 'level', 'beacon', 'guardian'\]/u);
});

test('starting gear counts only toward resonance, not first-relic funnel or timing', () => {
  const report = buildReport([
    event('run_started', { sessionId: 'opening-session', runId: 'opening-run' }),
    event('relic_chosen', {
      runId: 'opening-run',
      properties: {
        relic: 'moon_ring', family: 'moon_dance', source: 'opening', elapsed_ms: 0,
      },
    }),
    event('run_ended', {
      runId: 'opening-run', properties: { reason: 'defeat', duration_ms: 60000 },
    }),
  ], { to: '2026-08-26', minCohort: 1 });
  assert.equal(report.runFunnel.find(({ event: name }) => name === 'relic_chosen').count, 0);
  assert.equal(report.fun.medianFirstRelicMinutes, null);
  assert.equal(
    report.relicResonance.find(({ family }) => family === 'moon_dance').selectedRuns,
    1,
  );
});

test('aggregates play funnel, overcharge, and difficulty on unique runs', () => {
  const report = buildReport(fixtureEvents(), { to: '2026-09-02', minCohort: 3 });
  assert.deepEqual(report.activation, {
    openedSessions: 3,
    startedSessions: 3,
    rate: 100,
  });
  assert.deepEqual(
    report.runFunnel.map(({ count }) => count),
    [3, 1, 2, 1, 1, 1, 3],
  );
  assert.equal(report.overcharge.choices, 3);
  assert.equal(report.overcharge.beaconsLit, 2);
  assert.equal(report.overcharge.selected, 2);
  assert.equal(report.overcharge.selectionRate.toFixed(1), '66.7');
  assert.equal(report.overcharge.resolutionRate, 100);
  assert.equal(report.overcharge.successRate, 50);
  assert.equal(report.overcharge.outcomes.defeat, 1);
  assert.deepEqual(
    report.overcharge.byTerrain.map(({ terrain, choices, selected, resolved }) => ({
      terrain, choices, selected, resolved,
    })),
    [
      { terrain: 'forest', choices: 2, selected: 1, resolved: 1 },
      { terrain: 'field', choices: 0, selected: 0, resolved: 0 },
      { terrain: 'camp', choices: 1, selected: 1, resolved: 1 },
    ],
  );
  assert.equal(report.cycleDecision.total, 2);
  assert.equal(report.cycleDecision.continueRate, 50);
  assert.deepEqual(report.relicResonance.find(({ family }) => family === 'moon_dance'), {
    family: 'moon_dance',
    label: 'Moon Dance',
    selectedRuns: 1,
    resonantRuns: 1,
    resonanceRate: 100,
    evolvedRuns: 1,
    evolutionRate: 100,
    evolutionFromResonanceRate: 100,
    selectedSufficient: false,
    resonantSufficient: false,
  });
  assert.equal(report.fun.medianRunMinutes, 5);
  assert.equal(report.fun.p90RunMinutes, 10);
  assert.equal(report.fun.medianFirstRelicMinutes, 1);
  assert.equal(report.fun.medianFirstBeaconMinutes, 2.5);
  assert.equal(report.fun.guardianClearRate, 100);
  assert.equal(report.fun.earlyDefeats, 1);
  assert.equal(report.fun.earlyDefeatRate, 100);
  assert.equal(report.fun.cashoutRuns, 1);
  assert.equal(report.fun.cashoutRate.toFixed(1), '33.3');
});

test('picking the same relic several times does not count as two-kind resonance', () => {
  const report = buildReport([
    event('run_started', { runId: 'repeat-run' }),
    event('relic_chosen', {
      runId: 'repeat-run',
      properties: { family: 'starfall', relic: 'quick_arrow', stack: 1 },
    }),
    event('relic_chosen', {
      runId: 'repeat-run',
      properties: { family: 'starfall', relic: 'quick_arrow', stack: 2 },
    }),
    event('evolution_unlocked', {
      runId: 'repeat-run',
      properties: { family: 'starfall' },
    }),
  ], { to: '2026-08-26' });
  const starfall = report.relicResonance.find(({ family }) => family === 'starfall');
  assert.equal(starfall.selectedRuns, 1);
  assert.equal(starfall.resonantRuns, 0);
  assert.equal(starfall.resonanceRate, 0);
  assert.equal(starfall.evolvedRuns, 0);
  assert.equal(starfall.evolutionRate, 0);
  assert.equal(starfall.evolutionFromResonanceRate, null);
  assert.equal(starfall.selectedSufficient, false);
  assert.equal(starfall.resonantSufficient, false);
});

test('retention shows insufficient sample instead of a percent below min cohort', () => {
  const sufficient = buildReport(fixtureEvents(), {
    to: '2026-09-02', minCohort: 3,
  });
  assert.equal(sufficient.retention[0].size, 3);
  assert.equal(sufficient.retention[0].d1, 2);
  assert.equal(sufficient.retention[0].d7, 1);
  assert.deepEqual(sufficient.retention[0].eligible, { d1: 3, d7: 3, d30: 0 });
  assert.deepEqual(sufficient.retention[0].sufficient, {
    d1: true, d7: true, d30: false,
  });
  assert.match(renderMarkdown(sufficient), /2\/3 \(66\.7%\)/u);

  const insufficient = buildReport(fixtureEvents(), {
    to: '2026-09-02', minCohort: 4,
  });
  assert.equal(insufficient.retention[0].sufficient.d1, false);
  assert.match(renderMarkdown(insufficient), /n<4/u);
});

test('accumulates retention through observation end regardless of the date filter', () => {
  const report = buildReport(fixtureEvents(), {
    from: '2026-08-27',
    to: '2026-09-02',
    minCohort: 3,
  });
  assert.equal(report.retention.length, 1);
  assert.equal(report.retention[0].size, 3);
  assert.equal(report.retention[0].d1, 2);
  assert.equal(report.retention[0].d7, 1);
  assert.equal(report.retention[0].sufficient.d1, true);
  assert.equal(report.retention[0].sufficient.d7, true);
  assert.deepEqual(report.retentionWindow, {
    from: '2026-08-27',
    to: '2026-09-02',
    filtered: true,
    observationEnd: '2026-09-02',
    definition: 'utc_calendar_day_exact_return',
    activationDenominator: 'eligible_by_day_through_observation_end',
    checkpointNumerator: 'all_input_through_observation_end',
    completeCohortsBeforeTtlDays: 90,
  });
  assert.match(
    renderMarkdown(report),
    /accumulates from the input source start through --to observation end/u,
  );

  const d7Only = buildReport(fixtureEvents(), {
    from: '2026-09-02',
    to: '2026-09-02',
    minCohort: 3,
  });
  assert.equal(d7Only.retention[0].size, 3);
  assert.equal(d7Only.retention[0].d1, 2);
  assert.equal(d7Only.retention[0].d7, 1);
});

test('mobile resume app open does not inflate the cold-launch start-conversion denominator', () => {
  const report = buildReport([
    event('app_opened', {
      sessionId: 'cold-session', properties: { open_kind: 'cold' },
    }),
    event('run_started', { sessionId: 'cold-session', runId: 'active-run' }),
    event('app_opened', {
      sessionId: 'resume-session', properties: { open_kind: 'resume' },
    }),
  ], { to: '2026-08-26', minCohort: 1 });
  assert.equal(report.activation.openedSessions, 1);
  assert.equal(report.activation.startedSessions, 1);
  assert.equal(report.activation.rate, 100);
});

test('excludes new consents that have not yet reached the date from long-term retention denominators', () => {
  const events = [];
  for (let index = 0; index < 10; index += 1) {
    events.push(event('analytics_activated', {
      day: '2026-07-27',
      sessionId: `old-${index}`,
      properties: { cohort_version: '2.1.0', cohort_day: '2026-07-27' },
    }));
  }
  for (let index = 0; index < 90; index += 1) {
    events.push(event('analytics_activated', {
      day: '2026-08-26',
      sessionId: `new-${index}`,
      properties: { cohort_version: '2.1.0', cohort_day: '2026-08-26' },
    }));
  }
  for (let index = 0; index < 5; index += 1) {
    events.push(event('retention_checkpoint', {
      day: '2026-08-26',
      sessionId: `return-${index}`,
      properties: {
        cohort_version: '2.1.0', cohort_day: '2026-07-27', day: 30,
      },
    }));
  }
  const report = buildReport(events, { to: '2026-08-26', minCohort: 10 });
  const cohort = report.retention.find(({ version }) => version === '2.1.0');
  assert.ok(cohort);
  assert.equal(cohort.size, 100);
  assert.equal(cohort.eligible.d30, 10);
  assert.equal(cohort.d30, 5);
  assert.equal(cohort.sufficient.d30, true);
  assert.match(renderMarkdown(report), /5\/10 \(50\.0%\)/u);
});

test('computes D1 as the next UTC calendar-day return, not a 24-hour elapsed window', () => {
  const report = buildReport([
    event('analytics_activated', {
      day: '2026-08-26',
      at: '2026-08-26T23:59:00Z',
      sessionId: 'late-activation',
      properties: { cohort_version: '2.1.0', cohort_day: '2026-08-26' },
    }),
    event('app_opened', {
      day: '2026-08-27',
      at: '2026-08-27T00:01:00Z',
      sessionId: 'early-observation',
    }),
  ], { to: '2026-08-27', minCohort: 1 });
  assert.equal(report.retention[0].size, 1);
  assert.equal(report.retention[0].eligible.d1, 1);
  assert.equal(report.retention[0].sufficient.d1, true);
});

test('counts a retention checkpoint in the numerator only on the declared exact UTC calendar date', () => {
  const activation = event('analytics_activated', {
    day: '2026-08-01',
    properties: { cohort_version: '2.1.0', cohort_day: '2026-08-01' },
  });
  const lateD1 = event('retention_checkpoint', {
    day: '2026-08-08',
    properties: { cohort_version: '2.1.0', cohort_day: '2026-08-01', day: 1 },
  });
  const report = buildReport([activation, lateD1], {
    to: '2026-08-08', minCohort: 1,
  });
  assert.equal(report.retention[0].eligible.d1, 1);
  assert.equal(report.retention[0].d1, 0);
});

test('does not attach old checkpoints whose activation was TTL-deleted to a new cohort', () => {
  const report = buildReport([
    event('retention_checkpoint', {
      day: '2026-08-31',
      properties: {
        cohort_version: '2.1.0', cohort_day: '2026-08-01', day: 30,
      },
    }),
    event('analytics_activated', {
      day: '2026-10-01',
      properties: { cohort_version: '2.1.0', cohort_day: '2026-10-01' },
    }),
  ], { to: '2026-11-10', minCohort: 1 });
  assert.equal(report.retention.length, 1);
  assert.equal(report.retention[0].version, '2.1.0');
  assert.equal(report.retention[0].eligible.d30, 1);
  assert.equal(report.retention[0].d30, 0);
});

test('drops a same-date cohort that is only partly left at the TTL boundary', () => {
  const events = [];
  for (let index = 0; index < 20; index += 1) {
    events.push(event('analytics_activated', {
      day: '2026-08-01',
      properties: { cohort_version: '2.1.0', cohort_day: '2026-08-01' },
    }));
  }
  for (let index = 0; index < 100; index += 1) {
    events.push(event('retention_checkpoint', {
      day: '2026-08-31',
      properties: {
        cohort_version: '2.1.0', cohort_day: '2026-08-01', day: 30,
      },
    }));
  }
  for (let index = 0; index < 10; index += 1) {
    events.push(event('analytics_activated', {
      day: '2026-10-01',
      properties: { cohort_version: '2.1.0', cohort_day: '2026-10-01' },
    }));
  }
  const report = buildReport(events, { to: '2026-11-10', minCohort: 1 });
  assert.equal(report.retention.length, 1);
  assert.equal(report.retention[0].size, 10);
  assert.equal(report.retention[0].eligible.d30, 10);
  assert.equal(report.retention[0].d30, 0);
  assert.match(renderMarkdown(report), /90-day boundary/u);
});

test('merges small daily cohorts into the same version baseline to make a sufficient sample', () => {
  const events = [];
  for (let day = 1; day <= 10; day += 1) {
    const activationDay = `2026-08-${String(day).padStart(2, '0')}`;
    const returnDay = `2026-08-${String(day + 1).padStart(2, '0')}`;
    for (let index = 0; index < 5; index += 1) {
      events.push(event('analytics_activated', {
        day: activationDay,
        sessionId: `activation-${day}-${index}`,
        properties: { cohort_version: '2.1.0', cohort_day: activationDay },
      }));
      events.push(event('retention_checkpoint', {
        day: returnDay,
        sessionId: `return-${day}-${index}`,
        properties: {
          cohort_version: '2.1.0', cohort_day: activationDay, day: 1,
        },
      }));
    }
  }
  const report = buildReport(events, { to: '2026-08-11', minCohort: 20 });
  assert.equal(report.retention.length, 1);
  assert.equal(report.retention[0].size, 50);
  assert.equal(report.retention[0].eligible.d1, 50);
  assert.equal(report.retention[0].d1, 50);
  assert.equal(report.retention[0].sufficient.d1, true);
  assert.match(renderMarkdown(report), /50\/50 \(100\.0%\)/u);
});

test('biome and resonance tables hide rates below the min sample', () => {
  const report = buildReport(fixtureEvents(), {
    to: '2026-09-02', minCohort: 3,
  });
  const markdown = renderMarkdown(report);
  assert.match(markdown, /Overcharge by biome/u);
  assert.match(markdown, /\| Forest \| 2 \| 1 \| — \(n<3\)/u);
  assert.match(markdown, /\| Moon Dance \| 1 \| 1 \| — \(n<3\)/u);
});

test('does not expose session or run identifiers in the Markdown report', () => {
  const markdown = renderMarkdown(buildReport(fixtureEvents(), {
    to: '2026-09-02', minCohort: 1,
  }));
  assert.doesNotMatch(markdown, /session-secret/u);
  assert.doesNotMatch(markdown, /run-secret/u);
  assert.match(markdown, /Overcharge/u);
  assert.match(markdown, /Relic resonance/u);
  assert.match(markdown, /\| Moon Dance \| 1 \| 1 \| 100\.0%/u);
  assert.match(markdown, /Defeats before first beacon/u);
});

test('validates date and min-sample arguments', () => {
  assert.deepEqual(parseArgs([
    '--file', 'events.jsonl', '--from', '2026-08-01', '--to', '2026-08-31',
    '--version', '2.1.0', '--min-cohort', '30',
  ]), {
    file: 'events.jsonl',
    from: '2026-08-01',
    to: '2026-08-31',
    version: '2.1.0',
    minCohort: 30,
    help: false,
  });
  assert.equal(parseArgs([
    '--', '--file', 'events.jsonl', '--to', '2026-08-31',
  ]).file, 'events.jsonl');
  assert.throws(() => parseArgs(['events.json', '--min-cohort', '0']), /integer >= 1/u);
  assert.throws(() => parseArgs([
    'events.json', '--min-cohort', '20x',
  ]), /integer >= 1/u);
  assert.throws(() => parseArgs([
    'events.json', '--min-cohort', '1.5',
  ]), /integer >= 1/u);
  assert.throws(() => parseArgs(['events.json', '--from', '2026/08/01']), /YYYY-MM-DD/u);
  assert.throws(() => parseArgs([
    'events.json', '--to', '2026-02-30',
  ]), /real YYYY-MM-DD/u);
  assert.throws(() => parseArgs([
    'events.json', '--version', '../secret',
  ]), /safe app version/u);
  assert.throws(
    () => buildReport(fixtureEvents(), { minCohort: 1 }),
    /observation end/u,
  );
});

test('date filters aggregate a whole run that crosses midnight by run-start date', () => {
  const rows = [
    event('run_started', {
      day: '2026-08-26', sessionId: 'overnight-session', runId: 'overnight-run',
    }),
    event('beacon_choice', {
      day: '2026-08-26', runId: 'overnight-run',
      properties: { terrain: 'forest', mode: 'overcharge' },
    }),
    event('overcharge_resolved', {
      day: '2026-08-27', runId: 'overnight-run',
      properties: { terrain: 'forest', outcome: 'success' },
    }),
    event('run_ended', {
      day: '2026-08-27', runId: 'overnight-run',
      properties: { reason: 'cashout', duration_ms: 600000 },
    }),
  ];
  const included = buildReport(rows, {
    from: '2026-08-26', to: '2026-08-26', version: '2.1.0', minCohort: 1,
  });
  assert.equal(included.overcharge.selected, 1);
  assert.equal(included.overcharge.resolved, 1);
  assert.equal(included.fun.endedRuns, 1);
  const excluded = buildReport(rows, {
    from: '2026-08-27', to: '2026-08-27', version: '2.1.0', minCohort: 1,
  });
  assert.equal(excluded.overcharge.selected, 0);
  assert.equal(excluded.overcharge.resolved, 0);
  assert.equal(excluded.fun.endedRuns, 0);
});

test('does not mix app versions and computes the baseline only for an explicit version', () => {
  const oldRun = event('run_ended', {
    runId: 'old-run', properties: { reason: 'defeat', duration_ms: 60000 },
  });
  const oldStart = event('run_started', { runId: 'old-run' });
  const newStart = event('run_started', { runId: 'new-run' });
  const newRun = event('run_ended', {
    runId: 'new-run', properties: { reason: 'cashout', duration_ms: 600000 },
  });
  newStart.appVersion = '2.1.1';
  newRun.appVersion = '2.1.1';
  assert.throws(
    () => buildReport([oldStart, oldRun, newStart, newRun], { to: '2026-08-26' }),
    /Multiple app versions/u,
  );
  const report = buildReport([oldStart, oldRun, newStart, newRun], {
    to: '2026-08-26', version: '2.1.1', minCohort: 1,
  });
  assert.equal(report.appVersion, '2.1.1');
  assert.equal(report.fun.medianRunMinutes, 10);
  assert.equal(report.fun.cashoutRate, 100);
});

test('keeps a post-update return in the first-consent version retention cohort', () => {
  const activation = event('analytics_activated', {
    day: '2026-08-01',
    properties: { cohort_version: '2.1.0', cohort_day: '2026-08-01' },
  });
  const checkpoint = event('retention_checkpoint', {
    day: '2026-08-02',
    properties: { cohort_version: '2.1.0', cohort_day: '2026-08-01', day: 1 },
  });
  checkpoint.appVersion = '2.1.1';
  const currentOpen = event('app_opened', {
    day: '2026-08-02', sessionId: 'updated-session',
    properties: { open_kind: 'cold' },
  });
  currentOpen.appVersion = '2.1.1';

  assert.throws(
    () => buildReport([activation, checkpoint, currentOpen], { to: '2026-08-02' }),
    /Multiple app versions/u,
  );
  const report = buildReport([activation, checkpoint, currentOpen], {
    version: '2.1.0', to: '2026-08-02', minCohort: 1,
  });
  assert.equal(report.retention[0].eligible.d1, 1);
  assert.equal(report.retention[0].d1, 1);
});

test('Firebase deploy config includes private analytics collection rules', () => {
  const firebase = JSON.parse(readFileSync(resolve(repository, 'firebase.json'), 'utf8'));
  assert.equal(firebase.firestore?.rules, 'firestore.rules');
  const rules = readFileSync(resolve(repository, 'firestore.rules'), 'utf8');
  assert.match(rules, /match \/analytics_events_v1\/\{eventId\}/u);
  assert.match(rules, /allow read, update, delete: if false;/u);
  assert.match(rules, /data\.properties is map/u);
  assert.match(rules, /validProperties\(data\.event, data\.properties\)/u);
  assert.match(rules, /event == 'cycle_decision' && cycleDecisionProperties\(p\)/u);
  assert.match(rules, /event == 'beacon_choice' && beaconProperties\(p\)/u);
});
