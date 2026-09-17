const TRANSLATION_BOOTSTRAP_ERRORS = new Set([
  "ERROR: Cannot open file 'res://localization/moonlit.en.translation'.",
  "ERROR: Failed loading resource: res://localization/moonlit.en.translation.",
  "ERROR: Cannot open file 'res://localization/moonlit.ko.translation'.",
  "ERROR: Failed loading resource: res://localization/moonlit.ko.translation.",
]);

export function godotErrorMessages(engineOutput) {
  return String(engineOutput)
    .split(/\r?\n/)
    .map((line) => {
      const normalized = line.replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, '');
      const errorStart = normalized.indexOf('ERROR:');
      return errorStart >= 0 ? normalized.slice(errorStart).trim() : '';
    })
    .filter(Boolean);
}

export function isExpectedTranslationBootstrap({
  engineOutput,
  translationsMissingBefore,
  translationsPresentAfter,
}) {
  if (!translationsMissingBefore || !translationsPresentAfter) return false;

  const errors = godotErrorMessages(engineOutput);
  return errors.length > 0
    && errors.every((message) => TRANSLATION_BOOTSTRAP_ERRORS.has(message));
}
