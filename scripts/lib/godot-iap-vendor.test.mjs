import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const GODOT_IAP_VERSION = '3.5.1';

function readRepoFile(path) {
  return readFileSync(join(REPO_ROOT, path));
}

function sha256(path) {
  return createHash('sha256').update(readRepoFile(path)).digest('hex');
}

function sha256Absolute(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function documentedSha(contents, marker) {
  const markerIndex = contents.indexOf(marker);
  assert.notEqual(markerIndex, -1, `README marker not found: ${marker}`);
  const match = contents.slice(markerIndex + marker.length).match(/`([a-f0-9]{64})`/);
  assert.ok(match, `SHA-256 not found after README marker: ${marker}`);
  return match[1];
}

function assertPinnedFile({ contents, marker, path, expectedSha }) {
  assert.equal(documentedSha(contents, marker), expectedSha);
  assert.equal(sha256(path), expectedSha, `${path} drifted from its pinned SHA-256`);
}

test('godot-iap plugin version stays pinned to 3.5.1', () => {
  const pluginConfig = readRepoFile(
    'apps/game/addons/godot-iap/plugin.cfg',
  ).toString('utf8');
  const version = pluginConfig.match(/^version="([^"]+)"$/m)?.[1];

  assert.equal(version, GODOT_IAP_VERSION);
});

test('Android godot-iap AARs match the documented official binaries', () => {
  const readme = readRepoFile('vendor/godot-iap-android/README.md').toString(
    'utf8',
  );
  assert.match(readme, new RegExp(`godot-iap-${GODOT_IAP_VERSION.replaceAll('.', '\\.')}`));

  for (const pinned of [
    {
      marker: '- official debug AAR:',
      path: 'apps/game/addons/godot-iap/android/GodotIap.debug.aar',
      expectedSha: '3b19b3f8d9839b6e1596b3fbdf7a262ed54acda5983a43e17a85cb142aa4e34a',
    },
    {
      marker: '- official release AAR:',
      path: 'apps/game/addons/godot-iap/android/GodotIap.release.aar',
      expectedSha: '3b19b3f8d9839b6e1596b3fbdf7a262ed54acda5983a43e17a85cb142aa4e34a',
    },
  ]) {
    assertPinnedFile({ contents: readme, ...pinned });
  }
});

test('Moonlit GDScript integration reverses exactly to official 3.5.1', (t) => {
  const readme = readRepoFile('vendor/godot-iap/README.md').toString('utf8');
  const patchPath = 'vendor/godot-iap/0001-moonlit-integration.patch';
  const patchSha = 'afeb152265e5431233930237e5d4edc9c2042d9dfec00b4e0f7c09d251a649da';
  const files = [
    {
      path: 'apps/game/addons/godot-iap/godot_iap.gd',
      officialSha: 'd872fd1d34c9075b761ca6ba2ca90c8d513b8e7d8e94f1e9a96f3b9cf9e7c2cb',
      moonlitSha: '1bf74d123066a932b1cb7baf8fb3eb5c95c6d1166ff8bc6dfa923b0058bb2238',
    },
    {
      path: 'apps/game/addons/godot-iap/godot_iap_plugin.gd',
      officialSha: 'e0eb26b046700c2de24c7800927e0444ecec46e9eeb474c0d3476d865cb0fba0',
      moonlitSha: 'a3eaf879fb9f7b017133e2bffa52dc3e39fae5b44fb7332dbf047986a1c4a50b',
    },
    {
      path: 'apps/game/addons/godot-iap/scripts/fix_ios_embed.sh',
      officialSha: '2b6494b705ce1beb7e23e0e5cfc8d60eff852ea3b6ffb1c72579def15f041807',
      moonlitSha: '06e1f319396196146fcfa7db967e5a82cca4d2011ba5b2ccb6fd51daf2fca249',
    },
  ];

  assert.match(readme, /godot-iap-3\.5\.1/);
  assert.match(readme, /acb7924d6512cdf87a6a51d22bf75cb285f76dc9/);
  assert.match(readme, /types\.gd.*not.*reverse-patch/is);
  assert.match(readme, /var store := IapStore\.UNKNOWN/);
  assert.equal(documentedSha(readme, '- patch SHA-256:'), patchSha);
  assert.equal(sha256(patchPath), patchSha, `${patchPath} drifted`);

  const stagingRoot = mkdtempSync(join(tmpdir(), 'moonlit-godot-iap-vendor-'));
  t.after(() => rmSync(stagingRoot, { recursive: true, force: true }));

  for (const file of files) {
    assert.equal(sha256(file.path), file.moonlitSha, `${file.path} drifted`);
    assert.match(
      readme,
      new RegExp(`${file.officialSha}.*${file.moonlitSha}`),
      `${file.path} provenance row drifted`,
    );
    const stagedPath = join(stagingRoot, file.path);
    mkdirSync(dirname(stagedPath), { recursive: true });
    copyFileSync(join(REPO_ROOT, file.path), stagedPath);
  }

  const reversed = spawnSync(
    'git',
    ['apply', '--reverse', join(REPO_ROOT, patchPath)],
    { cwd: stagingRoot, encoding: 'utf8' },
  );
  assert.equal(
    reversed.status,
    0,
    `Moonlit patch did not reverse cleanly:\n${reversed.stderr || reversed.stdout}`,
  );

  for (const file of files) {
    assert.equal(
      sha256Absolute(join(stagingRoot, file.path)),
      file.officialSha,
      `${file.path} does not reverse to official 3.5.1`,
    );
  }
});

test('iOS godot-iap frameworks and descriptor match documented binaries', () => {
  const readme = readRepoFile('vendor/godot-iap-ios/README.md').toString(
    'utf8',
  );
  assert.match(readme, new RegExp(`godot-iap-${GODOT_IAP_VERSION.replaceAll('.', '\\.')}`));

  for (const pinned of [
    {
      marker: '`godot_iap.gdextension.ios`:',
      path: 'vendor/godot-iap-ios/bin/godot_iap.gdextension.ios',
      expectedSha: '17ceb8eea0298265e8a7569c16ed1ae725d75c07ca6ca3411462ede1045d128c',
    },
    {
      marker: '- official `GodotIap.framework/GodotIap`:',
      path: 'vendor/godot-iap-ios/bin/ios/GodotIap.framework/GodotIap',
      expectedSha: '0e9914201189d1409ad294228986b6751e1f4cb9a2bdd2192b98da8852214dd9',
    },
    {
      marker: '- official `SwiftGodotRuntime.framework/SwiftGodotRuntime`:',
      path: 'vendor/godot-iap-ios/bin/ios/SwiftGodotRuntime.framework/SwiftGodotRuntime',
      expectedSha: '89a1f9306992f6b83be0432c9bdec83454d6cf1393e19b6f4c2b2422bd9253b3',
    },
  ]) {
    assertPinnedFile({ contents: readme, ...pinned });
  }
});
