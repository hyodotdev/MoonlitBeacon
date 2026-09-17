import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// Godot 4.7.1's Android gradle template pins AGP 8.6.1 and compileSdk 36.
// AGP 8.6.1 is only tested through compileSdk 35. openiap-google:3.5.2
// (godot-iap 3.5.1) depends on androidx.core:1.18.0, which needs AGP 8.9.1.
// The template already ships Gradle 8.11.1, which is the 8.9.1 minimum.
export const GODOT_STOCK_ANDROID_GRADLE_PLUGIN = '8.6.1';
export const GODOT_COMPAT_ANDROID_GRADLE_PLUGIN = '8.9.1';
export const ANDROID_GRADLE_COMPAT_FILE = 'moonlit-androidx-compat.gradle';
export const ANDROID_GRADLE_COMPAT_APPLY =
  `apply from: '${ANDROID_GRADLE_COMPAT_FILE}'`;

const STOCK_AGP_LINE =
  `androidGradlePlugin: '${GODOT_STOCK_ANDROID_GRADLE_PLUGIN}'`;
const COMPAT_AGP_LINE =
  `androidGradlePlugin: '${GODOT_COMPAT_ANDROID_GRADLE_PLUGIN}'`;

export function ensureGodotAgpCompatibleAndroidx(gradleProject) {
  if (typeof gradleProject !== 'string' || gradleProject.trim() === '') {
    throw new Error('Android Gradle project path is missing.');
  }
  const configGradle = join(gradleProject, 'config.gradle');
  if (!existsSync(configGradle)) {
    throw new Error(
      `Android Gradle template is missing config.gradle at ${configGradle}`,
    );
  }

  const source = readFileSync(configGradle, 'utf8');
  if (source.includes(COMPAT_AGP_LINE)) {
    stripLegacyAndroidxPin(gradleProject);
    return false;
  }
  if (!source.includes(STOCK_AGP_LINE)) {
    throw new Error(
      'Godot 4.7.1 Android Gradle plugin 8.6.1 pin was not found in config.gradle',
    );
  }
  writeFileSync(configGradle, source.replace(STOCK_AGP_LINE, COMPAT_AGP_LINE), 'utf8');
  stripLegacyAndroidxPin(gradleProject);
  return true;
}

function stripLegacyAndroidxPin(gradleProject) {
  const buildGradle = join(gradleProject, 'build.gradle');
  if (existsSync(buildGradle)) {
    const source = readFileSync(buildGradle, 'utf8');
    if (source.includes(ANDROID_GRADLE_COMPAT_APPLY)) {
      writeFileSync(
        buildGradle,
        source.replace(new RegExp(`\n?${ANDROID_GRADLE_COMPAT_APPLY}\n?`), '\n'),
        'utf8',
      );
    }
  }
  rmSync(join(gradleProject, ANDROID_GRADLE_COMPAT_FILE), { force: true });
}
