import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY,
  ANDROID_CAPTURE_SIGNATURE_FILENAME,
  ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY,
  ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256,
  createSignedAndroidCaptureEvidence,
  serializeAndroidUnsignedCaptureReport,
  verifySignedAndroidCaptureEvidence,
} from './android-capture-signing.mjs';

const TEST_PASSWORD = 'local-fixture-password-not-a-secret';

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function javaTool(name) {
  const javaHome = process.env.JAVA_HOME?.trim();
  return javaHome ? join(javaHome, 'bin', name) : name;
}

function runJava(name, args, options = {}) {
  const result = spawnSync(javaTool(name), args, {
    encoding: options.binary ? null : 'utf8',
    env: options.env ?? process.env,
    maxBuffer: 32 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.error) throw result.error;
  assert.equal(
    result.status,
    0,
    `${name} failed: ${String(result.stderr ?? result.stdout)}`,
  );
  return result;
}

function createSigningFixture(root, name) {
  const signerRoot = join(root, `${name}-signer`);
  mkdirSync(signerRoot, { recursive: true, mode: 0o700 });
  const keystorePath = join(signerRoot, `${name}.p12`);
  const alias = `${name}-upload`;
  const passwordName = `MOONLIT_${name.toUpperCase()}_PASSWORD`;
  const env = { ...process.env, [passwordName]: TEST_PASSWORD };
  runJava('keytool', [
    '-genkeypair',
    '-alias', alias,
    '-keyalg', 'RSA',
    '-keysize', '2048',
    '-sigalg', 'SHA256withRSA',
    '-validity', '6000',
    '-dname', `CN=${name},OU=Moonlit Test,O=Moonlit Test,C=KR`,
    '-keystore', keystorePath,
    '-storetype', 'PKCS12',
    '-storepass:env', passwordName,
    '-keypass:env', passwordName,
    '-noprompt',
  ], { env });
  chmodSync(keystorePath, 0o600);
  const certificate = runJava('keytool', [
    '-exportcert',
    '-alias', alias,
    '-keystore', keystorePath,
    '-storepass:env', passwordName,
  ], { binary: true, env }).stdout;
  return {
    alias,
    certificateSha256: sha256(certificate),
    env: {
      ...process.env,
      GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: TEST_PASSWORD,
      GODOT_ANDROID_KEYSTORE_RELEASE_PATH: keystorePath,
      GODOT_ANDROID_KEYSTORE_RELEASE_USER: alias,
    },
    keystorePath,
  };
}

function evidenceFixture(captureId = '1'.repeat(64)) {
  const anchorBytes = Buffer.from(`${JSON.stringify({
    schema: 1,
    capture_id: captureId,
    settings_bytes: { observed_base64: 'bG9jYWxlPWtv' },
  }, null, 2)}\n`, 'utf8');
  const report = {
    schema: 2,
    platform: 'android',
    target: 'seven-inch-tablet',
    package: 'com.crossplatformkorea.moonlitbeacon',
    captured_at: '2026-08-02T00:00:00.000Z',
    persistence_anchor: {
      schema: 1,
      capture_id: captureId,
      path: 'builds/evidence/persistence-evidence.json',
      sha256: sha256(anchorBytes),
    },
  };
  return { anchorBytes, report };
}

test('binds the Android capture report+anchor with the upload-key signature and a pinned cert', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-capture-signing-test-'));
  try {
    const repositoryRoot = join(root, 'repository');
    const evidenceRoot = join(repositoryRoot, 'builds/evidence');
    mkdirSync(evidenceRoot, { recursive: true });
    const signer = createSigningFixture(root, 'primary');
    const { report, anchorBytes } = evidenceFixture();
    const outputPath = join(evidenceRoot, ANDROID_CAPTURE_SIGNATURE_FILENAME);
    const calls = [];
    const recordingSpawn = (command, args, options) => {
      calls.push({ command, args: [...args], env: { ...options.env } });
      return spawnSync(command, args, options);
    };
    const signed = createSignedAndroidCaptureEvidence({
      report,
      anchorBytes,
      outputPath,
      evidencePath: 'builds/evidence/persistence-signature.jar',
      repositoryRoot,
      env: signer.env,
      expectedCertificateSha256: signer.certificateSha256,
      spawn: recordingSpawn,
    });
    const finalReport = {
      ...report,
      persistence_signature: signed.descriptor,
    };

    assert.deepEqual(
      signed.reportBytes,
      serializeAndroidUnsignedCaptureReport(finalReport),
    );
    assert.deepEqual(signed.anchorBytes, anchorBytes);
    assert.deepEqual(signed.signatureBytes, readFileSync(outputPath));
    assert.equal(signed.descriptor.report_entry, ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY);
    assert.equal(signed.descriptor.anchor_entry, ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY);
    assert.equal(signed.descriptor.certificate_sha256, signer.certificateSha256);
    assert.equal(signed.descriptor.capture_id, report.persistence_anchor.capture_id);
    assert.equal(signed.descriptor.sha256, sha256(signed.signatureBytes));
    assert.equal(signed.descriptor.report_sha256, sha256(signed.reportBytes));
    assert.equal(signed.descriptor.anchor_sha256, sha256(anchorBytes));

    const verified = verifySignedAndroidCaptureEvidence(finalReport, {
      anchorBytes,
      signatureBytes: signed.signatureBytes,
      env: signer.env,
      expectedCertificateSha256: signer.certificateSha256,
    });
    assert.deepEqual(verified.reportBytes, signed.reportBytes);
    assert.deepEqual(verified.anchorBytes, anchorBytes);
    assert.equal(verified.certificateSha256, signer.certificateSha256);

    for (const call of calls) {
      assert.equal(call.args.includes(TEST_PASSWORD), false);
      assert.equal(call.args.join('\0').includes(TEST_PASSWORD), false);
    }
    assert.equal(signed.signatureBytes.includes(Buffer.from(TEST_PASSWORD)), false);
    assert.equal(JSON.stringify(signed.descriptor).includes(TEST_PASSWORD), false);
    assert.equal(signed.reportBytes.includes(Buffer.from(TEST_PASSWORD)), false);

    const changedReport = structuredClone(finalReport);
    changedReport.target = 'ten-inch-tablet';
    changedReport.persistence_signature.report_sha256 = sha256(
      serializeAndroidUnsignedCaptureReport(changedReport),
    );
    assert.throws(
      () => verifySignedAndroidCaptureEvidence(changedReport, {
        anchorBytes,
        signatureBytes: signed.signatureBytes,
        env: signer.env,
        expectedCertificateSha256: signer.certificateSha256,
      }),
      /payload bytes/u,
    );

    const otherEvidence = evidenceFixture('2'.repeat(64));
    const changedAnchorReport = structuredClone(finalReport);
    changedAnchorReport.persistence_anchor.capture_id =
      otherEvidence.report.persistence_anchor.capture_id;
    changedAnchorReport.persistence_anchor.sha256 =
      otherEvidence.report.persistence_anchor.sha256;
    changedAnchorReport.persistence_signature.anchor_sha256 =
      otherEvidence.report.persistence_anchor.sha256;
    changedAnchorReport.persistence_signature.capture_id =
      otherEvidence.report.persistence_anchor.capture_id;
    changedAnchorReport.persistence_signature.report_sha256 = sha256(
      serializeAndroidUnsignedCaptureReport(changedAnchorReport),
    );
    assert.throws(
      () => verifySignedAndroidCaptureEvidence(changedAnchorReport, {
        anchorBytes: otherEvidence.anchorBytes,
        signatureBytes: signed.signatureBytes,
        env: signer.env,
        expectedCertificateSha256: signer.certificateSha256,
      }),
      /payload bytes/u,
    );

    const corruptSignature = Buffer.from(signed.signatureBytes);
    corruptSignature[Math.floor(corruptSignature.length / 2)] ^= 0xff;
    const corruptReport = structuredClone(finalReport);
    corruptReport.persistence_signature.sha256 = sha256(corruptSignature);
    assert.throws(
      () => verifySignedAndroidCaptureEvidence(corruptReport, {
        anchorBytes,
        signatureBytes: corruptSignature,
        env: signer.env,
        expectedCertificateSha256: signer.certificateSha256,
      }),
      /JAR|signature/u,
    );

    assert.throws(
      () => verifySignedAndroidCaptureEvidence(finalReport, {
        anchorBytes,
        signatureBytes: signed.signatureBytes,
        env: signer.env,
      }),
      /descriptor/u,
      'a test signer must not be able to replace the production upload cert pin',
    );
    const forgedProductionPin = structuredClone(finalReport);
    forgedProductionPin.persistence_signature.certificate_sha256 =
      ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256;
    assert.throws(
      () => verifySignedAndroidCaptureEvidence(forgedProductionPin, {
        anchorBytes,
        signatureBytes: signed.signatureBytes,
        env: signer.env,
      }),
      /signer/u,
      'changing only the descriptor pin must fail because the real signer certificate differs',
    );
    assert.notEqual(
      signer.certificateSha256,
      ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256,
    );

    const unsignedExtraJar = join(evidenceRoot, 'unsigned-extra.jar');
    copyFileSync(outputPath, unsignedExtraJar);
    const extraRoot = join(root, 'extra');
    mkdirSync(extraRoot, { recursive: true });
    writeFileSync(join(extraRoot, 'extra.txt'), 'unsigned\n');
    runJava('jar', [
      '--update',
      '--file', unsignedExtraJar,
      '-C', extraRoot, 'extra.txt',
    ]);
    const unsignedExtraBytes = readFileSync(unsignedExtraJar);
    const unsignedExtraReport = structuredClone(finalReport);
    unsignedExtraReport.persistence_signature.sha256 = sha256(unsignedExtraBytes);
    assert.throws(
      () => verifySignedAndroidCaptureEvidence(unsignedExtraReport, {
        anchorBytes,
        signatureBytes: unsignedExtraBytes,
        env: signer.env,
        expectedCertificateSha256: signer.certificateSha256,
      }),
      /entry set|signature/u,
    );

    const extraField = structuredClone(finalReport);
    extraField.persistence_signature.unexpected = true;
    assert.throws(
      () => verifySignedAndroidCaptureEvidence(extraField, {
        anchorBytes,
        signatureBytes: signed.signatureBytes,
        env: signer.env,
        expectedCertificateSha256: signer.certificateSha256,
      }),
      /descriptor/u,
    );
    assert.throws(
      () => createSignedAndroidCaptureEvidence({
        report: finalReport,
        anchorBytes,
        outputPath,
        evidencePath: 'builds/evidence/persistence-signature.jar',
        repositoryRoot,
        env: signer.env,
        expectedCertificateSha256: signer.certificateSha256,
      }),
      /already has persistence_signature/u,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
