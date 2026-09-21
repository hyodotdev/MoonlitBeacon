import fs from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const defaultState = fileURLToPath(new URL('../notes/growth/state.json', import.meta.url));
const dayMs = 86400000;
const states = ['observed', 'unavailable', 'not_checked'];
const terminal = ['succeeded', 'failed', 'inconclusive', 'not_run'];
export function isDay(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
}
function requiredText(value, name) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${name}: text required`);
}
export function validateState(s) {
  if (s.schemaVersion !== 2 || !isDay(s.updatedAt)) throw new Error('Invalid schema/date');
  for (const name of ['snapshots', 'collectionAttempts', 'tasks', 'experiments', 'requiredStreams']) {
    if (!Array.isArray(s[name])) throw new Error(`${name}: array required`);
  }
  const ids = new Set();
  for (const x of s.snapshots) {
    requiredText(x.id, 'snapshot id');
    if (ids.has(x.id)) throw new Error(`Duplicate snapshot ${x.id}`);
    ids.add(x.id);
    for (const k of ['stream', 'source', 'scope', 'platform']) requiredText(x[k], k);
    if (!isDay(x.observedAt) || x.observedAt > s.updatedAt) throw new Error('Invalid observedAt');
    const p = x.period;
    if (!p) throw new Error('Missing period');
    requiredText(p.timezone, 'timezone');
    if (p.start === null && p.end === null) requiredText(p.reason, 'unknown period reason');
    else if (!isDay(p.start) || !isDay(p.end) || p.start > p.end || p.end > x.observedAt) throw new Error('Invalid period');
    if (!Array.isArray(x.metrics) || !x.metrics.length) throw new Error('Missing metrics');
    for (const m of x.metrics) {
      requiredText(m.key, 'metric key'); requiredText(m.label, 'metric label');
      if (!states.includes(m.status) || !['count', 'percent'].includes(m.unit)) throw new Error('Invalid metric kind');
      if (m.status === 'observed') {
        if (!Number.isFinite(m.value) || m.value < 0 || (m.unit === 'count' && !Number.isInteger(m.value))
          || (m.unit === 'percent' && m.value > 100)) throw new Error('Invalid observed value');
      } else {
        if (m.value !== null) throw new Error('Missing values must be null');
        requiredText(m.reason, 'missing value reason');
      }
    }
  }
  for (const a of s.collectionAttempts) {
    if (!isDay(a.attemptedAt) || a.attemptedAt > s.updatedAt || !['ok', 'partial', 'blocked'].includes(a.status)) throw new Error('Invalid attempt');
    requiredText(a.stream, 'attempt stream'); requiredText(a.detail, 'attempt detail');
  }
  for (const t of s.tasks) {
    if (!isDay(t.due) || !isDay(t.nextReview) || !['ready', 'blocked', 'done'].includes(t.status)) throw new Error('Invalid task');
    if (!Array.isArray(t.evidence)) throw new Error('Task evidence required');
    if (t.status === 'done' && !t.evidence.length) throw new Error('Done task needs evidence');
    if (t.status === 'blocked') requiredText(t.blocker, 'task blocker');
  }
  if (s.experiments.filter(x => x.status === 'running').length > 1) throw new Error('Only one running experiment');
  for (const e of s.experiments) {
    if (![...terminal, 'ready', 'queued', 'running'].includes(e.status) || !isDay(e.decisionDue) || !isDay(e.nextReview)) throw new Error('Invalid experiment');
    if (e.startedAt !== null && (!isDay(e.startedAt) || e.startedAt > s.updatedAt || e.startedAt > e.decisionDue)) throw new Error('Invalid experiment start');
    if (['running', 'succeeded', 'failed'].includes(e.status)) {
      if (!e.startedAt) throw new Error('Launch date required');
      requiredText(e.launchEvidence, 'launch evidence');
    }
    if (terminal.includes(e.status)) requiredText(e.result, 'experiment verdict');
    if (e.status === 'not_run' && (e.startedAt !== null || e.launchEvidence !== null)) throw new Error('Unlaunched experiment cannot have a launch');
  }
  if (!isDay(s.monitoring.nextReview) || s.monitoring.nextReview <= s.updatedAt) throw new Error('Next review must be future');
  if (!Number.isFinite(s.marketing.approvedBudget) || s.marketing.approvedBudget < 0) throw new Error('Invalid budget');
  if (s.marketing.approvedBudget > 0) requiredText(s.marketing.approvalEvidence, 'budget approval');
  return s;
}
export function latest(rows, field) {
  const byStream = new Map();
  for (const x of rows) if (!byStream.has(x.stream) || x[field] >= byStream.get(x.stream)[field]) byStream.set(x.stream, x);
  return byStream;
}
export function renderReport(s, today = new Date().toLocaleDateString('en-CA', {timeZone:'Asia/Seoul'})) {
  validateState(s);
  if (!isDay(today)) throw new Error('Invalid report date');
  const observations = latest(s.snapshots, 'observedAt');
  const attempts = latest(s.collectionAttempts, 'attemptedAt');
  const lines = [`# Moonlit Beacon growth · ${today}`, '', `Tracker: ${s.tracker.url}`, '', 'Source windows and units remain separate. Missing is not zero.', ''];
  for (const stream of new Set([...s.requiredStreams, ...observations.keys(), ...attempts.keys()])) {
    const x = observations.get(stream); const a = attempts.get(stream);
    lines.push(`## ${stream}`);
    if (!x) lines.push('No verified snapshot.');
    else {
      lines.push(`Observed ${x.observedAt}; window ${x.period.start ?? '?'} — ${x.period.end ?? '?'}; ${x.period.timezone}`, `Scope: ${x.scope}`, `Source: ${x.source}`);
      if (Date.parse(today) - Date.parse(x.observedAt) > 8 * dayMs) lines.push('STALE OBSERVATION');
      if (x.period.end && Date.parse(today) - Date.parse(x.period.end) > 8 * dayMs) lines.push('OLD OBSERVATION WINDOW');
      if (!x.period.start) lines.push(`UNKNOWN WINDOW: ${x.period.reason}`);
      if (x.caveat) lines.push(`CAUTION: ${x.caveat}`);
      for (const m of x.metrics) lines.push(`- ${m.label}: ${m.status === 'observed' ? `${m.value}${m.unit === 'percent' ? '%' : ''}` : `— (${m.reason})`}`);
    }
    if (a) lines.push(`Attempt ${a.attemptedAt}: ${a.status} — ${a.detail}`);
    lines.push('');
  }
  lines.push('## Work and decisions');
  for (const t of s.tasks) lines.push(`- ${t.id} ${t.status}: ${t.title}; due ${t.due}${t.status !== 'done' && t.due <= today ? ' [DUE/OVERDUE]' : ''}${t.blocker ? `; ${t.blocker}` : ''}`);
  for (const e of s.experiments) lines.push(`- ${e.id} ${e.status}: ${e.title}; decision ${e.decisionDue}${!terminal.includes(e.status) && e.decisionDue <= today ? ' [DECISION DUE]' : ''}; ${e.result ?? 'No verdict yet'}`);
  lines.push('', `Approved marketing budget: ${s.marketing.approvedBudget} ${s.marketing.currency}`, `Next review: ${s.monitoring.nextReview}${s.monitoring.nextReview <= today ? ' [OVERDUE]' : ''}`, 'Validation proves data structure, not collection success or growth.');
  return lines.join('\n') + '\n';
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const args = process.argv.slice(2).filter(x => x !== '--');
    let filename = defaultState; let date; let check = false;
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--check') check = true;
      else if (['--file', '--date'].includes(args[i]) && args[i + 1]) {
        const flag = args[i++]; if (flag === '--file') filename = args[i]; else date = args[i];
      } else throw new Error(`Unknown/incomplete argument: ${args[i]}`);
    }
    const state = validateState(JSON.parse(fs.readFileSync(filename, 'utf8')));
    process.stdout.write(check ? 'Growth state validation passed\n' : renderReport(state, date));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
