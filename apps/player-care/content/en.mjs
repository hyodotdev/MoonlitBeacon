// English player-care copy. Master text; other locales translate this page
// structure section by section.
import { LINKS, SUPPORT_EMAIL } from './shared.mjs';

const mailto = `mailto:${SUPPORT_EMAIL}`;

export const CONTENT = {
  lang: 'en',
  gameName: 'Moonlit Beacon',
  homeName: 'Player Care',
  skip: 'Skip to content',
  navHome: 'Home',
  navPrivacy: 'Privacy Policy',
  navSupport: 'Support',
  navDocs: 'Course & Docs',
  mainNavLabel: 'Pages',
  navLanguageLabel: 'Language',
  languageNames: {
    en: 'English',
    ko: '한국어',
    ja: '日本語',
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
  },

  homeTitle: 'Moonlit Beacon — Player Care',
  homeLede:
    'Privacy and support pages for Moonlit Beacon by Hyo Dev, in five languages.',
  homePrivacyHeading: 'Privacy Policy',
  homeSupportHeading: 'Support',
  homeContact:
    `Questions: <a href="${mailto}">${SUPPORT_EMAIL}</a>. Include your player ID so the request can be matched to your records.`,

  privacyTitle: 'Privacy Policy — Moonlit Beacon',
  privacyLede:
    'This policy explains what Moonlit Beacon by Hyo Dev collects and how it is handled.',
  updated: 'Updated for version 4.0.0.',
  privacySections: [
    {
      id: 'sign-in',
      num: '1',
      h: 'Ways to sign in',
      html: `<ul class="tight">
<li>Entry offers a guest door plus Google and Apple sign-in where the build configures them.</li>
<li>Guest entry creates an anonymous sign-in identity where the device supports it.</li>
<li>Google and Apple are separate sign-in identities. The Play Games gaming profile is a separate Android-only option and is not offered in this build.</li>
</ul>`,
    },
    {
      id: 'sign-in-data',
      num: '2',
      h: 'What sign-in handles',
      html: `<ul class="tight">
<li>Firebase and the Google or Apple provider you choose process identifiers, sign-in and session credentials, and the profile fields your consent and provider settings make available, to authenticate and recover the account.</li>
<li>The game keeps its own records: your public player ID, the private link between your signed-in account and that ID, and your checkpoint saves.</li>
<li>Only the game's on-device account list stores the server account reference in hashed form. Account and save records held by the backend carry the raw account reference and stay private to your account.</li>
<li>The game itself holds sign-in tokens in memory while it reaches your records. Gameplay save files contain no sign-in tokens, and tokens are never placed in public ranking. Staying signed in across launches is handled separately by the Firebase and provider SDKs, which keep their own session data under SDK and OS storage.</li>
<li>Email and profile information is not shown in public Hall rows. Provider-side profile handling follows that provider's own policy: <a href="${LINKS.firebasePrivacy}">Firebase</a>, <a href="${LINKS.googlePrivacy}">Google</a>, <a href="${LINKS.applePrivacy}">Apple</a>.</li>
</ul>`,
    },
    {
      id: 'player-id',
      num: '3',
      h: 'Your player ID',
      html: `<ul class="tight">
<li>Each install mints a durable public player ID of the form <code>MB-</code> plus 32 hexadecimal characters before first play.</li>
<li>It names your saved gate and your Hall rows, and it survives linking: connecting Google to the original guest keeps the same ID and the same checkpoint ownership.</li>
<li>Signing out starts a fresh guest ID on the device while the previous ID and its saves stay kept. Signing back in with the same provider returns to that account's ID and kept saves. One install can therefore hold more than one ID over time.</li>
<li>Include your player ID, shown in the game's account panel, when you contact support.</li>
</ul>`,
    },
    {
      id: 'cloud-saves',
      num: '4',
      h: 'Cloud saves',
      html: `<ul class="tight">
<li>A signed-in account owns one private versioned save holding its progress (cycle, hero, relics, growth, scores).</li>
<li>Saves land on the device first; uploads follow in the background.</li>
<li>Saves never carry purchase or balance records.</li>
<li>Downloads are fully checked before install, and a differing cloud copy waits for you to choose which side to keep.</li>
</ul>`,
    },
    {
      id: 'hall',
      num: '5',
      h: 'Hall board',
      html: `<ul class="tight">
<li>The Hall keeps one best entry per player ID: player ID, hero, score, progress, app version, and update time.</li>
<li>Board reads are public; only the owning account may write its entry. Scores only increase, and standing is derived from scores so equal scores share one rank.</li>
<li>No name, email, account reference, token, or save appears in a Hall entry.</li>
</ul>`,
    },
    {
      id: 'deletion',
      num: '6',
      h: 'Deletion',
      html: `<ul class="tight">
<li>Delete your cloud account from the game's account settings. Deletion first removes its Hall entry, cloud save, reservation, and profile together in one verified step; only after that confirmation is the sign-in itself deleted.</li>
<li>On iOS, deleting an Apple-linked account may ask you to confirm again through the Apple sign-in sheet.</li>
<li>Signing out ends the sign-in session and switches to a fresh guest ID; it deletes nothing on the device or in the cloud.</li>
<li>Deleting your cloud account removes your cloud records and sign-in, but files already on this device — local saves and the on-device account list — stay until you reinstall the game or clear its storage.</li>
<li>Account, checkpoint, and Hall records have no configured automatic expiry: they remain until the account is deleted.</li>
<li>You can also request access, correction, or deletion of your data by email at <a href="${mailto}">${SUPPORT_EMAIL}</a>. Include your player ID.</li>
<li>Support requests are matched to your records through your player ID; deletion requests that concern purchase records are forwarded to the purchase-verification processor.</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '7',
      h: 'Guests and offline play',
      html: `<ul class="tight">
<li>Guest play works offline as a device-only guest and is never shown as a registered cloud account.</li>
<li>If background sign-up fails, or the build has no sign-in setup, play continues anyway. Builds without sign-in setup make no registration attempt and show no error.</li>
<li>Sign-in, cloud saves, the Hall, the store, and purchase verification need an internet connection.</li>
</ul>`,
    },
    {
      id: 'analytics',
      num: '8',
      h: 'Analytics',
      html: `<p>Optional gameplay analytics stays off unless two switches agree: the shipped build's export configuration and your explicit consent in Settings, which defaults to off.</p>`,
    },
    {
      id: 'purchases',
      num: '9',
      h: 'Purchases',
      html: `<ul class="tight">
<li>Store receipts are verified through the <a href="${LINKS.iapkitDocs}">IAPKit purchase-verification service</a>. Store and product plus the receipt or token (Apple's signed JWS or Google's purchase token) are sent for verification.</li>
<li>Its validation record may retain transaction and order identifiers, store responses, request IP, verification result, and processing duration. Processing serves entitlement grants, restores and revocations, refunds, fraud and duplicate prevention, diagnosis, and service statistics.</li>
<li>For service statistics, IAPKit may send a project-first-valid-receipt event and the store kind to Mixpanel; that event excludes the purchase token, transaction ID, and IP. Convex provides IAPKit's infrastructure. Their policies: <a href="${LINKS.iapkitPrivacy}">IAPKit</a>, <a href="${LINKS.convexPrivacy}">Convex</a>, <a href="${LINKS.mixpanelPrivacy}">Mixpanel</a>. These third-party service statistics are separate from the game's optional gameplay analytics, which stays off unless you enable it in Settings.</li>
<li>Neither the app nor the developer receives your payment-card information or store-account password. Keys, signatures, and purchase tokens are kept out of logs and error messages.</li>
<li>Store-side purchase processing follows each store's own policy: <a href="${LINKS.applePrivacy}">Apple</a>, <a href="${LINKS.googlePrivacy}">Google</a>.</li>
</ul>`,
    },
    {
      id: 'support-requests',
      num: '10',
      h: 'Support requests',
      html: `<ul class="tight">
<li>Emailing support processes your email address, message, and any attachments you choose to send, together with the email service provider, to resolve your request.</li>
<li>Support keeps your request only while needed to resolve it and to meet legal duties.</li>
<li>When a purchase is involved, support asks only for the minimum order detail needed to locate the record — never a full receipt, password, or verification code.</li>
<li>Providers retain validation records as necessary for restoration, refunds, fraud prevention, statistics, accounting, and legal obligations; no uniform expiry is promised.</li>
<li>Records the law requires to keep can remain, and requests about processor-held records can be relayed to the processor.</li>
<li>Your support request and the verification above may be processed outside your country.</li>
</ul>`,
    },
    {
      id: 'changes',
      num: '11',
      h: 'Changes to this policy',
      html: `<p>When the game changes how it handles data, this page is updated with the new version. This edition covers version 4.0.0.</p>`,
    },
  ],

  supportTitle: 'Support — Moonlit Beacon',
  supportLede:
    'Help with purchases, accounts, saves, and the Hall.',
  supportSections: [
    {
      id: 'contact',
      num: '1',
      h: 'Contact us',
      html: `<ul class="tight">
<li>Email <a href="${mailto}">${SUPPORT_EMAIL}</a>. Include your player ID (<code>MB-</code>&#8230;, shown in the game's account panel), your device model and OS version, and what happened.</li>
<li>Never send passwords, purchase tokens, or verification codes; support never asks for them.</li>
<li>Bug reports are also welcome at <a href="${LINKS.issues}">GitHub Issues</a>.</li>
</ul>`,
    },
    {
      id: 'products',
      num: '2',
      h: 'Current items',
      html: `<p>The store sells 10 items: 7 permanent one-time items and 3 Continue Coin packs.</p>
%%PRODUCT_TABLE%%
<ul class="tight">
<li>Permanent items stay with your store account across reinstalls and come back through Restore purchases.</li>
<li>Coin packs grant 1, 5, or 10 coins. One coin resumes a run where you fell with score, level, and relics kept. Spent coins are not restored; each pack can be bought again after verification and consumption.</li>
<li>Prices and taxes follow each store's listing.</li>
</ul>`,
    },
    {
      id: 'restore',
      num: '3',
      h: 'Restore purchases vs game-account sign-in',
      html: `<ul class="tight">
<li>Restore purchases (at the bottom of the Store) recovers the 7 permanent items on the same store account (same Apple Account, same Google Play account) after reinstall or on a new device. It needs a connection to the store and the verification service.</li>
<li>Game-account sign-in (Google or Apple in the moon gate) recovers cloud saves and the Hall entry. It is separate from store restore: signing in does not restore purchases, and restoring does not sign you in.</li>
<li>No login is needed to open the Store: from the title screen, Store shows the items and Restore purchases is always visible.</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '4',
      h: 'Guests and lost progress',
      html: `<ul class="tight">
<li>Guest progress is device-only. Reinstalling or moving to a new device without signing in loses it.</li>
<li>Sign in with Google or Apple to keep a cloud copy of your checkpoint.</li>
<li>Signing out keeps the old ID and saves on the device and starts a fresh guest; signing back in with the same provider returns to that account's ID and kept saves.</li>
<li>Unlinked local data may be lost if you reinstall or clear storage (Terms).</li>
</ul>`,
    },
    {
      id: 'conflicts',
      num: '5',
      h: 'Cloud save conflicts',
      html: `<p>When the cloud copy differs, the game shows both sides and asks which to keep before anything is overwritten.</p>`,
    },
    {
      id: 'refunds',
      num: '6',
      h: 'Refunds',
      html: `<ul class="tight">
<li>Purchases follow each store's own payment, restore, and refund procedures; this game adds no extra fees or refund windows.</li>
<li>Apple purchases: request through Apple's official <a href="${LINKS.appleRefund}">Report a Problem</a> page.</li>
<li>Google Play purchases: request through Google Play's official <a href="${LINKS.googleRefund}">refund help</a>.</li>
<li>After a confirmed refund, only that purchase's entitlement is revoked; other permanent items stay.</li>
</ul>`,
    },
    {
      id: 'offline',
      num: '7',
      h: 'Connection and offline play',
      html: `<ul class="tight">
<li>Core play and local records work offline as a guest.</li>
<li>Loading store products, purchasing, purchase verification, sign-in, cloud saves, and the Hall need an internet connection.</li>
<li>There are no ads.</li>
</ul>`,
    },
    {
      id: 'privacy',
      num: '8',
      h: 'Privacy',
      html: `<ul class="tight">
<li>How the game handles accounts, saves, and the Hall: <a href="/en/privacy">Privacy Policy</a>.</li>
<li>Provider policies: <a href="${LINKS.firebasePrivacy}">Firebase</a>, <a href="${LINKS.googlePrivacy}">Google</a>, <a href="${LINKS.applePrivacy}">Apple</a>.</li>
</ul>`,
    },
  ],

  tableCaption: 'All 10 items sold in the store.',
  thItem: 'Item',
  thType: 'Type',
  thGrant: 'What it grants',
  typePermanent: 'Permanent',
  typeConsumable: 'Consumable',
  grantSupporter:
    'Supporter mark beside your name in Settings \u203a Credits, kept permanently.',
  grantHero:
    'Unlocks this hero in the Moon Shrine, permanently. Balanced sidegrade.',
  grantLantern:
    'Beacon flames in Ember, Moon, Violet, and Jade. Cosmetic only.',
  grantCoins: (count) =>
    count === 1
      ? 'Adds 1 coin to your balance.'
      : `Adds ${count} coins to your balance.`,

  footerContact: 'Questions',
  footerRights: '\u00a9 2026 Hyo Jang. Moonlit Beacon by Hyo Dev.',
};
