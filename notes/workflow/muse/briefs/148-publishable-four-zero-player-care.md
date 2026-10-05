# Brief 148: Publishable four-zero player care

## The ask
“물어보지말고 끝까지 진행해줘 배포까지”
Prepare truthful public privacy/support pages for this release.

## Where things stand
The old public player-care site has no editor access in the connected
account. Its English privacy page still says there are no accounts and the
global board is disabled; its support page lists three old permanent items.
The director read the game's existing Firebase Hosting default site: there
are zero releases, so using it will overwrite no existing hosted content.
The director will deploy only after inspecting this work. The approved
release-copy source is `notes/release/privacy-four-zero-draft.md`; current
products and five locales are in `notes/release/`. In-app Terms already exist
in GateEntry and must remain unchanged.

## Do
- Build a small, polished static player-care site in `apps/player-care/`,
  using an auditable buildless or small Node generator and no dependencies.
  Provide `/en`, `/ko`, `/ja`, `/zh-Hans`, `/zh-Hant` privacy and support
  routes, plus useful root/default routes. Match Moonlit's restrained dark
  night palette, readable text and accessible navigation on phone/tablet.
- Privacy must accurately disclose Firebase Google/Apple/anonymous identity,
  provider credential/profile processing, public ID, private cloud saves,
  the public hero/score/progress Hall, device-only offline guest limits,
  sign-out preservation and account deletion. Use the draft's source
  citations; do not publish audit notes as player copy or falsely promise
  that all server identifiers are hashed. No automatic account/save expiry
  is configured; never invent a retention deadline. Keep optional analytics
  disabled unless both build configuration and explicit consent enable it.
- Preserve the existing purchase-validation disclosure: store/product and
  receipt/token go to IAPKit, validation/order/IP/result/timing may be
  retained for restoration/refunds/fraud/statistics/legal obligations; its
  infrastructure/provider privacy links should be available. Preserve
  support-request handling and lawful access/correction/deletion contact.
  Public publisher/support details must come from existing repo sources.
- Support must reflect all 10 current products (7 permanent, 3 coin packs),
  precise coin grants, store-account restore vs game-account login, guest
  recovery limits and continued progress. No legacy bundle sales or claim
  that consumables can be restored as permanent entitlements. Include
  current official Apple/Google refund and Firebase/provider privacy links.
- Add hosting-only Firebase configuration scoped to the existing default
  site, an explicit dry build/check command, and meaningful route/content/
  local-link regressions. Configure the game's existing two contact URLs
  for `https://moonlitbeacon-778ee.web.app` through the existing contact
  contract, leaving locale routing and in-app Terms intact.

## Do not
No network, deployment, credentials, Site creation or claims that pages are
already published. Do not alter auth/save/purchase behavior, capture
consumers, gameplay, assets, Terms text, other Firebase services, or locked
project values. Do not add tracking, external fonts, scripts or forms.

## Acceptance and judgement
Build/check all routes; verify exact current product inventory and no stale
no-account/disabled-ranking/all-nonconsumable framing. Inspect generated
HTML and mobile/desktop rendering. Existing store-contact, locale and
metadata regressions must pass. Independently break one route/content
boundary and observe failure, then restore exact bytes. The director will
verify the live deployment and all 10 localized URLs before relying on it.

## Deliverables
Static site source/generator, narrow hosting configuration, checks/tests
and registration, the two game contact settings, and a short source-linked
publication note. No protected guides or version changes.
