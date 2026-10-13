#!/usr/bin/env node
// Verify course practice outputs end to end: scaffold each lesson into a
// throwaway folder, import, compile every script, boot the real main scene
// and close it through the production close path, then run the progression
// checks. Godot always runs with an isolated HOME, so
// installed-game saves and the real user data folder cannot be touched.
// Every step is judged on its output text: Godot exits 0 through parse
// errors, runtime script errors, and exit-time leaks.
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveGodot } from './godot.mjs';
import { isolatedEnvironment } from './lib/godot-run.mjs';
import { MAX_LESSON, MIN_LESSON, executePlan, planCreation } from './lib/course-practice.mjs';
import {
  collectDefects,
  diffSnapshots,
  isFirstScanTranslationNoise,
  isolatedUserDataRoot,
  realUserDataRoots,
  snapshotUserData,
} from './lib/course-verify-lib.mjs';

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const SOURCES = join(repository, 'examples', 'course', 'src');
const TESTS = join(repository, 'examples', 'course', 'tests');

const IMPORT_TIMEOUT_MS = 240000;
const STEP_TIMEOUT_MS = 120000;

function usage() {
  console.log(`Verify course practice lessons 1-16.

Usage:
  node scripts/course-verify.mjs [--lesson N] [--keep]

Scaffolds each lesson into a throwaway folder, imports it, compiles every
script, boots the real main scene and closes it through the production
close path (title -> arena -> restart on lessons 9+, plus the QuitPrompt
Yes path on lesson 16), and runs the progression checks. Lessons 14+
also re-run in a fresh process to prove saves survive a restart.
--keep leaves the last scaffold behind for inspection.`);
}

function runGodot(godot, project, args, home, timeoutMs) {
  const env = isolatedEnvironment(process.env, home);
  const run = spawnSync(godot, ['--headless', '--path', project, ...args], {
    env, encoding: 'utf8', timeout: timeoutMs,
  });
  const output = `${run.stdout ?? ''}\n${run.stderr ?? ''}`;
  return {
    status: run.status,
    timedOut: run.error?.code === 'ETIMEDOUT',
    output,
    defects: collectDefects(output),
  };
}

// A step passes only when the process exits 0 AND its output holds no
// engine errors, script errors, or leaks.
function gateFailures(label, run) {
  if (run.timedOut) {
    const tail = run.output.split('\n').filter((line) => line.trim() !== '').slice(-5);
    return [`${label} timed out: ${tail.join(' | ')}`];
  }
  if (run.status !== 0) {
    const shown = run.defects.slice(0, 5).join(' | ') || '(no error lines captured)';
    return [`${label} exit ${run.status}: ${shown}`];
  }
  if (run.defects.length > 0) {
    return [`${label} exit 0 with defects: ${run.defects.slice(0, 5).join(' | ')}`];
  }
  return [];
}

function projectScripts(out) {
  const found = [];
  const stack = [out];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const full = join(current, entry.name);
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) {
        if (entry.name === '.godot') continue;
        stack.push(full);
      } else if (entry.isFile() && entry.name.endsWith('.gd')) {
        found.push(`res://${relative(out, full).split(sep).join('/')}`);
      }
    }
  }
  return found.sort();
}

// Registers the close observer as a scaffold-only autoload: TestClose boots
// with the real main scene, autoloads, and current_scene, then only
// observes and presses production signals. The throwaway project.godot is
// the only file touched; shipped sources never name this singleton.
function registerTestAutoload(out) {
  const path = join(out, 'project.godot');
  const line = 'TestClose="*res://close_probe.gd"';
  const text = readFileSync(path, 'utf8');
  if (text.includes(line)) return;
  if (/^\[autoload\]/m.test(text)) {
    writeFileSync(path, text.replace(/^\[autoload\]/m, `[autoload]\n\n${line}`));
  } else {
    writeFileSync(path, `${text.replace(/\s*$/, '')}\n\n[autoload]\n\n${line}\n`);
  }
}

function checkSaveFiles(home, lesson, failures) {
  const root = isolatedUserDataRoot(home);
  const records = join(root, 'records.cfg');
  if (lesson >= 14) {
    if (!existsSync(records)) {
      failures.push(`save files: missing ${records} (saves left the isolated home?)`);
    } else if (!readFileSync(records, 'utf8').includes('best_score')) {
      failures.push('save files: records.cfg has no best_score');
    }
  }
  if (lesson >= 15) {
    const settings = join(root, 'settings.cfg');
    if (!existsSync(settings)) {
      failures.push(`save files: missing ${settings} (settings left the isolated home?)`);
    }
  }
}

function verifyLesson(godot, manifest, lesson, keep) {
  const work = mkdtempSync(join(tmpdir(), `course-verify-lesson-${lesson}-`));
  const home = mkdtempSync(join(tmpdir(), 'course-verify-home-'));
  const failures = [];
  try {
    const out = join(work, 'project');
    executePlan(planCreation({ repoRoot: repository, lesson, out, manifest }));
    for (const probe of ['practice_check', 'compile_probe']) {
      copyFileSync(join(TESTS, `${probe}.gd`), join(out, `${probe}.gd`));
      copyFileSync(join(TESTS, `${probe}.tscn`), join(out, `${probe}.tscn`));
    }
    copyFileSync(join(TESTS, 'close_probe.gd'), join(out, 'close_probe.gd'));
    registerTestAutoload(out);
    const firstImport = runGodot(godot, out, ['--editor', '--quit'], home, IMPORT_TIMEOUT_MS);
    const firstDefects = firstImport.defects.filter((line) => !isFirstScanTranslationNoise(line));
    failures.push(...gateFailures('import', { ...firstImport, defects: firstDefects }));
    if (failures.length > 0) return { lesson, failures };
    const importRun = runGodot(godot, out, ['--editor', '--quit'], home, IMPORT_TIMEOUT_MS);
    failures.push(...gateFailures('import confirm', importRun));
    if (failures.length > 0) return { lesson, failures };
    const scripts = projectScripts(out);
    const compileRun = runGodot(godot, out, [
      'res://compile_probe.tscn', '--',
      ...scripts.map((path) => `--file=${path}`),
    ], home, STEP_TIMEOUT_MS);
    failures.push(...gateFailures('compile', compileRun));
    const compiled = compileRun.output.split('\n').find((line) => line.startsWith('COMPILE RESULT'));
    if (!compiled || !compiled.includes('fail=0')) {
      failures.push(`compile: ${compiled ?? 'no result'}`);
    }
    if (failures.length > 0) return { lesson, failures };
    // Real startup, no scene override: the observer boots the configured
    // main scene, drives title -> arena (-> restart), then triggers the
    // production close path. Lesson 16 runs twice: the QuitPrompt Yes path
    // and the window-close path. Lessons 1-2 have no scripted title and no
    // looping voice, so their run ends after a clean plain quit.
    const closeModes = lesson === 16 ? ['yes', 'window'] : lesson <= 2 ? ['plain'] : ['window'];
    for (const mode of closeModes) {
      const closeRun = runGodot(godot, out, [
        '--', `--lesson=${lesson}`, `--close-mode=${mode}`,
      ], home, STEP_TIMEOUT_MS);
      failures.push(...gateFailures(`close ${mode}`, closeRun));
      const booted = closeRun.output.split('\n').find((line) => line.startsWith('BOOT RESULT'));
      if (!booted || !booted.includes('ok=true')) {
        failures.push(`close ${mode}: ${booted ?? 'no result'}`);
      }
      const sent = closeRun.output.split('\n').find((line) => line.startsWith('CLOSE SENT'));
      if (!sent) {
        failures.push(`close ${mode}: production close never triggered`);
      }
    }
    if (failures.length > 0) return { lesson, failures };
    const checkRun = runGodot(godot, out, ['res://practice_check.tscn', '--', `--lesson=${lesson}`], home, STEP_TIMEOUT_MS);
    failures.push(...gateFailures('checks', checkRun));
    const result = checkRun.output.split('\n').find((line) => line.startsWith('PRACTICE RESULT'));
    const failed = checkRun.output.split('\n').filter((line) => line.startsWith('PRACTICE FAIL'));
    if (!result || failed.length > 0) {
      failures.push(`checks: ${result ?? 'no result'} ${failed.slice(0, 5).join(' | ')}`);
    }
    if (lesson === 16) {
      const transition = checkRun.output.split('\n').find((line) => line.startsWith('TRANSITION RESULT'));
      if (!transition || !transition.includes('current=TitleMenu') || !transition.includes('paused=false')) {
        failures.push(`transition: ${transition ?? 'no result'}`);
      }
    }
    if (failures.length > 0) return { lesson, failures };
    if (lesson >= 14) {
      const saveRun = runGodot(godot, out, [
        'res://practice_check.tscn', '--', `--lesson=${lesson}`, '--verify-save',
      ], home, STEP_TIMEOUT_MS);
      failures.push(...gateFailures('save reload', saveRun));
      const saved = saveRun.output.split('\n').find((line) => line.startsWith('SAVE RESULT'));
      if (!saved || !saved.includes('ok=true')) {
        failures.push(`save reload: ${saved ?? 'no result'}`);
      }
      checkSaveFiles(home, lesson, failures);
    }
    return { lesson, failures };
  } finally {
    if (!keep) {
      rmSync(work, { recursive: true, force: true });
      rmSync(home, { recursive: true, force: true });
    } else {
      console.log(`kept scaffold: ${work}`);
    }
  }
}

function main(argv) {
  let lesson = null;
  let keep = false;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--help' || argv[i] === '-h') {
      usage();
      return;
    }
    if (argv[i] === '--keep') {
      keep = true;
    } else if (argv[i] === '--lesson') {
      lesson = Number(argv[i + 1]);
      i += 1;
    } else {
      console.error(`course-verify: unknown argument ${argv[i]}. See --help.`);
      process.exitCode = 2;
      return;
    }
  }
  const lessons = [];
  if (lesson === null) {
    for (let n = MIN_LESSON; n <= MAX_LESSON; n += 1) lessons.push(n);
  } else {
    if (!Number.isInteger(lesson) || lesson < MIN_LESSON || lesson > MAX_LESSON) {
      console.error(`course-verify: --lesson needs an integer ${MIN_LESSON}-${MAX_LESSON}.`);
      process.exitCode = 2;
      return;
    }
    lessons.push(lesson);
  }
  const search = resolveGodot();
  if (!search.bin) {
    console.error('course-verify: no Godot binary found (GODOT_BIN or PATH).');
    process.exitCode = 2;
    return;
  }
  const manifest = JSON.parse(readFileSync(join(SOURCES, 'manifest.json'), 'utf8'));
  const roots = realUserDataRoots();
  const before = snapshotUserData(roots);
  let failed = 0;
  for (const n of lessons) {
    const { failures } = verifyLesson(search.bin, manifest, n, keep);
    if (failures.length === 0) {
      console.log(`lesson ${n}: import/compile/boot/checks ok`);
    } else {
      failed += 1;
      console.log(`lesson ${n}: FAILED`);
      for (const failure of failures) console.log(`  ${failure}`);
    }
  }
  for (const root of diffSnapshots(before, snapshotUserData(roots))) {
    failed += 1;
    console.log(`FAILED: real user data changed during verification: ${root}`);
  }
  if (failed > 0) {
    process.exitCode = 1;
    return;
  }
  console.log(`course-verify: ${lessons.length} lesson(s) ok, real user data untouched`);
}

main(process.argv.slice(2));
