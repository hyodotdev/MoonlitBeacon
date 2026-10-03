// Run the 4.0.0 owned-cloud behavior tests isolated from real user data.
//
// The cloud local-store test writes user:// files, so this runner mirrors
// run_regression_tests.mjs isolation: a temporary HOME/XDG_DATA_HOME/APPDATA
// plus MOONLIT_VAULT_TEST_ROOT, passed only to the test process. It never
// touches the existing regression runner, which the cloud brief forbids
// changing; the director runs this file separately until integration.
//
// Usage:
//   node apps/game/tools/run_cloud_tests.mjs

import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { reportGodotNotFound, resolveGodot } from '../../../scripts/godot.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repository = resolve(here, '../../..');
const temporaryHome = mkdtempSync(join(tmpdir(), 'moonlit-cloud-test-'));

const checks = [
  ['Cloud transport bounds and statuses', 'res://tests/test_cloud_transport.gd'],
  ['Cloud identity registration and restore', 'res://tests/test_cloud_identity.gd'],
  ['Cloud checkpoint queue, guards, and conflicts', 'res://tests/test_cloud_checkpoint.gd'],
  ['Cloud Hall best score, board, and rank', 'res://tests/test_cloud_hall.gd'],
  ['Cloud account deletion order and local store', 'res://tests/test_cloud_account.gd'],
];

let status = 1;
try {
  const search = resolveGodot();
  if (!search.bin) {
    reportGodotNotFound(search);
    process.exitCode = 127;
  } else {
    status = 0;
    for (const [label, script] of checks) {
      console.log(`\n[${label}]`);
      const run = spawnSync(search.bin, [
        '--headless',
        '--path', resolve(repository, 'apps/game'),
        '--script', script,
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
  if (temporaryHome.startsWith(join(tmpdir(), 'moonlit-cloud-test-'))) {
    rmSync(temporaryHome, { recursive: true, force: true });
  }
}
