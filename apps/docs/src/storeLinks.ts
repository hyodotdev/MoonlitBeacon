// Single source for the public store/contact links used by the docs site's
// entry pages (homepage Play section, first-play invite). Plain constants:
// no click tracking, no pixels, no web storage is attached to these links.
export const PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.crossplatformkorea.moonlitbeacon'
  + '&utm_source=moonlit_course&utm_medium=referral&utm_campaign=course_first_play_20261013';

export const APP_STORE_URL = 'https://apps.apple.com/app/id6796293839';

export const SUPPORT_EMAIL = 'hyo@hyo.dev';

export const FIRST_PLAY_MAILTO =
  `mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent('Moonlit Beacon first-play volunteering')}`;

export const SUPPORT_PRIVACY_URL = 'https://moonlitbeacon.hyo.dev/en/privacy#support-requests';
