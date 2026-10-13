#!/usr/bin/env node
// Scaffold a standalone course practice project for Lessons 1-8.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  MAX_LESSON,
  MIN_LESSON,
  executePlan,
  parseCreateArgs,
  planCreation,
  printHelp,
} from './lib/course-practice.mjs';

const repository = dirname(dirname(fileURLToPath(import.meta.url)));

function loadManifest() {
  const path = join(repository, 'examples', 'course', 'src', 'manifest.json');
  return JSON.parse(readFileSync(path, 'utf8'));
}

function listLessons(manifest) {
  for (let n = MIN_LESSON; n <= MAX_LESSON; n += 1) {
    const entry = manifest.lessons[String(n)];
    console.log(`Lesson ${n} — ${entry.title}`);
    for (const asset of entry.assets) {
      console.log(`    + ${asset} -> ${manifest.assetDestinations[asset]}`);
    }
  }
}

function main(argv) {
  let args;
  try {
    args = parseCreateArgs(argv);
  } catch (error) {
    console.error(`course-create: ${error.message}`);
    process.exitCode = 2;
    return;
  }
  if (args.help) {
    printHelp();
    return;
  }
  const manifest = loadManifest();
  if (args.list) {
    listLessons(manifest);
    return;
  }
  let plan;
  try {
    plan = planCreation({ repoRoot: repository, lesson: args.lesson, out: args.out, manifest });
  } catch (error) {
    console.error(`course-create: ${error.message}`);
    process.exitCode = 2;
    return;
  }
  const result = executePlan(plan);
  console.log(`Lesson ${args.lesson} practice project: ${result.files} files -> ${result.target}`);
  console.log(`Open ${result.target} in Godot 4.7.1+ and run the title scene.`);
}

main(process.argv.slice(2));
