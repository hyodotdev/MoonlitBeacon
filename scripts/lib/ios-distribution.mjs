import {
  createHash,
  createPrivateKey,
  X509Certificate,
} from 'node:crypto';
import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
} from 'node:fs';
import { isAbsolute, relative, resolve, sep } from 'node:path';

export const APP_STORE_CREDENTIAL_ENV = Object.freeze({
  keyId: 'MOONLIT_ASC_KEY_ID',
  issuerId: 'MOONLIT_ASC_ISSUER_ID',
  privateKeyPath: 'MOONLIT_ASC_PRIVATE_KEY',
});
export const IOS_EXCLUSIVE_WORKFLOW_COMMANDS = Object.freeze([
  'export',
  'build',
  'capture-build',
  'capture-build-isolated',
  'run',
  'archive',
  'export-appstore',
  'validate',
  'upload',
]);
export const IOS_RELEASE_BUILD_CHAIN_INPUTS = Object.freeze([
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

const IOS_COMMANDS = Object.freeze([
  'devices',
  ...IOS_EXCLUSIVE_WORKFLOW_COMMANDS,
]);
const IOS_COMMAND_USAGE = 'Usage: node scripts/ios.mjs '
  + '<devices|export|build|capture-build|capture-build-isolated|run|archive|export-appstore|validate|upload> '
  + '[udid|--dry-run|--confirm-upload]';

function iosCliError(message) {
  return Object.assign(new Error(message), { exitCode: 2 });
}

export function parseIosCommandArguments(command, args = []) {
  if (!IOS_COMMANDS.includes(command)) {
    throw iosCliError(IOS_COMMAND_USAGE);
  }
  if (!Array.isArray(args)) {
    throw new TypeError('iOS command arguments must be an array.');
  }

  if (
    command === 'build'
    || command === 'capture-build'
    || command === 'capture-build-isolated'
    || command === 'run'
  ) {
    if (
      args.length > 1
      || args.some((arg) => (
        typeof arg !== 'string'
        || arg.length === 0
        || arg.startsWith('--')
      ))
    ) {
      throw iosCliError(
        `${command} accepts at most one device UDID.`,
      );
    }
    return {
      command,
      deviceId: args[0] ?? null,
      dryRun: false,
      confirmUpload: false,
    };
  }

  if (command === 'validate' || command === 'upload') {
    const allowed = new Set(['--dry-run', '--confirm-upload']);
    const invalid = args.filter((arg) => !allowed.has(arg));
    if (invalid.length > 0) {
      throw iosCliError('Unsupported iOS option.');
    }
    const duplicates = args.filter(
      (arg, index) => args.indexOf(arg) !== index,
    );
    if (duplicates.length > 0) {
      throw iosCliError(
        `Cannot specify the same iOS option more than once: ${[...new Set(duplicates)].join(', ')}`,
      );
    }

    const dryRun = args.includes('--dry-run');
    const confirmUpload = args.includes('--confirm-upload');
    if (command === 'validate' && confirmUpload) {
      throw iosCliError('validate does not take --confirm-upload.');
    }
    if (command === 'upload' && dryRun && confirmUpload) {
      throw iosCliError(
        'upload cannot take --dry-run and --confirm-upload together.',
      );
    }
    if (command === 'upload' && !dryRun && !confirmUpload) {
      throw iosCliError(
        'TestFlight upload requires --confirm-upload. '
        + 'Run `pnpm ios:upload:dry-run` first.',
      );
    }
    return {
      command,
      deviceId: null,
      dryRun,
      confirmUpload,
    };
  }

  if (args.length > 0) {
    throw iosCliError(
      `${command} does not take extra arguments.`,
    );
  }
  return {
    command,
    deviceId: null,
    dryRun: false,
    confirmUpload: false,
  };
}

export function iosCommandNeedsExclusiveWorkflow(command) {
  return IOS_EXCLUSIVE_WORKFLOW_COMMANDS.includes(command);
}

export function runExclusiveIosWorkflow(
  command,
  { acquire, execute, release },
) {
  const exclusive = iosCommandNeedsExclusiveWorkflow(command);
  let acquired = false;
  if (exclusive) {
    acquire();
    acquired = true;
  }
  try {
    return execute();
  } finally {
    if (acquired) release();
  }
}

export function runWithStableReleaseSources({
  alreadyLocked,
  acquire,
  execute,
  release,
}) {
  let acquired = false;
  if (!alreadyLocked) {
    acquire();
    acquired = true;
  }
  try {
    return execute();
  } finally {
    if (acquired) release();
  }
}

function escapeRegex(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function readQuotedSetting(source, key) {
  const match = source.match(
    new RegExp(`^${escapeRegex(key)}=(\"(?:[^\"\\\\]|\\\\.)*\")\\s*$`, 'm'),
  );
  if (!match) throw new Error(`Release setting ${key} was not found.`);
  try {
    return JSON.parse(match[1]);
  } catch {
    throw new Error(`Release setting ${key} string format is invalid.`);
  }
}

export function readIosReleaseMetadata(projectGodot, exportPresets) {
  const metadata = {
    projectVersion: readQuotedSetting(projectGodot, 'config/version'),
    bundleId: readQuotedSetting(
      exportPresets,
      'application/bundle_identifier',
    ),
    shortVersion: readQuotedSetting(
      exportPresets,
      'application/short_version',
    ),
    buildVersion: readQuotedSetting(exportPresets, 'application/version'),
    teamId: readQuotedSetting(exportPresets, 'application/app_store_team_id'),
  };
  if (metadata.projectVersion !== metadata.shortVersion) {
    throw new Error(
      `Shared version ${metadata.projectVersion} and iOS display version `
      + `${metadata.shortVersion} differ.`,
    );
  }
  return metadata;
}

export function assertIosReleaseMetadata(
  metadata,
  { expectedBundleId, expectedTeamId },
) {
  if (metadata.bundleId !== expectedBundleId) {
    throw new Error(
      `iOS release bundle ID differs: ${metadata.bundleId || 'missing'}`,
    );
  }
  if (metadata.teamId !== expectedTeamId) {
    throw new Error(
      `iOS release Team ID differs: ${metadata.teamId || 'missing'}`,
    );
  }
  for (const [name, value] of [
    ['display version', metadata.shortVersion],
    ['build number', metadata.buildVersion],
  ]) {
    if (!/^[0-9]+(?:\.[0-9]+){0,2}$/.test(value)) {
      throw new Error(`iOS ${name} format is invalid: ${value}`);
    }
  }
  return true;
}

export function assertArchiveMetadata(properties, expected) {
  if (!properties || typeof properties !== 'object') {
    throw new Error('xcarchive ApplicationProperties is missing.');
  }
  const comparisons = [
    ['bundle ID', properties.CFBundleIdentifier, expected.bundleId],
    [
      'display version',
      properties.CFBundleShortVersionString,
      expected.shortVersion,
    ],
    ['build number', properties.CFBundleVersion, expected.buildVersion],
    ['Team ID', properties.Team, expected.teamId],
  ];
  for (const [label, actual, wanted] of comparisons) {
    if (actual !== wanted) {
      throw new Error(
        `xcarchive ${label} does not match the release setting: `
        + `${actual || 'missing'} (expected ${wanted})`,
      );
    }
  }
  if (
    !Array.isArray(properties.Architectures)
    || !properties.Architectures.includes('arm64')
  ) {
    throw new Error('xcarchive has no arm64 architecture.');
  }
  return true;
}

export function assertIpaMetadata(info, expected) {
  const comparisons = [
    ['bundle ID', info?.CFBundleIdentifier, expected.bundleId],
    ['display version', info?.CFBundleShortVersionString, expected.shortVersion],
    ['build number', info?.CFBundleVersion, expected.buildVersion],
  ];
  for (const [label, actual, wanted] of comparisons) {
    if (actual !== wanted) {
      throw new Error(
        `IPA ${label} does not match the release setting: `
        + `${actual || 'missing'} (expected ${wanted})`,
      );
    }
  }
  return true;
}

export function iosReleaseExcludedPaths(root) {
  return [
    resolve(root, 'apps/game/tests'),
    resolve(root, 'apps/game/tools'),
    // Godot/Gradle recreates this file on Android export. It is not an iOS release
    // input, so a following Play build must not mark the xcarchive stale.
    resolve(root, 'apps/game/android/.build_version'),
    resolve(root, 'apps/game/android/.gradle'),
    resolve(root, 'apps/game/android/build'),
  ];
}

function newestFileUnder(path, current, {
  excludedPaths = [],
  exists = existsSync,
  lstat = lstatSync,
  readDir = readdirSync,
  stat = statSync,
} = {}) {
  if (excludedPaths.some((excluded) => pathIsInside(excluded, path))) {
    return current;
  }
  if (!exists(path)) return current;
  const entry = lstat(path);
  if (entry.isSymbolicLink()) return current;
  if (entry.isFile()) {
    const mtimeMs = stat(path).mtimeMs;
    return !current || mtimeMs > current.mtimeMs
      ? { path, mtimeMs }
      : current;
  }
  if (!entry.isDirectory()) return current;
  let newest = current;
  for (const child of readDir(path, { withFileTypes: true })) {
    if (child.name === '.godot' || child.name === '.git') continue;
    newest = newestFileUnder(resolve(path, child.name), newest, {
      excludedPaths,
      exists,
      lstat,
      readDir,
      stat,
    });
  }
  return newest;
}

export function newestReleaseInput(paths, { excludePaths = [], fs = {} } = {}) {
  const excludedPaths = excludePaths.map((path) => resolve(path));
  let newest = null;
  for (const path of paths) {
    newest = newestFileUnder(path, newest, {
      ...fs,
      excludedPaths,
    });
  }
  if (!newest) throw new Error('iOS release input file was not found.');
  return newest;
}

export function assertArtifactFresh({
  artifactPath,
  excludePaths = [],
  inputPaths,
  toleranceMs = 0,
  fs = {},
}) {
  const exists = fs.exists ?? existsSync;
  const stat = fs.stat ?? statSync;
  if (!exists(artifactPath)) {
    throw new Error(`iOS release output is missing: ${artifactPath}`);
  }
  const artifactMtimeMs = stat(artifactPath).mtimeMs;
  const newest = newestReleaseInput(inputPaths, { excludePaths, fs });
  if (artifactMtimeMs + toleranceMs < newest.mtimeMs) {
    throw new Error(
      `iOS release output is older than ${newest.path}. `
      + 'Re-run from `pnpm ios:archive`.',
    );
  }
  return newest;
}

export function assertArtifactNotOlderThan({
  artifactPath,
  prerequisitePath,
  toleranceMs = 0,
  fs = {},
}) {
  const exists = fs.exists ?? existsSync;
  const stat = fs.stat ?? statSync;
  if (!exists(artifactPath)) {
    throw new Error(`iOS release output is missing: ${artifactPath}`);
  }
  if (!exists(prerequisitePath)) {
    throw new Error(`iOS prerequisite output is missing: ${prerequisitePath}`);
  }
  if (
    stat(artifactPath).mtimeMs + toleranceMs
    < stat(prerequisitePath).mtimeMs
  ) {
    throw new Error(
      `${artifactPath} is older than the prerequisite output. `
      + 'Re-run `pnpm ios:export-appstore`.',
    );
  }
  return true;
}

export function assertMatchingReleasePayload(
  archivePayload,
  ipaPayload,
  { read = readFileSync } = {},
) {
  const digest = (path) => createHash('sha256').update(read(path)).digest();
  let archiveDigest;
  let ipaDigest;
  try {
    archiveDigest = digest(archivePayload);
    ipaDigest = digest(ipaPayload);
  } catch {
    throw new Error('Failed to read game payload from xcarchive and IPA.');
  }
  if (!archiveDigest.equals(ipaDigest)) {
    throw new Error('IPA game payload does not match the verified xcarchive.');
  }
  return true;
}

function pathIsInside(parent, child) {
  const relation = relative(resolve(parent), resolve(child));
  return relation === ''
    || (!relation.startsWith(`..${sep}`) && relation !== '..' && !isAbsolute(relation));
}

export function readAppStoreCredentials({
  env = process.env,
  root,
  exists = existsSync,
  lstat = lstatSync,
  read = readFileSync,
  realpath = realpathSync,
  parsePrivateKey = createPrivateKey,
} = {}) {
  const keyId = env[APP_STORE_CREDENTIAL_ENV.keyId]?.trim();
  const issuerId = env[APP_STORE_CREDENTIAL_ENV.issuerId]?.trim();
  const privateKeyPath = env[APP_STORE_CREDENTIAL_ENV.privateKeyPath]?.trim();
  const missing = Object.entries(APP_STORE_CREDENTIAL_ENV)
    .filter(([, envName]) => !env[envName]?.trim())
    .map(([, envName]) => envName);
  if (missing.length > 0) {
    throw new Error(
      `App Store Connect auth environment variable is missing: ${missing.join(', ')}`,
    );
  }
  if (!/^[A-Z0-9]{10}$/.test(keyId)) {
    throw new Error('App Store Connect Key ID format is invalid.');
  }
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(issuerId)
  ) {
    throw new Error('App Store Connect Issuer ID format is invalid.');
  }
  if (!isAbsolute(privateKeyPath)) {
    throw new Error('App Store Connect .p8 path must be absolute.');
  }
  if (pathIsInside(root, privateKeyPath)) {
    throw new Error('App Store Connect .p8 must live outside the repository.');
  }
  if (!exists(privateKeyPath)) {
    throw new Error('App Store Connect .p8 file was not found.');
  }
  const file = lstat(privateKeyPath);
  if (!file.isFile() || file.isSymbolicLink()) {
    throw new Error('App Store Connect .p8 must be a regular file.');
  }
  if (pathIsInside(realpath(root), realpath(privateKeyPath))) {
    throw new Error('App Store Connect .p8 must live outside the repository.');
  }
  if ((file.mode & 0o077) !== 0) {
    throw new Error('App Store Connect .p8 mode must be 600 or tighter.');
  }
  try {
    const key = parsePrivateKey(read(privateKeyPath));
    if (
      key.asymmetricKeyType !== 'ec'
      || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1'
    ) {
      throw new Error('unexpected key type');
    }
  } catch {
    throw new Error(
      'App Store Connect .p8 must be a P-256 EC private key.',
    );
  }
  return Object.freeze({ keyId, issuerId, privateKeyPath });
}

export function xcodebuildAuthenticationArguments(credentials) {
  return [
    '-authenticationKeyPath', credentials.privateKeyPath,
    '-authenticationKeyID', credentials.keyId,
    '-authenticationKeyIssuerID', credentials.issuerId,
  ];
}

export function altoolAuthenticationArguments(credentials) {
  return [
    '--api-key', credentials.keyId,
    '--api-issuer', credentials.issuerId,
    '--p8-file-path', credentials.privateKeyPath,
  ];
}

export function redactSensitiveValues(value, sensitiveValues = []) {
  let text = typeof value === 'string' ? value : '';
  const uniqueValues = [...new Set(
    sensitiveValues
      .filter((entry) => typeof entry === 'string' && entry.length > 0)
      .sort((left, right) => right.length - left.length),
  )];
  for (const sensitive of uniqueValues) {
    text = text.replaceAll(sensitive, '[REDACTED]');
  }
  return text;
}

function xmlEscape(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

export function appStoreExportOptionsPlist({ bundleId, teamId }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>destination</key>
\t<string>export</string>
\t<key>distributionBundleIdentifier</key>
\t<string>${xmlEscape(bundleId)}</string>
\t<key>manageAppVersionAndBuildNumber</key>
\t<false/>
\t<key>method</key>
\t<string>app-store-connect</string>
\t<key>signingStyle</key>
\t<string>automatic</string>
\t<key>stripSwiftSymbols</key>
\t<true/>
\t<key>teamID</key>
\t<string>${xmlEscape(teamId)}</string>
\t<key>uploadSymbols</key>
\t<true/>
</dict>
</plist>
`;
}

export function assertDistributionSignatureDetails(
  details,
  { bundleId, teamId },
) {
  if (!details.includes(`Identifier=${bundleId}`)) {
    throw new Error('IPA code-signature bundle identifier differs.');
  }
  if (!details.includes(`TeamIdentifier=${teamId}`)) {
    throw new Error('IPA code-signature Team identifier differs.');
  }
  if (!/^Authority=Apple Distribution:/m.test(details)) {
    throw new Error('IPA is not signed with an Apple Distribution certificate.');
  }
  if (/^Authority=Apple Development:/m.test(details)) {
    throw new Error('IPA still has an Apple Development signature.');
  }
  return true;
}

export function assertDistributionEntitlements(
  entitlements,
  { bundleId, teamId },
) {
  if (entitlements?.['get-task-allow'] === true) {
    throw new Error('IPA still has a development debugging entitlement.');
  }
  if (
    entitlements?.['com.apple.developer.team-identifier'] !== teamId
    || entitlements?.['application-identifier'] !== `${teamId}.${bundleId}`
  ) {
    throw new Error('IPA distribution entitlement app or Team identifier differs.');
  }
  return true;
}

export function assertDistributionProfile(
  profile,
  { bundleId, teamId, now = new Date() },
) {
  if (!profile || typeof profile !== 'object') {
    throw new Error('Failed to read the IPA distribution provisioning profile.');
  }
  if (profile.ProvisionsAllDevices === true || profile.ProvisionedDevices) {
    throw new Error('IPA contains a device/enterprise distribution profile, not App Store.');
  }
  const expiration = new Date(profile.ExpirationDate);
  if (!Number.isFinite(expiration.getTime()) || expiration <= now) {
    throw new Error('IPA distribution provisioning profile has expired.');
  }
  assertDistributionEntitlements(profile.Entitlements, {
    bundleId,
    teamId,
  });
  return true;
}

export function assertProfileContainsSigningCertificate(
  profile,
  signingCertificate,
) {
  const certificates = profile?.DeveloperCertificates;
  if (
    !Buffer.isBuffer(signingCertificate)
    || signingCertificate.length === 0
    || !Array.isArray(certificates)
    || certificates.length === 0
  ) {
    throw new Error(
      'Cannot compare IPA signer and provisioning profile certificates.',
    );
  }
  const matches = certificates.some((certificate) => {
    if (typeof certificate !== 'string' || certificate.length === 0) {
      return false;
    }
    const decoded = Buffer.from(certificate, 'base64');
    return decoded.length > 0
      && decoded.toString('base64') === certificate
      && decoded.equals(signingCertificate);
  });
  if (!matches) {
    throw new Error(
      'IPA signer certificate is not included in the provisioning profile.',
    );
  }
  return true;
}

export function assertSigningCertificateValid(
  signingCertificate,
  {
    now = new Date(),
    parse = (value) => new X509Certificate(value),
  } = {},
) {
  if (!Buffer.isBuffer(signingCertificate) || signingCertificate.length === 0) {
    throw new Error('Failed to read the IPA signer certificate.');
  }
  let certificate;
  try {
    certificate = parse(signingCertificate);
  } catch {
    throw new Error('IPA signer certificate format is invalid.');
  }
  const validFrom = new Date(certificate.validFrom);
  const validTo = new Date(certificate.validTo);
  if (
    !Number.isFinite(validFrom.getTime())
    || !Number.isFinite(validTo.getTime())
    || validFrom > now
    || validTo <= now
  ) {
    throw new Error('IPA signer certificate is not yet valid or has expired.');
  }
  return true;
}

export function extractPlistDataValues(xml, label = 'plist') {
  if (typeof xml !== 'string' || xml.length === 0) {
    throw new Error(`Failed to read ${label} certificate array.`);
  }
  const values = [
    ...xml.matchAll(/<data>\s*([\s\S]*?)\s*<\/data>/g),
  ].map((match) => match[1].replace(/\s/g, ''));
  if (
    values.length === 0
    || values.some((value) => {
      const decoded = Buffer.from(value, 'base64');
      return decoded.length === 0 || decoded.toString('base64') !== value;
    })
  ) {
    throw new Error(`Failed to read ${label} certificate array.`);
  }
  return values;
}

export function codeSigningCertificateArguments(prefix, app) {
  if (
    typeof prefix !== 'string'
    || prefix.length === 0
    || typeof app !== 'string'
    || app.length === 0
  ) {
    throw new Error('IPA signer certificate extract path is invalid.');
  }
  // codesign long-option arguments must be joined with '=' so the path is not
  // misread as a code object.
  return ['-d', `--extract-certificates=${prefix}`, app];
}

export function assertSafeIpaEntries(entries) {
  const names = Array.isArray(entries)
    ? entries
    : String(entries).split(/\r?\n/).filter(Boolean);
  if (names.length === 0) throw new Error('IPA is empty.');
  for (const name of names) {
    if (
      name.startsWith('/')
      || name.split('/').some((part) => part === '..')
      || name.includes('\\')
    ) {
      throw new Error('IPA contains an unsafe file path.');
    }
  }
  const appRoots = new Set(
    names
      .filter((name) => /^Payload\/[^/]+\.app(?:\/|$)/.test(name))
      .map((name) => name.match(/^(Payload\/[^/]+\.app)(?:\/|$)/)[1]),
  );
  if (appRoots.size !== 1) {
    throw new Error(`IPA top-level app bundle count is not 1: ${appRoots.size}`);
  }
  return [...appRoots][0];
}

export function appStoreAltoolArguments(operation, ipa, credentials) {
  const auth = altoolAuthenticationArguments(credentials);
  if (operation === 'validate') {
    return [
      'altool',
      '--validate-app', ipa,
      '-t', 'ios',
      ...auth,
      '--output-format', 'json',
      '--show-progress',
    ];
  }
  if (operation === 'upload') {
    return [
      'altool',
      '--upload-app',
      '-f', ipa,
      '-t', 'ios',
      ...auth,
      '--output-format', 'json',
      '--show-progress',
    ];
  }
  throw new Error(`Unsupported App Store operation: ${operation}`);
}
