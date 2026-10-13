// Output gating and user-data safety for scripts/course-verify.mjs.
// Godot exits 0 through parse errors, runtime script errors, and exit-time
// leaks, so every step is judged on its output text, not its status.
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { LEARNER_APP_NAME, REFERENCE_APP_NAME } from './course-practice.mjs';

// A defect line: engine errors, script errors (runtime or parse), and any
// leak report. Matched per line, case-sensitively: the macOS sandbox noise
// below is the only exclusion, and it is name-anchored, not a broad filter.
const DEFECT_PATTERN = /SCRIPT ERROR|Parse Error|leaked|still in use at exit|ERROR:/;
// macOS sandbox noise: the engine cannot reach the system CA store here.
// It appears in every run on this host regardless of project correctness.
// Anchored to the observed native condition text only: a bare identifier
// match would swallow a real script error that merely mentions noErr.
const ENVIRONMENT_PATTERN = /Condition "ret != noErr" is true/;
const ANSI_PATTERN = /\u001b\[[0-9;]*m/g;
// First-scan ordering noise: on the very first import the engine reads
// locale/translations before the CSV importer has generated the outputs,
// so the missing .translation paths log loader errors once. The import
// runs twice and only the first pass tolerates exactly these lines; a
// genuinely broken CSV still fails the second pass.
const FIRST_SCAN_TRANSLATION_PATTERN = /\.translation/;
const FIRST_SCAN_LOADER_PATTERN = /Cannot open file|Failed loading resource/;

export function isFirstScanTranslationNoise(line) {
  return FIRST_SCAN_TRANSLATION_PATTERN.test(line) && FIRST_SCAN_LOADER_PATTERN.test(line);
}


export function stripAnsi(line) {
  return line.replace(ANSI_PATTERN, '');
}

// Returns one entry per defect line, each with up to two trailing `at:`
// context lines joined in. Empty means the step's output is clean.
export function collectDefects(output) {
  const defects = [];
  const lines = String(output ?? '').split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const clean = stripAnsi(lines[i]).trim();
    if (clean === '' || ENVIRONMENT_PATTERN.test(clean)) continue;
    if (!DEFECT_PATTERN.test(clean)) continue;
    const entry = [clean];
    for (let j = i + 1; j < lines.length && j <= i + 2; j += 1) {
      const next = stripAnsi(lines[j]).trim();
      if (/^at: /.test(next)) entry.push(next);
      else break;
    }
    defects.push(entry.join(' <- '));
  }
  return defects;
}

// Real (non-isolated) user-data roots for the app names verification must
// never touch: the learner's own project and the reference checkpoints.
export function realUserDataRoots(env = process.env, appNames = [LEARNER_APP_NAME, REFERENCE_APP_NAME]) {
  const home = env.HOME ?? env.USERPROFILE ?? '';
  if (home === '') return [];
  const roots = [];
  for (const app of appNames) {
    if (process.platform === 'darwin') {
      roots.push(join(home, 'Library', 'Application Support', 'Godot', 'app_userdata', app));
    } else if (process.platform === 'win32') {
      roots.push(join(env.APPDATA ?? home, 'Godot', 'app_userdata', app));
    } else {
      const data = env.XDG_DATA_HOME ?? join(home, '.local', 'share');
      roots.push(join(data, 'godot', 'app_userdata', app));
    }
  }
  return roots;
}

// Where one isolated run stores its user:// files on this platform.
export function isolatedUserDataRoot(home, appName = REFERENCE_APP_NAME) {
  if (process.platform === 'darwin') {
    return join(home, 'Library', 'Application Support', 'Godot', 'app_userdata', appName);
  }
  if (process.platform === 'win32') {
    return join(home, 'AppData', 'Roaming', 'Godot', 'app_userdata', appName);
  }
  return join(home, '.local', 'share', 'godot', 'app_userdata', appName);
}

// Snapshot existence + size + content hash for everything under the roots,
// so a pre-existing learner save is proven byte-identical instead of merely
// "noticed": size and mtime alone cannot tell same-length edits apart. A bare
// timestamp touch with unchanged bytes is not flagged. Missing roots snapshot
// as absent, not as failures.
export function snapshotUserData(roots) {
  const snap = {};
  for (const root of roots) {
    let entries = null;
    try {
      entries = [];
      const stack = [''];
      while (stack.length > 0) {
        const relative = stack.pop();
        const full = relative === '' ? root : join(root, relative);
        const stat = statSync(full);
        if (stat.isDirectory()) {
          for (const child of readdirSync(full)) {
            stack.push(relative === '' ? child : join(relative, child));
          }
        } else {
          const hash = createHash('sha256').update(readFileSync(full)).digest('hex');
          entries.push(`${relative}=${stat.size}:${hash}`);
        }
      }
      entries.sort();
    } catch {
      entries = null;
    }
    snap[root] = entries;
  }
  return snap;
}

export function diffSnapshots(before, after) {
  const changed = [];
  for (const root of Object.keys(after)) {
    const a = before[root] ?? null;
    const b = after[root] ?? null;
    if (JSON.stringify(a) !== JSON.stringify(b)) changed.push(root);
  }
  return changed;
}
