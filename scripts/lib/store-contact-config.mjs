import { isIP } from 'node:net';

const GODOT_PRIVACY_KEY = 'config/privacy_policy_url';
const GODOT_SUPPORT_KEY = 'config/support_contact';

export const STORE_LOCALE_PATHS = Object.freeze({
  'en-US': 'en',
  ko: 'ko',
  ja: 'ja',
  'zh-Hans': 'zh-Hans',
  'zh-Hant': 'zh-Hant',
});

function requireString(value, label) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`${label} is required.`);
  }
  return value.trim();
}

export function normalizePublicSiteBaseUrl(value) {
  const raw = requireString(value, 'public support site URL');
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error('public support site URL is not a valid URL.');
  }
  if (parsed.protocol !== 'https:') {
    throw new Error('public support site URL must use HTTPS.');
  }
  const hostname = parsed.hostname.toLowerCase();
  const reservedHostname = (
    hostname === 'localhost'
    || hostname.endsWith('.localhost')
    || hostname.endsWith('.local')
    || hostname.endsWith('.internal')
    || hostname.endsWith('.invalid')
    || hostname.endsWith('.test')
    || hostname === 'example'
    || hostname.endsWith('.example')
  );
  if (
    parsed.username
    || parsed.password
    || parsed.search
    || parsed.hash
    || !parsed.hostname
    || parsed.pathname !== '/'
    || (parsed.port !== '' && parsed.port !== '443')
    || !hostname.includes('.')
    || isIP(hostname.replace(/^\[|\]$/gu, '')) !== 0
    || reservedHostname
  ) {
    throw new Error(
      'public support site URL must be an HTTPS origin with a public host '
      + 'and no path, credentials, query, or fragment.',
    );
  }
  return parsed.origin;
}

export function normalizePublicSupportEmail(value) {
  const email = requireString(value, 'public support email');
  if (
    email.length > 254
    || email.split('@').length !== 2
  ) {
    throw new Error('public support email is not a valid address.');
  }
  const [localPart, domain] = email.split('@');
  const domainLabels = domain.split('.');
  if (
    !localPart
    || !domain
    || localPart.length > 64
    || localPart.startsWith('.')
    || localPart.endsWith('.')
    || localPart.includes('..')
    || !/^[A-Za-z0-9._+-]+$/u.test(localPart)
    || domain.length > 253
    || domainLabels.length < 2
    || domainLabels.some(
      (label) => (
        label.length < 1
        || label.length > 63
        || !/^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/u.test(label)
      ),
    )
  ) {
    throw new Error('public support email is not a valid address.');
  }
  return email;
}

export function buildStoreContactPlan({ siteBaseUrl, supportEmail }) {
  const baseUrl = normalizePublicSiteBaseUrl(siteBaseUrl);
  const email = normalizePublicSupportEmail(supportEmail);
  const localizations = Object.fromEntries(
    Object.entries(STORE_LOCALE_PATHS).map(([locale, path]) => [
      locale,
      {
        privacyPolicyUrl: `${baseUrl}/${path}/privacy`,
        supportUrl: `${baseUrl}/${path}/support`,
      },
    ]),
  );
  return {
    siteBaseUrl: baseUrl,
    supportEmail: email,
    game: {
      privacyPolicyUrl: `${baseUrl}/{locale}/privacy`,
      supportContact: `${baseUrl}/{locale}/support`,
    },
    appStore: localizations,
    xDefault: {
      privacyPolicyUrl: `${baseUrl}/privacy`,
      supportUrl: `${baseUrl}/support`,
    },
  };
}

function replaceGodotStringSetting(source, key, value) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const pattern = new RegExp(`^${escapedKey}=.*$`, 'gmu');
  const matches = source.match(pattern) ?? [];
  if (matches.length !== 1) {
    throw new Error(
      `project.godot ${key} must appear exactly once: ${matches.length} found`,
    );
  }
  return source.replace(pattern, `${key}=${JSON.stringify(value)}`);
}

export function configureProjectContactSource(source, plan) {
  if (typeof source !== 'string' || !plan?.game) {
    throw new TypeError('project.godot source and a contact plan are required.');
  }
  const withPrivacy = replaceGodotStringSetting(
    source,
    GODOT_PRIVACY_KEY,
    plan.game.privacyPolicyUrl,
  );
  return replaceGodotStringSetting(
    withPrivacy,
    GODOT_SUPPORT_KEY,
    plan.game.supportContact,
  );
}

export function projectContactMatches(source, plan) {
  return configureProjectContactSource(source, plan) === source;
}
