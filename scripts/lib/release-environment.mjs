export const RELEASE_CREDENTIAL_ENV_NAMES = Object.freeze([
  'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD',
  'GODOT_ANDROID_KEYSTORE_RELEASE_PATH',
  'GODOT_ANDROID_KEYSTORE_RELEASE_USER',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'IAPKIT_API_KEY',
  'MOONLIT_ASC_ISSUER_ID',
  'MOONLIT_ASC_KEY_ID',
  'MOONLIT_ASC_PRIVATE_KEY',
]);

export function credentialFreeChildEnvironment(env = process.env) {
  const childEnv = { ...env };
  for (const name of RELEASE_CREDENTIAL_ENV_NAMES) delete childEnv[name];
  return childEnv;
}
