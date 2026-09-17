import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  ANDROID_GRADLE_COMPAT_APPLY,
  ANDROID_GRADLE_COMPAT_FILE,
  GODOT_COMPAT_ANDROID_GRADLE_PLUGIN,
  GODOT_STOCK_ANDROID_GRADLE_PLUGIN,
  ensureGodotAgpCompatibleAndroidx,
} from './android-gradle-compat.mjs';

function writeTemplate(dir, agp = GODOT_STOCK_ANDROID_GRADLE_PLUGIN) {
  writeFileSync(
    join(dir, 'config.gradle'),
    `ext.versions = [\n    androidGradlePlugin: '${agp}',\n    compileSdk         : 36,\n]\n`,
  );
  writeFileSync(
    join(dir, 'build.gradle'),
    `plugins {\n    id 'com.android.application'\n}\napply from: 'config.gradle'\n`,
  );
}

test('bumps Godot 4.7.1 AGP 8.6.1 to 8.9.1 so androidx.core 1.18.0 can resolve', () => {
  const dir = mkdtempSync(join(tmpdir(), 'moonlit-agp-compat-'));
  try {
    writeTemplate(dir);
    assert.equal(ensureGodotAgpCompatibleAndroidx(dir), true);
    assert.equal(ensureGodotAgpCompatibleAndroidx(dir), false);
    const source = readFileSync(join(dir, 'config.gradle'), 'utf8');
    assert.match(source, new RegExp(`androidGradlePlugin: '${GODOT_COMPAT_ANDROID_GRADLE_PLUGIN}'`));
    assert.doesNotMatch(source, new RegExp(`androidGradlePlugin: '${GODOT_STOCK_ANDROID_GRADLE_PLUGIN}'`));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('strips the older androidx.core force pin from a leftover Gradle template', () => {
  const dir = mkdtempSync(join(tmpdir(), 'moonlit-agp-strip-'));
  try {
    writeTemplate(dir);
    writeFileSync(
      join(dir, 'build.gradle'),
      `apply from: 'config.gradle'\n${ANDROID_GRADLE_COMPAT_APPLY}\n`,
    );
    writeFileSync(join(dir, ANDROID_GRADLE_COMPAT_FILE), 'configurations.configureEach {}\n');
    ensureGodotAgpCompatibleAndroidx(dir);
    const buildGradle = readFileSync(join(dir, 'build.gradle'), 'utf8');
    assert.doesNotMatch(buildGradle, new RegExp(ANDROID_GRADLE_COMPAT_APPLY));
    assert.equal(
      existsSyncAfter(dir, ANDROID_GRADLE_COMPAT_FILE),
      false,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('refuses a missing Gradle template instead of creating one', () => {
  const dir = mkdtempSync(join(tmpdir(), 'moonlit-agp-missing-'));
  try {
    assert.throws(
      () => ensureGodotAgpCompatibleAndroidx(dir),
      /missing config\.gradle/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

function existsSyncAfter(dir, name) {
  try {
    readFileSync(join(dir, name));
    return true;
  } catch {
    return false;
  }
}
