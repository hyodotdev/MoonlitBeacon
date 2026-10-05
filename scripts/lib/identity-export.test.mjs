import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  APPLE_SIGNIN_ENTITLEMENT_KEY,
  APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML,
  ENTITLEMENTS_ADDITIONAL_KEY,
  appleEntitlementMarkerPath,
  appleIosExportReady,
  appleSignInGranted,
  assertAppleSignInProfileSupport,
  cleanupIdentityExport,
  extraEntitlementsGrantAppleSignIn,
  generatedEntitlementsPromiseAppleSignIn,
  identityNativeArtifactStatus,
  identityPluginEnabledForPreset,
  prepareIdentityExport,
  recoverStaleAppleEntitlementGrant,
  restoreTemporaryAppleEntitlement,
  shouldStageAppleEntitlement,
  stageTemporaryAppleEntitlement,
  stageTemporaryAppleEntitlementSource,
} from './identity-export.mjs';
import { identityConfigPaths, resolvePublicIdentityConfig } from './player-identity-build.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, '../..');

function withTempRoot(run) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-identity-export-'));
  try {
    run(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const FAKE_IOS_CLIENT_ID = '123456789012-zyxwvutsrqponmlkjihg.apps.googleusercontent.com';
const FAKE_PROJECT = 'moonlit-test-123';
const FAKE_SENDER = '123456789012';
const FAKE_IOS_KEY = `AIza${'B'.repeat(35)}`;
const FAKE_IOS_APP = '1:123456789012:ios:abcdef123456';

function iosAppleEnv() {
  return {
    MOONLIT_GOOGLE_IOS_CLIENT_ID: FAKE_IOS_CLIENT_ID,
    MOONLIT_APPLE_IOS_ENABLED: 'true',
    MOONLIT_FIREBASE_PROJECT_ID: FAKE_PROJECT,
    MOONLIT_FIREBASE_SENDER_ID: FAKE_SENDER,
    MOONLIT_FIREBASE_IOS_API_KEY: FAKE_IOS_KEY,
    MOONLIT_FIREBASE_IOS_APP_ID: FAKE_IOS_APP,
  };
}

const PRESET_PLUGIN_ON = `
[preset.1]

name="iOS"
platform="iOS"

[preset.1.options]

plugins/GodotIap=true
plugins/MoonlitIdentity=true
application/bundle_identifier="com.example.game"
`;

const PRESET_PLUGIN_OFF = `
[preset.1]

name="iOS"
platform="iOS"

[preset.1.options]

plugins/GodotIap=true
plugins/MoonlitIdentity=false
`;

const FAKE_ENTITLEMENTS = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.application-identifier</key>
    <string>TEAMID.com.example.game</string>
    <key>com.apple.security.get-task-allow</key>
    <false/>
</dict>
</plist>
`;

test('prepare stages public config when identifiers exist, skips when empty', () => {
  withTempRoot((root) => {
    const staged = prepareIdentityExport({
      root,
      platform: 'ios',
      env: iosAppleEnv(),
    });
    assert.equal(staged.verdict.ok, true);
    assert.match(staged.report, /provider ios\/apple: READY/u);
    assert.ok(staged.installed);
    const paths = identityConfigPaths(root);
    assert.match(readFileSync(paths.installed, 'utf8'), /\[apple\]/u);
    assert.match(readFileSync(paths.installed, 'utf8'), /ios_enabled="true"/u);
    const cleaned = cleanupIdentityExport({ root });
    assert.equal(cleaned.removed.length, 2);
    assert.equal(existsSync(paths.installed), false, 'installed config is gone');
    assert.equal(existsSync(paths.staged), false, 'staged copy is gone');
  });
  withTempRoot((root) => {
    const empty = prepareIdentityExport({ root, platform: 'android', env: {} });
    assert.equal(empty.verdict.ok, false);
    assert.equal(empty.installed, null);
    const paths = identityConfigPaths(root);
    assert.equal(existsSync(paths.installed), false);
    const cleaned = cleanupIdentityExport({ root });
    assert.equal(cleaned.removed.length, 0);
  });
});

test('prepare stages partial config on malformed values without printing them', () => {
  withTempRoot((root) => {
    const secret = 'definitely-not-a-client-id';
    const partial = prepareIdentityExport({
      root,
      platform: 'ios',
      env: { ...iosAppleEnv(), MOONLIT_GOOGLE_IOS_CLIENT_ID: secret },
    });
    // A broken Google value must not block the Apple/guest export: the
    // config still stages, the report names the variable, and the value
    // appears nowhere.
    assert.equal(partial.verdict.ok, false);
    assert.ok(partial.installed);
    assert.match(partial.report, /MOONLIT_GOOGLE_IOS_CLIENT_ID/u);
    assert.equal(partial.report.includes(secret), false);
    assert.equal(partial.report.includes(FAKE_IOS_KEY), false);
    assert.equal(appleIosExportReady(partial.resolution), true);
    cleanupIdentityExport({ root });
  });
});

test('apple readiness needs the flag, firebase config, and the export plugin', () => {
  const ready = iosAppleEnv();
  const resolveEnv = (env) => resolvePublicIdentityConfig({ env });
  assert.equal(appleIosExportReady(resolveEnv(ready)), true);
  assert.equal(
    appleIosExportReady(resolveEnv({ ...ready, MOONLIT_APPLE_IOS_ENABLED: 'false' })),
    false,
  );
  assert.equal(appleIosExportReady(resolveEnv({ ...ready, MOONLIT_APPLE_IOS_ENABLED: '' })), false);
  assert.equal(
    appleIosExportReady(resolveEnv({ ...ready, MOONLIT_FIREBASE_IOS_API_KEY: 'bogus' })),
    false,
  );
  assert.equal(appleIosExportReady(resolveEnv({})), false);
  assert.equal(identityPluginEnabledForPreset(PRESET_PLUGIN_ON, 'iOS'), true);
  assert.equal(identityPluginEnabledForPreset(PRESET_PLUGIN_OFF, 'iOS'), false);
  assert.equal(identityPluginEnabledForPreset('[preset.0]\nname="Android"\n', 'iOS'), false);
  assert.equal(
    shouldStageAppleEntitlement({
      resolution: resolveEnv(ready),
      exportPresetsSource: PRESET_PLUGIN_ON,
    }),
    true,
  );
  assert.equal(
    shouldStageAppleEntitlement({
      resolution: resolveEnv(ready),
      exportPresetsSource: PRESET_PLUGIN_OFF,
    }),
    false,
  );
  assert.equal(
    shouldStageAppleEntitlement({
      resolution: resolveEnv({}),
      exportPresetsSource: PRESET_PLUGIN_ON,
    }),
    false,
  );
});

function assertSingleLineInserted(before, after, expectedLine) {
  const beforeLines = before.split('\n');
  const afterLines = after.split('\n');
  assert.equal(afterLines.length, beforeLines.length + 1);
  let at = 0;
  while (at < beforeLines.length && beforeLines[at] === afterLines[at]) at += 1;
  assert.equal(afterLines[at], expectedLine);
  assert.deepEqual(afterLines.slice(at + 1), beforeLines.slice(at));
  return at;
}

function assertSingleLineRewritten(before, after, expectedLine) {
  const beforeLines = before.split('\n');
  const afterLines = after.split('\n');
  assert.equal(afterLines.length, beforeLines.length);
  const differing = beforeLines
    .map((line, index) => (line === afterLines[index] ? -1 : index))
    .filter((index) => index >= 0);
  assert.deepEqual(differing.length, 1);
  assert.equal(afterLines[differing[0]], expectedLine);
  return differing[0];
}

test('temporary grant stages through the preset extras hook, preserving bytes', () => {
  // The real locked presets: proves the surgery on actual bytes.
  const plain = readFileSync(join(REPO_ROOT, 'apps/game/export_presets.cfg'), 'utf8');
  const staged = stageTemporaryAppleEntitlementSource(plain);
  assert.equal(staged.applied, true);
  const stagedLine = `${ENTITLEMENTS_ADDITIONAL_KEY}="${staged.hadKey ? `${staged.previousRaw}\\n` : ''}${APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML}"`;
  if (!staged.hadKey) {
    const at = assertSingleLineInserted(plain, staged.source, stagedLine);
    // The line lands after the last iOS option, before the blank separator.
    assert.equal(plain.split('\n')[at], '');
    assert.equal(staged.source.split('\n')[at + 1], '');
  } else {
    assertSingleLineRewritten(plain, staged.source, stagedLine);
  }
  // The staged value carries the exact grant the profile gate expects.
  assert.equal(
    extraEntitlementsGrantAppleSignIn(
      staged.source.split('\n').find((line) => line.startsWith(`${ENTITLEMENTS_ADDITIONAL_KEY}=`)),
    ),
    true,
  );
  assert.throws(
    () => stageTemporaryAppleEntitlementSource(plain, 'NoSuchPreset'),
    /not found/u,
  );
});

test('pre-existing extra XML is preserved byte for byte, never duplicated', () => {
  const previousRaw = '<key>com.example.first</key><true/>\\n<key>com.example.second</key><string>a\\"b\\\\c</string>';
  const fixture = [
    '[preset.0]',
    '',
    'name="Android"',
    'platform="Android"',
    '',
    '[preset.0.options]',
    '',
    'plugins/GodotIap=true',
    '',
    '[preset.1]',
    '',
    'name="iOS"',
    'platform="iOS"',
    '',
    '[preset.1.options]',
    '',
    'plugins/MoonlitIdentity=true',
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${previousRaw}"`,
    'capabilities/access_wifi=false',
    '',
    '[preset.2]',
    '',
    'name="Android Play"',
    'platform="Android"',
    '',
    '[preset.2.options]',
    '',
    'plugins/GodotIap=true',
    '',
  ].join('\n');
  const staged = stageTemporaryAppleEntitlementSource(fixture);
  assert.equal(staged.applied, true);
  assert.equal(staged.hadKey, true);
  assert.equal(staged.previousRaw, previousRaw);
  const expected = `${ENTITLEMENTS_ADDITIONAL_KEY}="${previousRaw}\\n${APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML}"`;
  assertSingleLineRewritten(fixture, staged.source, expected);
  // Empty extras take the bare grant.
  const emptyFixture = fixture.replace(
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${previousRaw}"`,
    `${ENTITLEMENTS_ADDITIONAL_KEY}=""`,
  );
  const emptyStaged = stageTemporaryAppleEntitlementSource(emptyFixture);
  assert.equal(emptyStaged.previousRaw, '');
  assertSingleLineRewritten(
    emptyFixture,
    emptyStaged.source,
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML}"`,
  );
  // The exact grant already present (even escaped multiline) stages nothing.
  const grantedRaw = '<key>com.apple.developer.applesignin</key>\\n<array>\\n<string>Default</string>\\n</array>';
  const grantedFixture = fixture.replace(
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${previousRaw}"`,
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${grantedRaw}"`,
  );
  const granted = stageTemporaryAppleEntitlementSource(grantedFixture);
  assert.equal(granted.applied, false);
  assert.equal(granted.source, grantedFixture);
  // Other applesignin values are refused, never altered or duplicated.
  const foreignRaw = '<key>com.apple.developer.applesignin</key><array><string>Other</string></array>';
  const foreignFixture = fixture.replace(
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${previousRaw}"`,
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${foreignRaw}"`,
  );
  assert.throws(
    () => stageTemporaryAppleEntitlementSource(foreignFixture),
    /unexpected values/u,
  );
  const bareFixture = fixture.replace(
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${previousRaw}"`,
    `${ENTITLEMENTS_ADDITIONAL_KEY}="<key>com.apple.developer.applesignin</key>"`,
  );
  assert.throws(
    () => stageTemporaryAppleEntitlementSource(bareFixture),
    /unexpected values/u,
  );
  // Malformed extras lines are refused untouched.
  for (const [label, badLine] of [
    ['unterminated', `${ENTITLEMENTS_ADDITIONAL_KEY}="<key>com.example.a</key>`],
    ['trailing text', `${ENTITLEMENTS_ADDITIONAL_KEY}="<key>com.example.a</key>" trailing`],
    ['unquoted', `${ENTITLEMENTS_ADDITIONAL_KEY}=<key>com.example.a</key>`],
  ]) {
    const badFixture = fixture.replace(
      `${ENTITLEMENTS_ADDITIONAL_KEY}="${previousRaw}"`,
      badLine,
    );
    assert.throws(
      () => stageTemporaryAppleEntitlementSource(badFixture),
      /quoted string|unterminated|trailing text/u,
      label,
    );
  }
  const noOptions = '[preset.0]\n\nname="iOS"\nplatform="iOS"\n';
  assert.throws(
    () => stageTemporaryAppleEntitlementSource(noOptions),
    /no options section/u,
  );
});

function writePresetFixture(root) {
  const gameDir = join(root, 'apps/game');
  mkdirSync(gameDir, { recursive: true });
  const plain = readFileSync(join(REPO_ROOT, 'apps/game/export_presets.cfg'), 'utf8');
  const presetsPath = join(gameDir, 'export_presets.cfg');
  writeFileSync(presetsPath, plain);
  return { presetsPath, plain };
}

test('preset staging round-trips through the marker, including a killed wrapper', () => {
  withTempRoot((root) => {
    const { presetsPath, plain } = writePresetFixture(root);
    const staged = stageTemporaryAppleEntitlement({ root });
    assert.equal(staged.staged, true);
    assert.equal(staged.presetsPath, presetsPath);
    assert.equal(staged.previous, plain);
    const markerPath = appleEntitlementMarkerPath(root);
    assert.equal(existsSync(markerPath), true);
    const marker = JSON.parse(readFileSync(markerPath, 'utf8'));
    assert.equal(marker.preset, 'iOS');
    assert.equal(
      readFileSync(presetsPath, 'utf8').includes(APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML),
      true,
    );
    assert.equal(
      restoreTemporaryAppleEntitlement({ root, presetsPath, previous: staged.previous }),
      true,
    );
    assert.equal(readFileSync(presetsPath, 'utf8'), plain, 'orderly restore is byte-exact');
    assert.equal(existsSync(markerPath), false);
    // A killed wrapper leaves the marker plus the patched preset and no
    // in-memory state; the next under-lock run recovers exact bytes.
    const killed = stageTemporaryAppleEntitlement({ root });
    assert.equal(killed.staged, true);
    const recovered = recoverStaleAppleEntitlementGrant({ root });
    assert.equal(recovered.recovered, true);
    assert.equal(readFileSync(presetsPath, 'utf8'), plain, 'kill recovery is byte-exact');
    assert.equal(existsSync(markerPath), false);
    assert.deepEqual(recoverStaleAppleEntitlementGrant({ root }), {
      recovered: false,
      note: 'no marker',
    });
  });
});

test('stale recovery restores previous extras and leaves foreign state alone', () => {
  withTempRoot((root) => {
    const { presetsPath, plain } = writePresetFixture(root);
    // Killed after staging onto pre-existing extras: previous XML returns.
    const previousRaw = '<key>com.example.keep</key><true/>';
    const stagedLines = stageTemporaryAppleEntitlementSource(plain).source.split('\n');
    const keyAt = stagedLines.findIndex(
      (line) => line.startsWith(`${ENTITLEMENTS_ADDITIONAL_KEY}=`),
    );
    assert.ok(keyAt >= 0, 'staged fixture carries the extras line');
    stagedLines[keyAt] = `${ENTITLEMENTS_ADDITIONAL_KEY}="${previousRaw}"`;
    const withExtras = stagedLines.join('\n');
    writeFileSync(presetsPath, withExtras);
    const staged = stageTemporaryAppleEntitlement({ root });
    assert.equal(staged.staged, true);
    const marker = JSON.parse(readFileSync(appleEntitlementMarkerPath(root), 'utf8'));
    assert.equal(marker.hadKey, true);
    assert.equal(marker.previousRaw, previousRaw);
    const recovered = recoverStaleAppleEntitlementGrant({ root });
    assert.deepEqual(recovered, { recovered: true, note: 'previous extras restored' });
    assert.equal(readFileSync(presetsPath, 'utf8'), withExtras);
    // Marker but preset already restored: clear quietly, touch nothing.
    stageTemporaryAppleEntitlement({ root });
    writeFileSync(presetsPath, withExtras);
    const already = recoverStaleAppleEntitlementGrant({ root });
    assert.deepEqual(already, { recovered: false, note: 'preset already restored' });
    assert.equal(readFileSync(presetsPath, 'utf8'), withExtras);
    // Externally changed extras: leave the foreign bytes, clear the marker.
    stageTemporaryAppleEntitlement({ root });
    const foreign = readFileSync(presetsPath, 'utf8').replace(
      APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML,
      '<key>com.example.foreign</key><true/>',
    );
    writeFileSync(presetsPath, foreign);
    const left = recoverStaleAppleEntitlementGrant({ root });
    assert.deepEqual(left, { recovered: false, note: 'preset externally changed; left alone' });
    assert.equal(readFileSync(presetsPath, 'utf8'), foreign);
    assert.equal(existsSync(appleEntitlementMarkerPath(root)), false);
    // An unreadable marker is removed without touching presets.
    writeFileSync(appleEntitlementMarkerPath(root), 'not json');
    const unreadable = recoverStaleAppleEntitlementGrant({ root });
    assert.deepEqual(unreadable, { recovered: false, note: 'unreadable marker removed' });
    assert.equal(existsSync(appleEntitlementMarkerPath(root)), false);
  });
});

test('generated entitlements gate still keys the profile check', () => {
  assert.equal(generatedEntitlementsPromiseAppleSignIn(FAKE_ENTITLEMENTS), false);
  assert.equal(extraEntitlementsGrantAppleSignIn(FAKE_ENTITLEMENTS), false);
  const granted = FAKE_ENTITLEMENTS.replace(
    '</dict>',
    `${APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML}\n</dict>`,
  );
  assert.equal(generatedEntitlementsPromiseAppleSignIn(granted), true);
  assert.equal(extraEntitlementsGrantAppleSignIn(granted), true);
});

test('profile support fails truthfully only when the grant is required', () => {
  assert.equal(assertAppleSignInProfileSupport(null, { required: false }), true);
  assert.equal(
    assertAppleSignInProfileSupport(
      { [APPLE_SIGNIN_ENTITLEMENT_KEY]: ['Default'] },
      { required: true },
    ),
    true,
  );
  assert.equal(appleSignInGranted({ [APPLE_SIGNIN_ENTITLEMENT_KEY]: ['Default', 'Extra'] }), true);
  assert.equal(appleSignInGranted({}), false);
  assert.equal(appleSignInGranted(null), false);
  assert.throws(
    () => assertAppleSignInProfileSupport({}, { required: true }),
    /signing profile lacks/u,
  );
  assert.throws(
    () => assertAppleSignInProfileSupport(
      { [APPLE_SIGNIN_ENTITLEMENT_KEY]: ['Other'] },
      { required: true },
    ),
    /signing profile lacks/u,
  );
});

test('artifact status reports bridge presence without failing', () => {
  withTempRoot((root) => {
    const missing = identityNativeArtifactStatus({ root, platform: 'android', variant: 'release' });
    assert.equal(missing.length, 1);
    assert.equal(missing[0].present, false);
    assert.match(missing[0].path, /MoonlitIdentity\.release\.aar/u);
    mkdirSync(join(root, 'apps/game/addons/moonlit-identity/android'), { recursive: true });
    writeFileSync(
      join(root, 'apps/game/addons/moonlit-identity/android/MoonlitIdentity.release.aar'),
      'fake-aar',
    );
    const present = identityNativeArtifactStatus({ root, platform: 'android', variant: 'release' });
    assert.equal(present[0].present, true);
    const ios = identityNativeArtifactStatus({ root, platform: 'ios', variant: 'debug' });
    assert.match(ios[0].path, /libmoonlit_identity\.debug\.a/u);
    assert.throws(
      () => identityNativeArtifactStatus({ root, platform: 'web', variant: 'release' }),
      /Unknown identity export platform/u,
    );
  });
});

test('ordinary export wrappers stage and clean identity config', () => {
  for (const wrapper of ['scripts/android-build.mjs', 'scripts/ios.mjs']) {
    const source = readFileSync(join(REPO_ROOT, wrapper), 'utf8');
    assert.match(source, /prepareIdentityExport/u, `${wrapper} runs identity preflight`);
    assert.match(source, /cleanupIdentityExport/u, `${wrapper} guarantees identity cleanup`);
    assert.match(
      source,
      /redactIdentitySecrets/u,
      `${wrapper} never prints config values`,
    );
  }
  const iosSource = readFileSync(join(REPO_ROOT, 'scripts/ios.mjs'), 'utf8');
  assert.match(
    iosSource,
    /stageTemporaryAppleEntitlement/u,
    'ios export stages the temporary preset grant when Apple is ready',
  );
  assert.match(
    iosSource,
    /restoreTemporaryAppleEntitlement/u,
    'ios export restores exact preset bytes after the run',
  );
  assert.match(
    iosSource,
    /recoverStaleAppleEntitlementGrant/u,
    'ios export recovers killed preset staging under lock',
  );
  assert.match(
    iosSource,
    /assertAppleSignInProfileSupport/u,
    'ios build verifies profile support truthfully',
  );
});

function exportPluginFunctions(source) {
  // Split the MoonlitIdentityExportPlugin class body into named method
  // blocks: each starts at a one-tab `func` line and runs to the next.
  const classAt = source.indexOf('class MoonlitIdentityExportPlugin');
  assert.ok(classAt >= 0, 'export plugin class is present');
  const body = source.slice(classAt);
  const starts = [...body.matchAll(/^\tfunc (\w+)\(/gmu)].map((match) => ({
    name: match[1],
    at: match.index,
  }));
  assert.ok(starts.length > 0, 'export plugin defines methods');
  return starts.map((entry, index) => ({
    name: entry.name,
    source: body.slice(
      entry.at,
      index + 1 < starts.length ? starts[index + 1].at : body.length,
    ),
  }));
}

test('export plugin stages the public identity config into the build', () => {
  const source = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/moonlit_identity_plugin.gd'),
    'utf8',
  );
  const configPath = source.match(
    /^[ \t]*const IDENTITY_CONFIG_PATH: String = "([^"]+)"$/mu,
  )?.[1];
  assert.equal(
    configPath,
    'res://moonlit_identity.cfg',
    'export plugin names the staged public config',
  );
  const methods = exportPluginFunctions(source);
  const staging = methods.filter((method) => method.source.includes(
    'add_file(\n\t\t\tIDENTITY_CONFIG_PATH,',
  ));
  assert.equal(
    staging.length,
    1,
    'exactly one export method stages the identity config file',
  );
  assert.match(
    staging[0].source,
    /FileAccess\.file_exists\(IDENTITY_CONFIG_PATH\)/u,
    'config staging skips silently when the wrapper staged nothing',
  );
  assert.match(
    staging[0].source,
    /get_file_as_bytes\(IDENTITY_CONFIG_PATH\)/u,
    'config stages as bytes, never stringified for logs',
  );
  const begin = methods.find((method) => method.name === '_export_begin');
  assert.ok(begin, 'export plugin defines _export_begin');
  assert.ok(
    begin.source.includes(`${staging[0].name}()`),
    '_export_begin reaches the config staging on every supported platform',
  );
});

test('export plugin never prints identity config values', () => {
  const source = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/moonlit_identity_plugin.gd'),
    'utf8',
  );
  const methods = exportPluginFunctions(source);
  for (const method of methods) {
    if (!method.source.includes('IDENTITY_CONFIG_PATH')) continue;
    assert.equal(
      /print\(/u.test(method.source.replace(
        /print\("\[MoonlitIdentity\] Public identity config found\."\)/u,
        '',
      )),
      false,
      `${method.name} prints nothing but the presence line`,
    );
    assert.equal(
      method.source.includes('get_file_as_string'),
      false,
      `${method.name} never reads the config as a printable string`,
    );
  }
});

test('staged config path agrees across installer, exporter, and runtime', () => {
  // A rename on any side breaks the chain silently: the wrapper would
  // stage a file the exporter never packs or the runtime never reads.
  const installed = identityConfigPaths(join(REPO_ROOT, 'probe-root')).installed;
  assert.equal(
    installed,
    join(REPO_ROOT, 'probe-root', 'apps/game/moonlit_identity.cfg'),
    'installer stages res://moonlit_identity.cfg for one export',
  );
  for (const file of [
    'apps/game/addons/moonlit-identity/moonlit_identity_plugin.gd',
    'apps/game/addons/moonlit-identity/moonlit_identity.gd',
  ]) {
    const source = readFileSync(join(REPO_ROOT, file), 'utf8');
    const path = source.match(
      /^[ \t]*(?:const IDENTITY_CONFIG_PATH|const CONFIG_PATH): String = "([^"]+)"$/mu,
    )?.[1];
    assert.equal(
      path,
      'res://moonlit_identity.cfg',
      `${file} reads the staged public config`,
    );
  }
});

test('real iOS preset opts into identity; incomplete Apple config still refuses', () => {
  const real = readFileSync(join(REPO_ROOT, 'apps/game/export_presets.cfg'), 'utf8');
  // Exactly one opt-in line in the whole file: the iOS options section,
  // immediately below the purchase plugin line. Both Android presets stay
  // without it.
  assert.equal(
    real.split('\n').filter((line) => line === 'plugins/MoonlitIdentity=true').length,
    1,
    'one identity opt-in in the real presets',
  );
  const blocks = real.split(/^\[preset\.\d+\]$/mu);
  const iosBlock = blocks.find((block) => /^name="iOS"$/mu.test(block));
  assert.ok(iosBlock, 'real presets contain the iOS preset');
  const iosLines = iosBlock.split('\n');
  const iapAt = iosLines.findIndex((line) => line === 'plugins/GodotIap=true');
  assert.ok(iapAt >= 0, 'iOS preset keeps the purchase plugin line');
  assert.equal(
    iosLines[iapAt + 1],
    'plugins/MoonlitIdentity=true',
    'identity opt-in sits directly below the purchase plugin line',
  );
  for (const block of blocks) {
    if (/^name="Android/mu.test(block)) {
      assert.equal(
        block.includes('plugins/MoonlitIdentity'),
        false,
        'Android presets carry no identity opt-in',
      );
    }
  }
  assert.equal(identityPluginEnabledForPreset(real, 'iOS'), true);
  assert.equal(identityPluginEnabledForPreset(real, 'Android'), false);
  assert.equal(identityPluginEnabledForPreset(real, 'Android Play'), false);
  // The fully configured fixture stages through every existing readiness
  // check against the real presets — and only then.
  const resolveEnv = (env) => resolvePublicIdentityConfig({ env });
  const ready = iosAppleEnv();
  assert.equal(
    shouldStageAppleEntitlement({ resolution: resolveEnv(ready), exportPresetsSource: real }),
    true,
  );
  // Each genuinely incomplete Apple config still refuses, opt-in or not.
  for (const [label, env] of [
    ['empty', {}],
    ['flag false', { ...ready, MOONLIT_APPLE_IOS_ENABLED: 'false' }],
    ['flag blank', { ...ready, MOONLIT_APPLE_IOS_ENABLED: '' }],
    ['bad ios key', { ...ready, MOONLIT_FIREBASE_IOS_API_KEY: 'bogus' }],
    ['missing ios app id', { ...ready, MOONLIT_FIREBASE_IOS_APP_ID: '' }],
  ]) {
    assert.equal(
      shouldStageAppleEntitlement({ resolution: resolveEnv(env), exportPresetsSource: real }),
      false,
      label,
    );
  }
  // The gate reads the real flag: flipping just that line back to false
  // refuses a fully configured export.
  const optedOut = real.replace(
    'plugins/MoonlitIdentity=true',
    'plugins/MoonlitIdentity=false',
  );
  assert.notEqual(optedOut, real, 'opt-out variant differs by the one line');
  assert.equal(
    shouldStageAppleEntitlement({ resolution: resolveEnv(ready), exportPresetsSource: optedOut }),
    false,
  );
});
