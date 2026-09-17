import {
  cpSync,
  existsSync,
  readFileSync,
  readdirSync,
  rmSync,
} from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const CLAUDE_SKILLS = '.claude/skills';
const CODEX_SKILLS = '.agents/skills';

function scanBelow(root, current = root, found = { files: [], nonRegular: [] }) {
  if (!existsSync(current)) return found;
  for (const entry of readdirSync(current, { withFileTypes: true })) {
    const path = join(current, entry.name);
    if (entry.isDirectory()) {
      scanBelow(root, path, found);
    } else if (entry.isFile()) {
      found.files.push(relative(root, path));
    } else {
      found.nonRegular.push(relative(root, path));
    }
  }
  found.files.sort();
  found.nonRegular.sort();
  return found;
}

export function agentSkillSyncProblems(repoRoot = REPO_ROOT) {
  const sourceRoot = join(repoRoot, CLAUDE_SKILLS);
  const targetRoot = join(repoRoot, CODEX_SKILLS);
  const sourceScan = scanBelow(sourceRoot);
  const targetScan = scanBelow(targetRoot);
  const sourceFiles = sourceScan.files;
  const targetFiles = targetScan.files;
  const sourceSet = new Set(sourceFiles);
  const targetSet = new Set(targetFiles);
  const problems = [];

  for (const file of sourceScan.nonRegular) {
    problems.push(`${CLAUDE_SKILLS}/${file}: skill tree may contain regular files only`);
  }
  for (const file of targetScan.nonRegular) {
    problems.push(`${CODEX_SKILLS}/${file}: skill mirror may contain regular files only`);
  }

  for (const file of sourceFiles) {
    if (!targetSet.has(file)) {
      problems.push(`${CODEX_SKILLS}/${file}: missing Codex copy of ${CLAUDE_SKILLS} source`);
      continue;
    }
    const source = readFileSync(join(sourceRoot, file));
    const target = readFileSync(join(targetRoot, file));
    if (!source.equals(target)) {
      problems.push(`${CODEX_SKILLS}/${file}: not byte-identical to ${CLAUDE_SKILLS}/${file}`);
    }
  }

  for (const file of targetFiles) {
    if (!sourceSet.has(file)) {
      problems.push(`${CODEX_SKILLS}/${file}: no matching ${CLAUDE_SKILLS} source`);
    }
  }

  return problems;
}

export function syncAgentSkills(repoRoot = REPO_ROOT) {
  const sourceRoot = join(repoRoot, CLAUDE_SKILLS);
  const targetRoot = join(repoRoot, CODEX_SKILLS);
  if (!existsSync(sourceRoot)) {
    throw new Error(`${CLAUDE_SKILLS} source folder is missing`);
  }

  // .agents/skills is a generated mirror in this repo. Editing it per
  // provider causes drift again, so replace the whole tree from source.
  rmSync(targetRoot, { recursive: true, force: true });
  cpSync(sourceRoot, targetRoot, { recursive: true });
}

export const AGENT_SKILL_SOURCE = CLAUDE_SKILLS;
export const AGENT_SKILL_TARGET = CODEX_SKILLS;
