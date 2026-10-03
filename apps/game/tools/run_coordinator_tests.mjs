// Run the 4.0.0 cloud-coordinator behavior tests isolated from real data.
//
// The coordinator suite writes real Journey/Vault files under user://, so this
// runner mirrors run_cloud_tests.mjs isolation: a temporary HOME/XDG_DATA_HOME
// plus MOONLIT_VAULT_TEST_ROOT, passed only to the test process. It never
// touches the shared regression runner, which stays unregistered by brief
// order; the director runs this file separately until integration.
//
// Usage:
//   node apps/game/tools/run_coordinator_tests.mjs

import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { reportGodotNotFound, resolveGodot } from '../../../scripts/godot.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repository = resolve(here, '../../..');
const temporaryHome = mkdtempSync(join(tmpdir(), 'moonlit-coord-test-'));

const checks = [
  ['Cloud coordinator owned-journey orchestration', 'res://tests/test_cloud_coordinator.tscn'],
];

let status = 1;
try {
  const search = resolveGodot();
  if (!search.bin) {
    reportGodotNotFound(search);
    process.exitCode = 127;
  } else {
    status = 0;
    for (const [label, scene] of checks) {
      console.log(`\n[${label}]`);
      const run = spawnSync(search.bin, [
        '--headless',
        '--path', resolve(repository, 'apps/game'),
        scene,
      ], {
        cwd: repository,
        encoding: 'utf8',
        maxBuffer: 10 * 1024 * 1024,
        shell: false,
        env: {
          ...process.env,
          HOME: temporaryHome,
          XDG_DATA_HOME: join(temporaryHome, '.local', 'share'),
          APPDATA: join(temporaryHome, 'AppData', 'Roaming'),
          MOONLIT_VAULT_TEST_ROOT: temporaryHome,
        },
      });
      if (run.stdout) process.stdout.write(run.stdout);
      if (run.stderr) process.stderr.write(run.stderr);
      status = run.status ?? 1;
      const engineOutput = `${run.stdout ?? ''}\n${run.stderr ?? ''}`;
      if (status === 0 && engineOutput.includes('ERROR:')) {
        console.error(`[${label}] Found Godot ERROR logs.`);
        status = 1;
      }
      if (status !== 0) break;
    }
    process.exitCode = status;
  }
} finally {
  if (temporaryHome.startsWith(join(tmpdir(), 'moonlit-coord-test-'))) {
    rmSync(temporaryHome, { recursive: true, force: true });
  }
}
