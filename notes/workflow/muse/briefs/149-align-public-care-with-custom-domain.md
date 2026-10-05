# Brief 149: Align public care with the custom domain

## The ask
“저기 firebase hosting을 moonlitbeacon.hyo.dev 로 hosting으로 연결해서 관련된 사이트는 chatgpt 호스팅이 아니라 저기에 다 올려서 관리해줘. 모노레포로 관리하면 되려나 개인정보 등등 모두.”
“vercel도 로그인해놨어 너가 hosting moonlitbeacon.hyo.dev로 연결해줘”
Continue brief 148 with this newly explicit public origin and finish its policy copy.

## Where things stand
Round 148 created the static five-language player-care site, but was briefed
before the user chose a custom origin. The director has registered that
origin in Firebase Hosting and added its server-specified DNS records.
Publication is not yet verified; do not claim it is. The default Firebase
site and working auth callback remain as currently configured. Root now
also contains an accepted title-capture bridge change; do not touch it.

## Do
- Make `https://moonlitbeacon.hyo.dev` the canonical player-care origin,
  generated canonical/hreflang links, two game contact settings and current
  player-facing contact instructions in `notes/release/store-page.md`.
  Regenerate and verify all static output. Retain the native auth callback
  and Firebase project identifiers exactly; they are not public site URLs.
- Finish disclosure gaps in all five languages: account/checkpoint records
  have no configured automatic expiry and remain until account deletion;
  local retained records and sign-out are distinct from cloud deletion.
  Explain Firebase/provider native-session storage accurately: gameplay save
  files contain no sign-in tokens, while native SDK session persistence is
  governed by SDK/OS storage. Do not imply all authentication credentials
  only ever live in memory.
- Preserve source-backed purchase processor/infrastructure/statistics and
  support-request handling/retention disclosures from the approved privacy
  draft and repo's IAPKit sources. Keep lawful access/correction/deletion
  contact. Do not invent a retention duration or processor policy URL.
  Clarify profile-data purposes without internal audit implementation prose.
- Refine awkward Korean translations such as “내구성 공개 ID”, “로그인·세션
  자격”, “비공개 버전 저장” into clear player-facing Korean; keep semantics
  aligned across five languages. Describe nonconsumable ownership and restore
  without promising irrevocable ownership after a refund. Keep coin grants
  and the seven/three product split exact.
- Extend focused regressions to pin the new canonical origin and retention/
  native-session/support-handling content. Keep existing meaningful negative
  tests and exact generated-output checks.

## Do not
No network/deployment, DNS writes, credentials, auth/IAP/save/gameplay changes,
new dependency, protected guide/guard/version changes or audit notes in player
copy. Leave historical evidence URLs, fixture URLs and native callback URLs
unchanged. Course hosting will be a separate brief; do not broaden this one.

## Acceptance
All 18 routes and ten localized policy/support pages build/check; contact and
locale regressions pass. Search active game/site/store-contact copy for the
old ChatGPT origin and ensure none remains. Read source-linked privacy
semantics rather than trusting substring checks. The director will render
mobile/desktop and verify live TLS/HTTP before store metadata relies on it.

## Deliverables
Narrow correction to the new site, tests, two contact settings and current
publication/store-contact notes. Record actual tests and unfinished operations.
