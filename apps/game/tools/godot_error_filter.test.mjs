import assert from 'node:assert/strict';
import test from 'node:test';
import {
  godotErrorMessages,
  isExpectedTranslationBootstrap,
} from './godot_error_filter.mjs';

const bootstrapOutput = `
ERROR: Cannot open file 'res://localization/moonlit.en.translation'.
   at: load (core/io/resource_format_binary.cpp:1156)
ERROR: Failed loading resource: res://localization/moonlit.en.translation.
ERROR: Cannot open file 'res://localization/moonlit.ko.translation'.
ERROR: Failed loading resource: res://localization/moonlit.ko.translation.
`;

test('allows only translation-resource errors from the first import', () => {
  assert.equal(isExpectedTranslationBootstrap({
    engineOutput: bootstrapOutput,
    translationsMissingBefore: true,
    translationsPresentAfter: true,
  }), true);
});

test('rejects translation errors mixed with other Godot errors', () => {
  assert.equal(isExpectedTranslationBootstrap({
    engineOutput: `${bootstrapOutput}\nERROR: Invalid scene owner.`,
    translationsMissingBefore: true,
    translationsPresentAfter: true,
  }), false);
});

test('does not hide errors if translation files were not created or already existed', () => {
  assert.equal(isExpectedTranslationBootstrap({
    engineOutput: bootstrapOutput,
    translationsMissingBefore: true,
    translationsPresentAfter: false,
  }), false);
  assert.equal(isExpectedTranslationBootstrap({
    engineOutput: bootstrapOutput,
    translationsMissingBefore: false,
    translationsPresentAfter: true,
  }), false);
});

test('extracts real Godot errors even with an ANSI prefix', () => {
  assert.deepEqual(
    godotErrorMessages(`\u001b[31mERROR: Invalid scene owner.\u001b[0m\nok`),
    ['ERROR: Invalid scene owner.'],
  );
});
