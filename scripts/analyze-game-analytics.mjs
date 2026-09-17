#!/usr/bin/env node

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/u;
const DEFAULT_MIN_COHORT = 20;
const DAY_MILLISECONDS = 24 * 60 * 60 * 1000;
const RETENTION_SERVER_TTL_DAYS = 90;
const RELIC_FAMILIES = [
  ['starfall', 'Starfall'],
  ['full_moon', 'Full Moon'],
  ['moon_dance', 'Moon Dance'],
];
const TERRAIN_SEGMENTS = [
  ['forest', 'Forest'],
  ['field', 'Field'],
  ['camp', 'Camp'],
];

function isValidDate(day) {
  if (!DATE_PATTERN.test(day)) return false;
  const unix = Date.parse(`${day}T00:00:00Z`);
  return Number.isFinite(unix)
    && new Date(unix).toISOString().slice(0, 10) === day;
}

export function parseArgs(argv) {
  const options = {
    file: '',
    from: '',
    to: '',
    version: '',
    minCohort: DEFAULT_MIN_COHORT,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--') {
      continue;
    } else if (argument === '--help' || argument === '-h') {
      options.help = true;
    } else if (argument === '--file' || argument === '-f') {
      options.file = argv[++index] ?? '';
    } else if (argument === '--from') {
      options.from = argv[++index] ?? '';
    } else if (argument === '--to') {
      options.to = argv[++index] ?? '';
    } else if (argument === '--version') {
      options.version = argv[++index] ?? '';
    } else if (argument === '--min-cohort') {
      const raw = argv[++index] ?? '';
      options.minCohort = /^\d+$/u.test(raw) ? Number(raw) : Number.NaN;
    } else if (!argument.startsWith('-') && !options.file) {
      options.file = argument;
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  if (!Number.isInteger(options.minCohort) || options.minCohort < 1) {
    throw new Error('--min-cohort must be an integer >= 1.');
  }
  for (const [name, value] of [['--from', options.from], ['--to', options.to]]) {
    if (value && !isValidDate(value)) {
      throw new Error(`${name} must be a real YYYY-MM-DD date.`);
    }
  }
  if (options.from && options.to && options.from > options.to) {
    throw new Error('--from cannot be later than --to.');
  }
  if (options.version && !/^[0-9A-Za-z][0-9A-Za-z._+-]{0,23}$/u.test(options.version)) {
    throw new Error('--version must be a safe app version of 24 characters or fewer.');
  }
  return options;
}

export function decodeFirestoreValue(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return value;
  if ('nullValue' in value) return null;
  if ('stringValue' in value) return String(value.stringValue);
  if ('integerValue' in value) return Number.parseInt(value.integerValue, 10);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('booleanValue' in value) return Boolean(value.booleanValue);
  if ('timestampValue' in value) return String(value.timestampValue);
  if ('mapValue' in value) return decodeFirestoreFields(value.mapValue?.fields ?? {});
  if ('arrayValue' in value) {
    return (value.arrayValue?.values ?? []).map(decodeFirestoreValue);
  }
  return value;
}

function decodeFirestoreFields(fields) {
  return Object.fromEntries(
    Object.entries(fields ?? {}).map(([key, value]) => [key, decodeFirestoreValue(value)]),
  );
}

function flattenInput(parsed) {
  if (Array.isArray(parsed)) return parsed.flatMap(flattenInput);
  if (!parsed || typeof parsed !== 'object') return [];
  if (Array.isArray(parsed.documents)) return parsed.documents.flatMap(flattenInput);
  if (Array.isArray(parsed.events)) return parsed.events.flatMap(flattenInput);
  if (parsed.document && typeof parsed.document === 'object') {
    return flattenInput(parsed.document);
  }
  return [parsed];
}

export function normalizeEvent(entry) {
  if (!entry || typeof entry !== 'object') return null;
  const decoded = entry.fields && typeof entry.fields === 'object'
    ? decodeFirestoreFields(entry.fields)
    : entry;
  const event = String(decoded.event ?? decoded.event_name ?? '');
  if (!event) return null;
  const clientAt = String(decoded.client_at ?? decoded.clientAt ?? '');
  const clientDay = String(decoded.client_day ?? decoded.clientDay
    ?? (clientAt ? clientAt.slice(0, 10) : ''));
  return {
    event,
    clientAt,
    clientDay,
    sessionId: String(decoded.session_id ?? decoded.sessionId ?? ''),
    runId: String(decoded.run_id ?? decoded.runId ?? ''),
    appVersion: String(decoded.app_version ?? decoded.appVersion ?? ''),
    platform: String(decoded.platform ?? ''),
    locale: String(decoded.locale ?? ''),
    properties: decoded.properties && typeof decoded.properties === 'object'
      ? decoded.properties
      : {},
  };
}

export function parseEventText(text) {
  const trimmed = text.trim();
  if (!trimmed) return [];
  let entries;
  try {
    entries = flattenInput(JSON.parse(trimmed));
  } catch {
    entries = trimmed.split(/\r?\n/u)
      .map((line) => line.trim())
      .filter(Boolean)
      .flatMap((line, index) => {
        try {
          return flattenInput(JSON.parse(line));
        } catch (error) {
          throw new Error(`Cannot read JSONL line ${index + 1}: ${error.message}`);
        }
      });
  }
  return entries.map(normalizeEvent).filter(Boolean);
}

export function readEvents(filePath) {
  return parseEventText(readFileSync(resolve(filePath), 'utf8'));
}

function unique(events, key) {
  return new Set(events.map(key).filter(Boolean));
}

function intersectionSize(left, right) {
  let count = 0;
  for (const value of left) if (right.has(value)) count += 1;
  return count;
}

function percentage(numerator, denominator) {
  return denominator > 0 ? (numerator / denominator) * 100 : null;
}

function median(values) {
  const numbers = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (numbers.length === 0) return null;
  const middle = Math.floor(numbers.length / 2);
  return numbers.length % 2 === 0
    ? (numbers[middle - 1] + numbers[middle]) / 2
    : numbers[middle];
}

function percentile(values, ratio) {
  const numbers = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (numbers.length === 0) return null;
  const index = Math.ceil(clamp(ratio, 0, 1) * numbers.length) - 1;
  return numbers[Math.max(index, 0)];
}

function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum);
}

function firstElapsedMinutes(events, allowedRuns) {
  const firstByRun = new Map();
  for (const event of events) {
    if (!event.runId || !allowedRuns.has(event.runId)) continue;
    const elapsed = Number(event.properties.elapsed_ms);
    if (!Number.isFinite(elapsed) || elapsed < 0) continue;
    const previous = firstByRun.get(event.runId);
    if (previous === undefined || elapsed < previous) firstByRun.set(event.runId, elapsed);
  }
  return [...firstByRun.values()].map((elapsed) => elapsed / 60000);
}

function inDateWindow(event, { from = '', to = '' } = {}) {
  return (!from || event.clientDay >= from) && (!to || event.clientDay <= to);
}

function eventVersion(event) {
  // Attribute return checkpoints to the first-consent version, not the current
  // app_version after an update, so updated users are not counted as churn from the old cohort.
  return String(event.properties.cohort_version || event.appVersion || '');
}

function resolveReportVersion(events, requested = '') {
  if (requested) return requested;
  const versions = [...new Set(events.map(eventVersion).filter(Boolean))].sort();
  if (versions.length > 1) {
    throw new Error(`Multiple app versions are mixed: ${versions.join(', ')}. Pass --version.`);
  }
  return versions[0] ?? '';
}

function filteredEvents(events, options = {}) {
  const versionRows = events.filter((event) => (
    !options.version || eventVersion(event) === options.version
  ));
  // The date window selects runs by run_started date instead of clipping individual events.
  // Overcharge and end events past midnight stay with the same run so numerator and denominator do not split.
  const selectedRuns = new Set(versionRows.filter((event) => (
    event.event === 'run_started' && event.runId && inDateWindow(event, options)
  )).map((event) => event.runId));
  return versionRows.filter((event) => (
    event.runId ? selectedRuns.has(event.runId) : inDateWindow(event, options)
  ));
}

function cohortVersion(event) {
  return event.properties.cohort_version || event.appVersion;
}

function cohortDay(event) {
  return event.event === 'analytics_activated'
    ? event.clientDay
    : String(event.properties.cohort_day ?? '');
}

function cohortKey(event) {
  const version = cohortVersion(event);
  const day = cohortDay(event);
  return version && isValidDate(day) ? `${version}|${day}` : '';
}

function isExactRetentionCheckpoint(event) {
  const checkpointDay = Number(event.properties.day);
  if (![1, 7, 30].includes(checkpointDay)) return false;
  const activatedAt = dayUnix(cohortDay(event));
  const returnedAt = dayUnix(event.clientDay);
  return Number.isFinite(activatedAt) && Number.isFinite(returnedAt)
    && returnedAt === activatedAt + checkpointDay * DAY_MILLISECONDS;
}

function dayUnix(day) {
  if (!DATE_PATTERN.test(day)) return Number.NaN;
  return Date.parse(`${day}T00:00:00Z`);
}

function eligibleByDay(activation, observationEnd, day) {
  // Use the same UTC client_day calendar-date definition as the runtime checkpoint. D1 is
  // the next calendar day after activation, so a gap shorter than 24 hours still qualifies for the denominator.
  const activatedAt = dayUnix(activation.clientDay);
  const observedAt = dayUnix(observationEnd);
  return Number.isFinite(activatedAt) && Number.isFinite(observedAt)
    && activatedAt + day * DAY_MILLISECONDS <= observedAt;
}

function cohortIsCompleteWithinTtl(event, observationEnd) {
  const activatedAt = dayUnix(cohortDay(event));
  const observedAt = dayUnix(observationEnd);
  return Number.isFinite(activatedAt) && Number.isFinite(observedAt)
    && observedAt < activatedAt + RETENTION_SERVER_TTL_DAYS * DAY_MILLISECONDS;
}

function outcomeCounts(events) {
  return Object.fromEntries(
    ['success', 'failed', 'abandoned', 'defeat'].map((outcome) => [
      outcome,
      events.filter((event) => event.properties.outcome === outcome).length,
    ]),
  );
}

function buildRelicResonance(relicChoices, evolutions, minCohort) {
  return RELIC_FAMILIES.map(([family, label]) => {
    const relicsByRun = new Map();
    for (const event of relicChoices) {
      if (!event.runId || event.properties.family !== family) continue;
      const relic = String(event.properties.relic ?? '');
      if (!relic) continue;
      if (!relicsByRun.has(event.runId)) relicsByRun.set(event.runId, new Set());
      relicsByRun.get(event.runId).add(relic);
    }

    const selectedRunIds = new Set(relicsByRun.keys());
    const resonantRunIds = new Set(
      [...relicsByRun.entries()]
        .filter(([, relics]) => relics.size >= 2)
        .map(([runId]) => runId),
    );
    const evolvedRunIds = unique(
      evolutions.filter((event) => (
        event.properties.family === family && resonantRunIds.has(event.runId)
      )),
      (event) => event.runId,
    );

    return {
      family,
      label,
      selectedRuns: selectedRunIds.size,
      resonantRuns: resonantRunIds.size,
      resonanceRate: percentage(resonantRunIds.size, selectedRunIds.size),
      evolvedRuns: evolvedRunIds.size,
      evolutionRate: percentage(evolvedRunIds.size, selectedRunIds.size),
      evolutionFromResonanceRate: percentage(evolvedRunIds.size, resonantRunIds.size),
      selectedSufficient: selectedRunIds.size >= minCohort,
      resonantSufficient: resonantRunIds.size >= minCohort,
    };
  });
}

function buildTerrainOvercharge(beaconChoices, overchargeResolutions, minCohort) {
  return TERRAIN_SEGMENTS.map(([terrain, label]) => {
    const choices = beaconChoices.filter((event) => event.properties.terrain === terrain);
    const selected = choices.filter((event) => event.properties.mode === 'overcharge');
    const resolutions = overchargeResolutions.filter(
      (event) => event.properties.terrain === terrain,
    );
    const outcomes = outcomeCounts(resolutions);
    return {
      terrain,
      label,
      choices: choices.length,
      selected: selected.length,
      resolved: resolutions.length,
      selectionRate: percentage(selected.length, choices.length),
      resolutionRate: percentage(resolutions.length, selected.length),
      successRate: percentage(outcomes.success, resolutions.length),
      selectionSufficient: choices.length >= minCohort,
      resolutionSufficient: selected.length >= minCohort,
      successSufficient: resolutions.length >= minCohort,
      outcomes,
    };
  });
}

export function buildReport(events, options = {}) {
  if (!options.to || !isValidDate(options.to)) {
    throw new Error('Pass retention observation end --to YYYY-MM-DD.');
  }
  const reportVersion = resolveReportVersion(events, options.version ?? '');
  const reportOptions = { ...options, version: reportVersion };
  const minCohort = options.minCohort ?? DEFAULT_MIN_COHORT;
  const rows = filteredEvents(events, reportOptions);
  const eventRows = (name) => rows.filter((event) => event.event === name);
  const sessionSet = (name) => unique(eventRows(name), (event) => event.sessionId);
  const runSet = (name) => unique(eventRows(name), (event) => event.runId);

  // Mobile foreground writes app_opened for D1/D7 signals, but a Control Center glance or
  // a single phone call is not a new-acquisition denominator. Start conversion looks at cold launch only.
  const openedSessions = unique(
    eventRows('app_opened').filter(
      (event) => event.properties.open_kind !== 'resume',
    ),
    (event) => event.sessionId,
  );
  const startedSessions = sessionSet('run_started');
  const startedRuns = runSet('run_started');
  const runStages = [
    ['Run started', 'run_started'],
    ['First relic chosen', 'relic_chosen'],
    ['Beacon lit', 'beacon_lit'],
    ['Gate crossed', 'gate_crossed'],
    ['Guardian encounter', 'guardian_started'],
    ['Guardian defeated', 'guardian_defeated'],
    ['Run ended', 'run_ended'],
  ].map(([label, eventName]) => {
    const stageEvents = eventName === 'relic_chosen'
      ? eventRows(eventName).filter((event) => event.properties.source !== 'opening')
      : eventRows(eventName);
    const runs = unique(stageEvents, (event) => event.runId);
    const count = eventName === 'run_started'
      ? startedRuns.size
      : intersectionSize(startedRuns, runs);
    return {
      label,
      event: eventName,
      count,
      rateFromStart: percentage(count, startedRuns.size),
    };
  });

  const beacons = eventRows('beacon_lit');
  const beaconChoices = eventRows('beacon_choice');
  const overchargeChoices = beaconChoices.filter(
    (event) => event.properties.mode === 'overcharge',
  );
  const overchargeResolutions = eventRows('overcharge_resolved');
  const outcomes = outcomeCounts(overchargeResolutions);
  const overchargeByTerrain = buildTerrainOvercharge(
    beaconChoices,
    overchargeResolutions,
    minCohort,
  );
  const cycleDecisions = eventRows('cycle_decision');
  const decisionCounts = Object.fromEntries(
    ['cashout', 'continue'].map((choice) => [
      choice,
      cycleDecisions.filter((event) => event.properties.choice === choice).length,
    ]),
  );

  // from/to is the play-metrics window. Retention keeps the input source start and only
  // accumulates through the observation end. Each D1/D7/D30 denominator includes only consents
  // old enough to actually hit that day, so new installs do not artificially pull long-term retention down.
  const versionEvents = events.filter((event) => (
    !reportVersion || eventVersion(event) === reportVersion
  ));
  const sourceDays = versionEvents.map((event) => event.clientDay).filter(Boolean).sort();
  const observationEnd = options.to || sourceDays.at(-1) || '';
  const retentionRows = versionEvents.filter((event) => (
    !observationEnd || event.clientDay <= observationEnd
  ));
  const allActivations = retentionRows.filter((event) => (
    event.event === 'analytics_activated'
    // Firestore TTL deletes per document asynchronously, so a 90-day boundary date can keep only
    // some activations. Drop that incomplete cohort entirely to avoid 100/20-style misreports.
    && cohortIsCompleteWithinTtl(event, observationEnd)
  ));
  const checkpoints = retentionRows.filter(
    (event) => event.event === 'retention_checkpoint',
  );
  // An orphan checkpoint whose original activation already hit TTL is accepted only when its
  // activation date matches, so it does not attach to a new-install numerator. The final sample is
  // still merged per version so a 2.1.x baseline can be seen even when daily samples are small.
  const activationKeys = new Set(
    allActivations.map(cohortKey).filter(Boolean),
  );
  const validCheckpoints = checkpoints.filter(
    (event) => activationKeys.has(cohortKey(event)) && isExactRetentionCheckpoint(event),
  );
  const cohortVersions = [...new Set(
    allActivations.map(cohortVersion).filter(Boolean),
  )].sort();
  const retention = cohortVersions.map((cohort) => {
    const cohortActivations = allActivations.filter(
      (event) => cohortVersion(event) === cohort,
    );
    const checkpointCount = (day) => validCheckpoints.filter((event) => (
      cohortVersion(event) === cohort
      && Number(event.properties.day) === day
    )).length;
    const checkpoint = Object.fromEntries([1, 7, 30].map((day) => [
      `d${day}`,
      checkpointCount(day),
    ]));
    const eligible = Object.fromEntries([1, 7, 30].map((day) => [
      `d${day}`,
      cohortActivations.filter(
        (event) => eligibleByDay(event, observationEnd, day),
      ).length,
    ]));
    const sufficient = Object.fromEntries([1, 7, 30].map((day) => [
      `d${day}`,
      eligible[`d${day}`] >= minCohort,
    ]));
    return {
      cohort,
      version: cohort,
      size: cohortActivations.length,
      sufficient,
      eligible,
      ...checkpoint,
    };
  });

  const ended = eventRows('run_ended');
  const defeated = ended.filter((event) => event.properties.reason === 'defeat');
  const cashouts = ended.filter((event) => event.properties.reason === 'cashout');
  const beaconRuns = runSet('beacon_lit');
  const earlyDefeats = defeated.filter(
    (event) => event.runId && !beaconRuns.has(event.runId),
  ).length;
  const runDurations = ended.map(
    (event) => Number(event.properties.duration_ms) / 60000,
  );
  const firstRelicMinutes = firstElapsedMinutes(
    eventRows('relic_chosen').filter((event) => event.properties.source !== 'opening'),
    startedRuns,
  );
  const relicResonance = buildRelicResonance(
    eventRows('relic_chosen'),
    eventRows('evolution_unlocked'),
    minCohort,
  );
  const firstBeaconMinutes = firstElapsedMinutes(beacons, startedRuns);
  const guardianStartedRuns = runSet('guardian_started');
  const guardianDefeatedRuns = runSet('guardian_defeated');
  const reachedGuardians = intersectionSize(startedRuns, guardianStartedRuns);
  const defeatedGuardians = intersectionSize(startedRuns, guardianDefeatedRuns);
  const days = rows.map((event) => event.clientDay).filter(Boolean).sort();
  return {
    totalEvents: rows.length,
    firstDay: days[0] ?? '',
    lastDay: days.at(-1) ?? '',
    appVersion: reportVersion,
    minCohort,
    activation: {
      openedSessions: openedSessions.size,
      startedSessions: intersectionSize(openedSessions, startedSessions),
      rate: percentage(intersectionSize(openedSessions, startedSessions), openedSessions.size),
    },
    runFunnel: runStages,
    overcharge: {
      choices: beaconChoices.length,
      beaconsLit: beacons.length,
      selected: overchargeChoices.length,
      resolved: overchargeResolutions.length,
      selectionRate: percentage(overchargeChoices.length, beaconChoices.length),
      resolutionRate: percentage(overchargeResolutions.length, overchargeChoices.length),
      successRate: percentage(outcomes.success, overchargeResolutions.length),
      outcomes,
      byTerrain: overchargeByTerrain,
    },
    cycleDecision: {
      total: cycleDecisions.length,
      cashout: decisionCounts.cashout,
      continue: decisionCounts.continue,
      continueRate: percentage(decisionCounts.continue, cycleDecisions.length),
    },
    relicResonance,
    retentionWindow: {
      from: options.from ?? '',
      to: options.to ?? '',
      filtered: Boolean(options.from || options.to),
      observationEnd,
      definition: 'utc_calendar_day_exact_return',
      activationDenominator: 'eligible_by_day_through_observation_end',
      checkpointNumerator: 'all_input_through_observation_end',
      completeCohortsBeforeTtlDays: RETENTION_SERVER_TTL_DAYS,
    },
    retention,
    fun: {
      endedRuns: unique(ended, (event) => event.runId).size,
      medianRunMinutes: median(runDurations),
      p90RunMinutes: percentile(runDurations, 0.9),
      medianFirstRelicMinutes: median(firstRelicMinutes),
      medianFirstBeaconMinutes: median(firstBeaconMinutes),
      guardianReachedRuns: reachedGuardians,
      guardianDefeatedRuns: defeatedGuardians,
      guardianClearRate: percentage(defeatedGuardians, reachedGuardians),
      defeatedRuns: defeated.length,
      earlyDefeats,
      earlyDefeatRate: percentage(earlyDefeats, defeated.length),
      cashoutRuns: cashouts.length,
      cashoutRate: percentage(cashouts.length, ended.length),
    },
  };
}

function formatPercent(value) {
  return value === null ? '—' : `${value.toFixed(1)}%`;
}

function formatSegmentPercent(value, sufficient, minimum) {
  return sufficient ? formatPercent(value) : `— (n<${minimum})`;
}

function formatRetention(checkpoints, eligible, sufficient, minimum) {
  if (!sufficient) return `${checkpoints}/${eligible} (n<${minimum})`;
  return `${checkpoints}/${eligible} (${formatPercent(percentage(checkpoints, eligible))})`;
}

export function renderMarkdown(report) {
  const period = report.firstDay
    ? `${report.firstDay}${report.lastDay && report.lastDay !== report.firstDay ? ` ~ ${report.lastDay}` : ''}`
    : 'no data';
  const lines = [
    '# Moonlit Beacon game analytics',
    '',
    `- App version: ${report.appVersion || 'no data'}`,
    `- Period: ${period}`,
    `- Valid events: ${report.totalEvents.toLocaleString('en-US')}`,
    `- Retention min cohort: n=${report.minCohort}`,
    '',
    '## Start conversion',
    '',
    '| Cold-launch sessions | Sessions that started a run | Conversion |',
    '| ---: | ---: | ---: |',
    `| ${report.activation.openedSessions} | ${report.activation.startedSessions} | ${formatPercent(report.activation.rate)} |`,
    '',
    '## Run funnel',
    '',
    '| Step | Unique runs | vs start |',
    '| --- | ---: | ---: |',
    ...report.runFunnel.map((stage) => (
      `| ${stage.label} | ${stage.count} | ${formatPercent(stage.rateFromStart)} |`
    )),
    '',
    '## Overcharge',
    '',
    '| Beacon chosen | Overcharge chosen | Resolved | Success | Fail | Leave | Defeat |',
    '| ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    `| ${report.overcharge.choices} | ${report.overcharge.selected} (${formatPercent(report.overcharge.selectionRate)}) | ${report.overcharge.resolved} (${formatPercent(report.overcharge.resolutionRate)}) | ${report.overcharge.outcomes.success} | ${report.overcharge.outcomes.failed} | ${report.overcharge.outcomes.abandoned} | ${report.overcharge.outcomes.defeat} |`,
    '',
    `- Overcharge resolve success rate: ${formatPercent(report.overcharge.successRate)}`,
    '',
    '### Overcharge by biome',
    '',
    '| Biome | Beacon chosen | Overcharge | Pick rate | Resolved | Resolve rate | Success | Fail | Leave | Defeat | Success rate |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    ...report.overcharge.byTerrain.map((terrain) => (
      `| ${terrain.label} | ${terrain.choices} | ${terrain.selected} | ${formatSegmentPercent(terrain.selectionRate, terrain.selectionSufficient, report.minCohort)} | ${terrain.resolved} | ${formatSegmentPercent(terrain.resolutionRate, terrain.resolutionSufficient, report.minCohort)} | ${terrain.outcomes.success} | ${terrain.outcomes.failed} | ${terrain.outcomes.abandoned} | ${terrain.outcomes.defeat} | ${formatSegmentPercent(terrain.successRate, terrain.successSufficient, report.minCohort)} |`
    )),
    '',
    '## Choice after Guardian',
    '',
    '| All choices | Cash out | Continue | Continue rate |',
    '| ---: | ---: | ---: | ---: |',
    `| ${report.cycleDecision.total} | ${report.cycleDecision.cashout} | ${report.cycleDecision.continue} | ${formatPercent(report.cycleDecision.continueRate)} |`,
    '',
    '## Relic resonance',
    '',
    '| Path | Runs that picked | Resonated runs (2+ kinds) | Resonance rate | Evolved runs | Pick→evolve | Resonance→evolve |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: |',
    ...report.relicResonance.map((family) => (
      `| ${family.label} | ${family.selectedRuns} | ${family.resonantRuns} | ${formatSegmentPercent(family.resonanceRate, family.selectedSufficient, report.minCohort)} | ${family.evolvedRuns} | ${formatSegmentPercent(family.evolutionRate, family.selectedSufficient, report.minCohort)} | ${formatSegmentPercent(family.evolutionFromResonanceRate, family.resonantSufficient, report.minCohort)} |`
    )),
    '',
    '## Retention signal',
    '',
    '| Consent cohort | Base n | D1 | D7 | D30 |',
    '| --- | ---: | ---: | ---: | ---: |',
  ];
  if (report.retention.length === 0) {
    lines.push('| — | 0 | — | — | — |');
  } else {
    for (const cohort of report.retention) {
      lines.push(`| ${cohort.cohort} | ${cohort.size} | ${formatRetention(cohort.d1, cohort.eligible.d1, cohort.sufficient.d1, report.minCohort)} | ${formatRetention(cohort.d7, cohort.eligible.d7, cohort.sufficient.d7, report.minCohort)} | ${formatRetention(cohort.d30, cohort.eligible.d30, cohort.sufficient.d30, report.minCohort)} |`);
    }
  }
  lines.push(
    '',
    '> Retention is a cohort-total signal from a return checkpoint issued once on-device; it does not track individuals for re-identification.',
    `> D1/D7/D30 are returns on that UTC client_day calendar date. The denominator includes only consents that could reach each date by observation end ${report.retentionWindow.observationEnd || '—'}.`,
    `> Cohorts on the ${report.retentionWindow.completeCohortsBeforeTtlDays}-day boundary that may be only partly left after per-document async TTL deletes are excluded from both numerator and denominator.`,
    ...(report.retentionWindow.filtered
      ? ['> Date filters apply to play metrics. Retention accumulates from the input source start through --to observation end so consents before the period start are not dropped.']
      : []),
    '',
    '## Fun and difficulty check',
    '',
    `- Ended unique runs: ${report.fun.endedRuns}`,
    `- Median play time: ${report.fun.medianRunMinutes === null ? '—' : `${report.fun.medianRunMinutes.toFixed(1)} min`}`,
    `- p90 play time: ${report.fun.p90RunMinutes === null ? '—' : `${report.fun.p90RunMinutes.toFixed(1)} min`}`,
    `- Median to first relic: ${report.fun.medianFirstRelicMinutes === null ? '—' : `${report.fun.medianFirstRelicMinutes.toFixed(1)} min`}`,
    `- Median to first beacon: ${report.fun.medianFirstBeaconMinutes === null ? '—' : `${report.fun.medianFirstBeaconMinutes.toFixed(1)} min`}`,
    `- Guardian defeated after first reach: ${report.fun.guardianDefeatedRuns}/${report.fun.guardianReachedRuns} (${formatPercent(report.fun.guardianClearRate)})`,
    `- Cycle-reward cashout ends: ${report.fun.cashoutRuns}/${report.fun.endedRuns} (${formatPercent(report.fun.cashoutRate)})`,
    `- Defeats before first beacon: ${report.fun.earlyDefeats}/${report.fun.defeatedRuns} (${formatPercent(report.fun.earlyDefeatRate)})`,
    '',
  );
  return lines.join('\n');
}

function usage() {
  return [
    'Usage:',
    '  node scripts/analyze-game-analytics.mjs --file export.json --to YYYY-MM-DD [options]',
    '',
    'Options:',
    '  --from YYYY-MM-DD       start date (inclusive)',
    '  --to YYYY-MM-DD         observation end (inclusive, required)',
    '  --version VERSION       app version (required if several versions are mixed)',
    `  --min-cohort N          min sample for retention percents (default ${DEFAULT_MIN_COHORT})`,
  ].join('\n');
}

export function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return 0;
  }
  if (!options.file) throw new Error('Specify a Firestore JSON or JSONL file.');
  const events = readEvents(options.file);
  const report = buildReport(events, options);
  process.stdout.write(`${renderMarkdown(report)}\n`);
  return 0;
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : '';
if (import.meta.url === invokedPath) {
  try {
    process.exitCode = main();
  } catch (error) {
    process.stderr.write(`Analysis failed: ${error.message}\n`);
    process.exitCode = 1;
  }
}
