import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildStoreContactPlan,
  configureProjectContactSource,
  normalizePublicSiteBaseUrl,
  normalizePublicSupportEmail,
  projectContactMatches,
  STORE_LOCALE_PATHS,
} from './store-contact-config.mjs';

const PROJECT_SOURCE = `[application]

config/name="Moonlit Beacon"
config/privacy_policy_url=""
config/support_contact=""

[display]
`;

test('normalizes the public site URL and email', () => {
  assert.equal(
    normalizePublicSiteBaseUrl('https://support.example.com/'),
    'https://support.example.com',
  );
  assert.equal(
    normalizePublicSupportEmail('support+moonlit@example.com'),
    'support+moonlit@example.com',
  );
  for (const invalid of [
    'http://example.com',
    'https://user@example.com',
    'https://example.com?draft=1',
    'https://example.com/#draft',
    'https://example.com/moonlit',
    'https://localhost',
    'https://127.0.0.1',
    'https://support.local',
    'https://support.example.com:8443',
  ]) {
    assert.throws(() => normalizePublicSiteBaseUrl(invalid));
  }
  for (const invalid of [
    '',
    'support@example',
    'support+moonlit@example.com?subject=x',
    'two@@example.com',
    'first..last@example.com',
    'support@example..com',
    'support@-example.com',
    'support%0A@example.com',
    'support?subject=hijack@example.com',
    'support#fragment@example.com',
    'support/name@example.com',
  ]) {
    assert.throws(() => normalizePublicSupportEmail(invalid));
  }
});

test('builds the five App Store locale URLs and x-default deterministically', () => {
  const plan = buildStoreContactPlan({
    siteBaseUrl: 'https://support.example.com/',
    supportEmail: 'support@example.com',
  });
  assert.deepEqual(Object.keys(plan.appStore), Object.keys(STORE_LOCALE_PATHS));
  assert.deepEqual(plan.appStore['en-US'], {
    privacyPolicyUrl: 'https://support.example.com/en/privacy',
    supportUrl: 'https://support.example.com/en/support',
  });
  assert.deepEqual(plan.appStore['zh-Hant'], {
    privacyPolicyUrl: 'https://support.example.com/zh-Hant/privacy',
    supportUrl: 'https://support.example.com/zh-Hant/support',
  });
  assert.deepEqual(plan.xDefault, {
    privacyPolicyUrl: 'https://support.example.com/privacy',
    supportUrl: 'https://support.example.com/support',
  });
  assert.equal(
    plan.game.privacyPolicyUrl,
    'https://support.example.com/{locale}/privacy',
  );
});

test('changes only the two public links in project.godot', () => {
  const plan = buildStoreContactPlan({
    siteBaseUrl: 'https://support.example.com',
    supportEmail: 'support@example.com',
  });
  const configured = configureProjectContactSource(PROJECT_SOURCE, plan);
  assert.match(
    configured,
    /^config\/privacy_policy_url="https:\/\/support\.example\.com\/\{locale\}\/privacy"$/mu,
  );
  assert.match(
    configured,
    /^config\/support_contact="https:\/\/support\.example\.com\/\{locale\}\/support"$/mu,
  );
  assert.match(configured, /^config\/name="Moonlit Beacon"$/mu);
  assert.equal(projectContactMatches(configured, plan), true);
  assert.equal(projectContactMatches(PROJECT_SOURCE, plan), false);
});

test('does not silently create a missing or duplicate Godot setting', () => {
  const plan = buildStoreContactPlan({
    siteBaseUrl: 'https://support.example.com',
    supportEmail: 'support@example.com',
  });
  assert.throws(
    () => configureProjectContactSource(
      PROJECT_SOURCE.replace('config/support_contact=""\n', ''),
      plan,
    ),
    /exactly once/u,
  );
  assert.throws(
    () => configureProjectContactSource(
      `${PROJECT_SOURCE}config/privacy_policy_url=""\n`,
      plan,
    ),
    /exactly once/u,
  );
});
