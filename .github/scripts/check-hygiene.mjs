#!/usr/bin/env node
// Repo-rules check. CI and local look at **the same thing**.
//
// These checks used to live only as bash in ci.yml, with a paste block in
// the local `/verify` doc. The two copies drifted a little —
// CI used `grep -rni "phase"` while local was case-sensitive, so lowercase
// `phase` passed locally and died only in CI. That actually happened with
// `.mb-phase-table`.
//
// So they were merged into one copy. `pnpm verify` and CI call this file.
//
// The check covers **git-tracked files only**. `.godot/` still holds export
// cache from before a rename, so walking the filesystem would fail a clean
// repo.

import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import { agentSkillSyncProblems } from '../../scripts/lib/agent-skill-sync.mjs';
import { containsForbiddenPhaseTerm } from '../../scripts/lib/hygiene-terms.mjs';

const problems = [];
const notes = [];

if (
  !containsForbiddenPhaseTerm('phase-03')
  || containsForbiddenPhaseTerm('_diagnostic_broadphase_checks')
) {
  throw new Error('lesson-term checker word-boundary contract is broken');
}

const git = (...args) =>
  execFileSync('git', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
    .split('\n')
    .filter(Boolean);

const tracked = git('ls-files');
const isText = (p) => !/\.(png|jpg|jpeg|mp4|avi|ogg|ttf|otf|zip|apk|ico|webp|import|translation|uid)$/i.test(p);

// --- 1. Do not write "Phase" ------------------------------------------------
// Case-insensitive. Documents that explain the ban itself are out of scope.
const TERM_SCOPE = /^(apps|notes)\/|^README\.md$/;
// The official godot-iap source uses `phase` as a payment-lifecycle field
// name. That is an external API and cannot be renamed.
const TERM_EXEMPT = /^apps\/game\/addons\/godot-iap\//;
for (const file of tracked) {
  if (!TERM_SCOPE.test(file) || TERM_EXEMPT.test(file) || !isText(file)) continue;
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    if (containsForbiddenPhaseTerm(line)) problems.push(`${file}:${i + 1}: "phase" — number lessons as 'Lesson N' (case-insensitive)`);
  });
}

// --- 2. Things that must not be committed -----------------------------------
// `.godot/` contains export_credentials.cfg, which holds the signing
// keystore password. `_tmp_*` are scenes created briefly inside res://
// while extracting a clip, then deleted.
const FORBIDDEN = [
  [/\.godot\//, '.godot/ is committed. It contains the signing keystore password'],
  [/\.zip$/, 'an original asset ZIP is committed'],
  [/(^|\/)_tmp_/, 'a render temp file (_tmp_*) is committed'],
];
for (const file of tracked) {
  for (const [pattern, why] of FORBIDDEN) {
    if (pattern.test(file)) problems.push(`${file}: ${why}`);
  }
}

// --- 3. Clip budget — silent and under 1MB ----------------------------------
const clips = tracked.filter((f) => f.startsWith('apps/docs/static/video/') && f.endsWith('.mp4'));
let biggest = 0;
for (const clip of clips) {
  const bytes = statSync(clip).size;
  biggest = Math.max(biggest, bytes);
  if (bytes > 1024 * 1024) problems.push(`${clip}: ${(bytes / 1024).toFixed(0)}KB — over 1MB`);
  try {
    const audio = execFileSync(
      'ffprobe',
      ['-v', 'error', '-select_streams', 'a', '-show_entries', 'stream=index', '-of', 'csv=p=0', clip],
      { encoding: 'utf8' }
    ).trim();
    if (audio) problems.push(`${clip}: has an audio stream — repo clips must be silent`);
  } catch {
    notes.push('ffprobe is missing, skipped the silence check');
    break;
  }
}

// --- 4. Godot output paths are relative to apps/game ------------------------
// `--export-*` takes the preset name first, then the output path. Omitting
// the path entirely uses the preset's export_path, which is fine.
const OUTPUT_PATH = [
  /godot .*--export-(?:debug|release) +"[^"]+" +[^-#\s]/,
  /godot .*--write-movie +[^-#\s]/,
];
for (const file of tracked) {
  if (!isText(file) || file.endsWith('ci.yml') || file.endsWith('check-hygiene.mjs')) continue;
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    if (line.includes('../../')) return;
    if (OUTPUT_PATH.some((p) => p.test(line)))
      problems.push(`${file}:${i + 1}: output paths are relative to apps/game — write ../../builds/...`);
  });
}

// --- 5. Hardcoded absolute paths --------------------------------------------
// Comments are allowed. An explanation like "this path used to be baked in"
// is how the next person learns why the code is shaped this way. Only
// executable lines are blocked.
for (const file of tracked) {
  if (!/^(notes|scripts)\/.*\.(ps1|mjs|py)$/.test(file)) continue;
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    if (/^\s*(#|\/\/)/.test(line)) return;
    if (/[A-Za-z]:[\\/](Users|Github)/.test(line))
      problems.push(`${file}:${i + 1}: an executable line has an absolute path — use $PSScriptRoot or GODOT_BIN`);
  });
}

// Author-machine home directories must not ship in the public tree.
// Split so this file does not match its own needle.
const AUTHOR_HOME = ['/Users', 'hyo'].join('/');
for (const file of tracked) {
  if (!isText(file)) continue;
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    if (line.includes(AUTHOR_HOME))
      problems.push(`${file}:${i + 1}: author-machine path — use $HOME, an env var, or a repo-relative path`);
  });
}

// --- 6. BOM direction is opposite -------------------------------------------
// PowerShell 5.1 reads a BOM-less .ps1 as ANSI and the parser dies on Hangul
// comments. Godot, on the other hand, treats a BOM as part of the key name.
const hasBom = (p) => readFileSync(p).subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf]));
for (const file of tracked.filter((f) => f.endsWith('.ps1'))) {
  if (!hasBom(file)) problems.push(`${file}: .ps1 files need a UTF-8 BOM`);
}
if (hasBom('apps/game/project.godot'))
  problems.push('apps/game/project.godot: has a BOM — Godot will read it as part of the key name');

// --- 7. Claude/Codex skills share one source --------------------------------
// .claude/skills is the source; .agents/skills is a byte-identical mirror.
// Editing the two copies separately would make the same request see different
// review scopes, so CI blocks that.
problems.push(...agentSkillSyncProblems());

// --- 8. project.godot locked values -----------------------------------------
// The editor has actually reverted values.
const LOCKED = [
  'window/size/viewport_width=808',
  'window/size/viewport_height=360',
  'window/size/window_width_override=1616',
  'window/size/window_height_override=720',
  'window/stretch/mode="canvas_items"',
  'window/stretch/aspect="expand"',
  'window/handheld/orientation=4',
  'pointing/emulate_touch_from_mouse=true',
  'textures/canvas_textures/default_texture_filter=0',
  'renderer/rendering_method="gl_compatibility"',
];
const project = readFileSync('apps/game/project.godot', 'utf8').split('\n');
for (const locked of LOCKED) {
  if (!project.includes(locked)) {
    const key = locked.split('=')[0];
    const actual = project.find((l) => l.startsWith(key + '=')) ?? 'missing';
    problems.push(`apps/game/project.godot: expected ${locked}, got ${actual}`);
  }
}

// --- 9. iOS release uses the App Store method --------------------------------
// Enterprise does not show up on a device debug build but blocks App Store IAP shipping.
const iosExport = readFileSync('apps/game/export_presets.cfg', 'utf8').split('\n');
const appStoreReleaseMethod = 'application/export_method_release=0';
if (!iosExport.includes(appStoreReleaseMethod)) {
  const actual =
    iosExport.find((line) => line.startsWith('application/export_method_release=')) ?? 'missing';
  problems.push(
    `apps/game/export_presets.cfg: expected ${appStoreReleaseMethod}, got ${actual}`
  );
}

// --- 10. Music imported as looping ------------------------------------------
// `.ogg` import defaults to loop=false. If it snaps back, music plays one
// loop then goes quiet, while the game still runs, so no other check catches it.
for (const file of tracked.filter((f) => /audio\/music\/.*\.ogg\.import$/.test(f))) {
  if (!readFileSync(file, 'utf8').includes('loop=true'))
    problems.push(`${file}: loop=true is missing — music will play one loop and stop`);
}

// --- 11. Values landed in `.env.example` ------------------------------------
// This file is committed. `.env` is ignored, so it is easy to think this file
// is safe too — it is the opposite. Once committed, deleting the file does
// not remove it from git history, and a leaked Android keystore password
// cannot be rotated — Play treats the signing key as the app's identity.
// So only `NAME=` is allowed; anything to the right is blocked.
if (tracked.includes('.env.example')) {
  const lines = readFileSync('.env.example', 'utf8').split('\n');
  lines.forEach((line, index) => {
    const trimmed = line.trim();
    if (trimmed === '' || trimmed.startsWith('#')) return;
    const match = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(trimmed);
    if (match === null) {
      problems.push(`.env.example:${index + 1}: neither a comment nor \`NAME=\``);
      return;
    }
    if (match[2] !== '')
      problems.push(
        `.env.example:${index + 1}: ${match[1]} has a value — this file is committed`
      );
  });
}

// --- Result -----------------------------------------------------------------
for (const note of new Set(notes)) console.log(`  (skipped) ${note}`);
if (problems.length > 0) {
  for (const problem of problems) console.error(`  ${problem}`);
  console.error(`repo-rules check failed — ${problems.length} problem(s)`);
  process.exit(1);
}
console.log(
  `repo rules ok — ${tracked.length} tracked · ${clips.length} clip(s) (max ${(biggest / 1024).toFixed(0)}KB) · ${LOCKED.length} project.godot locked value(s)`
);
