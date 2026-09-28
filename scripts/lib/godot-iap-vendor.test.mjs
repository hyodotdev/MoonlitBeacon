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
const GODOT_IAP_VERSION = '3.6.1';

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

test(`godot-iap plugin version stays pinned to ${GODOT_IAP_VERSION}`, () => {
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

test(`Moonlit GDScript integration reverses exactly to official ${GODOT_IAP_VERSION}`, (t) => {
  const readme = readRepoFile('vendor/godot-iap/README.md').toString('utf8');
  const patchPath = 'vendor/godot-iap/0001-moonlit-integration.patch';
  const patchSha = '84839a7e1141dbf2b163c2b197c5e9c2f868ffacdecef4347c59c8666874c667';
  const files = [
    {
      path: 'apps/game/addons/godot-iap/godot_iap.gd',
      officialSha: '2bf54bbf119886a607ea1deb2897e9d28de27ca01c7b4f7ca6daebe3a1188bfe',
      moonlitSha: 'e31fdf59e230b7f677c2513a8f6323240a794382ddedf92cde771a93cf3c899d',
    },
    {
      path: 'apps/game/addons/godot-iap/godot_iap_plugin.gd',
      officialSha: '31500d82ee2ed4b78e42fcbc1dd8c28ad5d97419df18b29a72b08bd83bea9ab8',
      moonlitSha: '47ec04b62c99d99addd6e76636143007edd944cc3a6229dd416c92993b9899a6',
    },
  ];
  const unmodified = {
    'types.gd': 'd14c4b108c8af4f5b0b42203706fe83ada10d173e6c862c18e77bb2d69fc7970',
    'android_store.gd': '1b9d4b80e70c2a93811c0fe973aab21b4f2149f0d391f2ca6971ecb603f43ffd',
    'scripts/fix_ios_embed.sh': '1606332b07dcf2aa2b77ae266e476414a62423ce8769368122a52672002d938e',
    'android/GodotIap.gdap': 'b776033d531bb439ca85c69d079f4ca0f82ad2cacd35065318248349492ac806',
  };

  assert.match(readme, /godot-iap-3\.6\.1/);
  assert.match(readme, /c1a3658e12a0bb7de6fdcfb40f0d82df9f68a653/);
  for (const [file, expectedSha] of Object.entries(unmodified)) {
    assertPinnedFile({
      contents: readme,
      marker: `- \`${file}\`:`,
      path: `apps/game/addons/godot-iap/${file}`,
      expectedSha,
    });
  }
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
      `${file.path} does not reverse to official ${GODOT_IAP_VERSION}`,
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
