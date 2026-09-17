#!/usr/bin/env node
import {
  AGENT_SKILL_SOURCE,
  AGENT_SKILL_TARGET,
  agentSkillSyncProblems,
  syncAgentSkills,
} from './lib/agent-skill-sync.mjs';

const mode = process.argv[2] ?? '--check';
if (!['--check', '--write'].includes(mode) || process.argv.length > 3) {
  console.error('Usage: node scripts/sync-agent-skills.mjs [--check|--write]');
  process.exit(2);
}

if (mode === '--write') syncAgentSkills();

const problems = agentSkillSyncProblems();
if (problems.length > 0) {
  for (const problem of problems) console.error(`  ${problem}`);
  console.error(`Claude/Codex skill sync failed — ${problems.length} problem(s)`);
  process.exit(1);
}

console.log(`${AGENT_SKILL_SOURCE} → ${AGENT_SKILL_TARGET} skill bytes in sync`);
