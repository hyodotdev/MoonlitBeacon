import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  symlinkSync,
  utimesSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import {
  APP_STORE_CREDENTIAL_ENV,
  altoolAuthenticationArguments,
  appStoreAltoolArguments,
  appStoreExportOptionsPlist,
  assertArchiveMetadata,
  assertArtifactFresh,
  assertArtifactNotOlderThan,
  assertDistributionEntitlements,
  assertDistributionProfile,
  assertDistributionSignatureDetails,
  assertIosReleaseMetadata,
  assertIpaMetadata,
  assertMatchingReleasePayload,
  assertProfileContainsSigningCertificate,
  assertSafeIpaEntries,
  assertSigningCertificateValid,
  codeSigningCertificateArguments,
  extractPlistDataValues,
  iosCommandNeedsExclusiveWorkflow,
  IOS_RELEASE_BUILD_CHAIN_INPUTS,
  iosReleaseExcludedPaths,
  parseIosCommandArguments,
  redactSensitiveValues,
  readAppStoreCredentials,
  readIosReleaseMetadata,
  runExclusiveIosWorkflow,
  runWithStableReleaseSources,
  xcodebuildAuthenticationArguments,
} from './ios-distribution.mjs';

const EXPECTED = {
  bundleId: 'com.crossplatformkorea.moonlitbeacon',
  shortVersion: '1.0.0',
  buildVersion: '17',
  teamId: 'PRDQGB267K',
};

test('iOS release freshness inputs include official commands and the full build chain', () => {
  assert.deepEqual(IOS_RELEASE_BUILD_CHAIN_INPUTS, [
    'package.json',
    'apps/game',
    'notes/release/store-localizations.csv',
    'vendor/godot-iap-ios',
    'scripts/godot.mjs',
    'scripts/ios.mjs',
    'scripts/lib/godot-export-preflight.mjs',
    'scripts/lib/iapkit-config.mjs',
    'scripts/lib/ios-build.mjs',
    'scripts/lib/ios-distribution.mjs',
    'scripts/lib/release-environment.mjs',
  ]);
});

test('iOS CLI strictly validates per-command argument contracts before taking the lock', () => {
  assert.deepEqual(parseIosCommandArguments('devices', []), {
    command: 'devices',
    deviceId: null,
    dryRun: false,
    confirmUpload: false,
  });
  assert.deepEqual(parseIosCommandArguments('build', ['DEVICE-UDID']), {
    command: 'build',
    deviceId: 'DEVICE-UDID',
    dryRun: false,
    confirmUpload: false,
  });
  assert.deepEqual(parseIosCommandArguments('capture-build', ['DEVICE-UDID']), {
    command: 'capture-build',
    deviceId: 'DEVICE-UDID',
    dryRun: false,
    confirmUpload: false,
  });
  assert.deepEqual(parseIosCommandArguments('capture-build-isolated', ['DEVICE-UDID']), {
    command: 'capture-build-isolated',
    deviceId: 'DEVICE-UDID',
    dryRun: false,
    confirmUpload: false,
  });
  assert.deepEqual(parseIosCommandArguments('run', []), {
    command: 'run',
    deviceId: null,
    dryRun: false,
    confirmUpload: false,
  });
  assert.deepEqual(parseIosCommandArguments('validate', ['--dry-run']), {
    command: 'validate',
    deviceId: null,
    dryRun: true,
    confirmUpload: false,
  });
  assert.deepEqual(parseIosCommandArguments('upload', ['--confirm-upload']), {
    command: 'upload',
    deviceId: null,
    dryRun: false,
    confirmUpload: true,
  });
  assert.deepEqual(parseIosCommandArguments('upload', ['--dry-run']), {
    command: 'upload',
    deviceId: null,
    dryRun: true,
    confirmUpload: false,
  });

  for (const [command, args, message] of [
    ['devices', ['extra'], /extra arguments/],
    ['export', ['extra'], /extra arguments/],
    ['archive', ['--dry-run'], /extra arguments/],
    ['export-appstore', ['extra'], /extra arguments/],
    ['build', ['A', 'B'], /at most one/],
    ['capture-build', ['A', 'B'], /at most one/],
    ['capture-build-isolated', ['A', 'B'], /at most one/],
    ['run', ['--dry-run'], /device UDID/],
    ['validate', ['--dry-run', '--dry-run'], /more than once/],
    ['validate', ['--confirm-upload'], /confirm-upload/],
    ['upload', ['--confirm-upload', '--confirm-upload'], /more than once/],
    ['upload', ['--dry-run', '--confirm-upload'], /together/],
    ['upload', [], /requires --confirm-upload/],
    ['upload', ['--unknown'], /Unsupported/],
    ['unknown', [], /Usage/],
    [undefined, [], /Usage/],
  ]) {
    assert.throws(
      () => parseIosCommandArguments(command, args),
      (error) => error.exitCode === 2 && message.test(error.message),
      `${command ?? 'no command'} ${args.join(' ')}`,
    );
  }
});

function withTempRoot(callback) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-ios-distribution-'));
  try {
    return callback(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('reads Godot and iOS preset release metadata as one contract', () => {
  const metadata = readIosReleaseMetadata(
    'config/version="1.0.0"\n',
    [
      'application/bundle_identifier="com.crossplatformkorea.moonlitbeacon"',
      'application/short_version="1.0.0"',
      'application/version="17"',
      'application/app_store_team_id="PRDQGB267K"',
    ].join('\n'),
  );
  assert.deepEqual(metadata, {
    projectVersion: '1.0.0',
    ...EXPECTED,
  });
  assert.equal(assertIosReleaseMetadata(metadata, {
    expectedBundleId: EXPECTED.bundleId,
    expectedTeamId: EXPECTED.teamId,
  }), true);

  assert.throws(
    () => readIosReleaseMetadata(
      'config/version="1.0.1"\n',
      'application/bundle_identifier="x"\n'
        + 'application/short_version="1.0.0"\n'
        + 'application/version="17"\n'
        + 'application/app_store_team_id="T"\n',
    ),
    /Shared version/,
  );
});

test('archive and IPA bundle, version, and build number must be exact', () => {
  assert.equal(assertArchiveMetadata({
    CFBundleIdentifier: EXPECTED.bundleId,
    CFBundleShortVersionString: EXPECTED.shortVersion,
    CFBundleVersion: EXPECTED.buildVersion,
    Team: EXPECTED.teamId,
    Architectures: ['arm64'],
  }, EXPECTED), true);
  assert.equal(assertIpaMetadata({
    CFBundleIdentifier: EXPECTED.bundleId,
    CFBundleShortVersionString: EXPECTED.shortVersion,
    CFBundleVersion: EXPECTED.buildVersion,
  }, EXPECTED), true);
  assert.throws(
    () => assertArchiveMetadata({
      CFBundleIdentifier: 'wrong.bundle',
      CFBundleShortVersionString: EXPECTED.shortVersion,
      CFBundleVersion: EXPECTED.buildVersion,
      Team: EXPECTED.teamId,
      Architectures: ['arm64'],
    }, EXPECTED),
    /bundle ID/,
  );
  assert.throws(
    () => assertIpaMetadata({
      CFBundleIdentifier: EXPECTED.bundleId,
      CFBundleShortVersionString: EXPECTED.shortVersion,
      CFBundleVersion: '16',
    }, EXPECTED),
    /build number/,
  );
});

test('rejects an archive or IPA older than inputs and prerequisite output', () => {
  withTempRoot((root) => {
    const inputDir = join(root, 'input');
    const artifact = join(root, 'artifact');
    const prerequisite = join(root, 'prerequisite');
    mkdirSync(inputDir);
    const input = join(inputDir, 'game.gd');
    writeFileSync(input, 'game');
    writeFileSync(artifact, 'archive');
    writeFileSync(prerequisite, 'archive-info');
    const old = new Date('2026-01-01T00:00:00Z');
    const middle = new Date('2026-01-02T00:00:00Z');
    const fresh = new Date('2026-01-03T00:00:00Z');

    utimesSync(artifact, old, old);
    utimesSync(input, fresh, fresh);
    assert.throws(
      () => assertArtifactFresh({
        artifactPath: artifact,
        inputPaths: [inputDir],
      }),
      /ios:archive/,
    );

    utimesSync(artifact, fresh, fresh);
    assert.equal(assertArtifactFresh({
      artifactPath: artifact,
      inputPaths: [inputDir],
    }).path, input);

    const almostFresh = new Date(fresh.getTime() - 500);
    utimesSync(artifact, almostFresh, almostFresh);
    assert.throws(
      () => assertArtifactFresh({
        artifactPath: artifact,
        inputPaths: [inputDir],
      }),
      /ios:archive/,
      'must not allow an archive even 1 second stale',
    );

    utimesSync(prerequisite, fresh, fresh);
    utimesSync(artifact, middle, middle);
    assert.throws(
      () => assertArtifactNotOlderThan({
        artifactPath: artifact,
        prerequisitePath: prerequisite,
      }),
      /ios:export-appstore/,
    );

    utimesSync(artifact, almostFresh, almostFresh);
    assert.throws(
      () => assertArtifactNotOlderThan({
        artifactPath: artifact,
        prerequisitePath: prerequisite,
      }),
      /ios:export-appstore/,
      'must not allow an IPA even 1 second stale',
    );
  });
});

test('IPA game payload must match the just-verified xcarchive byte for byte', () => {
  const payloads = new Map([
    ['/archive/game.pck', Buffer.from('release payload')],
    ['/ipa/game.pck', Buffer.from('release payload')],
  ]);
  const read = (path) => payloads.get(path);
  assert.equal(
    assertMatchingReleasePayload(
      '/archive/game.pck',
      '/ipa/game.pck',
      { read },
    ),
    true,
  );
  payloads.set('/ipa/game.pck', Buffer.from('stale payload'));
  assert.throws(
    () => assertMatchingReleasePayload(
      '/archive/game.pck',
      '/ipa/game.pck',
      { read },
    ),
    /does not match the verified xcarchive/,
  );
  assert.throws(
    () => assertMatchingReleasePayload(
      '/archive/missing.pck',
      '/ipa/game.pck',
      { read: () => { throw new Error('missing'); } },
    ),
    /Failed to read game payload/,
  );
});

test('tests and tools excluded from export do not invalidate archive freshness', () => {
  withTempRoot((root) => {
    const game = join(root, 'game');
    const tests = join(game, 'tests');
    const tools = join(game, 'tools');
    mkdirSync(tests, { recursive: true });
    mkdirSync(tools, { recursive: true });
    const source = join(game, 'scripts.gd');
    const testSource = join(tests, 'test_game.gd');
    const toolSource = join(tools, 'capture.py');
    const artifact = join(root, 'archive-info.plist');
    for (const path of [source, testSource, toolSource, artifact]) {
      writeFileSync(path, 'input');
    }
    const old = new Date('2026-01-01T00:00:00Z');
    const archiveTime = new Date('2026-01-02T00:00:00Z');
    const future = new Date('2026-01-03T00:00:00Z');
    utimesSync(source, old, old);
    utimesSync(artifact, archiveTime, archiveTime);
    utimesSync(testSource, future, future);
    utimesSync(toolSource, future, future);

    assert.equal(
      assertArtifactFresh({
        artifactPath: artifact,
        inputPaths: [game],
        excludePaths: [tests, tools],
      }).path,
      source,
    );
    assert.throws(
      () => assertArtifactFresh({
        artifactPath: artifact,
        inputPaths: [game],
      }),
      /ios:archive/,
    );
  });
});

test('Android-generated output does not invalidate archive freshness', () => {
  withTempRoot((root) => {
    const game = join(root, 'apps/game');
    const source = join(game, 'resources/heroes/keeper.tres');
    const androidBuild = join(
      game,
      'android/build/res/values/godot_project_name_string.xml',
    );
    const androidGradle = join(
      game,
      'android/.gradle/caches/build-cache.bin',
    );
    const androidBuildVersion = join(game, 'android/.build_version');
    const artifact = join(root, 'archive-info.plist');
    for (const path of [
      source,
      androidBuild,
      androidGradle,
      androidBuildVersion,
      artifact,
    ]) {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, 'input');
    }
    const old = new Date('2026-01-01T00:00:00Z');
    const archiveTime = new Date('2026-01-02T00:00:00Z');
    const future = new Date('2026-01-03T00:00:00Z');
    utimesSync(source, old, old);
    utimesSync(artifact, archiveTime, archiveTime);
    for (const generated of [
      androidBuild,
      androidGradle,
      androidBuildVersion,
    ]) {
      utimesSync(generated, future, future);
    }

    assert.equal(
      assertArtifactFresh({
        artifactPath: artifact,
        inputPaths: [game],
        excludePaths: iosReleaseExcludedPaths(root),
      }).path,
      source,
    );

    utimesSync(source, future, future);
    assert.throws(
      () => assertArtifactFresh({
        artifactPath: artifact,
        inputPaths: [game],
        excludePaths: iosReleaseExcludedPaths(root),
      }),
      /ios:archive/,
      'an actual game resource change must still mark the archive stale',
    );
  });
});

test('API key allows only a mode-600 P-256 EC p8 outside the repository', () => {
  withTempRoot((root) => {
    const outside = mkdtempSync(join(tmpdir(), 'moonlit-asc-key-'));
    try {
      const privateKeyPath = join(outside, 'AuthKey_TESTKEY123.p8');
      const { privateKey } = generateKeyPairSync('ec', {
        namedCurve: 'P-256',
      });
      writeFileSync(
        privateKeyPath,
        privateKey.export({ format: 'pem', type: 'pkcs8' }),
        { mode: 0o600 },
      );
      chmodSync(privateKeyPath, 0o600);
      const env = {
        [APP_STORE_CREDENTIAL_ENV.keyId]: 'TESTKEY123',
        [APP_STORE_CREDENTIAL_ENV.issuerId]:
          '01234567-89ab-cdef-0123-456789abcdef',
        [APP_STORE_CREDENTIAL_ENV.privateKeyPath]: privateKeyPath,
      };
      const credentials = readAppStoreCredentials({ env, root });
      assert.deepEqual(credentials, {
        keyId: 'TESTKEY123',
        issuerId: '01234567-89ab-cdef-0123-456789abcdef',
        privateKeyPath,
      });

      chmodSync(privateKeyPath, 0o644);
      assert.throws(
        () => readAppStoreCredentials({ env, root }),
        /mode must be 600/,
      );
      chmodSync(privateKeyPath, 0o600);

      const inside = join(root, 'AuthKey_TESTKEY123.p8');
      writeFileSync(inside, privateKey.export({ format: 'pem', type: 'pkcs8' }), {
        mode: 0o600,
      });
      assert.throws(
        () => readAppStoreCredentials({
          env: {
            ...env,
            [APP_STORE_CREDENTIAL_ENV.privateKeyPath]: inside,
          },
          root,
        }),
        /outside the repository/,
      );

      const aliasRoot = mkdtempSync(join(tmpdir(), 'moonlit-asc-alias-'));
      try {
        symlinkSync(root, join(aliasRoot, 'repository'));
        assert.throws(
          () => readAppStoreCredentials({
            env: {
              ...env,
              [APP_STORE_CREDENTIAL_ENV.privateKeyPath]: join(
                aliasRoot,
                'repository',
                'AuthKey_TESTKEY123.p8',
              ),
            },
            root,
          }),
          /outside the repository/,
        );
      } finally {
        rmSync(aliasRoot, { recursive: true, force: true });
      }

      const wrongCurvePath = join(outside, 'AuthKey_WRONGCURVE.p8');
      const { privateKey: wrongCurve } = generateKeyPairSync('ec', {
        namedCurve: 'P-384',
      });
      writeFileSync(
        wrongCurvePath,
        wrongCurve.export({ format: 'pem', type: 'pkcs8' }),
        { mode: 0o600 },
      );
      assert.throws(
        () => readAppStoreCredentials({
          env: {
            ...env,
            [APP_STORE_CREDENTIAL_ENV.privateKeyPath]: wrongCurvePath,
          },
          root,
        }),
        /P-256 EC/,
      );
    } finally {
      rmSync(outside, { recursive: true, force: true });
    }
  });
});

test('xcodebuild and altool auth arguments do not include p8 contents', () => {
  const credentials = {
    keyId: 'TESTKEY123',
    issuerId: '01234567-89ab-cdef-0123-456789abcdef',
    privateKeyPath: '/outside/AuthKey_TESTKEY123.p8',
  };
  assert.deepEqual(xcodebuildAuthenticationArguments(credentials), [
    '-authenticationKeyPath', credentials.privateKeyPath,
    '-authenticationKeyID', credentials.keyId,
    '-authenticationKeyIssuerID', credentials.issuerId,
  ]);
  assert.deepEqual(altoolAuthenticationArguments(credentials), [
    '--api-key', credentials.keyId,
    '--api-issuer', credentials.issuerId,
    '--p8-file-path', credentials.privateKeyPath,
  ]);
  assert.deepEqual(
    appStoreAltoolArguments('validate', '/tmp/app.ipa', credentials).slice(0, 5),
    ['altool', '--validate-app', '/tmp/app.ipa', '-t', 'ios'],
  );
  assert.deepEqual(
    appStoreAltoolArguments('upload', '/tmp/app.ipa', credentials).slice(0, 6),
    ['altool', '--upload-app', '-f', '/tmp/app.ipa', '-t', 'ios'],
  );
  assert.equal(
    redactSensitiveValues(
      `key=${credentials.keyId} issuer=${credentials.issuerId} `
        + `path=${credentials.privateKeyPath}`,
      Object.values(credentials),
    ),
    'key=[REDACTED] issuer=[REDACTED] path=[REDACTED]',
  );
});

test('App Store export options use automatic distribution signing and a pinned version', () => {
  const plist = appStoreExportOptionsPlist(EXPECTED);
  assert.match(plist, /<string>app-store-connect<\/string>/);
  assert.match(plist, /<key>destination<\/key>\s*<string>export<\/string>/);
  assert.match(
    plist,
    /<key>manageAppVersionAndBuildNumber<\/key>\s*<false\/>/,
  );
  assert.match(plist, /<key>signingStyle<\/key>\s*<string>automatic<\/string>/);
  assert.doesNotMatch(plist, /TESTKEY|PRIVATE KEY|issuer/i);
});

test('rejects development/device distribution in distribution signature, entitlements, and profile', () => {
  const signature = [
    `Identifier=${EXPECTED.bundleId}`,
    'Authority=Apple Distribution: Example (PRDQGB267K)',
    `TeamIdentifier=${EXPECTED.teamId}`,
  ].join('\n');
  const entitlements = {
    'application-identifier': `${EXPECTED.teamId}.${EXPECTED.bundleId}`,
    'com.apple.developer.team-identifier': EXPECTED.teamId,
    'get-task-allow': false,
  };
  assert.equal(
    assertDistributionSignatureDetails(signature, EXPECTED),
    true,
  );
  assert.equal(assertDistributionEntitlements(entitlements, EXPECTED), true);
  assert.equal(assertDistributionProfile({
    ExpirationDate: '2030-01-01T00:00:00Z',
    Entitlements: entitlements,
  }, {
    ...EXPECTED,
    now: new Date('2026-01-01T00:00:00Z'),
  }), true);

  assert.throws(
    () => assertDistributionSignatureDetails(
      signature.replace('Apple Distribution', 'Apple Development'),
      EXPECTED,
    ),
    /Apple Distribution/,
  );
  assert.throws(
    () => assertDistributionEntitlements({
      ...entitlements,
      'get-task-allow': true,
    }, EXPECTED),
    /debugging/,
  );
  assert.throws(
    () => assertDistributionProfile({
      ExpirationDate: '2030-01-01T00:00:00Z',
      ProvisionedDevices: ['device'],
      Entitlements: entitlements,
    }, EXPECTED),
    /device\/enterprise distribution/,
  );

  const signingCertificate = Buffer.from('signing certificate');
  assert.equal(
    assertProfileContainsSigningCertificate({
      DeveloperCertificates: [
        Buffer.from('other certificate').toString('base64'),
        signingCertificate.toString('base64'),
      ],
    }, signingCertificate),
    true,
  );
  assert.throws(
    () => assertProfileContainsSigningCertificate({
      DeveloperCertificates: [
        Buffer.from('other certificate').toString('base64'),
      ],
    }, signingCertificate),
    /not included/,
  );
  assert.throws(
    () => assertProfileContainsSigningCertificate({
      DeveloperCertificates: ['not base64'],
    }, signingCertificate),
    /not included/,
  );
  assert.equal(
    assertSigningCertificateValid(signingCertificate, {
      now: new Date('2026-07-30T00:00:00Z'),
      parse: () => ({
        validFrom: '2026-01-01T00:00:00Z',
        validTo: '2027-01-01T00:00:00Z',
      }),
    }),
    true,
  );
  assert.throws(
    () => assertSigningCertificateValid(signingCertificate, {
      now: new Date('2027-01-01T00:00:00Z'),
      parse: () => ({
        validFrom: '2026-01-01T00:00:00Z',
        validTo: '2027-01-01T00:00:00Z',
      }),
    }),
    /expired/,
  );

  const certificateValues = extractPlistDataValues(
    `<plist><array>
      <data>
        ${Buffer.from('first').toString('base64')}
      </data>
      <data>${signingCertificate.toString('base64')}</data>
    </array></plist>`,
    'distribution provisioning profile',
  );
  assert.deepEqual(certificateValues, [
    Buffer.from('first').toString('base64'),
    signingCertificate.toString('base64'),
  ]);
  assert.throws(
    () => extractPlistDataValues(
      '<plist><array><data>not base64</data></array></plist>',
      'distribution provisioning profile',
    ),
    /certificate array/,
  );
  assert.deepEqual(
    codeSigningCertificateArguments(
      '/tmp/signing-certificate-',
      '/tmp/MoonlitBeacon.app',
    ),
    [
      '-d',
      '--extract-certificates=/tmp/signing-certificate-',
      '/tmp/MoonlitBeacon.app',
    ],
  );
});

test('IPA must contain exactly one safe Payload app bundle', () => {
  assert.equal(assertSafeIpaEntries([
    'Payload/MoonlitBeacon.app/',
    'Payload/MoonlitBeacon.app/Info.plist',
  ]), 'Payload/MoonlitBeacon.app');
  assert.throws(
    () => assertSafeIpaEntries([
      'Payload/A.app/Info.plist',
      'Payload/B.app/Info.plist',
    ]),
    /count is not 1/,
  );
  assert.throws(
    () => assertSafeIpaEntries([
      'Payload/MoonlitBeacon.app/../../escape',
    ]),
    /unsafe/,
  );
});

test('every command that reads or changes iOS output is serialized for the whole run', () => {
  for (const command of [
    'export',
    'build',
    'capture-build',
    'capture-build-isolated',
    'run',
    'archive',
    'export-appstore',
    'validate',
    'upload',
  ]) {
    assert.equal(iosCommandNeedsExclusiveWorkflow(command), true, command);
  }
  assert.equal(iosCommandNeedsExclusiveWorkflow('devices'), false);

  const events = [];
  let held = false;
  const hooks = {
    acquire() {
      if (held) throw new Error('busy');
      held = true;
      events.push('acquire');
    },
    release() {
      assert.equal(held, true);
      events.push('release');
      held = false;
    },
  };

  runExclusiveIosWorkflow('capture-build', {
    ...hooks,
    execute() {
      events.push('godot-export');
      assert.throws(
        () => runExclusiveIosWorkflow('run', {
          ...hooks,
          execute() {
            events.push('second-run');
          },
        }),
        /busy/,
      );
      events.push('xcodebuild-capture');
      assert.throws(
        () => runExclusiveIosWorkflow('export-appstore', {
          ...hooks,
          execute() {
            events.push('second-export');
          },
        }),
        /busy/,
      );
    },
  });

  assert.deepEqual(events, [
    'acquire',
    'godot-export',
    'xcodebuild-capture',
    'release',
  ]);
  assert.equal(held, false);
});

test('releases the workflow lock at the end even when the whole iOS job fails', () => {
  const events = [];
  assert.throws(
    () => runExclusiveIosWorkflow('archive', {
      acquire() {
        events.push('acquire');
      },
      execute() {
        events.push('archive');
        throw new Error('archive failed');
      },
      release() {
        events.push('release');
      },
    }),
    /archive failed/,
  );
  assert.deepEqual(events, ['acquire', 'archive', 'release']);
});

test('iOS release freshness check is serialized with Android export temporary source moves', () => {
  const events = [];
  assert.equal(
    runWithStableReleaseSources({
      alreadyLocked: false,
      acquire() {
        events.push('acquire-iap-source');
      },
      execute() {
        events.push('scan-release-source');
        return 'fresh';
      },
      release() {
        events.push('release-iap-source');
      },
    }),
    'fresh',
  );
  assert.deepEqual(events, [
    'acquire-iap-source',
    'scan-release-source',
    'release-iap-source',
  ]);

  events.length = 0;
  assert.throws(
    () => runWithStableReleaseSources({
      alreadyLocked: false,
      acquire() {
        events.push('acquire-iap-source');
      },
      execute() {
        events.push('scan-release-source');
        throw new Error('stale');
      },
      release() {
        events.push('release-iap-source');
      },
    }),
    /stale/,
  );
  assert.deepEqual(events, [
    'acquire-iap-source',
    'scan-release-source',
    'release-iap-source',
  ]);

  events.length = 0;
  runWithStableReleaseSources({
    alreadyLocked: true,
    acquire() {
      events.push('unexpected-acquire');
    },
    execute() {
      events.push('nested-scan');
    },
    release() {
      events.push('unexpected-release');
    },
  });
  assert.deepEqual(events, ['nested-scan']);
});
