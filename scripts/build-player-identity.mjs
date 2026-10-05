// Preflight, check, staging, and native bridge builds for MoonlitIdentity.
//
//     node scripts/build-player-identity.mjs --dry-run [--platform android|ios|all]
//     node scripts/build-player-identity.mjs --check [--platform android|ios|all]
//     node scripts/build-player-identity.mjs --install [--platform android|ios|all]
//     node scripts/build-player-identity.mjs --clean
//     node scripts/build-player-identity.mjs --build-android [--debug|--release] [--dry-run]
//     node scripts/build-player-identity.mjs --build-ios [--debug|--release] [--dry-run]
//     node scripts/build-player-identity.mjs --fetch-deps --platform ios
//
// --dry-run (the default) validates config and reports; it writes nothing.
// --check is the same validation with a failing exit code when not ready.
// --install stages `res://moonlit_identity.cfg` for one export (partial
// configs stage with warnings; each provider gates on its own keys at
// runtime); --clean removes it again. --build-android/--build-ios compile
// the native bridges from the pinned official dependencies (fetched when
// the director runs the build); with --dry-run they only report missing
// prerequisites. No command prints a value, only names.

import './lib/load-env.mjs';

import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  checkAndroidBuildPrereqs,
  checkIosBuildPrereqs,
  cleanIdentityConfig,
  dryRunIdentityPreflight,
  fetchIosDeps,
  formatBuildPrereqReport,
  identityArtifactPaths,
  identityBuildDirs,
  identityIosFrameworksDir,
  identityIosResourcesDir,
  installIdentityConfig,
  iosSconsArgs,
  redactIdentitySecrets,
  renderAndroidPluginProject,
  renderIosBridgeProject,
  resolvePublicIdentityConfig,
  runBridgeBuild,
  stageIosFrameworks,
  stageIosResources,
  validateIdentityConfig,
  verifyAndroidArtifact,
  verifyIosExportInputs,
} from './lib/player-identity-build.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const COMMANDS = ['--dry-run', '--check', '--install', '--clean', '--build-android', '--build-ios', '--fetch-deps'];

function usage() {
  return [
    'Usage: node scripts/build-player-identity.mjs [--dry-run|--check|--install|--clean|--build-android|--build-ios|--fetch-deps] [--platform android|ios|all] [--debug|--release] [--dry-run]',
    '',
    '  --dry-run       Validate and report; write nothing (default).',
    '  --check         Validate and exit 1 when not ready; write nothing.',
    '  --install       Stage res://moonlit_identity.cfg for one export.',
    '  --clean         Remove the staged config again.',
    '  --build-android Compile the Android plugin AAR from pinned deps.',
    '  --build-ios     Compile the iOS static library from pinned deps.',
    '  --fetch-deps    Fetch the pinned iOS Firebase SDK (director runs it).',
    '  --platform      Which provider config to require (default all).',
    '  --debug         Build the debug variant (default release).',
    '  --dry-run       With --build-*: report prerequisites only.',
  ].join('\n');
}

function parseArgs(argv) {
  const args = { command: '--dry-run', platform: 'all', variant: 'release', reportOnly: false };
  let explicitCommand = false;
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--help' || token === '-h') return { help: true };
    if (token === '--dry-run' && explicitCommand && args.command.startsWith('--build-')) {
      args.reportOnly = true;
      continue;
    }
    if (COMMANDS.includes(token)) {
      args.command = token;
      explicitCommand = true;
      continue;
    }
    if (token === '--debug' || token === '--release') {
      args.variant = token.slice('--'.length);
      continue;
    }
    if (token.startsWith('--platform=')) {
      args.platform = token.slice('--platform='.length);
      continue;
    }
    if (token === '--platform') {
      const next = argv[i + 1];
      if (next === undefined) return { error: 'Missing value for --platform.' };
      args.platform = next;
      i += 1;
      continue;
    }
    return { error: `Unknown argument "${token}".` };
  }
  if (!['android', 'ios', 'all'].includes(args.platform)) {
    return { error: `Unknown --platform "${args.platform}". Use android, ios, or all.` };
  }
  return args;
}

function buildAndroid(variant, reportOnly) {
  const prereqs = checkAndroidBuildPrereqs({ root: ROOT });
  console.log(redactIdentitySecrets(formatBuildPrereqReport('Android', prereqs)).trimEnd());
  if (!prereqs.ok) return 1;
  if (reportOnly) return 0;
  const { android: outDir } = identityBuildDirs(ROOT);
  renderAndroidPluginProject({ root: ROOT, outDir });
  console.log(`Rendered standalone Gradle project at ${outDir}.`);
  const task = variant === 'debug' ? ':MoonlitIdentity:assembleDebug' : ':MoonlitIdentity:assembleRelease';
  console.log(`Running: gradle ${task}`);
  const build = runBridgeBuild({ command: 'gradle', args: [task, '--console=plain'], cwd: outDir });
  if (build.output) console.log(build.output);
  if (!build.ok) {
    console.error(`Gradle build failed (exit ${build.status}).`);
    return 1;
  }
  const built = join(outDir, 'MoonlitIdentity/build/outputs/aar', `MoonlitIdentity-${variant}.aar`);
  const artifacts = identityArtifactPaths(ROOT);
  const dest = variant === 'debug' ? artifacts.androidDebugAar : artifacts.androidReleaseAar;
  if (!existsSync(built)) {
    console.error(`Gradle succeeded but produced no AAR at ${built}.`);
    return 1;
  }
  mkdirSync(dirname(dest), { recursive: true });
  copyFileSync(built, dest);
  const verdict = verifyAndroidArtifact(dest);
  if (!verdict.ok) {
    for (const check of verdict.checks) console.error(`artifact: ${check}`);
    return 1;
  }
  console.log(`Verified ${dest}.`);
  return 0;
}

function buildIos(variant, reportOnly) {
  const prereqs = checkIosBuildPrereqs({ root: ROOT });
  console.log(redactIdentitySecrets(formatBuildPrereqReport('iOS', prereqs)).trimEnd());
  if (!prereqs.ok) return 1;
  if (reportOnly) return 0;
  const { ios: outDir, iosDeps } = identityBuildDirs(ROOT);
  renderIosBridgeProject({ root: ROOT, outDir });
  console.log(`Rendered standalone SCons project at ${outDir}.`);
  const sconsArgs = iosSconsArgs(variant);
  console.log(`Running: scons ${sconsArgs.join(' ')}`);
  const build = runBridgeBuild({ command: 'scons', args: sconsArgs, cwd: outDir });
  if (build.output) console.log(build.output);
  if (!build.ok) {
    console.error(`SCons build failed (exit ${build.status}).`);
    return 1;
  }
  const built = join(outDir, 'lib', `libmoonlit_identity.${variant}.a`);
  const artifacts = identityArtifactPaths(ROOT);
  const dest = variant === 'debug' ? artifacts.iosDebugLib : artifacts.iosReleaseLib;
  if (!existsSync(built)) {
    console.error(`SCons succeeded but produced no library at ${built}.`);
    return 1;
  }
  mkdirSync(dirname(dest), { recursive: true });
  copyFileSync(built, dest);
  const staged = stageIosFrameworks({
    depsRoot: iosDeps,
    variant,
    destDir: identityIosFrameworksDir(ROOT, variant),
  });
  if (!staged.ok) {
    for (const check of staged.checks) console.error(`frameworks: ${check}`);
    return 1;
  }
  console.log(`Staged ${staged.staged.length} Firebase framework(s): ${staged.staged.join(', ')}.`);
  const resources = stageIosResources({
    depsRoot: iosDeps,
    variant,
    destDir: identityIosResourcesDir(ROOT, variant),
  });
  if (!resources.ok) {
    for (const check of resources.checks) console.error(`resources: ${check}`);
    return 1;
  }
  console.log(`Staged ${resources.staged.length} privacy resource(s): ${resources.staged.join(', ')}.`);
  const verdict = verifyIosExportInputs({ root: ROOT, variant });
  if (!verdict.ok) {
    for (const check of verdict.checks) console.error(`export-inputs: ${check}`);
    return 1;
  }
  console.log(`Verified ${dest} plus staged frameworks and resources.`);
  return 0;
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    console.log(usage());
    return 0;
  }
  if (args.error) {
    console.error(redactIdentitySecrets(args.error));
    console.error(usage());
    return 2;
  }
  if (args.command === '--clean') {
    const { removed } = cleanIdentityConfig({ root: ROOT });
    console.log(
      removed.length > 0
        ? `Removed staged identity config (${removed.length} file(s)).`
        : 'No staged identity config to remove.',
    );
    return 0;
  }
  if (args.command === '--build-android') return buildAndroid(args.variant, args.reportOnly);
  if (args.command === '--build-ios') return buildIos(args.variant, args.reportOnly);
  if (args.command === '--fetch-deps') {
    if (args.platform === 'android') {
      console.log('Android dependencies resolve inside the Gradle build; nothing to pre-fetch.');
      return 0;
    }
    if (args.platform !== 'ios') {
      console.error('Use --fetch-deps --platform ios (android dependencies resolve at build time).');
      return 2;
    }
    const fetched = fetchIosDeps({ root: ROOT });
    if (fetched.output) console.log(fetched.output);
    for (const check of fetched.checks) console.error(`deps: ${check}`);
    if (!fetched.ok) return 1;
    const names = fetched.variants?.release?.frameworks ?? [];
    console.log(
      `Fetched identity iOS SDK frameworks under ${fetched.linkDir} `
      + `(${names.length} frameworks: ${names.join(', ')}).`,
    );
    return 0;
  }
  const resolution = resolvePublicIdentityConfig();
  const verdict = validateIdentityConfig(resolution, args.platform);
  if (args.command === '--install') {
    // Providers gate independently at runtime, so a partial config still
    // stages: unready providers report not_configured while ready ones
    // and guest play work. --check keeps the strict full-readiness gate.
    if (!verdict.ok) {
      const { report } = dryRunIdentityPreflight({ platform: args.platform });
      console.log(redactIdentitySecrets(report).trimEnd());
      console.log('Staging a partial config; see the provider lines above.');
    }
    const paths = installIdentityConfig({ root: ROOT, resolution });
    console.log('Staged public identity config for one export.');
    console.log(`installed: ${paths.installed}`);
    console.log('Remove it with --clean after the export. Never commit it.');
    return 0;
  }
  const { report } = dryRunIdentityPreflight({ platform: args.platform });
  console.log(redactIdentitySecrets(report).trimEnd());
  if (args.command === '--check') return verdict.ok ? 0 : 1;
  return 0;
}

process.exit(main(process.argv.slice(2)));
