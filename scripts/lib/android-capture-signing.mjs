import {
  createHash,
  randomBytes,
} from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import {
  dirname,
  isAbsolute,
  join,
  normalize,
  relative,
  resolve,
  sep,
} from 'node:path';
import {
  aabVerificationIsSigned,
  assertAndroidSigningCertificateValid,
  resolveAndroidJavaToolInvocation,
} from './android-build.mjs';
import { resolveAndroidReleaseSigning } from './android-release-signing.mjs';
import { credentialFreeChildEnvironment } from './release-environment.mjs';

export const ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256 =
  '9c5cd1cf2822a31e66a1ddacdd4566bae14db2af929ed8d8f20e7c1d74765138';
export const ANDROID_CAPTURE_SIGNATURE_FILENAME = 'persistence-signature.jar';
export const ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY =
  'capture-report.unsigned.json';
export const ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY =
  'persistence-evidence.json';

const SIGNATURE_FILE_BASENAME = 'MOONLIT';
const SIGNATURE_ALGORITHM = 'SHA256withRSA';
const DIGEST_ALGORITHM = 'SHA-256';
const ARCHIVE_DATE = '1980-01-01T00:00:02Z';
const TOOL_TIMEOUT_MS = 5 * 60 * 1000;
const HASH_PATTERN = /^[0-9a-f]{64}$/u;
const DESCRIPTOR_KEYS = Object.freeze([
  'anchor_entry',
  'anchor_sha256',
  'capture_id',
  'certificate_sha256',
  'digest_algorithm',
  'format',
  'path',
  'report_entry',
  'report_sha256',
  'schema',
  'sha256',
  'signature_algorithm',
]);
const ARCHIVE_ENTRIES = Object.freeze([
  'META-INF/',
  'META-INF/MANIFEST.MF',
  `META-INF/${SIGNATURE_FILE_BASENAME}.SF`,
  `META-INF/${SIGNATURE_FILE_BASENAME}.RSA`,
  ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY,
  ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY,
]);

function fail(message) {
  throw new Error(message);
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function assertBuffer(value, label) {
  if (!Buffer.isBuffer(value)) fail(`${label} bytes is not a Buffer.`);
  return value;
}

function assertSafeEvidencePath(value) {
  if (
    typeof value !== 'string'
    || value.trim() !== value
    || value === ''
    || isAbsolute(value)
    || value.includes('\\')
    || normalize(value).split(sep).includes('..')
    || value.split('/').includes('..')
    || !value.endsWith(`/${ANDROID_CAPTURE_SIGNATURE_FILENAME}`)
  ) {
    fail('Android capture signing evidence path is not safe.');
  }
  return value;
}

function assertOutputPath(outputPath, repositoryRoot) {
  if (
    typeof outputPath !== 'string'
    || !isAbsolute(outputPath)
    || typeof repositoryRoot !== 'string'
    || !isAbsolute(repositoryRoot)
  ) {
    fail('Android capture signing output and repo paths must be absolute.');
  }
  const buildsRoot = resolve(repositoryRoot, 'builds');
  const relation = relative(buildsRoot, resolve(outputPath));
  if (
    relation === ''
    || relation === '..'
    || relation.startsWith(`..${sep}`)
    || isAbsolute(relation)
    || !resolve(outputPath).endsWith(`${sep}${ANDROID_CAPTURE_SIGNATURE_FILENAME}`)
  ) {
    fail('Android capture signing output must be a fixed file under repo builds.');
  }
}

function javaSiblingTool(tool, env, platform) {
  const jarsigner = resolveAndroidJavaToolInvocation('jarsigner', {
    env,
    platform,
  });
  if (tool === 'jarsigner') return jarsigner;
  if (tool === 'keytool') {
    return resolveAndroidJavaToolInvocation('keytool', { env, platform });
  }
  return isAbsolute(jarsigner.command)
    ? { command: join(dirname(jarsigner.command), tool), prefixArgs: [] }
    : { command: tool, prefixArgs: [] };
}

function runTool(tool, args, {
  cwd,
  env,
  platform,
  spawn,
  binary = false,
  timeoutMs,
} = {}) {
  const invocation = javaSiblingTool(tool, env, platform);
  const result = spawn(
    invocation.command,
    [...invocation.prefixArgs, ...args],
    {
      cwd,
      encoding: binary ? null : 'utf8',
      env,
      killSignal: 'SIGTERM',
      maxBuffer: 32 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: timeoutMs,
    },
  );
  if (result.error) throw result.error;
  return result;
}

function parseSingleCertificate(output) {
  const matches = [...String(output).matchAll(
    /-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----/gu,
  )];
  if (matches.length !== 1) {
    fail('Did not read exactly one Android capture signing certificate.');
  }
  const encoded = matches[0][1].replace(/\s/gu, '');
  const certificate = Buffer.from(encoded, 'base64');
  if (certificate.length === 0 || certificate.toString('base64') !== encoded) {
    fail('Android capture signing certificate is not canonical DER.');
  }
  return certificate;
}

function assertAnchorContract(report, anchorBytes) {
  assertBuffer(anchorBytes, 'Android persistence anchor');
  const anchor = report?.persistence_anchor;
  if (
    anchor === null
    || typeof anchor !== 'object'
    || Array.isArray(anchor)
    || anchor.schema !== 1
    || typeof anchor.capture_id !== 'string'
    || !HASH_PATTERN.test(anchor.capture_id)
    || typeof anchor.sha256 !== 'string'
    || !HASH_PATTERN.test(anchor.sha256)
    || sha256(anchorBytes) !== anchor.sha256
  ) {
    fail('Android persistence anchor does not match the signing input.');
  }
  return anchor;
}

export function serializeAndroidUnsignedCaptureReport(report) {
  if (report === null || typeof report !== 'object' || Array.isArray(report)) {
    fail('Android capture report is not an object.');
  }
  const unsignedReport = Object.fromEntries(
    Object.entries(report).filter(([key]) => key !== 'persistence_signature'),
  );
  try {
    return Buffer.from(`${JSON.stringify(unsignedReport, null, 2)}\n`, 'utf8');
  } catch (error) {
    fail(`Failed to serialize the Android capture report: ${error.message}`);
  }
}

function assertDescriptor(report, anchorBytes, signatureBytes, expectedCertificateSha256) {
  const descriptor = report?.persistence_signature;
  const anchor = assertAnchorContract(report, anchorBytes);
  if (
    descriptor === null
    || typeof descriptor !== 'object'
    || Array.isArray(descriptor)
    || JSON.stringify(Object.keys(descriptor).sort())
      !== JSON.stringify(DESCRIPTOR_KEYS)
    || descriptor.schema !== 1
    || descriptor.format !== 'jar'
    || descriptor.signature_algorithm !== SIGNATURE_ALGORITHM
    || descriptor.digest_algorithm !== DIGEST_ALGORITHM
    || descriptor.certificate_sha256 !== expectedCertificateSha256
    || descriptor.report_entry !== ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY
    || descriptor.anchor_entry !== ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY
    || descriptor.anchor_sha256 !== anchor.sha256
    || descriptor.capture_id !== anchor.capture_id
    || !HASH_PATTERN.test(descriptor.sha256 ?? '')
    || !HASH_PATTERN.test(descriptor.report_sha256 ?? '')
    || sha256(signatureBytes) !== descriptor.sha256
    || sha256(anchorBytes) !== descriptor.anchor_sha256
  ) {
    fail('Android capture persistence signature descriptor is invalid.');
  }
  assertSafeEvidencePath(descriptor.path);
  const reportBytes = serializeAndroidUnsignedCaptureReport(report);
  if (sha256(reportBytes) !== descriptor.report_sha256) {
    fail('Android capture report bytes do not match the signing descriptor.');
  }
  return { descriptor, reportBytes };
}

function assertArchiveListing(output) {
  const entries = String(output)
    .split(/\r?\n/gu)
    .map((entry) => entry.trim())
    .filter(Boolean);
  if (
    new Set(entries).size !== entries.length
    || JSON.stringify([...entries].sort())
      !== JSON.stringify([...ARCHIVE_ENTRIES].sort())
  ) {
    fail('Android capture signing JAR entry set does not match the fixed contract.');
  }
}

function extractSignedPayloads(archivePath, {
  env,
  platform,
  spawn,
  timeoutMs,
}) {
  const extractionRoot = mkdtempSync(join(tmpdir(), 'moonlit-capture-verify-'));
  try {
    const extracted = runTool('jar', [
      '--extract',
      '--file', archivePath,
      ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY,
      ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY,
    ], {
      cwd: extractionRoot,
      env,
      platform,
      spawn,
      timeoutMs,
    });
    if (extracted.status !== 0) {
      fail('Failed to extract the Android capture signing JAR payload.');
    }
    const reportPath = join(extractionRoot, ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY);
    const anchorPath = join(extractionRoot, ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY);
    if (!existsSync(reportPath) || !existsSync(anchorPath)) {
      fail('Android capture signing JAR payload is missing.');
    }
    return {
      reportBytes: readFileSync(reportPath),
      anchorBytes: readFileSync(anchorPath),
    };
  } finally {
    rmSync(extractionRoot, { recursive: true, force: true });
  }
}

export function verifySignedAndroidCaptureEvidence(
  report,
  {
    anchorBytes,
    signatureBytes,
    env = process.env,
    expectedCertificateSha256 = ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256,
    platform = process.platform,
    spawn = spawnSync,
    timeoutMs = TOOL_TIMEOUT_MS,
    validateCertificate = assertAndroidSigningCertificateValid,
  } = {},
) {
  assertBuffer(signatureBytes, 'Android capture signing JAR');
  if (!HASH_PATTERN.test(expectedCertificateSha256)) {
    fail('Android capture trust certificate SHA-256 is invalid.');
  }
  const expected = assertDescriptor(
    report,
    anchorBytes,
    signatureBytes,
    expectedCertificateSha256,
  );
  const safeEnv = {
    ...credentialFreeChildEnvironment(env),
    LANG: 'C',
    LC_ALL: 'C',
  };
  const verificationRoot = mkdtempSync(join(tmpdir(), 'moonlit-capture-signature-'));
  const archivePath = join(verificationRoot, ANDROID_CAPTURE_SIGNATURE_FILENAME);
  try {
    writeFileSync(archivePath, signatureBytes, { flag: 'wx', mode: 0o600 });
    const listing = runTool('jar', ['--list', '--file', archivePath], {
      cwd: verificationRoot,
      env: safeEnv,
      platform,
      spawn,
      timeoutMs,
    });
    if (listing.status !== 0) {
      fail('Failed to read the Android capture signing JAR listing.');
    }
    assertArchiveListing(listing.stdout);

    const verification = runTool('jarsigner', [
      '-verify',
      archivePath,
    ], {
      cwd: verificationRoot,
      env: safeEnv,
      platform,
      spawn,
      timeoutMs,
    });
    if (!aabVerificationIsSigned(verification)) {
      fail('Android capture persistence JAR signature is missing or invalid.');
    }

    const certificateResult = runTool('keytool', [
      '-printcert',
      '-rfc',
      '-jarfile', archivePath,
    ], {
      cwd: verificationRoot,
      env: safeEnv,
      platform,
      spawn,
      timeoutMs,
    });
    if (certificateResult.status !== 0) {
      fail('Failed to read the Android capture persistence JAR certificate.');
    }
    const certificate = parseSingleCertificate(certificateResult.stdout);
    const certificateSha256 = sha256(certificate);
    if (
      certificateSha256 !== expectedCertificateSha256
      || certificateSha256 !== expected.descriptor.certificate_sha256
    ) {
      fail('Android capture persistence JAR signer does not match the upload certificate.');
    }
    validateCertificate(certificate);

    const extracted = extractSignedPayloads(archivePath, {
      env: safeEnv,
      platform,
      spawn,
      timeoutMs,
    });
    if (
      !extracted.reportBytes.equals(expected.reportBytes)
      || !extracted.anchorBytes.equals(anchorBytes)
    ) {
      fail('Android capture persistence JAR payload bytes do not match the report.');
    }
    return Object.freeze({
      reportBytes: Buffer.from(extracted.reportBytes),
      anchorBytes: Buffer.from(extracted.anchorBytes),
      certificateSha256,
    });
  } finally {
    rmSync(verificationRoot, { recursive: true, force: true });
  }
}

export function createSignedAndroidCaptureEvidence({
  report,
  anchorBytes,
  outputPath,
  evidencePath,
  repositoryRoot,
  env = process.env,
  expectedCertificateSha256 = ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256,
  platform = process.platform,
  resolveSigning = resolveAndroidReleaseSigning,
  spawn = spawnSync,
  timeoutMs = TOOL_TIMEOUT_MS,
  validateCertificate = assertAndroidSigningCertificateValid,
} = {}) {
  if (Object.hasOwn(report ?? {}, 'persistence_signature')) {
    fail('Android capture report already has persistence_signature before signing.');
  }
  assertOutputPath(outputPath, repositoryRoot);
  assertSafeEvidencePath(evidencePath);
  const anchor = assertAnchorContract(report, anchorBytes);
  const reportBytes = serializeAndroidUnsignedCaptureReport(report);
  const signing = resolveSigning({
    env,
    root: repositoryRoot,
    spawn,
  });
  const password = signing?.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD;
  const keystorePath = signing?.GODOT_ANDROID_KEYSTORE_RELEASE_PATH;
  const alias = signing?.GODOT_ANDROID_KEYSTORE_RELEASE_USER;
  if (
    typeof password !== 'string'
    || password === ''
    || typeof keystorePath !== 'string'
    || keystorePath === ''
    || typeof alias !== 'string'
    || alias === ''
  ) {
    fail('Android capture upload signing config is incomplete.');
  }

  mkdirSync(dirname(outputPath), { recursive: true });
  const workingRoot = mkdtempSync(join(dirname(outputPath), '.capture-signing-'));
  const payloadRoot = join(workingRoot, 'payload');
  const unsignedPath = join(workingRoot, 'unsigned.jar');
  const signedPath = join(workingRoot, ANDROID_CAPTURE_SIGNATURE_FILENAME);
  try {
    mkdirSync(payloadRoot, { recursive: false, mode: 0o700 });
    writeFileSync(
      join(payloadRoot, ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY),
      reportBytes,
      { flag: 'wx', mode: 0o600 },
    );
    writeFileSync(
      join(payloadRoot, ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY),
      anchorBytes,
      { flag: 'wx', mode: 0o600 },
    );
    const safeEnv = credentialFreeChildEnvironment(env);
    const archive = runTool('jar', [
      '--create',
      '--file', unsignedPath,
      '--date', ARCHIVE_DATE,
      '-C', payloadRoot, ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY,
      '-C', payloadRoot, ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY,
    ], {
      cwd: workingRoot,
      env: safeEnv,
      platform,
      spawn,
      timeoutMs,
    });
    if (archive.status !== 0) {
      fail('Failed to create the Android capture persistence JAR.');
    }

    const passwordEnvironmentName =
      `MOONLIT_CAPTURE_SIGNING_${randomBytes(12).toString('hex').toUpperCase()}`;
    const signingEnv = {
      ...safeEnv,
      [passwordEnvironmentName]: password,
      LANG: 'C',
      LC_ALL: 'C',
    };
    const signed = runTool('jarsigner', [
      '-keystore', keystorePath,
      '-storepass:env', passwordEnvironmentName,
      '-keypass:env', passwordEnvironmentName,
      '-sigfile', SIGNATURE_FILE_BASENAME,
      '-digestalg', DIGEST_ALGORITHM,
      '-sigalg', SIGNATURE_ALGORITHM,
      '-signedjar', signedPath,
      unsignedPath,
      alias,
    ], {
      cwd: workingRoot,
      env: signingEnv,
      platform,
      spawn,
      timeoutMs,
    });
    if (signed.status !== 0 || !existsSync(signedPath)) {
      fail('Android capture persistence JAR upload-key signing failed.');
    }
    chmodSync(signedPath, 0o600);
    const signatureBytes = readFileSync(signedPath);
    const descriptor = Object.freeze({
      schema: 1,
      format: 'jar',
      signature_algorithm: SIGNATURE_ALGORITHM,
      digest_algorithm: DIGEST_ALGORITHM,
      certificate_sha256: expectedCertificateSha256,
      path: evidencePath,
      sha256: sha256(signatureBytes),
      report_entry: ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY,
      report_sha256: sha256(reportBytes),
      anchor_entry: ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY,
      anchor_sha256: anchor.sha256,
      capture_id: anchor.capture_id,
    });
    const finalReport = { ...report, persistence_signature: descriptor };
    const verified = verifySignedAndroidCaptureEvidence(finalReport, {
      anchorBytes,
      signatureBytes,
      env: safeEnv,
      expectedCertificateSha256,
      platform,
      spawn,
      timeoutMs,
      validateCertificate,
    });
    renameSync(signedPath, outputPath);
    if (!readFileSync(outputPath).equals(signatureBytes)) {
      fail('Published Android capture signing JAR bytes do not match the verified copy.');
    }
    return Object.freeze({
      descriptor,
      signatureBytes: Buffer.from(signatureBytes),
      reportBytes: Buffer.from(verified.reportBytes),
      anchorBytes: Buffer.from(verified.anchorBytes),
    });
  } finally {
    rmSync(workingRoot, { recursive: true, force: true });
  }
}
