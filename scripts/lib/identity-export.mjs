import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  cleanIdentityConfig,
  formatPreflightReport,
  identityArtifactPaths,
  installIdentityConfig,
  providerReadiness,
  resolvePublicIdentityConfig,
  validateIdentityConfig,
} from './player-identity-build.mjs';

// Staged identity config lifecycle for the ordinary Android/iOS export
// wrappers. Both wrappers resolve the public identifiers, print the
// per-provider diagnostics, stage the config for exactly one export, and
// remove it again on success, failure, or cancel (a killed wrapper leaves
// stale staging for the next run's under-lock recovery, like IAP staging).
//
// Staging never blocks guest play: a missing or malformed provider setup
// stages partial (or no) config with warnings, and the runtime capability
// gates keep each provider truthful on its own. Only a staging I/O error
// fails the export. Nothing here prints a value: reports name the
// variable and its presence only.

/**
 * Resolve, report, and stage the public identity config for one export.
 * Returns `{ resolution, verdict, report, installed }` where `installed`
 * is null when no identifier is set (guest-only export, nothing to clean).
 * The caller prints the redacted report.
 */
export function prepareIdentityExport({ root, platform, env = process.env }) {
  const resolution = resolvePublicIdentityConfig({ env });
  const verdict = validateIdentityConfig(resolution, platform);
  const report = formatPreflightReport(resolution, { platform });
  const anyPresent = Object.entries(resolution).some(
    ([key, slot]) => key !== 'appleService' && slot.present,
  );
  const installed = anyPresent
    ? installIdentityConfig({ root, resolution })
    : null;
  return { resolution, verdict, report, installed };
}

/** Remove staged identity config after an export. Never throws for absence. */
export function cleanupIdentityExport({ root }) {
  return cleanIdentityConfig({ root });
}

/**
 * Native bridge artifact presence for one export variant, informational:
 * `{ label, path, present }[]`. A missing artifact never fails the
 * wrapper; the export plugin warns and the build runs without native
 * sign-in, exactly like a missing provider setup.
 */
export function identityNativeArtifactStatus({ root, platform, variant }) {
  const artifacts = identityArtifactPaths(root);
  if (platform === 'android') {
    const aar = variant === 'debug' ? artifacts.androidDebugAar : artifacts.androidReleaseAar;
    return [{ label: `android-${variant}-aar`, path: aar, present: existsSync(aar) }];
  }
  if (platform === 'ios') {
    return [
      {
        label: `ios-${variant}-static-lib`,
        path: variant === 'debug' ? artifacts.iosDebugLib : artifacts.iosReleaseLib,
        present: existsSync(variant === 'debug' ? artifacts.iosDebugLib : artifacts.iosReleaseLib),
      },
    ];
  }
  throw new Error(`Unknown identity export platform "${platform}".`);
}

// Apple Sign in with Apple entitlement for iOS exports.
//
// Godot 4.7.1's Apple exporter appends the `entitlements/additional` preset
// option verbatim as XML into the generated .entitlements file: the option
// is registered as a multiline string defaulting to "", and its value plus
// "\n" is appended after the fixed keys inside the top-level dict
// (editor/export/editor_export_platform_apple_embedded.cpp; the official
// 4.7.1-stable source evidence is staged under
// builds/director-evidence/). `capabilities/additional` only lists
// installation requirements and can never carry this grant.
//
// The wrapper therefore stages the grant as a TEMPORARY per-export preset
// edit: the applesignin array is appended to the iOS preset's
// `entitlements/additional` value (pre-existing extra XML is preserved
// byte for byte), the export runs, and the exact previous preset bytes are
// restored on success, failure, or cancel. A marker file lets the next
// under-lock run recover staging left by a killed wrapper. The locked
// preset file never changes persistently.
//
// The grant stages only when native iOS Apple readiness is explicitly
// acknowledged and supported: the setup flag plus well-formed iOS Firebase
// config plus the MoonlitIdentity export plugin enabled for the preset.
// The signing profile must then grant it, or the build fails truthfully.

export const APPLE_SIGNIN_ENTITLEMENT_KEY = 'com.apple.developer.applesignin';
export const APPLE_SIGNIN_ENTITLEMENT_VALUES = Object.freeze(['Default']);
export const ENTITLEMENTS_ADDITIONAL_KEY = 'entitlements/additional';
// Single-line plist XML: no quotable characters, so staging appends it to
// the preset value with no escaping and preserves pre-existing bytes.
export const APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML =
  '<key>com.apple.developer.applesignin</key><array><string>Default</string></array>';

/** True when the staged config promises the native iOS Apple sheet. */
export function appleIosExportReady(resolution) {
  return providerReadiness(resolution, 'ios').ios.apple.ready === true;
}

/** True when the preset enables the MoonlitIdentity export plugin. */
export function identityPluginEnabledForPreset(exportPresetsSource, presetName) {
  const blocks = String(exportPresetsSource ?? '').split(/^\[preset\.\d+\]$/mu);
  for (const block of blocks) {
    if (!block.match(new RegExp(`^name="${presetName}"$`, 'mu'))) continue;
    const setting = block.match(/^plugins\/MoonlitIdentity=(true|false)\s*$/mu)?.[1];
    return setting === 'true';
  }
  return false;
}

export function shouldStageAppleEntitlement({
  resolution,
  exportPresetsSource,
  presetName = 'iOS',
}) {
  return appleIosExportReady(resolution)
    && identityPluginEnabledForPreset(exportPresetsSource, presetName);
}

function applesigninArrayValues(entitlementsXml) {
  const text = String(entitlementsXml ?? '');
  const keyTag = `<key>${APPLE_SIGNIN_ENTITLEMENT_KEY}</key>`;
  const keyIndex = text.indexOf(keyTag);
  if (keyIndex < 0) return null;
  const array = text.slice(keyIndex + keyTag.length)
    .match(/^\s*<array>([\s\S]*?)<\/array>/u)?.[1] ?? '';
  return [...array.matchAll(/<string>([^<]*)<\/string>/gu)]
    .map((match) => match[1]);
}

/** True when entitlements text already carries the exact Apple grant. */
export function extraEntitlementsGrantAppleSignIn(entitlementsXml) {
  const values = applesigninArrayValues(entitlementsXml);
  return (
    values !== null
    && values.length === APPLE_SIGNIN_ENTITLEMENT_VALUES.length
    && values.every((value, index) => value === APPLE_SIGNIN_ENTITLEMENT_VALUES[index])
  );
}

/** True when generated .entitlements XML promises the Apple grant. */
export function generatedEntitlementsPromiseAppleSignIn(entitlementsXml) {
  try {
    return (applesigninArrayValues(entitlementsXml) ?? []).includes('Default');
  } catch {
    return false;
  }
}

/** True when a parsed entitlements object grants the Apple array. */
export function appleSignInGranted(entitlements) {
  const values = entitlements?.[APPLE_SIGNIN_ENTITLEMENT_KEY];
  return Array.isArray(values) && values.includes('Default');
}

// Godot ConfigFile string escapes, for reading the current extras value.
// Detection only: staging concatenates the raw quoted content, so the
// preserved part never passes through an escape round-trip.
function unescapePresetString(raw) {
  return String(raw).replace(/\\(\\|"|n|t|r)/gu, (match, code) => {
    if (code === 'n') return '\n';
    if (code === 't') return '\t';
    if (code === 'r') return '\r';
    return code;
  });
}

function parsePresetQuotedValue(line, key) {
  const rest = line.slice(key.length + 1);
  if (!rest.startsWith('"')) {
    throw new Error(`Preset ${key} value is not a quoted string: ${line}`);
  }
  let raw = '';
  for (let index = 1; index < rest.length; index += 1) {
    const ch = rest[index];
    if (ch === '\\' && index + 1 < rest.length) {
      raw += ch + rest[index + 1];
      index += 1;
      continue;
    }
    if (ch === '"') {
      if (rest.slice(index + 1) !== '') {
        throw new Error(`Preset ${key} line has trailing text: ${line}`);
      }
      return raw;
    }
    raw += ch;
  }
  throw new Error(`Preset ${key} value is unterminated: ${line}`);
}

function presetOptionsRange(lines, presetName) {
  for (let index = 0; index < lines.length; index += 1) {
    const preset = lines[index].match(/^\[preset\.(\d+)\]$/u)?.[1];
    if (preset === undefined) continue;
    let end = lines.length;
    for (let scan = index + 1; scan < lines.length; scan += 1) {
      if (/^\[preset\.\d+\]$/u.test(lines[scan])) {
        end = scan;
        break;
      }
    }
    const named = lines.slice(index, end).some((line) => line === `name="${presetName}"`);
    if (!named) continue;
    const options = lines
      .slice(index, end)
      .findIndex((line) => line === `[preset.${preset}.options]`);
    if (options < 0) {
      throw new Error(`Preset "${presetName}" has no options section.`);
    }
    const header = index + options;
    let sectionEnd = lines.length;
    for (let scan = header + 1; scan < lines.length; scan += 1) {
      if (lines[scan].startsWith('[')) {
        sectionEnd = scan;
        break;
      }
    }
    return { header, end: sectionEnd };
  }
  throw new Error(`Preset "${presetName}" not found.`);
}

/**
 * Append the temporary applesignin grant to one preset's
 * `entitlements/additional` value. Returns `{ source, applied, hadKey,
 * previousRaw }`. Pre-existing extra XML is preserved byte for byte; every
 * other preset byte is untouched. Idempotent when the exact grant is
 * already present (`applied: false`); throws when the key carries other
 * applesignin values, so staging never alters or duplicates a grant.
 */
export function stageTemporaryAppleEntitlementSource(presetsSource, presetName = 'iOS') {
  const text = String(presetsSource ?? '');
  const lines = text.split('\n');
  const { header, end } = presetOptionsRange(lines, presetName);
  const prefix = `${ENTITLEMENTS_ADDITIONAL_KEY}=`;
  const keyIndex = lines.slice(header + 1, end).findIndex((line) => line.startsWith(prefix));
  if (keyIndex >= 0) {
    const at = header + 1 + keyIndex;
    const raw = parsePresetQuotedValue(lines[at], ENTITLEMENTS_ADDITIONAL_KEY);
    if (raw.includes(APPLE_SIGNIN_ENTITLEMENT_KEY)) {
      if (extraEntitlementsGrantAppleSignIn(unescapePresetString(raw))) {
        return { source: text, applied: false, hadKey: true, previousRaw: raw };
      }
      throw new Error(
        `Preset ${ENTITLEMENTS_ADDITIONAL_KEY} already carries ${APPLE_SIGNIN_ENTITLEMENT_KEY} `
        + 'with unexpected values; refusing to alter it.',
      );
    }
    const staged = raw === ''
      ? APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML
      : `${raw}\\n${APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML}`;
    const next = [...lines];
    next[at] = `${ENTITLEMENTS_ADDITIONAL_KEY}="${staged}"`;
    return { source: next.join('\n'), applied: true, hadKey: true, previousRaw: raw };
  }
  let insertAt = header + 1;
  for (let scan = header + 1; scan < end; scan += 1) {
    if (lines[scan] !== '') insertAt = scan + 1;
  }
  const next = [...lines];
  next.splice(
    insertAt,
    0,
    `${ENTITLEMENTS_ADDITIONAL_KEY}="${APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML}"`,
  );
  return { source: next.join('\n'), applied: true, hadKey: false, previousRaw: null };
}

const APPLE_ENTITLEMENT_MARKER = 'builds/.identity-apple-entitlement.staged.json';

export function appleEntitlementMarkerPath(root) {
  return join(root, APPLE_ENTITLEMENT_MARKER);
}

function writeAppleEntitlementMarker(root, record) {
  const marker = appleEntitlementMarkerPath(root);
  mkdirSync(join(root, 'builds'), { recursive: true });
  writeFileSync(marker, `${JSON.stringify(record, null, 2)}\n`, { encoding: 'utf8' });
  return marker;
}

/**
 * Stage the temporary grant into the preset file. Writes the stale-recovery
 * marker before touching presets, so a kill at any point recovers. Returns
 * `{ staged, presetsPath, previous }`; `previous` restores exact bytes.
 */
export function stageTemporaryAppleEntitlement({ root, presetName = 'iOS' }) {
  const presetsPath = join(root, 'apps/game/export_presets.cfg');
  const before = readFileSync(presetsPath, 'utf8');
  const staged = stageTemporaryAppleEntitlementSource(before, presetName);
  if (!staged.applied) return { staged: false, presetsPath, previous: before };
  writeAppleEntitlementMarker(root, {
    presetsPath,
    preset: presetName,
    hadKey: staged.hadKey,
    previousRaw: staged.previousRaw,
    pid: process.pid,
  });
  writeFileSync(presetsPath, staged.source, { encoding: 'utf8' });
  return { staged: true, presetsPath, previous: before };
}

/**
 * Restore exact preset bytes after an export and clear the marker. Throws
 * without clearing when the restored bytes do not verify, so the next
 * under-lock run retries the recovery.
 */
export function restoreTemporaryAppleEntitlement({ root, presetsPath, previous }) {
  writeFileSync(presetsPath, previous, { encoding: 'utf8' });
  const current = readFileSync(presetsPath, 'utf8');
  if (current !== previous) {
    throw new Error(`Staged preset restoration did not verify: ${presetsPath}`);
  }
  rmSync(appleEntitlementMarkerPath(root), { force: true });
  return true;
}

/**
 * Recover staging left by a killed wrapper. Restores the recorded previous
 * extras only when the preset still holds exactly the staged value; leaves
 * an already-restored or externally changed preset alone. Returns
 * `{ recovered, note }` and always clears a readable marker.
 */
export function recoverStaleAppleEntitlementGrant({ root }) {
  const marker = appleEntitlementMarkerPath(root);
  if (!existsSync(marker)) return { recovered: false, note: 'no marker' };
  let record = null;
  try {
    record = JSON.parse(readFileSync(marker, 'utf8'));
  } catch {
    record = null;
  }
  if (record === null || typeof record !== 'object' || Array.isArray(record)) {
    rmSync(marker, { force: true });
    return { recovered: false, note: 'unreadable marker removed' };
  }
  const clear = (recovered, note) => {
    rmSync(marker, { force: true });
    return { recovered, note };
  };
  let lines;
  try {
    lines = readFileSync(record.presetsPath, 'utf8').split('\n');
  } catch {
    return clear(false, 'preset file unreadable; marker cleared');
  }
  let range;
  try {
    range = presetOptionsRange(lines, record.preset);
  } catch {
    return clear(false, 'preset section missing; marker cleared');
  }
  const prefix = `${ENTITLEMENTS_ADDITIONAL_KEY}=`;
  const keyIndex = lines.slice(range.header + 1, range.end)
    .findIndex((line) => line.startsWith(prefix));
  if (!record.hadKey) {
    const added = `${ENTITLEMENTS_ADDITIONAL_KEY}="${APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML}"`;
    if (keyIndex >= 0 && lines[range.header + 1 + keyIndex] === added) {
      const next = [...lines];
      next.splice(range.header + 1 + keyIndex, 1);
      writeFileSync(record.presetsPath, next.join('\n'), { encoding: 'utf8' });
      return clear(true, 'added extras line removed');
    }
    return clear(false, 'preset already restored or externally changed');
  }
  if (keyIndex < 0) {
    return clear(false, 'extras line vanished externally; left alone');
  }
  const at = range.header + 1 + keyIndex;
  let raw;
  try {
    raw = parsePresetQuotedValue(lines[at], ENTITLEMENTS_ADDITIONAL_KEY);
  } catch {
    return clear(false, 'extras line malformed externally; left alone');
  }
  const expected = record.previousRaw === ''
    ? APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML
    : `${record.previousRaw}\\n${APPLE_SIGNIN_EXTRA_ENTITLEMENTS_XML}`;
  if (raw === expected) {
    const next = [...lines];
    next[at] = `${ENTITLEMENTS_ADDITIONAL_KEY}="${record.previousRaw}"`;
    writeFileSync(record.presetsPath, next.join('\n'), { encoding: 'utf8' });
    return clear(true, 'previous extras restored');
  }
  if (raw === record.previousRaw) {
    return clear(false, 'preset already restored');
  }
  return clear(false, 'preset externally changed; left alone');
}

/**
 * Fail truthfully when the build promises the Apple sheet but the signing
 * profile does not grant it. `profileEntitlements` is the parsed
 * `Entitlements` dict of the provisioning profile; `required` says
 * whether the built product carries the temporary grant.
 */
export function assertAppleSignInProfileSupport(profileEntitlements, { required }) {
  if (!required) return true;
  if (!appleSignInGranted(profileEntitlements)) {
    throw new Error(
      `Apple iOS sign-in is staged ready but the signing profile lacks ${APPLE_SIGNIN_ENTITLEMENT_KEY} `
      + '[Default]. Enable the capability on the App ID and rebuild with a matching profile.',
    );
  }
  return true;
}
