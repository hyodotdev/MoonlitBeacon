import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  BUILD_CHILD_ENV_ALLOWLIST,
  IDENTITY_PINS,
  IDENTITY_REQUIRED_PRIVACY_BUNDLES,
  IOS_STAGED_IMPORT_EXCLUSION,
  NM_SYMBOL_BUFFER_BYTES,
  buildFirebaseLinkTree,
  checkAndroidBuildPrereqs,
  checkIosBuildPrereqs,
  checkPbxprojTemplate,
  checkPodsTargetAgreement,
  checkXmlWellFormed,
  cleanIdentityConfig,
  describeNmFailure,
  discoverFirebaseFrameworks,
  discoverFirebaseResources,
  dryRunIdentityPreflight,
  fetchIosDeps,
  firebaseLinkPaths,
  formatBuildPrereqReport,
  formatPreflightReport,
  gradleMajorMinor,
  identityArtifactPaths,
  identityBuildDirs,
  identityConfigPaths,
  identityIosFrameworksDir,
  identityIosResourcesDir,
  installIdentityConfig,
  iosCompileFlags,
  iosSconsArgs,
  javaMajorVersion,
  podMajorMinor,
  podsAggregateProductName,
  podsAggregateTarget,
  readGitHeadRevision,
  readInstalledIdentityConfig,
  readLibSymbols,
  redactIdentitySecrets,
  renderAndroidPluginProject,
  renderIdentityConfigFile,
  renderIosBridgeProject,
  renderIosDepsProject,
  resolvePublicIdentityConfig,
  runBridgeBuild,
  sanitizedBuildEnv,
  stageIosFrameworks,
  stageIosResources,
  validateIdentityConfig,
  verifyAndroidArtifact,
  verifyIosArtifact,
  verifyIosExportInputs,
  writeIosStagingImportExclusion,
} from './player-identity-build.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');

const FAKE_GOOGLE_ID = '123456789012-abcdef0123456789ghij.apps.googleusercontent.com';
const FAKE_IOS_CLIENT_ID = '123456789012-zyxwvutsrqponmlkjihg.apps.googleusercontent.com';
const FAKE_APP_ID = '123456789012';
const FAKE_PROJECT = 'moonlit-test-123';
const FAKE_SENDER = '123456789012';
const FAKE_ANDROID_KEY = `AIza${'A'.repeat(35)}`;
const FAKE_ANDROID_APP = '1:123456789012:android:abcdef123456';
const FAKE_IOS_KEY = `AIza${'B'.repeat(35)}`;
const FAKE_IOS_APP = '1:123456789012:ios:abcdef123456';
const FAKE_APPLE_SVC = 'com.example.moonlit.signin';

function withTempRoot(run) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-identity-'));
  try {
    mkdirSync(join(root, 'apps/game'), { recursive: true });
    run(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function fullEnv() {
  return {
    MOONLIT_PLAY_SERVER_CLIENT_ID: FAKE_GOOGLE_ID,
    MOONLIT_PLAY_APP_ID: FAKE_APP_ID,
    MOONLIT_GOOGLE_IOS_CLIENT_ID: FAKE_IOS_CLIENT_ID,
    MOONLIT_APPLE_ANDROID_ENABLED: 'true',
    MOONLIT_APPLE_IOS_ENABLED: 'true',
    MOONLIT_APPLE_SERVICE_ID: FAKE_APPLE_SVC,
    MOONLIT_FIREBASE_PROJECT_ID: FAKE_PROJECT,
    MOONLIT_FIREBASE_SENDER_ID: FAKE_SENDER,
    MOONLIT_FIREBASE_ANDROID_API_KEY: FAKE_ANDROID_KEY,
    MOONLIT_FIREBASE_ANDROID_APP_ID: FAKE_ANDROID_APP,
    MOONLIT_FIREBASE_IOS_API_KEY: FAKE_IOS_KEY,
    MOONLIT_FIREBASE_IOS_APP_ID: FAKE_IOS_APP,
  };
}

function androidEnv() {
  return {
    MOONLIT_PLAY_SERVER_CLIENT_ID: FAKE_GOOGLE_ID,
    MOONLIT_PLAY_APP_ID: FAKE_APP_ID,
    MOONLIT_APPLE_ANDROID_ENABLED: 'true',
    MOONLIT_FIREBASE_PROJECT_ID: FAKE_PROJECT,
    MOONLIT_FIREBASE_SENDER_ID: FAKE_SENDER,
    MOONLIT_FIREBASE_ANDROID_API_KEY: FAKE_ANDROID_KEY,
    MOONLIT_FIREBASE_ANDROID_APP_ID: FAKE_ANDROID_APP,
  };
}

function iosEnv() {
  return {
    MOONLIT_GOOGLE_IOS_CLIENT_ID: FAKE_IOS_CLIENT_ID,
    MOONLIT_APPLE_IOS_ENABLED: 'true',
    MOONLIT_FIREBASE_PROJECT_ID: FAKE_PROJECT,
    MOONLIT_FIREBASE_SENDER_ID: FAKE_SENDER,
    MOONLIT_FIREBASE_IOS_API_KEY: FAKE_IOS_KEY,
    MOONLIT_FIREBASE_IOS_APP_ID: FAKE_IOS_APP,
  };
}

test('resolves all public identifiers from the environment', () => {
  const resolution = resolvePublicIdentityConfig({ env: fullEnv() });
  assert.equal(resolution.google.value, FAKE_GOOGLE_ID);
  assert.equal(resolution.googleIosClient.value, FAKE_IOS_CLIENT_ID);
  assert.equal(resolution.appleAndroidEnabled.value, 'true');
  assert.equal(resolution.appleIosEnabled.value, 'true');
  assert.equal(resolution.appleService.value, FAKE_APPLE_SVC);
  assert.equal(resolution.firebaseProject.value, FAKE_PROJECT);
  assert.equal(resolution.firebaseAndroidKey.value, FAKE_ANDROID_KEY);
  assert.equal(resolution.firebaseIosApp.value, FAKE_IOS_APP);
  assert.equal(validateIdentityConfig(resolution, 'all').ok, true);
});

test('missing identifiers resolve as absent, not empty-string present', () => {
  const resolution = resolvePublicIdentityConfig({ env: {} });
  assert.equal(resolution.google.present, false);
  assert.equal(resolution.googleIosClient.present, false);
  assert.equal(resolution.appleAndroidEnabled.present, false);
  assert.equal(resolution.appleIosEnabled.present, false);
  assert.equal(resolution.firebaseIosKey.present, false);
  const verdict = validateIdentityConfig(resolution, 'all');
  assert.equal(verdict.ok, false);
  assert.ok(verdict.missing.includes('MOONLIT_PLAY_SERVER_CLIENT_ID'));
  assert.ok(verdict.missing.includes('MOONLIT_GOOGLE_IOS_CLIENT_ID'));
  assert.ok(verdict.missing.includes('MOONLIT_APPLE_ANDROID_ENABLED'));
  assert.ok(verdict.missing.includes('MOONLIT_APPLE_IOS_ENABLED'));
  assert.ok(verdict.missing.includes('MOONLIT_FIREBASE_PROJECT_ID'));
  assert.ok(verdict.missing.includes('MOONLIT_FIREBASE_IOS_API_KEY'));
  assert.ok(!verdict.missing.includes('MOONLIT_APPLE_SERVICE_ID'));
});

test('android needs the play id plus firebase android config', () => {
  const android = resolvePublicIdentityConfig({ env: androidEnv() });
  assert.equal(validateIdentityConfig(android, 'android').ok, true);
  assert.equal(validateIdentityConfig(android, 'ios').ok, false);
  const noPlay = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_PLAY_SERVER_CLIENT_ID: '' },
  });
  const verdict = validateIdentityConfig(noPlay, 'android');
  assert.equal(verdict.ok, false);
  assert.deepEqual(verdict.missing, ['MOONLIT_PLAY_SERVER_CLIENT_ID']);
});

test('android needs the numeric play app id for the manifest stamp', () => {
  const noAppId = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_PLAY_APP_ID: '' },
  });
  const missing = validateIdentityConfig(noAppId, 'android');
  assert.equal(missing.ok, false);
  assert.deepEqual(missing.missing, ['MOONLIT_PLAY_APP_ID']);
  const malformed = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_PLAY_APP_ID: 'not-numeric!' },
  });
  const verdict = validateIdentityConfig(malformed, 'android');
  assert.equal(verdict.ok, false);
  assert.equal(verdict.errors.length, 1);
  assert.match(verdict.errors[0], /MOONLIT_PLAY_APP_ID/);
  // iOS never needs the Play app id.
  const ios = resolvePublicIdentityConfig({ env: iosEnv() });
  assert.equal(validateIdentityConfig(ios, 'ios').ok, true);
});

test('ios needs firebase ios config and no services id', () => {
  const ios = resolvePublicIdentityConfig({ env: iosEnv() });
  assert.equal(validateIdentityConfig(ios, 'ios').ok, true);
  assert.equal(validateIdentityConfig(ios, 'android').ok, false);
  const noKey = resolvePublicIdentityConfig({
    env: { ...iosEnv(), MOONLIT_FIREBASE_IOS_API_KEY: '' },
  });
  const verdict = validateIdentityConfig(noKey, 'ios');
  assert.equal(verdict.ok, false);
  assert.ok(verdict.missing.includes('MOONLIT_FIREBASE_IOS_API_KEY'));
});

test('a malformed services id is a note, never a readiness block', () => {
  const resolution = resolvePublicIdentityConfig({
    env: { ...fullEnv(), MOONLIT_APPLE_SERVICE_ID: 'no-dots-here' },
  });
  const verdict = validateIdentityConfig(resolution, 'all');
  assert.equal(verdict.ok, true);
  assert.equal(verdict.errors.length, 0);
  assert.equal(verdict.notes.length, 1);
  assert.match(verdict.notes[0], /MOONLIT_APPLE_SERVICE_ID/);
});

test('a wrong-shaped google id is an error, not a silent accept', () => {
  const resolution = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_PLAY_SERVER_CLIENT_ID: 'not-a-web-client-id' },
  });
  const verdict = validateIdentityConfig(resolution, 'android');
  assert.equal(verdict.ok, false);
  assert.equal(verdict.missing.length, 0);
  assert.equal(verdict.errors.length, 1);
  assert.match(verdict.errors[0], /MOONLIT_PLAY_SERVER_CLIENT_ID/);
});

test('a wrong-shaped ios client id is an error naming the variable', () => {
  const resolution = resolvePublicIdentityConfig({
    env: { ...iosEnv(), MOONLIT_GOOGLE_IOS_CLIENT_ID: 'com.example.bundle' },
  });
  const verdict = validateIdentityConfig(resolution, 'ios');
  assert.equal(verdict.ok, false);
  assert.equal(verdict.missing.length, 0);
  assert.equal(verdict.errors.length, 1);
  assert.match(verdict.errors[0], /MOONLIT_GOOGLE_IOS_CLIENT_ID/);
});

test('the apple android flag acknowledges only an explicit true', () => {
  const absent = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_APPLE_ANDROID_ENABLED: '' },
  });
  const missing = validateIdentityConfig(absent, 'android');
  assert.equal(missing.ok, false);
  assert.ok(missing.missing.includes('MOONLIT_APPLE_ANDROID_ENABLED'));
  assert.equal(missing.errors.length, 0);
  for (const off of ['false', '0']) {
    const declined = resolvePublicIdentityConfig({
      env: { ...androidEnv(), MOONLIT_APPLE_ANDROID_ENABLED: off },
    });
    const verdict = validateIdentityConfig(declined, 'android');
    assert.equal(verdict.ok, false);
    assert.ok(verdict.missing.includes('MOONLIT_APPLE_ANDROID_ENABLED'));
    assert.equal(verdict.errors.length, 0);
  }
  const garbage = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_APPLE_ANDROID_ENABLED: 'maybe' },
  });
  const bad = validateIdentityConfig(garbage, 'android');
  assert.equal(bad.ok, false);
  assert.equal(bad.errors.length, 1);
  assert.match(bad.errors[0], /MOONLIT_APPLE_ANDROID_ENABLED/);
  const enabled = resolvePublicIdentityConfig({ env: androidEnv() });
  assert.equal(validateIdentityConfig(enabled, 'android').ok, true);
});

test('the apple ios flag acknowledges only an explicit true', () => {
  const absent = resolvePublicIdentityConfig({
    env: { ...iosEnv(), MOONLIT_APPLE_IOS_ENABLED: '' },
  });
  const missing = validateIdentityConfig(absent, 'ios');
  assert.equal(missing.ok, false);
  assert.ok(missing.missing.includes('MOONLIT_APPLE_IOS_ENABLED'));
  assert.equal(missing.errors.length, 0);
  for (const off of ['false', '0']) {
    const declined = resolvePublicIdentityConfig({
      env: { ...iosEnv(), MOONLIT_APPLE_IOS_ENABLED: off },
    });
    const verdict = validateIdentityConfig(declined, 'ios');
    assert.equal(verdict.ok, false);
    assert.ok(verdict.missing.includes('MOONLIT_APPLE_IOS_ENABLED'));
    assert.equal(verdict.errors.length, 0);
  }
  const garbage = resolvePublicIdentityConfig({
    env: { ...iosEnv(), MOONLIT_APPLE_IOS_ENABLED: 'maybe' },
  });
  const bad = validateIdentityConfig(garbage, 'ios');
  assert.equal(bad.ok, false);
  assert.equal(bad.errors.length, 1);
  assert.match(bad.errors[0], /MOONLIT_APPLE_IOS_ENABLED/);
  const enabled = resolvePublicIdentityConfig({ env: iosEnv() });
  assert.equal(validateIdentityConfig(enabled, 'ios').ok, true);
});

test('providers gate independently of each other', () => {
  const full = resolvePublicIdentityConfig({ env: fullEnv() });
  const ready = validateIdentityConfig(full, 'all').providers;
  assert.equal(ready.android.google.ready, true);
  assert.equal(ready.android.play_games.ready, true);
  assert.equal(ready.android.apple.ready, true);
  assert.equal(ready.ios.google.ready, true);
  assert.equal(ready.ios.apple.ready, true);
  // No Google web id: Android Google and Play Games refuse, Apple stands.
  const noGoogle = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_PLAY_SERVER_CLIENT_ID: '' },
  });
  const googleOut = validateIdentityConfig(noGoogle, 'android').providers;
  assert.equal(googleOut.android.google.ready, false);
  assert.ok(googleOut.android.google.missing.includes('MOONLIT_PLAY_SERVER_CLIENT_ID'));
  assert.equal(googleOut.android.play_games.ready, false);
  assert.equal(googleOut.android.apple.ready, true);
  // No Play app id: only the gaming profile refuses; Google stands.
  const noAppId = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_PLAY_APP_ID: '' },
  });
  const playOut = validateIdentityConfig(noAppId, 'android').providers;
  assert.equal(playOut.android.google.ready, true);
  assert.equal(playOut.android.apple.ready, true);
  assert.equal(playOut.android.play_games.ready, false);
  assert.ok(playOut.android.play_games.missing.includes('MOONLIT_PLAY_APP_ID'));
  // No Apple acknowledgement: only Apple refuses; Google stands.
  const noApple = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_APPLE_ANDROID_ENABLED: 'false' },
  });
  const appleOut = validateIdentityConfig(noApple, 'android').providers;
  assert.equal(appleOut.android.google.ready, true);
  assert.equal(appleOut.android.play_games.ready, true);
  assert.equal(appleOut.android.apple.ready, false);
  // No iOS client id: iOS Google refuses while Apple stands.
  const noIosClient = resolvePublicIdentityConfig({
    env: { ...iosEnv(), MOONLIT_GOOGLE_IOS_CLIENT_ID: '' },
  });
  const iosOut = validateIdentityConfig(noIosClient, 'ios').providers;
  assert.equal(iosOut.ios.google.ready, false);
  assert.ok(iosOut.ios.google.missing.includes('MOONLIT_GOOGLE_IOS_CLIENT_ID'));
  assert.equal(iosOut.ios.apple.ready, true);
  // No iOS Apple acknowledgement: only Apple refuses; Google stands.
  const noIosApple = resolvePublicIdentityConfig({
    env: { ...iosEnv(), MOONLIT_APPLE_IOS_ENABLED: '' },
  });
  const iosAppleOut = validateIdentityConfig(noIosApple, 'ios').providers;
  assert.equal(iosAppleOut.ios.google.ready, true);
  assert.equal(iosAppleOut.ios.apple.ready, false);
  assert.ok(iosAppleOut.ios.apple.missing.includes('MOONLIT_APPLE_IOS_ENABLED'));
  // No Firebase: every provider on the platform refuses together.
  const noFirebase = resolvePublicIdentityConfig({
    env: { ...iosEnv(), MOONLIT_FIREBASE_IOS_API_KEY: '' },
  });
  const dark = validateIdentityConfig(noFirebase, 'ios').providers;
  assert.equal(dark.ios.google.ready, false);
  assert.equal(dark.ios.apple.ready, false);
  assert.ok(dark.ios.apple.missing.includes('MOONLIT_FIREBASE_IOS_API_KEY'));
});

test('wrong-shaped firebase values are errors naming the variable', () => {
  const resolution = resolvePublicIdentityConfig({
    env: {
      ...androidEnv(),
      MOONLIT_FIREBASE_PROJECT_ID: 'UPPERCASE!',
      MOONLIT_FIREBASE_ANDROID_API_KEY: 'not-an-api-key',
      MOONLIT_FIREBASE_ANDROID_APP_ID: '1:123:web:zzz',
    },
  });
  const verdict = validateIdentityConfig(resolution, 'android');
  assert.equal(verdict.ok, false);
  assert.equal(verdict.errors.length, 3);
  assert.ok(verdict.errors.some((line) => line.includes('MOONLIT_FIREBASE_PROJECT_ID')));
  assert.ok(verdict.errors.some((line) => line.includes('MOONLIT_FIREBASE_ANDROID_API_KEY')));
  assert.ok(verdict.errors.some((line) => line.includes('MOONLIT_FIREBASE_ANDROID_APP_ID')));
});

test('unknown platforms are rejected', () => {
  const resolution = resolvePublicIdentityConfig({ env: fullEnv() });
  assert.throws(() => validateIdentityConfig(resolution, 'windows'), /Unknown identity platform/);
});

test('preflight names missing config without printing values', () => {
  const empty = resolvePublicIdentityConfig({ env: {} });
  const report = formatPreflightReport(empty, { platform: 'all' });
  assert.match(report, /MOONLIT_PLAY_SERVER_CLIENT_ID: MISSING/);
  assert.match(report, /MOONLIT_FIREBASE_IOS_API_KEY: MISSING/);
  assert.match(report, /MOONLIT_APPLE_SERVICE_ID: MISSING \(server-side, optional\)/);
  assert.match(report, /MOONLIT_GOOGLE_IOS_CLIENT_ID: MISSING/);
  assert.match(report, /MOONLIT_APPLE_ANDROID_ENABLED: MISSING/);
  assert.match(report, /MOONLIT_APPLE_IOS_ENABLED: MISSING/);
  assert.match(report, /provider android\/google: NOT READY/);
  assert.match(report, /provider ios\/apple: NOT READY/);
  assert.match(report, /result: NOT READY/);
  assert.match(report, /guest play are unaffected/);

  const full = resolvePublicIdentityConfig({ env: fullEnv() });
  const ready = formatPreflightReport(full, { platform: 'all' });
  assert.match(ready, /result: READY/);
  assert.match(ready, /provider android\/google: READY/);
  assert.match(ready, /provider android\/play_games: READY/);
  assert.match(ready, /provider android\/apple: READY/);
  assert.match(ready, /provider ios\/google: READY/);
  assert.match(ready, /provider ios\/apple: READY/);
  for (const secret of [FAKE_GOOGLE_ID, FAKE_IOS_CLIENT_ID, FAKE_APP_ID, FAKE_PROJECT, FAKE_ANDROID_KEY, FAKE_IOS_APP, FAKE_APPLE_SVC]) {
    assert.ok(!ready.includes(secret), 'report must not contain a value');
  }
  assert.match(ready, /set \(\d+ chars\)/);

  const partial = resolvePublicIdentityConfig({
    env: { ...androidEnv(), MOONLIT_APPLE_ANDROID_ENABLED: '' },
  });
  const mixed = formatPreflightReport(partial, { platform: 'android' });
  assert.match(mixed, /provider android\/google: READY/);
  assert.match(mixed, /provider android\/apple: NOT READY \(missing MOONLIT_APPLE_ANDROID_ENABLED\)/);
  assert.match(mixed, /result: NOT READY/);
});

test('dry-run writes nothing', () => {
  withTempRoot((root) => {
    const before = identityConfigPaths(root);
    assert.equal(existsSync(before.installed), false);
    const { report, ok } = dryRunIdentityPreflight({ env: {}, platform: 'all' });
    assert.equal(ok, false);
    assert.match(report, /NOT READY/);
    assert.equal(existsSync(before.installed), false);
    assert.equal(existsSync(before.staged), false);
  });
});

test('install writes a readable config and clean removes every trace', () => {
  withTempRoot((root) => {
    const resolution = resolvePublicIdentityConfig({ env: fullEnv() });
    const paths = installIdentityConfig({ root, resolution });
    assert.equal(existsSync(paths.installed), true);
    assert.equal(existsSync(paths.staged), true);
    const body = readFileSync(paths.installed, 'utf8');
    assert.match(body, /server_client_id="123456789012-abcdef0123456789ghij\.apps\.googleusercontent\.com"/);
    assert.match(body, /play_app_id="123456789012"/);
    assert.match(body, /ios_client_id="123456789012-zyxwvutsrqponmlkjihg\.apps\.googleusercontent\.com"/);
    assert.match(body, /project_id="moonlit-test-123"/);
    assert.match(body, new RegExp(`android_api_key="${FAKE_ANDROID_KEY}"`));
    assert.match(body, /ios_app_id="1:123456789012:ios:abcdef123456"/);
    assert.match(body, /^\[apple\]$/m);
    assert.match(body, /^android_enabled="true"$/m);
    assert.match(body, /^ios_enabled="true"$/m);
    assert.ok(!body.includes(FAKE_APPLE_SVC), 'services id is server-side; never staged');
    assert.match(body, /Do not commit/);
    assert.equal(readInstalledIdentityConfig(root), body);
    const { removed } = cleanIdentityConfig({ root });
    assert.equal(removed.length, 2);
    assert.equal(existsSync(paths.installed), false);
    assert.equal(existsSync(paths.staged), false);
    assert.equal(readInstalledIdentityConfig(root), null);
  });
});

test('rendered config matches the wrapper section and key names', () => {
  const resolution = resolvePublicIdentityConfig({ env: fullEnv() });
  const body = renderIdentityConfigFile(resolution);
  assert.match(body, /^\[google\]$/m);
  assert.match(body, /^\[apple\]$/m);
  assert.match(body, /^\[firebase\]$/m);
  assert.match(body, /^server_client_id="/m);
  assert.match(body, /^play_app_id="/m);
  assert.match(body, /^ios_client_id="/m);
  assert.match(body, /^android_enabled="true"$/m);
  assert.match(body, /^ios_enabled="true"$/m);
  assert.match(body, /^project_id="/m);
  assert.match(body, /^sender_id="/m);
  assert.match(body, /^android_api_key="/m);
  assert.match(body, /^android_app_id="/m);
  assert.match(body, /^ios_api_key="/m);
  assert.match(body, /^ios_app_id="/m);
});

test('rendered config normalizes the apple flag and keeps partial keys', () => {
  for (const [flag, want] of [['1', 'true'], ['true', 'true'], ['false', ''], ['0', ''], ['', ''], ['maybe', '']]) {
    const resolution = resolvePublicIdentityConfig({
      env: { ...androidEnv(), MOONLIT_APPLE_ANDROID_ENABLED: flag },
    });
    const body = renderIdentityConfigFile(resolution);
    assert.match(body, new RegExp(`^android_enabled="${want}"$`, 'm'), `flag ${flag} stages as ${want}`);
  }
  for (const [flag, want] of [['1', 'true'], ['true', 'true'], ['false', ''], ['0', ''], ['', ''], ['maybe', '']]) {
    const resolution = resolvePublicIdentityConfig({
      env: { ...iosEnv(), MOONLIT_APPLE_IOS_ENABLED: flag },
    });
    const body = renderIdentityConfigFile(resolution);
    assert.match(body, new RegExp(`^ios_enabled="${want}"$`, 'm'), `ios flag ${flag} stages as ${want}`);
  }
  const partial = resolvePublicIdentityConfig({
    env: { ...iosEnv(), MOONLIT_GOOGLE_IOS_CLIENT_ID: '' },
  });
  const body = renderIdentityConfigFile(partial);
  assert.match(body, /^ios_client_id=""$/m);
  assert.match(body, /^project_id="moonlit-test-123"$/m);
});

test('pins repeat into the gradle, gdap, scons, and pod templates', () => {
  const android = (name) => readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android', name), 'utf8');
  const ios = (name) => readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios', name), 'utf8');
  assert.match(android('root-build.gradle.tmpl'), new RegExp(IDENTITY_PINS.androidGradlePlugin));
  assert.match(android('root-build.gradle.tmpl'), new RegExp(IDENTITY_PINS.kotlin));
  assert.match(android('gradle-wrapper.properties.tmpl'), new RegExp(`gradle-${IDENTITY_PINS.gradle}-bin`));
  assert.match(android('build.gradle.tmpl'), new RegExp(`compileSdk ${IDENTITY_PINS.compileSdk}`));
  assert.match(android('build.gradle.tmpl'), new RegExp(`minSdk ${IDENTITY_PINS.minSdk}`));
  assert.match(android('build.gradle.tmpl'), new RegExp(`godot:${IDENTITY_PINS.godotAndroidLib}`));
  assert.match(android('MoonlitIdentity.gdap'), new RegExp(`games-v2:${IDENTITY_PINS.playServicesGamesV2}`));
  assert.match(android('MoonlitIdentity.gdap'), new RegExp(`firebase-auth:${IDENTITY_PINS.firebaseAuthAndroid}`));
  assert.match(android('MoonlitIdentity.gdap'), new RegExp(`credentials:credentials:${IDENTITY_PINS.credentialsAndroid}`));
  assert.match(android('MoonlitIdentity.gdap'), new RegExp(`credentials-play-services-auth:${IDENTITY_PINS.credentialsPlayServicesAuth}`));
  assert.match(android('MoonlitIdentity.gdap'), new RegExp(`googleid:googleid:${IDENTITY_PINS.googleIdAndroid}`));
  assert.match(android('MoonlitIdentity.gdap'), new RegExp(`kotlinx-coroutines-android:${IDENTITY_PINS.coroutinesAndroid}`));
  assert.match(android('build.gradle.tmpl'), new RegExp(`kotlinx-coroutines-android:${IDENTITY_PINS.coroutinesAndroid}`));
  assert.match(android('build.gradle.tmpl'), new RegExp(`credentials:credentials:${IDENTITY_PINS.credentialsAndroid}`));
  assert.match(android('build.gradle.tmpl'), new RegExp(`credentials-play-services-auth:${IDENTITY_PINS.credentialsPlayServicesAuth}`));
  assert.match(android('build.gradle.tmpl'), new RegExp(`googleid:googleid:${IDENTITY_PINS.googleIdAndroid}`));
  assert.match(android('AndroidManifest.xml.tmpl'), /org\.godotengine\.plugin\.v2\.MoonlitIdentity/);
  assert.match(android('AndroidManifest.xml.tmpl'), /dev\.moonlitbeacon\.identity\.MoonlitIdentityPlugin/);
  assert.match(ios('Podfile.tmpl'), new RegExp(`FirebaseAuth', '${IDENTITY_PINS.firebaseAuthIos}'`));
  assert.match(ios('Podfile.tmpl'), new RegExp(`GoogleSignIn', '${IDENTITY_PINS.googleSignInIos}'`));
  assert.match(ios('Podfile.tmpl'), new RegExp(`platform :ios, '${IDENTITY_PINS.iosPodsPlatform}'`));
  assert.match(ios('Podfile.tmpl'), /use_frameworks! :linkage => :static/);
  assert.match(ios('SConstruct.tmpl'), new RegExp(IDENTITY_PINS.godotCppTag));
  assert.match(ios('SConstruct.tmpl'), new RegExp(IDENTITY_PINS.godotCppRev));
  assert.match(ios('SConstruct.tmpl'), /libtool -static/);
  assert.match(ios('SConstruct.tmpl'), /FIREBASE_PODS_DIR/);
  assert.match(ios('SConstruct.tmpl'), /MoonlitLink\/firebase-flags\.json/);
  assert.ok(!/env\.Append\(FRAMEWORKPATH/.test(ios('SConstruct.tmpl')),
    'FRAMEWORKPATH never reached the compile; explicit -F does');
  assert.match(ios('SConstruct.tmpl'), /CCFLAGS=\["-F" \+ frameworks_dir\]/);
  assert.match(ios('SConstruct.tmpl'), /"-fmodules",/);
  assert.match(ios('SConstruct.tmpl'), /"-fcxx-modules",/);
  assert.match(ios('SConstruct.tmpl'), /fmodules-cache-path/);
  assert.match(ios('SConstruct.tmpl'), /frameworks_dir/);
  assert.ok(!ios('SConstruct.tmpl').includes('Headers/Public'),
    'no assumed CocoaPods header layout; the link tree is discovered');
  assert.match(ios('SConstruct.tmpl'), /Do NOT pass a custom_api_file/,
    'the 4.7.1 dump prohibition is documented (that generator collides)');
  assert.ok(!/custom_api_file\s*=/.test(ios('SConstruct.tmpl')),
    'no custom api file is ever passed to the build');
  assert.match(ios('SConstruct.tmpl'), /arm64/);
  assert.ok(!ios('SConstruct.tmpl').includes('x86_64'), 'device-only: no simulator arch');
});

test('google sign-in pins match the official documentation examples', () => {
  // Firebase's Android Google-sign-in example pins these exact versions;
  // the iOS pin is the GoogleSignIn release contemporary with FirebaseAuth
  // 11.0.0 and the documented configuration/callback integration.
  assert.equal(IDENTITY_PINS.credentialsAndroid, '1.3.0');
  assert.equal(IDENTITY_PINS.credentialsPlayServicesAuth, '1.3.0');
  assert.equal(IDENTITY_PINS.googleIdAndroid, '1.1.1');
  assert.equal(IDENTITY_PINS.coroutinesAndroid, '1.10.1');
  assert.equal(IDENTITY_PINS.googleSignInIos, '7.1.0');
  const scons = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/SConstruct.tmpl'), 'utf8');
  assert.match(scons, /\["FirebaseAuth", "GoogleSignIn"\]/,
    'the bridge compile requires both frameworks and header sets');
});

test('kotlin compiler matches dependency metadata and resolved stdlib', () => {
  assert.equal(IDENTITY_PINS.kotlin, '2.1.21');
  assert.equal(IDENTITY_PINS.godotKotlinStdlib, '2.1.21');
  assert.equal(IDENTITY_PINS.kotlin, IDENTITY_PINS.godotKotlinStdlib);
  assert.ok(IDENTITY_PINS.kotlin.startsWith(`${IDENTITY_PINS.kotlinMetadata}.`),
    'compiler minor matches the dependencies metadata minor');
  const root = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android/root-build.gradle.tmpl'), 'utf8');
  assert.match(root, new RegExp(`version '${IDENTITY_PINS.kotlin.replaceAll('.', '\\.')}'`));
});

test('godot-cpp pin is the tag that exists, with its exact revision', () => {
  assert.equal(IDENTITY_PINS.godotCppTag, 'godot-4.5-stable');
  assert.equal(IDENTITY_PINS.godotCppRev, 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77');
  assert.equal(IDENTITY_PINS.iosMinVersion, '13.0');
  assert.deepEqual(iosSconsArgs('debug'),
    ['platform=ios', 'arch=arm64', 'target=template_debug', 'ios_min_version=13.0']);
  assert.deepEqual(iosSconsArgs('release'),
    ['platform=ios', 'arch=arm64', 'target=template_release', 'ios_min_version=13.0']);
});

test('android render produces a standalone gradle project', () => {
  withTempRoot((root) => {
    const outDir = join(root, 'builds/moonlit-identity/android');
    const { files } = renderAndroidPluginProject({ root: REPO_ROOT, outDir });
    for (const name of ['settings.gradle', 'build.gradle', 'gradle.properties',
      'gradle/wrapper/gradle-wrapper.properties', 'MoonlitIdentity/build.gradle',
      'MoonlitIdentity/consumer-rules.pro', 'MoonlitIdentity/src/main/AndroidManifest.xml',
      'MoonlitIdentity.gdap']) {
      assert.equal(existsSync(join(outDir, name)), true, `renders ${name}`);
    }
    const kotlin = join(outDir, 'MoonlitIdentity/src/main/kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt');
    assert.equal(existsSync(kotlin), true);
    assert.match(readFileSync(kotlin, 'utf8'), /requestServerSideAccess/);
    assert.ok(files.length >= 9);
  });
});

test('ios render produces a standalone scons project', () => {
  withTempRoot((root) => {
    const outDir = join(root, 'builds/moonlit-identity/ios');
    const { files } = renderIosBridgeProject({ root: REPO_ROOT, outDir });
    for (const name of ['SConstruct', 'src/MoonlitIdentityIos.mm',
      'include/MoonlitIdentityIos.h']) {
      assert.equal(existsSync(join(outDir, name)), true, `renders ${name}`);
    }
    assert.match(readFileSync(join(outDir, 'src/MoonlitIdentityIos.mm'), 'utf8'),
      /revokeTokenWithAuthorizationCode/);
    assert.ok(files.length >= 3);
  });
});

test('ios deps render produces a pod-installable project', () => {
  withTempRoot((root) => {
    const outDir = join(root, 'builds/moonlit-identity/ios-deps');
    const { files } = renderIosDepsProject({ root: REPO_ROOT, outDir });
    assert.equal(existsSync(join(outDir, 'Podfile')), true);
    assert.equal(existsSync(join(outDir, 'FirebasePods.xcodeproj/project.pbxproj')), true);
    assert.ok(files.length >= 2);
  });
});

test('podfile target matches the template xcodeproj target', () => {
  const ios = (name) => readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios', name), 'utf8');
  const podfile = ios('Podfile.tmpl');
  const pbxproj = ios('xcodeproj/project.pbxproj.tmpl');
  assert.match(podfile, /project 'FirebasePods\.xcodeproj'/);
  const agreement = checkPodsTargetAgreement(podfile, pbxproj);
  assert.equal(agreement.ok, true);
  assert.equal(agreement.target, 'MoonlitIdentityPods');
  assert.equal(podsAggregateTarget(agreement.target), 'Pods-MoonlitIdentityPods');
  const broken = checkPodsTargetAgreement(
    podfile.replace('MoonlitIdentityPods', 'SomethingElse'), pbxproj);
  assert.equal(broken.ok, false);
  assert.match(broken.error, /SomethingElse/);
});

test('xcodeproj template carries the keys target inspection needs', () => {
  const pbxproj = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/xcodeproj/project.pbxproj.tmpl'),
    'utf8');
  const verdict = checkPbxprojTemplate(pbxproj, { target: 'MoonlitIdentityPods' });
  assert.deepEqual(verdict.checks, []);
  assert.equal(verdict.ok, true);
});

test('xcodeproj validator rejects each load-bearing defect', () => {
  const pbxproj = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/xcodeproj/project.pbxproj.tmpl'),
    'utf8');
  // The measured CocoaPods crash: missing project path keys.
  const noPaths = checkPbxprojTemplate(
    pbxproj.replace('projectDirPath = ""; projectRoot = ""; ', ''));
  assert.equal(noPaths.ok, false);
  assert.ok(noPaths.checks.some((line) => line.includes('projectDirPath')));
  assert.ok(noPaths.checks.some((line) => line.includes('projectRoot')));
  const noTarget = checkPbxprojTemplate(pbxproj, { target: 'Missing' });
  assert.equal(noTarget.ok, false);
  assert.ok(noTarget.checks.some((line) => line.includes('Missing')));
  const noRelease = checkPbxprojTemplate(pbxproj.replaceAll('name = Release;', 'name = Beta;'));
  assert.equal(noRelease.ok, false);
  assert.ok(noRelease.checks.some((line) => line.includes('Release')));
  const withLdflags = checkPbxprojTemplate(
    pbxproj.replace('SKIP_INSTALL = YES;', 'SKIP_INSTALL = YES; OTHER_LDFLAGS = "-ObjC";'));
  assert.equal(withLdflags.ok, false);
  assert.ok(withLdflags.checks.some((line) => line.includes('OTHER_LDFLAGS')));
  const dangling = checkPbxprojTemplate(
    pbxproj.replace('1A2B3C4D000000000000000D /* Products */', 'AAAAAAAAAAAAAAAAAAAAAAAA /* Gone */'));
  assert.equal(dangling.ok, false);
  assert.ok(dangling.checks.some((line) => line.includes('dangling')));
});

test('build dirs and artifact paths stay under ignored and addon roots', () => {
  const dirs = identityBuildDirs(REPO_ROOT);
  assert.match(dirs.android, /builds\/moonlit-identity\/android$/);
  assert.match(dirs.ios, /builds\/moonlit-identity\/ios$/);
  const artifacts = identityArtifactPaths(REPO_ROOT);
  assert.match(artifacts.androidReleaseAar, /addons\/moonlit-identity\/android\/MoonlitIdentity\.release\.aar$/);
  assert.match(artifacts.iosReleaseLib, /addons\/moonlit-identity\/bin\/ios\/libmoonlit_identity\.release\.a$/);
});

function throwingExec() {
  return () => { throw new Error('no such command'); };
}

function cannedExec(handlers) {
  return (command) => {
    for (const [prefix, output] of handlers) {
      if (command.startsWith(prefix)) return output;
    }
    throw new Error(`unexpected command: ${command}`);
  };
}

test('java version parsing covers modern, legacy, and missing runtimes', () => {
  assert.equal(javaMajorVersion({ exec: cannedExec([['java -version', 'openjdk version "17.0.9"']]) }), 17);
  assert.equal(javaMajorVersion({ exec: cannedExec([['java -version', 'openjdk version "21.0.1"']]) }), 21);
  assert.equal(javaMajorVersion({ exec: cannedExec([['java -version', 'openjdk version "1.8.0_382"']]) }), 8);
  assert.equal(javaMajorVersion({ exec: throwingExec() }), null);
});

test('android prereqs report every missing piece without values', () => {
  const result = checkAndroidBuildPrereqs({ env: {}, root: REPO_ROOT, exec: throwingExec() });
  assert.equal(result.ok, false);
  assert.ok(result.missing.some((line) => line.startsWith('java')));
  assert.ok(result.missing.some((line) => line.includes('ANDROID_SDK_ROOT')));
  assert.ok(result.missing.some((line) => line.includes('gradle')));
  const report = formatBuildPrereqReport('Android', result);
  assert.match(report, /result: NOT READY/);
});

test('gradle version parsing requires the pinned tool', () => {
  const gradle87 = cannedExec([['gradle --version', '------------------------------------------------------------\nGradle 8.7\n------------------------------------------------------------\n']]);
  assert.equal(gradleMajorMinor({ exec: gradle87 }), '8.7');
  const gradle810 = cannedExec([['gradle --version', 'Gradle 8.10\n']]);
  assert.equal(gradleMajorMinor({ exec: gradle810 }), '8.10');
  assert.equal(gradleMajorMinor({ exec: throwingExec() }), null);
});

test('android prereqs reject a wrong gradle version by name', () => {
  withTempRoot((root) => {
    const sdk = join(root, 'sdk');
    mkdirSync(sdk, { recursive: true });
    const exec = cannedExec([
      ['java -version', 'openjdk version "17.0.9"'],
      ['gradle --version', 'Gradle 8.10\n'],
    ]);
    const result = checkAndroidBuildPrereqs({
      env: { ANDROID_SDK_ROOT: sdk },
      root: REPO_ROOT,
      exec,
    });
    assert.equal(result.ok, false);
    assert.ok(result.missing.some((line) => line === 'gradle 8.7 (found 8.10)'));
  });
});

test('android prereqs pass with a complete fake toolchain', () => {
  withTempRoot((root) => {
    const sdk = join(root, 'sdk');
    mkdirSync(sdk, { recursive: true });
    const exec = cannedExec([
      ['java -version', 'openjdk version "17.0.9"'],
      ['gradle --version', 'Gradle 8.7\n'],
    ]);
    const result = checkAndroidBuildPrereqs({
      env: { ANDROID_SDK_ROOT: sdk },
      root: REPO_ROOT,
      exec,
    });
    assert.equal(result.ok, true);
    assert.match(formatBuildPrereqReport('Android', result), /READY TO BUILD/);
  });
});

test('pod version parsing requires the verified line', () => {
  assert.equal(podMajorMinor({ exec: cannedExec([['pod --version', '1.16.2\n']]) }), '1.16');
  assert.equal(podMajorMinor({ exec: cannedExec([['pod --version', '1.15.2\n']]) }), '1.15');
  assert.equal(podMajorMinor({ exec: throwingExec() }), null);
});

test('ios prereqs report every missing piece without values', () => {
  withTempRoot((root) => {
    // Point the pods dir at a temp empty root: the default builds/
    // location may hold a real fetched link tree, which must not
    // affect this test.
    const result = checkIosBuildPrereqs({
      env: { FIREBASE_PODS_DIR: join(root, 'Pods') },
      root: REPO_ROOT,
      exec: throwingExec(),
    });
    assert.equal(result.ok, false);
    assert.ok(result.missing.some((line) => line.includes('xcodebuild')));
    assert.ok(result.missing.some((line) => line.includes('scons')));
    assert.ok(result.missing.some((line) => line.includes('pod')));
    assert.ok(result.missing.some((line) => line.includes('GODOT_CPP')));
    assert.ok(result.missing.some((line) => line.includes('FirebaseAuth 11.0.0')));
    assert.ok(result.missing.some((line) => line.includes('GoogleSignIn 7.1.0')));
    assert.ok(result.missing.some((line) => line.includes('MoonlitLink')));
    assert.ok(result.notes.some((line) => line.includes('--fetch-deps')));
    assert.match(formatBuildPrereqReport('iOS', result), /result: NOT READY/);
  });
});

function completeIosToolchain(root) {
  const godotCpp = join(root, 'godot-cpp');
  const godotCppLib = join(root, 'godot-cpp-lib');
  const depsRoot = join(root, 'ios-deps');
  const podsDir = join(depsRoot, 'Pods');
  mkdirSync(join(godotCpp, '.git'), { recursive: true });
  mkdirSync(godotCppLib, { recursive: true });
  writeFileSync(join(godotCpp, 'SConstruct'), '# fake\n');
  writeFileSync(join(godotCpp, '.git/HEAD'), `${IDENTITY_PINS.godotCppRev}\n`);
  writeFileSync(join(godotCppLib, 'libgodot-cpp.ios.template_debug.arm64.a'), 'fake');
  writeFileSync(join(godotCppLib, 'libgodot-cpp.ios.template_release.arm64.a'), 'fake');
  const link = firebaseLinkPaths(podsDir);
  mkdirSync(link.linkDir, { recursive: true });
  writeFileSync(link.flagsFile, JSON.stringify({
    variants: {
      debug: { frameworks: ['FirebaseAuth', 'FirebaseCore', 'GoogleSignIn'] },
      release: { frameworks: ['FirebaseAuth', 'FirebaseCore', 'GoogleSignIn'] },
    },
  }));
  return { godotCpp, godotCppLib, podsDir };
}

function iosToolchainExec() {
  return cannedExec([
    ['command -v xcodebuild', '/usr/bin/xcodebuild\n'],
    ['command -v scons', '/usr/local/bin/scons\n'],
    ['command -v pod', '/usr/local/bin/pod\n'],
    ['pod --version', '1.16.2\n'],
  ]);
}

test('ios prereqs pass with a complete fake toolchain', () => {
  withTempRoot((root) => {
    const { godotCpp, godotCppLib, podsDir } = completeIosToolchain(root);
    const result = checkIosBuildPrereqs({
      env: { GODOT_CPP: godotCpp, GODOT_CPP_LIB: godotCppLib, FIREBASE_PODS_DIR: podsDir },
      root: REPO_ROOT,
      exec: iosToolchainExec(),
    });
    assert.equal(result.ok, true);
    assert.match(formatBuildPrereqReport('iOS', result), /READY TO BUILD/);
  });
});

test('ios prereqs reject a wrong godot-cpp revision and pod line', () => {
  withTempRoot((root) => {
    const { godotCpp, godotCppLib, podsDir } = completeIosToolchain(root);
    writeFileSync(join(godotCpp, '.git/HEAD'), `${'0'.repeat(40)}\n`);
    const exec = cannedExec([
      ['command -v xcodebuild', '/usr/bin/xcodebuild\n'],
      ['command -v scons', '/usr/local/bin/scons\n'],
      ['command -v pod', '/usr/local/bin/pod\n'],
      ['pod --version', '1.15.2\n'],
    ]);
    const result = checkIosBuildPrereqs({
      env: { GODOT_CPP: godotCpp, GODOT_CPP_LIB: godotCppLib, FIREBASE_PODS_DIR: podsDir },
      root: REPO_ROOT,
      exec,
    });
    assert.equal(result.ok, false);
    assert.ok(result.missing.some((line) => line.includes('cocoapods 1.16.x (found 1.15)')));
    assert.ok(result.missing.some((line) => line.includes('godot-cpp godot-4.5-stable revision e83fd0904c13')));
  });
});

// The real dependency pods, as built by the director's CocoaPods run: the
// nine Firebase pods plus the GoogleSignIn closure (GoogleSignIn itself
// with its AppAuth/GTMAppAuth companions; GTMSessionFetcher and
// GoogleUtilities are shared with FirebaseAuth).
const NESTED_PODS = [
  'AppAuth',
  'FirebaseAppCheckInterop',
  'FirebaseAuth',
  'FirebaseAuthInterop',
  'FirebaseCore',
  'FirebaseCoreExtension',
  'FirebaseCoreInternal',
  'GTMAppAuth',
  'GTMSessionFetcher',
  'GoogleSignIn',
  'GoogleUtilities',
  'RecaptchaInterop',
];

const BUNDLE_OWNERS = {
  'FirebaseAuth_Privacy.bundle': 'FirebaseAuth',
  'FirebaseCore_Privacy.bundle': 'FirebaseCore',
  'FirebaseCoreExtension_Privacy.bundle': 'FirebaseCoreExtension',
  'FirebaseCoreInternal_Privacy.bundle': 'FirebaseCoreInternal',
  'GTMSessionFetcher_Core_Privacy.bundle': 'GTMSessionFetcher',
  'GoogleUtilities_Privacy.bundle': 'GoogleUtilities',
  'AppAuthCore_Privacy.bundle': 'AppAuth',
  'GTMAppAuth_Privacy.bundle': 'GTMAppAuth',
  'GoogleSignIn.bundle': 'GoogleSignIn',
};

function fakeFrameworkBuild(outDir) {
  // Mirror the real xcodebuild products: each pod nested under its own
  // target dir with its framework, the nine privacy bundles nested beside
  // them (the AppAuthCore/GTMAppAuth/GoogleSignIn names included), and the
  // aggregate scaffolding at the root. Flat fakes missed the nesting defect.
  for (const config of ['Debug', 'Release']) {
    const root = join(outDir, 'Build', `${config}-iphoneos`);
    for (const pod of NESTED_PODS) {
      const headers = join(root, pod, `${pod}.framework`, 'Headers');
      mkdirSync(headers, { recursive: true });
      writeFileSync(join(headers, `${pod}.h`), '// fake umbrella\n');
    }
    for (const [bundle, owner] of Object.entries(BUNDLE_OWNERS)) {
      const dir = join(root, owner, bundle);
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, 'PrivacyInfo.xcprivacy'), `<!-- fake ${bundle} -->\n`);
      writeFileSync(join(dir, 'Info.plist'), '<!-- fake -->\n');
    }
    mkdirSync(join(root, 'Pods_MoonlitIdentityPods.framework'), { recursive: true });
  }
}

test('ios deps fetch installs pods, builds frameworks, and links them', () => {
  withTempRoot((root) => {
    const outDir = join(root, 'ios-deps');
    const seen = [];
    const fetched = fetchIosDeps({
      root: REPO_ROOT,
      outDir,
      spawn: (command, args, options) => {
        seen.push({ command, args, cwd: options.cwd });
        if (command === 'xcodebuild') fakeFrameworkBuild(outDir);
        return { status: 0, stdout: command === 'pod' ? 'Pod installation complete' : '', stderr: '' };
      },
    });
    assert.deepEqual(seen[0].command, 'pod');
    assert.deepEqual(seen[0].args, ['install']);
    assert.equal(seen[0].cwd, outDir);
    const builds = seen.filter((call) => call.command === 'xcodebuild');
    assert.equal(builds.length, 2);
    for (const built of builds) {
      assert.ok(built.args.includes('Pods-MoonlitIdentityPods'));
      assert.ok(built.args.includes('iphoneos'));
      assert.ok(built.args.includes('arm64'));
      assert.ok(built.args.some((arg) => arg.startsWith('SYMROOT=')));
      assert.ok(!built.args.some((arg) => arg.includes('simulator')));
    }
    assert.ok(builds.some((built) => built.args.includes('Debug')));
    assert.ok(builds.some((built) => built.args.includes('Release')));
    assert.equal(existsSync(join(outDir, 'Podfile')), true);
    assert.equal(existsSync(join(outDir, 'FirebasePods.xcodeproj/project.pbxproj')), true);
    assert.equal(fetched.ok, true);
    assert.match(fetched.output, /Pod installation complete/);
    assert.deepEqual(fetched.variants.release.frameworks, NESTED_PODS);
    assert.ok(!fetched.variants.release.frameworks.includes('Pods_MoonlitIdentityPods'),
      'aggregate scaffolding is not a linked dependency');
    assert.match(
      fetched.variants.release.framework_sources.FirebaseAuth,
      new RegExp(`Release-iphoneos${'/'}FirebaseAuth${'/'}FirebaseAuth\\.framework$`),
    );
    assert.deepEqual(
      fetched.variants.release.resources,
      [...IDENTITY_REQUIRED_PRIVACY_BUNDLES].sort(),
    );
    assert.match(
      fetched.variants.release.resource_sources['GTMSessionFetcher_Core_Privacy.bundle'],
      new RegExp(`GTMSessionFetcher${'/'}GTMSessionFetcher_Core_Privacy\\.bundle$`),
    );
    assert.equal(
      existsSync(join(outDir, 'MoonlitLink/Release/Headers/FirebaseAuth/FirebaseAuth.h')),
      true,
    );
  });
});

test('ios deps fetch fails loudly when frameworks never appear', () => {
  withTempRoot((root) => {
    const fetched = fetchIosDeps({
      root: REPO_ROOT,
      outDir: join(root, 'ios-deps'),
      spawn: () => ({ status: 0, stdout: '', stderr: '' }),
    });
    assert.equal(fetched.ok, false);
    assert.ok(fetched.checks.some((line) => line.includes('Debug: missing framework output dir')));
    assert.ok(fetched.checks.some((line) => line.includes('Release: missing framework output dir')));
  });
});

test('ios deps fetch fails loudly when pod install fails', () => {
  withTempRoot((root) => {
    const fetched = fetchIosDeps({
      root: REPO_ROOT,
      outDir: join(root, 'ios-deps'),
      spawn: () => ({ status: 1, stdout: '', stderr: 'boom' }),
    });
    assert.equal(fetched.ok, false);
    assert.ok(fetched.checks.some((line) => line.includes('pod install failed')));
  });
});

test('aggregate product name follows the xcode c99 transform', () => {
  assert.equal(podsAggregateProductName('MoonlitIdentityPods'), 'Pods_MoonlitIdentityPods');
});

test('framework discovery finds the real nested layout', () => {
  withTempRoot((root) => {
    const outDir = join(root, 'ios-deps');
    fakeFrameworkBuild(outDir);
    for (const config of ['Debug', 'Release']) {
      const found = discoverFirebaseFrameworks(
        join(outDir, 'Build', `${config}-iphoneos`),
        { exclude: ['Pods_MoonlitIdentityPods'] },
      );
      assert.deepEqual(found.checks, []);
      assert.equal(found.ok, true);
      assert.deepEqual(found.frameworks, NESTED_PODS);
      assert.equal(found.paths.FirebaseAuth, join('FirebaseAuth', 'FirebaseAuth.framework'));
      assert.equal(found.paths.RecaptchaInterop, join('RecaptchaInterop', 'RecaptchaInterop.framework'));
    }
    const missing = discoverFirebaseFrameworks(join(root, 'nope'));
    assert.equal(missing.ok, false);
  });
});

test('framework discovery skips only the exact aggregate product', () => {
  withTempRoot((root) => {
    const configDir = join(root, 'Release-iphoneos');
    for (const pod of ['FirebaseAuth', 'GoogleSignIn']) {
      mkdirSync(join(configDir, pod, `${pod}.framework/Headers`), { recursive: true });
      writeFileSync(join(configDir, pod, `${pod}.framework/Headers/${pod}.h`), '// fake\n');
    }
    mkdirSync(join(configDir, 'Pods_MoonlitIdentityPods.framework'), { recursive: true });
    mkdirSync(join(configDir, 'Other.framework'), { recursive: true });
    const found = discoverFirebaseFrameworks(configDir, { exclude: ['Pods_MoonlitIdentityPods'] });
    assert.equal(found.ok, true);
    assert.deepEqual(found.frameworks, ['FirebaseAuth', 'GoogleSignIn', 'Other']);
  });
});

test('framework discovery rejects ambiguous duplicates', () => {
  withTempRoot((root) => {
    const configDir = join(root, 'Release-iphoneos');
    for (const dir of ['FirebaseAuth', 'StaleCopy']) {
      mkdirSync(join(configDir, dir, 'FirebaseAuth.framework/Headers'), { recursive: true });
      writeFileSync(join(configDir, dir, 'FirebaseAuth.framework/Headers/FirebaseAuth.h'), '// fake\n');
    }
    const found = discoverFirebaseFrameworks(configDir);
    assert.equal(found.ok, false);
    assert.ok(found.checks.some((line) => line.includes('ambiguous FirebaseAuth.framework')));
    assert.ok(found.checks.some((line) => line.includes('refusing to guess')));
  });
});

test('framework discovery requires both bridge umbrella headers', () => {
  withTempRoot((root) => {
    const configDir = join(root, 'Release-iphoneos');
    mkdirSync(join(configDir, 'FirebaseAuth/FirebaseAuth.framework/Headers'), { recursive: true });
    const bare = discoverFirebaseFrameworks(configDir);
    assert.equal(bare.ok, false);
    assert.ok(bare.checks.some((line) => line.includes('no GoogleSignIn.framework')));
    mkdirSync(join(configDir, 'GoogleSignIn/GoogleSignIn.framework/Headers'), { recursive: true });
    writeFileSync(join(configDir, 'GoogleSignIn/GoogleSignIn.framework/Headers/GoogleSignIn.h'), '// fake\n');
    const noAuthHeader = discoverFirebaseFrameworks(configDir);
    assert.equal(noAuthHeader.ok, false);
    assert.ok(noAuthHeader.checks.some((line) => line.includes('FirebaseAuth.h')));
    writeFileSync(join(configDir, 'FirebaseAuth/FirebaseAuth.framework/Headers/FirebaseAuth.h'), '// fake\n');
    mkdirSync(join(configDir, 'FirebaseCore/FirebaseCore.framework'), { recursive: true });
    const found = discoverFirebaseFrameworks(configDir);
    assert.equal(found.ok, true);
    assert.deepEqual(found.frameworks, ['FirebaseAuth', 'FirebaseCore', 'GoogleSignIn']);
  });
});

test('required privacy set is the measured nine director-built bundles', () => {
  assert.deepEqual(IDENTITY_REQUIRED_PRIVACY_BUNDLES, [
    'FirebaseAuth_Privacy.bundle',
    'FirebaseCore_Privacy.bundle',
    'FirebaseCoreExtension_Privacy.bundle',
    'FirebaseCoreInternal_Privacy.bundle',
    'GTMSessionFetcher_Core_Privacy.bundle',
    'GoogleUtilities_Privacy.bundle',
    'AppAuthCore_Privacy.bundle',
    'GTMAppAuth_Privacy.bundle',
    'GoogleSignIn.bundle',
  ]);
});

test('resource discovery finds the real nested bundle layout', () => {
  withTempRoot((root) => {
    const outDir = join(root, 'ios-deps');
    fakeFrameworkBuild(outDir);
    for (const config of ['Debug', 'Release']) {
      const found = discoverFirebaseResources(join(outDir, 'Build', `${config}-iphoneos`));
      assert.deepEqual(found.checks, []);
      assert.equal(found.ok, true);
      assert.deepEqual(found.resources, [...IDENTITY_REQUIRED_PRIVACY_BUNDLES].sort());
      assert.equal(
        found.paths['GTMSessionFetcher_Core_Privacy.bundle'],
        join('GTMSessionFetcher', 'GTMSessionFetcher_Core_Privacy.bundle'),
      );
    }
  });
});

test('resource discovery rejects missing, extra, and manifest-less bundles', () => {
  withTempRoot((root) => {
    const outDir = join(root, 'ios-deps');
    fakeFrameworkBuild(outDir);
    const configDir = join(outDir, 'Build', 'Release-iphoneos');
    rmSync(join(configDir, 'FirebaseCore', 'FirebaseCore_Privacy.bundle'),
      { recursive: true, force: true });
    const missing = discoverFirebaseResources(configDir);
    assert.equal(missing.ok, false);
    assert.ok(missing.checks.some((line) => line.includes('missing required resource FirebaseCore_Privacy.bundle')));
  });
  withTempRoot((root) => {
    const outDir = join(root, 'ios-deps');
    fakeFrameworkBuild(outDir);
    const configDir = join(outDir, 'Build', 'Debug-iphoneos');
    mkdirSync(join(configDir, 'FirebaseAuth', 'Extra_Privacy.bundle'), { recursive: true });
    writeFileSync(
      join(configDir, 'FirebaseAuth', 'Extra_Privacy.bundle', 'PrivacyInfo.xcprivacy'), '<!-- x -->\n');
    const extra = discoverFirebaseResources(configDir);
    assert.equal(extra.ok, false);
    assert.ok(extra.checks.some((line) => line.includes('unexpected resource Extra_Privacy.bundle')));
  });
  withTempRoot((root) => {
    const outDir = join(root, 'ios-deps');
    fakeFrameworkBuild(outDir);
    const configDir = join(outDir, 'Build', 'Release-iphoneos');
    rmSync(join(configDir, 'GoogleUtilities', 'GoogleUtilities_Privacy.bundle', 'PrivacyInfo.xcprivacy'));
    const bare = discoverFirebaseResources(configDir);
    assert.equal(bare.ok, false);
    assert.ok(bare.checks.some((line) => line.includes('lacks PrivacyInfo.xcprivacy')));
  });
  withTempRoot((root) => {
    const outDir = join(root, 'ios-deps');
    fakeFrameworkBuild(outDir);
    const configDir = join(outDir, 'Build', 'Release-iphoneos');
    mkdirSync(join(configDir, 'StaleCopy', 'FirebaseAuth_Privacy.bundle'), { recursive: true });
    const dup = discoverFirebaseResources(configDir);
    assert.equal(dup.ok, false);
    assert.ok(dup.checks.some((line) => line.includes('ambiguous FirebaseAuth_Privacy.bundle')));
  });
});

test('resource staging copies bundles byte for byte', () => {
  withTempRoot((root) => {
    const depsRoot = join(root, 'ios-deps');
    fakeFrameworkBuild(depsRoot);
    const tree = buildFirebaseLinkTree({
      depsRoot,
      excludeProducts: ['Pods_MoonlitIdentityPods'],
    });
    assert.equal(tree.ok, true);
    // A path with spaces proves argv/fs safety for real machine dirs.
    const dest = join(identityIosResourcesDir(root, 'release'), '..', 'release with spaces');
    const staged = stageIosResources({ depsRoot, variant: 'release', destDir: dest });
    assert.equal(staged.ok, true);
    assert.deepEqual(staged.staged, [...IDENTITY_REQUIRED_PRIVACY_BUNDLES].sort());
    for (const name of staged.staged) {
      const want = readFileSync(
        join(depsRoot, 'Build', 'Release-iphoneos',
          BUNDLE_OWNERS[name], name, 'PrivacyInfo.xcprivacy'));
      const got = readFileSync(join(dest, name, 'PrivacyInfo.xcprivacy'));
      assert.ok(got.equals(want), `${name} bytes preserved`);
    }
    const unlinked = stageIosResources({
      depsRoot: join(root, 'empty-deps'),
      variant: 'release',
      destDir: join(root, 'out'),
    });
    assert.equal(unlinked.ok, false);
    assert.ok(unlinked.checks.some((line) => line.includes('--fetch-deps')));
  });
});

test('staging writes the Godot import exclusion outside the bundles', () => {
  withTempRoot((root) => {
    const depsRoot = join(root, 'ios-deps');
    fakeFrameworkBuild(depsRoot);
    // GoogleSignIn carries native button images beside its manifest; the
    // editor tried to import them and broke reimport. Staging must keep
    // every bundle byte-identical and exclude the staging dir instead.
    const buttonImage = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01, 0x02]);
    writeFileSync(
      join(depsRoot, 'Build', 'Release-iphoneos', 'GoogleSignIn', 'GoogleSignIn.bundle', 'google@2x.png'),
      buttonImage,
    );
    const tree = buildFirebaseLinkTree({
      depsRoot,
      excludeProducts: ['Pods_MoonlitIdentityPods'],
    });
    assert.equal(tree.ok, true);
    const frameworksDir = identityIosFrameworksDir(root, 'release');
    const frameworks = stageIosFrameworks({ depsRoot, variant: 'release', destDir: frameworksDir });
    assert.equal(frameworks.ok, true);
    const resourcesDir = identityIosResourcesDir(root, 'release');
    const resources = stageIosResources({ depsRoot, variant: 'release', destDir: resourcesDir });
    assert.equal(resources.ok, true);
    for (const destDir of [frameworksDir, resourcesDir]) {
      const exclusion = join(destDir, IOS_STAGED_IMPORT_EXCLUSION);
      assert.equal(existsSync(exclusion), true, `${destDir} keeps the import exclusion`);
      assert.match(readFileSync(exclusion, 'utf8'), /\*/u);
    }
    for (const name of IDENTITY_REQUIRED_PRIVACY_BUNDLES) {
      assert.equal(
        existsSync(join(resourcesDir, name, IOS_STAGED_IMPORT_EXCLUSION)),
        false,
        `${name} stays byte-identical with no exclusion inside`,
      );
    }
    const stagedImage = readFileSync(join(resourcesDir, 'GoogleSignIn.bundle', 'google@2x.png'));
    assert.ok(stagedImage.equals(buttonImage), 'GoogleSignIn button image bytes preserved');
  });
});

test('staged export inputs keep the full export contract with the exclusion present', () => {
  withTempRoot((root) => {
    const depsRoot = join(root, 'ios-deps');
    fakeFrameworkBuild(depsRoot);
    const tree = buildFirebaseLinkTree({
      depsRoot,
      excludeProducts: ['Pods_MoonlitIdentityPods'],
    });
    assert.equal(tree.ok, true);
    const frameworksDir = identityIosFrameworksDir(root, 'release');
    const frameworks = stageIosFrameworks({ depsRoot, variant: 'release', destDir: frameworksDir });
    assert.equal(frameworks.ok, true);
    const resourcesDir = identityIosResourcesDir(root, 'release');
    const resources = stageIosResources({ depsRoot, variant: 'release', destDir: resourcesDir });
    assert.equal(resources.ok, true);
    // Mirror ios_export_manifest._child_paths: sorted child dirs with the
    // suffix. The exclusion is a file, so explicit export discovery still
    // lists the full staged sets.
    const childPaths = (parentDir, suffix) => readdirSync(parentDir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && entry.name.endsWith(suffix))
      .map((entry) => entry.name)
      .sort();
    assert.deepEqual(childPaths(frameworksDir, '.framework'), NESTED_PODS.map((name) => `${name}.framework`).sort());
    assert.deepEqual(childPaths(resourcesDir, '.bundle'), [...IDENTITY_REQUIRED_PRIVACY_BUNDLES].sort());
    const addon = join(root, 'apps/game/addons/moonlit-identity');
    mkdirSync(join(addon, 'ios'), { recursive: true });
    writeFileSync(join(addon, 'ios/moonlit_identity.gdextension.ios'), '# fake\n');
    writeFileSync(join(addon, 'bin/ios/libmoonlit_identity.release.a'), 'fake archive');
    const fakeNm = () => '0000000000000000 T _moonlit_identity_ios_entry\n';
    const good = verifyIosExportInputs({ root, variant: 'release', nm: fakeNm });
    assert.deepEqual(good.checks, []);
    assert.equal(good.ok, true);
  });
});

test('export inputs verification demands the full link-time set', () => {
  withTempRoot((root) => {
    const addon = join(root, 'apps/game/addons/moonlit-identity');
    const fakeNm = () => '0000000000000000 T _moonlit_identity_ios_entry\n';
    mkdirSync(join(addon, 'ios'), { recursive: true });
    writeFileSync(join(addon, 'ios/moonlit_identity.gdextension.ios'), '# fake\n');
    const lib = join(addon, 'bin/ios/libmoonlit_identity.release.a');
    mkdirSync(join(addon, 'bin/ios'), { recursive: true });
    writeFileSync(lib, 'fake archive');
    const frameworksDir = identityIosFrameworksDir(root, 'release');
    mkdirSync(join(frameworksDir, 'FirebaseAuth.framework'), { recursive: true });
    mkdirSync(join(frameworksDir, 'GoogleSignIn.framework'), { recursive: true });
    mkdirSync(join(frameworksDir, 'FirebaseCore.framework'), { recursive: true });
    const resourcesDir = identityIosResourcesDir(root, 'release');
    for (const name of IDENTITY_REQUIRED_PRIVACY_BUNDLES) {
      mkdirSync(join(resourcesDir, name), { recursive: true });
      writeFileSync(join(resourcesDir, name, 'PrivacyInfo.xcprivacy'), '<!-- fake -->\n');
    }
    writeIosStagingImportExclusion(frameworksDir);
    writeIosStagingImportExclusion(resourcesDir);
    const good = verifyIosExportInputs({ root, variant: 'release', nm: fakeNm });
    assert.deepEqual(good.checks, []);
    assert.equal(good.ok, true);
    rmSync(lib);
    const noLib = verifyIosExportInputs({ root, variant: 'release', nm: fakeNm });
    assert.equal(noLib.ok, false);
    assert.ok(noLib.checks.some((line) => line.includes('missing static library')));
    writeFileSync(lib, 'fake archive');
    const noSymbol = verifyIosExportInputs({
      root, variant: 'release', nm: () => '0000000000000000 T _something_else\n',
    });
    assert.equal(noSymbol.ok, false);
    assert.ok(noSymbol.checks.some((line) => line.includes('moonlit_identity_ios_entry')));
    rmSync(join(frameworksDir, 'FirebaseAuth.framework'), { recursive: true, force: true });
    const noAuth = verifyIosExportInputs({ root, variant: 'release', nm: fakeNm });
    assert.equal(noAuth.ok, false);
    assert.ok(noAuth.checks.some((line) => line.includes('lack FirebaseAuth.framework')));
    mkdirSync(join(frameworksDir, 'FirebaseAuth.framework'), { recursive: true });
    rmSync(join(frameworksDir, 'GoogleSignIn.framework'), { recursive: true, force: true });
    const noSignIn = verifyIosExportInputs({ root, variant: 'release', nm: fakeNm });
    assert.equal(noSignIn.ok, false);
    assert.ok(noSignIn.checks.some((line) => line.includes('lack GoogleSignIn.framework')));
    mkdirSync(join(frameworksDir, 'GoogleSignIn.framework'), { recursive: true });
    rmSync(join(resourcesDir, 'FirebaseCore_Privacy.bundle'), { recursive: true, force: true });
    const noBundle = verifyIosExportInputs({ root, variant: 'release', nm: fakeNm });
    assert.equal(noBundle.ok, false);
    assert.ok(noBundle.checks.some((line) => line.includes('FirebaseCore_Privacy.bundle')));
    mkdirSync(join(resourcesDir, 'FirebaseCore_Privacy.bundle'), { recursive: true });
    writeFileSync(join(resourcesDir, 'FirebaseCore_Privacy.bundle', 'PrivacyInfo.xcprivacy'), '<!-- fake -->\n');
    rmSync(join(frameworksDir, IOS_STAGED_IMPORT_EXCLUSION));
    const noFrameworkExclusion = verifyIosExportInputs({ root, variant: 'release', nm: fakeNm });
    assert.equal(noFrameworkExclusion.ok, false);
    assert.ok(noFrameworkExclusion.checks.some((line) => line.includes('no Godot import exclusion')));
    writeIosStagingImportExclusion(frameworksDir);
    rmSync(join(resourcesDir, IOS_STAGED_IMPORT_EXCLUSION));
    const noResourceExclusion = verifyIosExportInputs({ root, variant: 'release', nm: fakeNm });
    assert.equal(noResourceExclusion.ok, false);
    assert.ok(noResourceExclusion.checks.some((line) => line.includes('no Godot import exclusion')));
  });
});

test('compile flags derive the exact scons argv fragments', () => {
  withTempRoot((root) => {
    const flagsFile = join(root, 'firebase-flags.json');
    writeFileSync(flagsFile, JSON.stringify({
      variants: {
        release: {
          headers: join(root, 'Moonlit Link', 'Headers'),
          frameworks_dir: join(root, 'Moonlit Link', 'Frameworks'),
          frameworks: ['FirebaseAuth', 'FirebaseCore', 'GoogleSignIn'],
        },
      },
    }));
    const cache = join(root, 'build dir', '.module-cache');
    const derived = iosCompileFlags({ flagsFile, variant: 'release', moduleCacheDir: cache });
    assert.deepEqual(derived.checks, []);
    assert.equal(derived.ok, true);
    assert.deepEqual(derived.flags, [
      `-F${join(root, 'Moonlit Link', 'Frameworks')}`,
      `-I${join(root, 'Moonlit Link', 'Headers')}`,
      '-fmodules',
      '-fcxx-modules',
      `-fmodules-cache-path=${cache}`,
    ]);
    assert.equal(derived.flags.filter((item) => item.startsWith('-F')).length, 1);
    const noVariant = iosCompileFlags({ flagsFile, variant: 'debug', moduleCacheDir: cache });
    assert.equal(noVariant.ok, false);
    assert.ok(noVariant.checks.some((line) => line.includes('has no debug variant')));
    const noFile = iosCompileFlags({
      flagsFile: join(root, 'nope.json'), variant: 'release', moduleCacheDir: cache,
    });
    assert.equal(noFile.ok, false);
    assert.ok(noFile.checks.some((line) => line.includes('cannot read link tree')));
  });
});

test('framework staging copies the variant set for the export', () => {
  withTempRoot((root) => {
    const depsRoot = join(root, 'ios-deps');
    fakeFrameworkBuild(depsRoot);
    const tree = buildFirebaseLinkTree({
      depsRoot,
      excludeProducts: ['Pods_MoonlitIdentityPods'],
    });
    assert.equal(tree.ok, true);
    const dest = identityIosFrameworksDir(root, 'release');
    const staged = stageIosFrameworks({ depsRoot, variant: 'release', destDir: dest });
    assert.equal(staged.ok, true);
    assert.deepEqual(staged.staged, NESTED_PODS);
    assert.equal(existsSync(join(dest, 'FirebaseAuth.framework/Headers/FirebaseAuth.h')), true);
    assert.equal(existsSync(join(dest, 'Pods_MoonlitIdentityPods.framework')), false);
    const unlinked = stageIosFrameworks({
      depsRoot: join(root, 'empty-deps'),
      variant: 'release',
      destDir: join(root, 'out'),
    });
    assert.equal(unlinked.ok, false);
    assert.ok(unlinked.checks.some((line) => line.includes('--fetch-deps')));
  });
});

test('framework staging refuses a set without firebaseauth', () => {
  withTempRoot((root) => {
    const depsRoot = join(root, 'ios-deps');
    const link = firebaseLinkPaths(join(depsRoot, 'Pods'));
    mkdirSync(link.linkDir, { recursive: true });
    const frameworksDir = join(link.linkDir, 'Release', 'Frameworks');
    mkdirSync(join(frameworksDir, 'FirebaseCore.framework'), { recursive: true });
    writeFileSync(link.flagsFile, JSON.stringify({
      variants: {
        release: { frameworks: ['FirebaseCore'], frameworks_dir: frameworksDir },
      },
    }));
    const staged = stageIosFrameworks({
      depsRoot,
      variant: 'release',
      destDir: join(root, 'out'),
    });
    assert.equal(staged.ok, false);
    assert.ok(staged.checks.some((line) => line.includes('staged no FirebaseAuth')));
  });
  withTempRoot((root) => {
    const depsRoot = join(root, 'ios-deps');
    const link = firebaseLinkPaths(join(depsRoot, 'Pods'));
    mkdirSync(link.linkDir, { recursive: true });
    const frameworksDir = join(link.linkDir, 'Release', 'Frameworks');
    mkdirSync(join(frameworksDir, 'FirebaseAuth.framework'), { recursive: true });
    writeFileSync(link.flagsFile, JSON.stringify({
      variants: {
        release: { frameworks: ['FirebaseAuth'], frameworks_dir: frameworksDir },
      },
    }));
    const staged = stageIosFrameworks({
      depsRoot,
      variant: 'release',
      destDir: join(root, 'out'),
    });
    assert.equal(staged.ok, false);
    assert.ok(staged.checks.some((line) => line.includes('staged no GoogleSignIn')));
  });
});

test('git head revision reads detached, branch, and worktree checkouts', () => {
  withTempRoot((root) => {
    const sha = IDENTITY_PINS.godotCppRev;
    const detached = join(root, 'detached');
    mkdirSync(join(detached, '.git'), { recursive: true });
    writeFileSync(join(detached, '.git/HEAD'), `${sha}\n`);
    assert.equal(readGitHeadRevision(detached), sha);
    const branch = join(root, 'branch');
    mkdirSync(join(branch, '.git/refs/heads'), { recursive: true });
    writeFileSync(join(branch, '.git/HEAD'), 'ref: refs/heads/main\n');
    writeFileSync(join(branch, '.git/refs/heads/main'), `${sha}\n`);
    assert.equal(readGitHeadRevision(branch), sha);
    const worktree = join(root, 'worktree');
    const gitdir = join(root, 'real-git');
    mkdirSync(gitdir, { recursive: true });
    writeFileSync(join(gitdir, 'HEAD'), `${sha}\n`);
    mkdirSync(worktree, { recursive: true });
    writeFileSync(join(worktree, '.git'), `gitdir: ${gitdir}\n`);
    assert.equal(readGitHeadRevision(worktree), sha);
    assert.equal(readGitHeadRevision(join(root, 'no-git-here')), null);
  });
});

test('build child env passes only the allowlist', () => {
  const env = {
    PATH: '/usr/bin',
    HOME: '/home/dev',
    ANDROID_SDK_ROOT: '/sdk',
    GODOT_CPP: '/cpp',
    MOONLIT_FIREBASE_PROJECT_ID: FAKE_PROJECT,
    OPENIAP_SECRET: 'openiap-kit_sk_nope',
    ASC_API_KEY: 'secret',
    MY_TOKEN: 'secret',
    EMPTY_OK: '',
  };
  const clean = sanitizedBuildEnv(env);
  assert.deepEqual(Object.keys(clean).sort(), [
    'ANDROID_SDK_ROOT', 'GODOT_CPP', 'HOME', 'PATH',
  ]);
  assert.equal(clean.PATH, '/usr/bin');
  for (const name of Object.keys(env)) {
    if (!BUILD_CHILD_ENV_ALLOWLIST.includes(name)) {
      assert.ok(!(name in clean), `${name} must not reach build children`);
    }
  }
});

test('bridge build runner passes the exact sanitized env to spawn', () => {
  const seen = [];
  runBridgeBuild({
    command: 'scons',
    args: ['platform=ios'],
    cwd: '/tmp/x',
    env: {
      PATH: '/usr/bin', HOME: '/home/dev', FIREBASE_PODS_DIR: '/pods',
      MOONLIT_PLAY_SERVER_CLIENT_ID: FAKE_GOOGLE_ID, SOME_SECRET: 'x',
    },
    spawn: (command, args, options) => {
      seen.push({ ...options.env });
      return { status: 0, stdout: '', stderr: '' };
    },
  });
  assert.deepEqual(seen[0], { PATH: '/usr/bin', HOME: '/home/dev', FIREBASE_PODS_DIR: '/pods' });
});

test('bridge build runner reports status and redacts output', () => {
  const seen = [];
  const spawn = (command, args, options) => {
    seen.push({ command, args, cwd: options.cwd });
    return { status: 0, stdout: 'BUILD SUCCESSFUL', stderr: `leak ${FAKE_GOOGLE_ID}` };
  };
  const result = runBridgeBuild({ command: 'gradle', args: [':MoonlitIdentity:assembleRelease'], cwd: '/tmp/x', spawn });
  assert.equal(result.ok, true);
  assert.deepEqual(seen[0].args, [':MoonlitIdentity:assembleRelease']);
  assert.ok(!result.output.includes(FAKE_GOOGLE_ID));
  assert.match(result.output, /BUILD SUCCESSFUL/);
  const failed = runBridgeBuild({
    command: 'scons', args: ['platform=ios'], cwd: '/tmp/x',
    spawn: () => ({ status: 2, stdout: '', stderr: 'boom' }),
  });
  assert.equal(failed.ok, false);
  assert.equal(failed.status, 2);
});

test('android artifact verification checks registration, not just presence', () => {
  withTempRoot((root) => {
    const missing = verifyAndroidArtifact(join(root, 'nope.aar'));
    assert.equal(missing.ok, false);
    const aar = join(root, 'MoonlitIdentity.release.aar');
    writeFileSync(aar, 'fake-aar');
    const good = verifyAndroidArtifact(aar, {
      listZip: () => 'AndroidManifest.xml\nclasses.jar\n',
      readZipEntry: () => '<meta-data android:name="org.godotengine.plugin.v2.MoonlitIdentity" android:value="dev.moonlitbeacon.identity.MoonlitIdentityPlugin" />',
    });
    assert.equal(good.ok, true);
    const bad = verifyAndroidArtifact(aar, {
      listZip: () => 'AndroidManifest.xml\nclasses.jar\n',
      readZipEntry: () => '<manifest></manifest>',
    });
    assert.equal(bad.ok, false);
    assert.ok(bad.checks.some((line) => line.includes('registration')));
    const malformed = verifyAndroidArtifact(aar, {
      listZip: () => 'AndroidManifest.xml\nclasses.jar\n',
      readZipEntry: () => '<manifest><!-- oops -- --><meta-data android:name="org.godotengine.plugin.v2.MoonlitIdentity" android:value="dev.moonlitbeacon.identity.MoonlitIdentityPlugin" /></manifest>',
    });
    assert.equal(malformed.ok, false);
    assert.ok(malformed.checks.some((line) => line.includes('not well-formed')));
    const bare = verifyAndroidArtifact(aar, { listZip: () => 'R.txt\n', readZipEntry: () => '' });
    assert.equal(bare.ok, false);
  });
});

test('android manifest template parses as xml, with no double hyphens', () => {
  const manifest = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android/AndroidManifest.xml.tmpl'), 'utf8');
  assert.deepEqual(checkXmlWellFormed(manifest, 'AndroidManifest.xml.tmpl'), { ok: true });
  withTempRoot((root) => {
    const outDir = join(root, 'builds/moonlit-identity/android');
    renderAndroidPluginProject({ root: REPO_ROOT, outDir });
    const rendered = readFileSync(
      join(outDir, 'MoonlitIdentity/src/main/AndroidManifest.xml'), 'utf8');
    assert.deepEqual(checkXmlWellFormed(rendered, 'AndroidManifest.xml'), { ok: true });
  });
});

test('xml parser rejects each well-formedness defect', () => {
  const cases = [
    ['<!-- a -- b -->', '"--" is not permitted'],
    ['<a><b></a>', 'mismatched close tag'],
    ['<a b=c/>', 'unquoted attribute'],
    ['<a>&bogus;</a>', 'bad entity reference'],
    ['<a></a><b></b>', 'content after the root'],
    ['', 'missing root element'],
    ['<?xml version="1.0"?><a><?xml version="1.0"?></a>', 'only allowed in the prolog'],
  ];
  for (const [input, want] of cases) {
    const verdict = checkXmlWellFormed(input, 'case');
    assert.equal(verdict.ok, false, `${input} must not parse`);
    assert.match(verdict.error, new RegExp(want));
  }
  const good = [
    '<?xml version="1.0" encoding="utf-8"?><a n="v&amp;w"><!-- ok --><b/><![CDATA[x<y]]></a>',
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="x"><uses-sdk android:minSdkVersion="23" /></manifest>',
  ];
  for (const input of good) {
    assert.deepEqual(checkXmlWellFormed(input, 'case'), { ok: true });
  }
});

test('ios artifact verification checks the entry symbol', () => {
  withTempRoot((root) => {
    const missing = verifyIosArtifact(join(root, 'nope.a'));
    assert.equal(missing.ok, false);
    const lib = join(root, 'libmoonlit_identity.release.a');
    writeFileSync(lib, 'fake-lib');
    assert.equal(verifyIosArtifact(lib, { nm: () => '_moonlit_identity_ios_entry\n_other\n' }).ok, true);
    const bad = verifyIosArtifact(lib, { nm: () => '_other\n' });
    assert.equal(bad.ok, false);
    assert.ok(bad.checks.some((line) => line.includes('moonlit_identity_ios_entry')));
  });
});

function stripGradleNoise(source) {
  return source
    .replace(/\/\/.*$/gm, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/'(?:\\.|[^'\\])*'/g, "''")
    .replace(/"(?:\\.|[^"\\])*"/g, '""');
}

function assertBalanced(label, source, open, close) {
  const stripped = stripGradleNoise(source);
  const opens = stripped.split(open).length - 1;
  const closes = stripped.split(close).length - 1;
  assert.equal(opens, closes, `${label}: ${opens} "${open}" vs ${closes} "${close}"`);
}

test('rendered gradle files contain no groovy-invalid comments', () => {
  for (const name of ['settings.gradle.tmpl', 'root-build.gradle.tmpl', 'build.gradle.tmpl']) {
    const body = readFileSync(
      join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android', name), 'utf8');
    for (const [index, line] of body.split('\n').entries()) {
      assert.ok(!/^\s*#/.test(line), `${name}:${index + 1} uses a '#' comment`);
    }
    assertBalanced(name, body, '{', '}');
    assertBalanced(name, body, '(', ')');
  }
});

test('gradle templates carry the required standalone blocks', () => {
  const android = (name) => readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android', name), 'utf8');
  assert.match(android('settings.gradle.tmpl'), /pluginManagement\s*\{/);
  assert.match(android('settings.gradle.tmpl'), /dependencyResolutionManagement\s*\{/);
  assert.match(android('settings.gradle.tmpl'), /include\s*\(\s*":MoonlitIdentity"\s*\)/);
  assert.match(android('root-build.gradle.tmpl'), /com\.android\.library/);
  assert.match(android('root-build.gradle.tmpl'), /org\.jetbrains\.kotlin\.android/);
  assert.match(android('build.gradle.tmpl'), /namespace\s+'dev\.moonlitbeacon\.identity'/);
  assert.match(android('build.gradle.tmpl'), /consumerProguardFiles/);
});

test('kotlin uses the real v2 task api, not the v1 intent api', () => {
  const kotlin = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android/src/main/kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt'),
    'utf8');
  for (const forbidden of ['signInIntent', 'getSignInIntent', 'startActivityForResult',
    'onMainActivityResult', 'org.godotengine.plugin.v1', 'SignInClient(host).signOut']) {
    assert.ok(!kotlin.includes(forbidden), `kotlin must not reference ${forbidden}`);
  }
  for (const required of ['org.godotengine.godot.plugin.GodotPlugin',
    'org.godotengine.godot.plugin.UsedByGodot', '.signIn()', '.isAuthenticated',
    'requestServerSideAccess', 'PlayGamesAuthProvider', 'FirebaseOptions',
    'FirebaseApp.initializeApp', 'moonlitCancelRequest', 'mutationOwner',
    'mutation_in_progress', 'auth.signOut()', 'APP_ID']) {
    assert.ok(kotlin.includes(required), `kotlin must use ${required}`);
  }
});

test('kotlin signs google in through credential manager, apple through oauth', () => {
  const kotlin = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android/src/main/kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt'),
    'utf8');
  for (const forbidden of ['.getDisplayName', '.getEmail', '.getPhotoUrl',
    '.getPhoneNumber', 'requestIdToken', 'GoogleSignInClient', 'Auth.GoogleSignInApi',
    'host.mainExecutor', 'OutcomeReceiver', 'CancellationSignal',
    'attachReauthTask', 'Task<Void>']) {
    assert.ok(!kotlin.includes(forbidden), `kotlin must not reference ${forbidden}`);
  }
  for (const required of ['CredentialManager.create', 'GetCredentialRequest',
    'GetGoogleIdOption', 'setServerClientId', 'setFilterByAuthorizedAccounts(false)',
    'setAutoSelectEnabled(false)', 'GoogleIdTokenCredential',
    'TYPE_GOOGLE_ID_TOKEN_CREDENTIAL', 'GoogleAuthProvider.getCredential',
    'GetCredentialCancellationException', 'NoCredentialException',
    'kotlinx.coroutines', 'Dispatchers.Main', 'credentialScope.launch',
    'CancellationException', 'credentialJobs',
    'OAuthProvider.newBuilder', 'pendingAuthResult',
    'startActivityForSignInWithProvider', 'startActivityForLinkWithProvider',
    'startActivityForReauthenticateWithProvider', 'ERROR_WEB_CONTEXT_CANCELLED',
    'attachReauth', 'Task<AuthResult>',
    '"google.com"', '"apple.com"', '"playgames.google.com"',
    'no_google_account', 'completeWithCredential']) {
    assert.ok(kotlin.includes(required), `kotlin must use ${required}`);
  }
});

test('kotlin cold-start session initializes firebase before the first read', () => {
  const kotlin = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android/src/main/kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt'),
    'utf8');
  // The startup operation runs first: it must configure the default app
  // from staged public config before reading the session, so a saved
  // Firebase user restores instead of answering local guest.
  const entryStart = kotlin.indexOf('fun moonlitGetSession(');
  assert.ok(entryStart > 0, 'kotlin must define moonlitGetSession');
  const entryEnd = kotlin.indexOf('fun moonlitGetIdToken(', entryStart);
  assert.ok(entryEnd > entryStart, 'moonlitGetSession body is bounded');
  const entry = kotlin.slice(entryStart, entryEnd);
  assert.ok(entry.includes('JSONObject(argsJson)'),
    'session entry parses the staged public config');
  assert.ok(entry.includes('ensureSessionApp'),
    'session entry initializes the default app before the first read');
  assert.ok(!entry.includes('ensureFirebase('),
    'session entry uses the synchronous initializer, never the bookkeeping one');
  assert.ok(entry.includes('describeSession'),
    'session entry answers through the shared session helper');
  assert.ok(entry.indexOf('ensureSessionApp') < entry.indexOf('describeSession'),
    'initialization runs before the session read');
  for (const forbidden of ['begin(', 'beginMutating', 'finish(', 'pendingReceipt',
    'terminalReceipt', 'markMutation', 'rememberSettled', 'emitSignal',
    'moonlit_identity_event', 'signInAnonymously', 'signInWithCredential',
    'linkWithCredential']) {
    assert.ok(!entry.includes(forbidden),
      `session entry stays synchronous with no signal and no sign-in (${forbidden})`);
  }
  // The synchronous initializer preserves an already configured app,
  // builds from the same staged keys as the mutating path, and never
  // touches request bookkeeping or Auth.
  const initStart = kotlin.indexOf('private fun ensureSessionApp(');
  assert.ok(initStart > 0, 'kotlin must define the synchronous session initializer');
  const initEnd = kotlin.indexOf('fun moonlitSignInGuest(', initStart);
  assert.ok(initEnd > initStart, 'session initializer body is bounded');
  const init = kotlin.slice(initStart, initEnd);
  assert.ok(init.includes('FirebaseApp.getApps') && init.includes('isNotEmpty'),
    'session initializer preserves an already configured app');
  for (const required of ['firebase_api_key', 'firebase_app_id',
    'firebase_project_id', 'firebase_sender_id', 'FirebaseOptions',
    'FirebaseApp.initializeApp']) {
    assert.ok(init.includes(required), `session initializer uses ${required}`);
  }
  for (const forbidden of ['begin(', 'beginMutating', 'finish(', 'pendingReceipt',
    'markMutation', 'rememberSettled', 'emitSignal', 'FirebaseAuth',
    'currentUser', 'signInAnonymously', 'id_token', 'getEmail', 'getDisplayName']) {
    assert.ok(!init.includes(forbidden),
      `session initializer never touches ${forbidden}`);
  }
});

test('kotlin shared session helper never touches auth without a configured app', () => {
  const kotlin = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/android/src/main/kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt'),
    'utf8');
  // The shared reader backs the session answer: it must guard the
  // unconfigured case before any Auth access, because the persisted user
  // is unavailable until the default app is configured.
  const start = kotlin.indexOf('private fun describeSession(');
  assert.ok(start > 0, 'kotlin must define describeSession');
  const end = kotlin.indexOf('private fun providerOfUser(', start);
  assert.ok(end > start, 'describeSession body is bounded');
  const body = kotlin.slice(start, end);
  assert.ok(body.includes('FirebaseApp.getApps'),
    'session helper guards the unconfigured case');
  assert.ok(body.includes('auth.currentUser'),
    'session helper still reads the live user when configured');
  assert.ok(body.indexOf('FirebaseApp.getApps') < body.indexOf('auth.currentUser'),
    'the configured-app guard runs before any Auth access');
  assert.ok(body.includes('localSession'),
    'unconfigured session answers the honest local session');
  assert.ok(body.includes('providerOfUser'),
    'configured session keeps real provider ownership');
  for (const forbidden of ['begin(', 'beginMutating', 'finish(', 'pendingReceipt',
    'markMutation', 'rememberSettled', 'emitSignal',
    'FirebaseApp.initializeApp', 'FirebaseOptions', 'signInAnonymously',
    'signInWithCredential', 'id_token']) {
    assert.ok(!body.includes(forbidden),
      `session helper stays a synchronous read (${forbidden})`);
  }
});

test('objc uses safe apple/firebase calls with no personal scopes', () => {
  const objc = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm'), 'utf8');
  for (const forbidden of ['ASAuthorizationScopeFullName', 'ASAuthorizationScopeEmail',
    'appleKeepProviderGrant', 'credential.fullName', 'credential.email',
    'credentialOfType:', 'options.apiKey', 'gcmSenderID:']) {
    assert.ok(!objc.includes(forbidden), `objc must not reference ${forbidden}`);
  }
  for (const required of ['requestedScopes = @[]', 'FIROptions', 'configureWithOptions',
    'revokeTokenWithAuthorizationCode', 'appleCredentialWithIDToken',
    'FirebaseAuth-Swift.h', 'FirebaseCore/FIRApp.h', 'FirebaseCore/FIROptions.h',
    'options.APIKey', 'GCMSenderID:',
    'authorization.credential', 'isKindOfClass',
    'moonlitCancelRequest', 'markMutation', 'kSettledCap', '__bridge_retained',
    'mutationOwner', 'mutation_in_progress']) {
    assert.ok(objc.includes(required), `objc must use ${required}`);
  }
});

test('objc sign-out failure keeps the real session', () => {
  const objc = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm'), 'utf8');
  for (const required of ['signOut:&error', 'kCodeSignOutFailed',
    'sign_out_failed', 'signOutFailedOutcome', 'sessionOutcome']) {
    assert.ok(objc.includes(required), `objc must use ${required}`);
  }
  // The signOut body fails through the dedicated outcome (error plus the
  // re-read session), keeps the operation lock, and keeps the no-config
  // local-session no-op — never an unconditional guest success.
  const start = objc.indexOf('- (NSString *)signOut:(NSString *)requestId {');
  assert.ok(start > 0, 'objc must define the signOut method');
  const body = objc.slice(start, objc.indexOf('- (NSDictionary *)signOutFailedOutcome:'));
  assert.ok(body.includes('busyReceipt'), 'sign-out keeps the operation lock');
  assert.ok(body.includes('[FIRApp defaultApp] == nil'),
    'sign-out keeps the no-config no-op case');
  const failureStart = body.indexOf('if (error != nil) {');
  const failure = body.slice(failureStart, body.indexOf('\n\t}\n', failureStart));
  assert.ok(failure.includes('signOutFailedOutcome'),
    'sign-out failure returns the dedicated error outcome');
  assert.ok(!failure.includes('localSession'),
    'sign-out failure never declares a guest success');
});

test('objc sign-out failure reads a dictionary session, not serialized JSON', () => {
  const objc = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm'), 'utf8');
  // describeSession returns a JSON NSString; assigning it to an NSDictionary
  // is the arm64 compile error this guards against. No site may do it.
  const jsonAsDict = /NSDictionary\s*\*\s*\w+\s*=\s*\[self describeSession/;
  assert.ok(!jsonAsDict.test(objc),
    'no NSDictionary may be initialized from describeSession JSON');
  // The failure outcome merges session fields, so it must source the
  // dictionary helper — never the serialized string.
  const outcomeStart = objc.indexOf('- (NSDictionary *)signOutFailedOutcome:');
  assert.ok(outcomeStart > 0, 'objc must define the sign-out failure outcome');
  const outcome = objc.slice(outcomeStart, objc.indexOf('\n}\n', outcomeStart));
  assert.ok(outcome.includes('sessionOutcome'),
    'sign-out failure reads the dictionary session helper');
  assert.ok(!outcome.includes('describeSession'),
    'sign-out failure never touches the serialized session string');
  // The serialized session answer keeps its wire format: the same
  // dictionary wrapped in jsonString.
  const describeStart = objc.indexOf('- (NSString *)describeSession:');
  assert.ok(describeStart > 0, 'objc must define describeSession');
  const describe = objc.slice(describeStart, objc.indexOf('\n}\n', describeStart));
  assert.ok(describe.includes('sessionOutcome') && describe.includes('jsonString'),
    'describeSession serializes the shared session dictionary');
});

test('objc cold-start session initializes firebase before the first read', () => {
  const objc = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm'), 'utf8');
  // The startup operation runs first: it must configure the default app
  // from staged public config before reading the session, so a saved
  // Firebase user restores instead of answering local guest.
  const entryStart = objc.indexOf('MoonlitIdentityIos::moonlitGetSession(');
  assert.ok(entryStart > 0, 'objc must define moonlitGetSession');
  const entryEnd = objc.indexOf('MoonlitIdentityIos::moonlitGetIdToken(', entryStart);
  assert.ok(entryEnd > entryStart, 'moonlitGetSession body is bounded');
  const entry = objc.slice(entryStart, entryEnd);
  assert.ok(!entry.includes('(void)p_args_json'),
    'session entry consumes its staged config instead of discarding it');
  assert.ok(entry.includes('parseArgs'),
    'session entry parses the staged public config');
  assert.ok(entry.includes('ensureSessionApp'),
    'session entry initializes the default app before the first read');
  assert.ok(!entry.includes(' ensureApp:'),
    'session entry uses the synchronous initializer, never the bookkeeping one');
  assert.ok(entry.includes('describeSession'),
    'session entry answers through the shared session helper');
  assert.ok(entry.indexOf('ensureSessionApp') < entry.indexOf('describeSession'),
    'initialization runs before the session read');
  for (const forbidden of ['beginRequest', 'beginMutating', 'finishRequest',
    'pendingReceipt', 'markMutation', 'rememberSettled', '_emit_outcome',
    'call_deferred', 'moonlit_identity_event']) {
    assert.ok(!entry.includes(forbidden),
      `session entry stays synchronous with no signal (${forbidden})`);
  }
  // The synchronous initializer preserves an already configured app,
  // builds from the same staged keys as the mutating path, and never
  // touches request bookkeeping or Auth.
  const initStart = objc.indexOf('- (BOOL)ensureSessionApp:');
  assert.ok(initStart > 0, 'objc must define the synchronous session initializer');
  const initEnd = objc.indexOf('- (NSString *)pendingReceipt:', initStart);
  assert.ok(initEnd > initStart, 'session initializer body is bounded');
  const init = objc.slice(initStart, initEnd);
  assert.ok(init.includes('[FIRApp defaultApp] != nil'),
    'session initializer preserves an already configured app');
  for (const required of ['firebase_api_key', 'firebase_app_id',
    'firebase_project_id', 'firebase_sender_id', 'FIROptions',
    'configureWithOptions']) {
    assert.ok(init.includes(required), `session initializer uses ${required}`);
  }
  for (const forbidden of ['beginRequest', 'beginMutating', 'finishRequest',
    'pendingReceipt', 'markMutation', 'rememberSettled', 'FIRAuth',
    'id_token', 'email', 'display_name']) {
    assert.ok(!init.includes(forbidden),
      `session initializer never touches ${forbidden}`);
  }
});

test('objc shared session helper never touches auth without a configured app', () => {
  const objc = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm'), 'utf8');
  // The shared reader backs both the session answer and the sign-out
  // failure terminal: it must guard the unconfigured case before any
  // Auth access, because the Swift missing-app fatalError is uncatchable
  // from Objective-C.
  const start = objc.indexOf('- (NSDictionary *)sessionOutcome:');
  assert.ok(start > 0, 'objc must define sessionOutcome');
  const end = objc.indexOf('- (NSString *)describeSession:', start);
  assert.ok(end > start, 'sessionOutcome body is bounded');
  const body = objc.slice(start, end);
  assert.ok(body.includes('[FIRApp defaultApp] == nil'),
    'session helper guards the unconfigured case');
  assert.ok(body.includes('[FIRAuth auth]'),
    'session helper still reads the live user when configured');
  assert.ok(body.indexOf('[FIRApp defaultApp]') < body.indexOf('[FIRAuth auth]'),
    'the configured-app guard runs before any Auth access');
  assert.ok(body.includes('localSession'),
    'unconfigured session answers the honest local session');
  assert.ok(!body.includes('@try') && !body.includes('@catch'),
    'session helper guards with FIRApp, never try/catch around Auth');
  for (const forbidden of ['beginRequest', 'beginMutating', 'finishRequest',
    'pendingReceipt', 'markMutation', 'rememberSettled',
    'configureWithOptions', 'id_token', 'email']) {
    assert.ok(!body.includes(forbidden),
      `session helper stays a synchronous read (${forbidden})`);
  }
  // The serialized answer keeps its wire format through the guarded
  // helper, with no bookkeeping and no signal of its own.
  const describeStart = objc.indexOf('- (NSString *)describeSession:');
  assert.ok(describeStart > 0, 'objc must define describeSession');
  const describeEnd = objc.indexOf('- (NSString *)fetchIdToken:', describeStart);
  assert.ok(describeEnd > describeStart, 'describeSession body is bounded');
  const describe = objc.slice(describeStart, describeEnd);
  assert.ok(describe.includes('sessionOutcome') && describe.includes('jsonString'),
    'describeSession serializes the shared session dictionary');
  for (const forbidden of ['beginRequest', 'beginMutating', 'finishRequest',
    'pendingReceipt', '_emit_outcome', 'call_deferred',
    'moonlit_identity_event', '[FIRAuth auth]']) {
    assert.ok(!describe.includes(forbidden),
      `describeSession stays synchronous with no signal (${forbidden})`);
  }
});

test('objc signs google in through googlesignin with a chaining forwarder', () => {
  const objc = readFileSync(
    join(REPO_ROOT, 'apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm'), 'utf8');
  for (const forbidden of ['user.profile', '.profile.email', 'givenName',
    'familyName', 'GIDSignInButton', 'signInWithConfiguration:',
    'restorePreviousSignIn', '(void *)method_getImplementation']) {
    assert.ok(!objc.includes(forbidden), `objc must not reference ${forbidden}`);
  }
  for (const required of ['GoogleSignIn/GoogleSignIn.h', 'GIDConfiguration',
    'initWithClientID:', 'signInWithPresentingViewController:',
    'FIRGoogleAuthProvider', 'credentialWithIDToken:',
    'idToken.tokenString', 'accessToken.tokenString',
    'MoonlitGoogleURLForwarder', 'installOnce', 'handleURL:',
    'application:openURL:options:', 's_originalOpenURL',
    'MoonlitOpenURLIMP', '(MoonlitOpenURLIMP)method_getImplementation',
    'method_setImplementation', 'class_addMethod',
    'options.clientID', 'topViewController',
    '"google.com"', 'google_sign_in_unavailable']) {
    assert.ok(objc.includes(required), `objc must use ${required}`);
  }
  // The forwarder offers Google the URL first and chains anything else to
  // the previous implementation; deleting either half breaks the test.
  const forwardStart = objc.indexOf('static BOOL MoonlitForwardOpenURL');
  assert.ok(forwardStart > 0, 'objc must define the forwarding function');
  const forwardBody = objc.slice(forwardStart, objc.indexOf('@interface MoonlitGoogleURLForwarder'));
  assert.ok(forwardBody.includes('handleURL:'), 'forwarder offers the url to GoogleSignIn');
  assert.ok(forwardBody.includes('s_originalOpenURL(self, cmd, app, url, options)'),
    'forwarder chains unclaimed urls to the previous implementation');
});

test('redaction masks pasted secrets and public ids alike', () => {
  const dirty =
    `id=${FAKE_GOOGLE_ID} key=openiap-kit_sk_SECRETVALUE123 ` +
    'pem=-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----';
  const clean = redactIdentitySecrets(dirty);
  assert.ok(!clean.includes(FAKE_GOOGLE_ID));
  assert.ok(!clean.includes('openiap-kit_sk_SECRETVALUE123'));
  assert.ok(!clean.includes('BEGIN PRIVATE KEY'));
  assert.match(clean, /\[google-client-id\]/);
  assert.match(clean, /\[iapkit-secret\]/);
  assert.match(clean, /\[private-key\]/);
});

function xmllintAvailable() {
  try {
    execFileSync('xmllint', ['--version'], { stdio: ['ignore', 'pipe', 'pipe'] });
    return true;
  } catch {
    return false;
  }
}

test('xmllint agrees the rendered manifest is well-formed', { skip: !xmllintAvailable() }, () => {
  withTempRoot((root) => {
    const outDir = join(root, 'builds/moonlit-identity/android');
    renderAndroidPluginProject({ root: REPO_ROOT, outDir });
    const rendered = join(outDir, 'MoonlitIdentity/src/main/AndroidManifest.xml');
    execFileSync('xmllint', ['--noout', rendered], { stdio: ['ignore', 'pipe', 'pipe'] });
  });
});

test('nm symbol reads allow output larger than the 1 MiB exec default', () => {
  assert.equal(NM_SYMBOL_BUFFER_BYTES, 16 * 1024 * 1024);
  withTempRoot((root) => {
    const lib = join(root, 'lib.a');
    writeFileSync(lib, 'fake archive');
    // The real merged archive reports ~5.9 MB of defined symbols; the reader
    // must request a buffer that fits instead of execFileSync's 1 MiB default.
    const big = `${'_symbol_padding\n'.repeat(80 * 1024)}moonlit_identity_ios_entry\n`;
    assert.ok(big.length > 1024 * 1024, `fixture is ${big.length} bytes`);
    let seen = null;
    const read = (command, args, options) => {
      seen = { command, args, options };
      return big;
    };
    const symbols = readLibSymbols(lib, read);
    assert.equal(seen.command, 'nm');
    assert.deepEqual(seen.args, ['-gUj', lib]);
    assert.equal(seen.options.maxBuffer, 16 * 1024 * 1024);
    assert.ok(symbols.includes('moonlit_identity_ios_entry'));
    assert.equal(verifyIosArtifact(lib, { nm: () => symbols }).ok, true);
  });
});

test('nm failures distinguish tool, overflow, exit status, and missing symbol', () => {
  withTempRoot((root) => {
    const lib = join(root, 'lib.a');
    writeFileSync(lib, 'fake archive');
    const missing = Object.assign(new Error('spawn nm ENOENT'), { code: 'ENOENT' });
    assert.deepEqual(verifyIosArtifact(lib, { nm: () => { throw missing; } }).checks, [
      'could not read symbols (Xcode nm not found)',
    ]);
    const overflow = Object.assign(new Error('stdout maxBuffer length exceeded'), { code: 'ENOBUFS' });
    assert.deepEqual(verifyIosArtifact(lib, { nm: () => { throw overflow; } }).checks, [
      'could not read symbols (nm output exceeded the 16 MiB cap)',
    ]);
    const failed = Object.assign(new Error('Command failed: nm'), { status: 1 });
    assert.deepEqual(verifyIosArtifact(lib, { nm: () => { throw failed; } }).checks, [
      'could not read symbols (nm failed with exit 1)',
    ]);
    assert.equal(describeNmFailure(new Error('boom')), 'could not read symbols (need Xcode nm)');
    assert.deepEqual(verifyIosArtifact(lib, { nm: () => 'other symbols\n' }).checks, [
      'library lacks the moonlit_identity_ios_entry symbol',
    ]);
  });
});

const IOS_ENTRY_SYMBOL = 'moonlit_identity_ios_entry';

function shellToolAvailable(command, args) {
  try {
    execFileSync(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    return true;
  } catch (error) {
    // Present but unhappy with the probe still counts as present.
    return error?.code !== 'ENOENT';
  }
}

function iosRegistrationToolchainAvailable() {
  if (!resolveGodotBinary()) return false;
  return shellToolAvailable('xcrun', ['clang++', '--version'])
    && shellToolAvailable('ar', ['--version'])
    && shellToolAvailable('nm', ['--version']);
}

function resolveGodotBinary() {
  if (process.env.GODOT_BIN) return process.env.GODOT_BIN;
  for (const name of ['godot', 'godot4']) {
    try {
      execFileSync('which', [name], { stdio: ['ignore', 'pipe', 'pipe'] });
      return name;
    } catch {
      // Try the next candidate.
    }
  }
  for (const base of ['/Applications/Godot.app/Contents/MacOS', '/usr/local/bin']) {
    for (const entry of readdirOrEmpty(base)) {
      if (/^Godot/.test(entry)) return join(base, entry);
    }
  }
  return null;
}

function readdirOrEmpty(dir) {
  try {
    return readdirSync(dir);
  } catch {
    return [];
  }
}

// The export template places the emitted C++ at namespace scope in
// dummy.cpp. This test dumps the exact manifest bytes through the real
// engine, compiles that whole source untouched at namespace scope, links
// it against a static archive holding the C entry, and proves the engine
// init callback defers the symbol-table write until initialize runs.
test('emitted registration compiles at namespace scope and defers to init',
  { skip: !iosRegistrationToolchainAvailable() }, () => {
    withTempRoot((root) => {
      const godotBin = resolveGodotBinary();
      assert.ok(godotBin, 'Godot binary resolves for the snippet dump');
      // The manifest gates on library presence, not content: an empty
      // placeholder keeps this hermetic instead of depending on the
      // ignored director-built archive.
      const fakeLib = join(root, 'libmoonlit_identity.debug.a');
      writeFileSync(fakeLib, '');
      const dumpScript = join(root, 'dump_registration.gd');
      writeFileSync(dumpScript, `extends SceneTree
const IOS_MANIFEST_SCRIPT: Script = preload(
\t"res://addons/moonlit-identity/ios_export_manifest.gd")
func _init() -> void:
\tvar code: String = IOS_MANIFEST_SCRIPT.registration_cpp_code(
\t\t"${fakeLib.replace(/\\/g, '/')}")
\tprint("REGISTRATION_DUMP_BEGIN")
\tprint(code)
\tprint("REGISTRATION_DUMP_END")
\tquit()
`);
      const homeDir = join(root, 'home');
      mkdirSync(homeDir, { recursive: true });
      const dumped = spawnSync(godotBin,
        ['--headless', '--path', join(REPO_ROOT, 'apps/game'),
          '--script', dumpScript],
        { encoding: 'utf8', timeout: 120000, env: { ...process.env, HOME: homeDir } });
      assert.equal(dumped.status, 0,
        `snippet dump exits cleanly: ${dumped.stderr ?? ''}`.slice(0, 500));
      const stdout = dumped.stdout ?? '';
      const begin = stdout.indexOf('REGISTRATION_DUMP_BEGIN\n');
      const end = stdout.indexOf('REGISTRATION_DUMP_END');
      assert.ok(begin >= 0 && end > begin, 'dump markers surround the snippet');
      const snippet = stdout.slice(begin + 'REGISTRATION_DUMP_BEGIN\n'.length, end);
      assert.ok(snippet.includes(IOS_ENTRY_SYMBOL),
        'dumped snippet names the entry');
      assert.ok(snippet.includes('MoonlitIdentityInitRegistrar'),
        'dumped snippet carries the registrar');
      // Whole-source compile at namespace scope: no wrapper, exactly as
      // the template consumes it. A naked call here fails the same way
      // the real export did ("a type specifier is required").
      const snippetCpp = join(root, 'registration.cpp');
      writeFileSync(snippetCpp, snippet);
      const entryStub = join(root, 'entry_stub.cpp');
      writeFileSync(entryStub,
        `extern "C" unsigned char ${IOS_ENTRY_SYMBOL}(void *, void *, void *) { return 7; }\n`);
      const entryObj = join(root, 'entry_stub.o');
      const entryLib = join(root, 'libentry.a');
      execFileSync('xcrun',
        ['clang++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
          '-c', entryStub, '-o', entryObj],
        { stdio: ['ignore', 'pipe', 'pipe'] });
      execFileSync('ar', ['rcs', entryLib, entryObj],
        { stdio: ['ignore', 'pipe', 'pipe'] });
      const harnessCpp = join(root, 'engine_harness.cpp');
      writeFileSync(harnessCpp, `#include <cstdio>
#include <cstring>
// Zero-initialized primitive registry, mirroring the engine side.
static void (*saved_callback)() = 0;
static int callback_count = 0;
static int table_writes = 0;
static char table_name[64];
static void *table_addr = 0;
void add_apple_embedded_platform_init_callback(void (*callback)()) {
\tsaved_callback = callback;
\tcallback_count += 1;
}
void register_dynamic_symbol(char *name, void *address) {
\tstd::strncpy(table_name, name, sizeof(table_name) - 1);
\ttable_addr = address;
\ttable_writes += 1;
}
extern "C" unsigned char ${IOS_ENTRY_SYMBOL}(void *, void *, void *);
int main() {
\t// Static initializers ran before main: exactly one callback queued,
\t// and crucially no symbol-table write yet.
\tif (callback_count != 1) {
\t\tstd::printf("callbacks=%d\\n", callback_count);
\t\treturn 10;
\t}
\tif (table_writes != 0) {
\t\tstd::printf("early table write\\n");
\t\treturn 11;
\t}
\t// Engine initialize stage: run the queued callback.
\tsaved_callback();
\tif (table_writes != 1) {
\t\tstd::printf("writes=%d\\n", table_writes);
\t\treturn 12;
\t}
\tconst bool ok = table_addr == (void *)&${IOS_ENTRY_SYMBOL}
\t\t&& std::strcmp(table_name, "${IOS_ENTRY_SYMBOL}") == 0;
\tstd::printf("registered=%s deferred=%s\\n", table_name, ok ? "yes" : "no");
\treturn ok ? 0 : 1;
}
`);
      const appPath = join(root, 'registration_app');
      execFileSync('xcrun',
        ['clang++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
          snippetCpp, harnessCpp, entryLib, '-o', appPath],
        { stdio: ['ignore', 'pipe', 'pipe'] });
      const run = spawnSync(appPath, [], { encoding: 'utf8', timeout: 30000 });
      assert.equal(run.status, 0, `harness defers registration to init: ${run.stdout ?? ''}`);
      assert.match(run.stdout ?? '', new RegExp(
        `registered=${IOS_ENTRY_SYMBOL} deferred=yes`));
      const symbols = String(execFileSync('nm', ['-gj', appPath],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
      assert.ok(symbols.split('\n').some((line) => line.trim() === `_${IOS_ENTRY_SYMBOL}`),
        'linked executable retains the C entry');
    });
  });
