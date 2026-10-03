// Shared player-care site data: locales, outbound links, product order.
// No dependencies. Product names come from store-localizations.csv at build.

export const SITE_BASE = 'https://moonlitbeacon.hyo.dev';

export const SUPPORT_EMAIL = 'hyo@hyo.dev';

export const LOCALES = ['en', 'ko', 'ja', 'zh-Hans', 'zh-Hant'];

// hreflang values per site path (x-default handled separately).
export const HREFLANG = {
  en: 'en',
  ko: 'ko',
  ja: 'ja',
  'zh-Hans': 'zh-Hans',
  'zh-Hant': 'zh-Hant',
};

// Canonical outbound links used by the pages.
export const LINKS = {
  appleRefund: 'https://reportaproblem.apple.com',
  googleRefund: 'https://support.google.com/googleplay/answer/2479637',
  firebasePrivacy: 'https://firebase.google.com/support/privacy',
  googlePrivacy: 'https://policies.google.com/privacy',
  applePrivacy: 'https://www.apple.com/legal/privacy/',
  iapkitDocs: 'https://kit.openiap.dev/docs/api',
  iapkitPrivacy: 'https://kit.openiap.dev/privacy-policy',
  convexPrivacy: 'https://www.convex.dev/legal/privacy',
  mixpanelPrivacy: 'https://mixpanel.com/legal/privacy-policy/',
  issues: 'https://github.com/hyodotdev/MoonlitBeacon/issues',
};

// Sale order on the support page: 7 permanent, then 3 coin packs.
export const PRODUCT_ORDER = [
  'com.crossplatformkorea.moonlitbeacon.supporter',
  'com.crossplatformkorea.moonlitbeacon.hero_dancer',
  'com.crossplatformkorea.moonlitbeacon.hero_keeper',
  'com.crossplatformkorea.moonlitbeacon.hero_knight',
  'com.crossplatformkorea.moonlitbeacon.hero_eclipse',
  'com.crossplatformkorea.moonlitbeacon.hero_sage',
  'com.crossplatformkorea.moonlitbeacon.lantern_colors',
  'com.crossplatformkorea.moonlitbeacon.continue_coin',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_5',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_10',
];

export const PERMANENT_IDS = new Set(PRODUCT_ORDER.slice(0, 7));

// Precise coin grant per consumable product.
export const COIN_GRANTS = {
  'com.crossplatformkorea.moonlitbeacon.continue_coin': 1,
  'com.crossplatformkorea.moonlitbeacon.continue_coin_5': 5,
  'com.crossplatformkorea.moonlitbeacon.continue_coin_10': 10,
};

// CSV locale columns mapped onto site paths (names match across both).
export const CSV_LOCALES = {
  en: ['en-US'],
  ko: ['ko', 'ko-KR'],
  ja: ['ja', 'ja-JP'],
  'zh-Hans': ['zh-Hans', 'zh-CN'],
  'zh-Hant': ['zh-Hant', 'zh-TW'],
};
