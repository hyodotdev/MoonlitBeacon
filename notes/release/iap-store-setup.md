# IAP store setup · sandbox test checklist

Store shop code and automatic tests are separate from store setup where real
money moves. This document is a checklist filled before release by the
**actual selling party with App Store Connect and Google Play Console
access**. Do not guess account owner, business information, contacts,
tax/payout information, sales countries, or final prices into this
repository.

## Locked product definitions

The 10 sale items are 7 permanently owned non-consumables and 3 consumable
Continue Coins. Do not make subscriptions, gacha products, or combat-power
tiers. Shop prices show the local price returned by that store, not a value
from code. The five heroes are balanced sidegrades with different control
feel and art/attack presentation; a higher price does not mean higher combat
power. The free Moonlit Warden can play every region, Guardian, and cycle.

| Shop display name | Product ID | Type | Baseline price | Grant |
| --- | --- | --- | --- | --- |
| Moonlit Supporter | `com.crossplatformkorea.moonlitbeacon.supporter` | non-consumable / one-time | ₩3,300 | Credits: current local ladder name plus supporter mark |
| Shadow Dancer | `com.crossplatformkorea.moonlitbeacon.hero_dancer` | non-consumable / one-time | US $4.99 | Balanced hero with violet twin-moon arcs and spiral moonlight |
| Beacon Keeper | `com.crossplatformkorea.moonlitbeacon.hero_keeper` | non-consumable / one-time | US $9.99 | Balanced hero with jade-lantern ripples and gold impact |
| Silver Moon Knight | `com.crossplatformkorea.moonlitbeacon.hero_knight` | non-consumable / one-time | US $14.99 | Balanced hero with silver crescent fans and white star shards |
| Eclipse Mage | `com.crossplatformkorea.moonlitbeacon.hero_eclipse` | non-consumable / one-time | US $19.99 | Balanced hero with crimson eclipse rings and dark-red embers |
| Constellation Sage | `com.crossplatformkorea.moonlitbeacon.hero_sage` | non-consumable / one-time | US $24.99 | Balanced hero with teal constellation chains and gold stars |
| Lantern Colors | `com.crossplatformkorea.moonlitbeacon.lantern_colors` | non-consumable / one-time | ₩1,100 | Four beacon-flame colors. No detection-range or combat change |
| Continue Coin | `com.crossplatformkorea.moonlitbeacon.continue_coin` | **consumable** | $0.49 | Resume the run where you fell. Can be bought ahead; one coin per purchase |
| Continue Coins ×5 | `com.crossplatformkorea.moonlitbeacon.continue_coin_5` | **consumable** | $1.99 | Five coins per purchase. $0.398 each |
| Continue Coins ×10 | `com.crossplatformkorea.moonlitbeacon.continue_coin_10` | **consumable** | $3.49 | Ten coins per purchase. $0.349 each |

Do not change product IDs after release. Console product IDs, the
bundle/package ID in `project.godot`, and the build signing subject must all
point at the same app.

`com.crossplatformkorea.moonlitbeacon.hero_bundle` is a legacy SKU excluded
from new sales, CSV, and the release manifest. Prior buyers' Shadow Dancer
and Beacon Keeper entitlements still restore; a confirmed refund revokes only
this legacy source. Do not sell that product again or reuse it as a new
product.

## Privacy-notice baseline

Release-build purchase verification sends IAPKit Apple JWS or a Google
purchase token, product ID, and store kind. The verification server
persistently stores transaction/order identifiers, store verification
responses, request IP, verification result, and processing time, and uses
whether the project has had a first successful verification in stats.
Neither the app nor the developer receives payment-card information or store-
account passwords.

- App Store App Privacy: answer that `Financial Info > Purchase History` and
  `Performance Data` are collected, linked to the user, not used for tracking.
  Purposes are `App Functionality` and `Analytics`.
- Google Play Data safety: answer `Financial info > Purchase history` and
  `App info and performance > Diagnostics` as collected, not shared, not
  ephemeral, optional. Purposes are App functionality, Analytics, Fraud
  prevention/security/compliance, and encryption in transit is `Yes`.
- The 2.1.0 submit has no protected collection path, so anonymous game
  analytics is disabled. Only a later release with a protection path and
  public notice sends explicitly allowed game events to Firestore, and does
  not put product ID, JWS, purchase token, transaction/order ID, ladder
  name, or device/permanent-install ID in analytics events. Only that later
  build compares App Store `Usage Data > Product Interaction` and Google
  Play `App activity > App interactions` as optional Analytics collection
  against the real binary.
- Until a public support email and a real manual-deletion request process
  are ready, Google's deletion-request-available answer is `No`. After they
  are ready, it can become `Yes` only if support requests can be safely
  matched to purchase records and deletion/de-identification requests can
  be forwarded to the IAPKit processor.
- Do not guess answers from whether `firebase.cfg` is included. Inspect
  actual release config and transmitted data for the global ladder and
  anonymous analytics separately, and update the privacy policy, App
  Privacy, and Data safety together. Turning analytics on also requires
  remote deploy of Firestore rules, indexes, and 90-day TTL.

## Localization for console input

[`store-localizations.csv`](./store-localizations.csv) is the source of short
fields for Google Play, App Store Connect, and IAPKit, plus 5-language App
Review Notes. Customer-facing copy for the 10 sale products is kept the same
on both platforms, and descriptions were written at 45 characters or fewer
to match the stricter App Store limit.

| Product | Korean name · description | English name · description |
| --- | --- | --- |
| Moonlit Supporter | **달빛 후원자** · 크레딧 이름 옆에 후원자 표식을 영구히 남깁니다. | **Moonlit Supporter** · Permanent supporter mark beside your name. |
| Shadow Dancer | **그림자 무희** · 보랏빛 쌍월호 연출의 균형형 영웅입니다. | **Shadow Dancer** · Balanced style with purple twin arcs. |
| Beacon Keeper | **봉화지기** · 비취 등불 파문 연출의 균형형 영웅입니다. | **Beacon Keeper** · Balanced style with jade lantern ripples. |
| Silver Moon Knight | **백월 기사** · 은빛 초승달 부채 연출의 균형형 영웅입니다. | **Silver Moon Knight** · Balanced style with silver crescent fans. |
| Eclipse Mage | **월식 마도사** · 진홍 월식 고리 연출의 균형형 영웅입니다. | **Eclipse Mage** · Balanced style with crimson eclipse rings. |
| Constellation Sage | **성좌 현자** · 청록 성좌 사슬 연출의 균형형 영웅입니다. | **Constellation Sage** · Balanced style with teal star chains. |
| Lantern Colors | **봉화 색상 꾸러미** · 봉화 불빛 4색을 선택합니다. 전투 성능은 그대로입니다. | **Lantern Colors** · Choose four beacon colors. No combat boost. |
| Continue Coin | **이어하기 코인** · 쓰러진 자리에서 이어갑니다. 점수·유물 유지. | **Continue Coin** · Resume where you fell. Score and relics stay. |
| Continue Coins ×5 | **이어하기 코인 5개** · 코인 5개 묶음. 개당 가격이 내려갑니다. | **Continue Coins ×5** · Five continue coins. Lower price per coin. |
| Continue Coins ×10 | **이어하기 코인 10개** · 코인 10개 묶음. 개당 가격이 가장 쌉니다. | **Continue Coins ×10** · Ten continue coins. Best price per coin. |

| Product | Japanese name · description | Simplified Chinese name · description | Traditional Chinese name · description |
| --- | --- | --- | --- |
| Moonlit Supporter | **月明かりの支援者** · クレジットの名前に支援者印を永久表示します。 | **月光支持者** · 在制作名单的名字旁永久显示支持者标记。 | **月光贊助者** · 在製作名單的名字旁永久顯示贊助者標記。 |
| Shadow Dancer | **影の舞姫** · 紫の双月弧を描く、性能均衡型の英雄です。 | **暗影舞者** · 平衡型英雄，释放紫色双月弧与螺旋月光。 | **暗影舞者** · 平衡型英雄，釋放紫色雙月弧與螺旋月光。 |
| Beacon Keeper | **烽火の守り人** · 翡翠の灯火波紋を描く、性能均衡型の英雄です。 | **烽火守护者** · 平衡型英雄，释放翡翠灯火波纹与金色冲击。 | **烽火守護者** · 平衡型英雄，釋放翡翠燈火波紋與金色衝擊。 |
| Silver Moon Knight | **白月の騎士** · 銀の三日月扇を描く、性能均衡型の英雄です。 | **白月骑士** · 平衡型英雄，释放银色新月扇与白色星屑。 | **白月騎士** · 平衡型英雄，釋放銀色新月扇與白色星屑。 |
| Eclipse Mage | **月蝕の魔導士** · 深紅の月蝕輪を描く、性能均衡型の英雄です。 | **月蚀法师** · 平衡型英雄，释放深红月蚀环与黑红余烬。 | **月蝕法師** · 平衡型英雄，釋放深紅月蝕環與黑紅餘燼。 |
| Constellation Sage | **星座の賢者** · 青緑の星座連鎖を描く、性能均衡型の英雄です。 | **星座贤者** · 平衡型英雄，释放青绿星链与金色星座。 | **星座賢者** · 平衡型英雄，釋放青綠星鏈與金色星座。 |
| Lantern Colors | **烽火カラーパック** · 烽火の炎を4色から選択。戦闘性能は変わりません。 | **烽火颜色包** · 从4种烽火颜色中选择，不提升战斗能力。 | **烽火顏色包** · 從4種烽火顏色中選擇，不提升戰鬥能力。 |
| Continue Coin | **コンティニューコイン** · 倒れた場所から再開。スコアと遺物は維持。 | **继续游戏金币** · 从倒下之处继续。分数与遗物保留。 | **繼續遊戲金幣** · 從倒下之處繼續。分數與遺物保留。 |
| Continue Coins ×5 | **コンティニューコイン 5個** · コンティニューコイン5枚。1枚あたりが安い。 | **继续游戏金币 5 个** · 继续游戏金币5枚，单价更低。 | **繼續遊戲金幣 5 個** · 繼續遊戲金幣5枚，單價更低。 |
| Continue Coins ×10 | **コンティニューコイン 10個** · コンティニューコイン10枚。1枚あたり最安。 | **继续游戏金币 10 个** · 继续游戏金币10枚，单价最低。 | **繼續遊戲金幣 10 個** · 繼續遊戲金幣10枚，單價最低。 |

Limits and product types as of 2026-07-30:

| Platform | Type | Name | Description | Review notes |
| --- | --- | --- | --- | --- |
| App Store | Non-Consumable | 2–30 characters | max 45 characters | max 4,000 characters |
| App Store | Consumable | 2–30 characters | max 45 characters | max 4,000 characters |
| Google Play | One-time product · Buy · multi-quantity off | max 55 characters | max 200 characters | no per-product field |

Sources are [Apple In-App Purchase information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
and
[Google Play One-time product API](https://developers.google.com/android-publisher/api-ref/rest/v3/monetization.onetimeproducts).
Google Play Console has not supported product CSV import since 2025-05-19, so
do not upload this CSV to the console. Use it as a human comparison source
before IAPKit sync or per-item console entry.

### App Review Notes

From the title screen, which needs no login, `Store` shows 3 coin products
above and 7 permanent products below, and `Restore purchases` is always
visible. Each hero's portrait can be pressed to confirm full body and
dedicated attack presentation before purchase. All 50 Apple rows in
`store-localizations.csv` include Review Notes in 5 languages, and the
release manifest uses each product's English note as the App Store Connect
per-product Review Note. The other four language notes are comparison
sources for operators and review response. Every hero note states
non-consumable, permanent ownership, restore path, balanced sidegrade, that
price reflects art and presentation differences, and that the free Moonlit
Warden can complete the whole game. Coin notes state consumable, grant
count, where they are used, and that they can be purchased again; they are
not described as restore targets.

Do not clone one shared review screenshot. `pnpm store:capture-screenshots`
scrolls the Korean real shop's horizontal list to each product position,
then makes the files below, and the `app-store-release` manifest binds them
1:1 to product IDs. If a debug build does not receive a real localized
price, leave the real `device store only` price and App Store/Google Play
notices as-is. Show buy/restore copy, but both buttons are disabled as in
reality, and capture-prep code does not overwrite price, state, or button
values.

| Product | Review image |
| --- | --- |
| `hero_dancer` | `builds/release/app-store/iap-review/hero-dancer.png` |
| `hero_keeper` | `builds/release/app-store/iap-review/hero-keeper.png` |
| `hero_knight` | `builds/release/app-store/iap-review/hero-knight.png` |
| `hero_eclipse` | `builds/release/app-store/iap-review/hero-eclipse.png` |
| `hero_sage` | `builds/release/app-store/iap-review/hero-sage.png` |
| `supporter` | `builds/release/app-store/iap-review/supporter.png` |
| `lantern_colors` | `builds/release/app-store/iap-review/lantern-colors.png` |
| `continue_coin` | `builds/release/app-store/iap-review/continue-coin.png` |
| `continue_coin_5` | `builds/release/app-store/iap-review/continue-coin-5.png` |
| `continue_coin_10` | `builds/release/app-store/iap-review/continue-coin-10.png` |

Legacy `hero_bundle` is kept only for past-purchase restore and is not put
in new product lists, review images, or the release manifest.

#### Moonlit Supporter

```text
앱 실행 후 타이틀의 상점 > 달빛 후원자를 누릅니다. 비소모성 구매이며 설정 > 크레딧에 현재 로컬 순위표 이름과 후원자 표식을 영구히 추가합니다. 이름이 없으면 이름없음으로 표시됩니다. 전투 수치는 바뀌지 않습니다. 상점 하단의 구매 복원으로 복원할 수 있습니다.
```

```text
Launch the app and open Store > Moonlit Supporter. This non-consumable permanently adds the current local high-score name and a supporter mark in Settings > Credits. If no name exists the app shows Nameless. It does not change combat. Use Restore purchases at the bottom of the Store to restore it.
```

#### Legacy hero bundle — do not submit new

```text
영웅 묶음은 신규 판매 목록에서 숨깁니다. 과거 구매 복원 시 그림자 무희와 봉화지기 권한을 되살리고, 환불 확정 시 레거시 묶음 출처만 회수합니다.
```

```text
Hero Bundle is retired from new sales. Restore purchases must still recover Shadow Dancer and Beacon Keeper for prior buyers, while a confirmed refund revokes only the legacy bundle source.
```

#### Lantern Colors

```text
앱 실행 후 타이틀의 상점 > 봉화 색상 꾸러미를 누릅니다. 비소모성 구매이며 기본 불씨에 달빛·보랏빛·비취빛을 추가합니다. 같은 상점 화면에서 색을 장착합니다. 꾸미기 전용이며 피해·범위·감지·체력에 영향을 주지 않습니다. 상점 하단의 구매 복원으로 복원할 수 있습니다.
```

```text
Launch the app and open Store > Lantern Colors. This non-consumable unlocks Moon, Violet, and Jade in addition to the default Ember color. Select a color in the same Store panel. It is cosmetic and does not change damage, range, detection, or health. Use Restore purchases at the bottom of the Store to restore it.
```

### Japanese operator comparison notes

```text
アプリを起動し、タイトル画面で「ストア」>「月明かりの支援者」を開きます。買い切りの非消耗型商品で、設定 > クレジットに現在のローカルランキング名と支援者印を永久表示します。名前がない場合は「名無し」と表示されます。戦闘性能は変わりません。ストア下部の「購入を復元」から復元できます。
```

```text
英雄セットは新規販売を終了します。過去の購入者が「購入を復元」を使った場合は影の舞姫と烽火の守り人を復元し、返金確定時は旧セット由来の権利だけを取り消します。
```

```text
アプリを起動し、タイトル画面で「ストア」>「烽火カラーパック」を開きます。買い切りの非消耗型商品で、基本の残り火に月光・紫・翡翠の3色を追加します。同じストア画面で色を選べます。見た目だけの変更で、ダメージ・範囲・索敵・体力は変わりません。ストア下部の「購入を復元」から復元できます。
```

### Simplified Chinese operator comparison notes

```text
启动应用，在标题画面打开“商店”>“月光支持者”。这是一次买断的非消耗型商品，会在“设置”>“制作名单”中永久显示当前本地排行榜名称与支持者标记。没有名称时显示“无名”。不会改变战斗能力。可使用商店底部的“恢复购买”进行恢复。
```

```text
英雄组合包已停止新销售。过去的购买者使用“恢复购买”时仍会恢复暗影舞者与烽火守护者；确认退款时只撤销旧组合包来源的权限。
```

```text
启动应用，在标题画面打开“商店”>“烽火颜色包”。这是一次买断的非消耗型商品，会在默认余烬色之外解锁月光、紫罗兰与翡翠三种颜色，可在同一商店画面中选择。仅改变外观，不影响伤害、范围、侦测或生命。可使用商店底部的“恢复购买”进行恢复。
```

### Traditional Chinese operator comparison notes

```text
啟動應用程式，在標題畫面開啟「商店」>「月光贊助者」。這是一次買斷的非消耗型商品，會在「設定」>「製作名單」中永久顯示目前本機排行榜名稱與贊助者標記。沒有名稱時顯示「無名」。不會改變戰鬥能力。可使用商店底部的「恢復購買」進行恢復。
```

```text
英雄組合包已停止新銷售。過去的購買者使用「恢復購買」時仍會恢復暗影舞者與烽火守護者；確認退款時只撤銷舊組合包來源的權限。
```

```text
啟動應用程式，在標題畫面開啟「商店」>「烽火顏色包」。這是一次買斷的非消耗型商品，會在預設餘燼色之外解鎖月光、紫羅蘭與翡翠三種顏色，可在同一商店畫面中選擇。僅改變外觀，不影響傷害、範圍、偵測或生命。可使用商店底部的「恢復購買」進行恢復。
```

## Shared pre-release prep

- [ ] Prepared the actual selling party's Apple Developer Program and Google
      Play Console accounts.
- [ ] Each platform's contracts, tax, and payout/bank information were
      entered and approved by the actual selling party.
- [ ] Wrote the privacy policy, seller display, customer-support/refund
      contact, and digital-content withdrawal notice for the countries and
      sales method actually applied.
- [ ] After the actual selling party approved the public support email and
      site deploy, reviewed `configure-store-contact.mjs` dry-run and
      applied the game's 5-language links with
      `--apply --confirm-public-contact`.
      The site value must be an HTTPS origin with no subpath, and the same
      values were also put in `MOONLIT_PUBLIC_SITE_URL` ·
      `MOONLIT_SUPPORT_EMAIL` so the App Store release manifest's 5-language
      URLs were verified.
- [ ] After public URLs were applied, rebuilt the Android AAB and iOS
      archive/IPA; did not reuse products made before that as the final
      submit.
- [ ] Confirmed the app package/bundle ID is `com.crossplatformkorea.moonlitbeacon`.
- [ ] This upload's version code and build number are higher than the previous
      upload.
- [ ] The Android 2.1.0(14) / iOS 2.1.0(9) submit has no analytics config, the
      settings screen does not show an analytics-consent choice, and store
      privacy answers match this disabled state.
- [ ] Before a later release that turns protected analytics on, updated the
      5-language privacy policy and both stores' privacy answers, and
      remotely deployed Firestore rules/indexes/90-day TTL.
- [ ] First verified App Check enforcement + valid tokens or an
      authenticated quota collection proxy, then injected the later-release
      `firebase.cfg` `[analytics] enabled=true`, `ingestion_hardened=true`,
      and web API key from outside the repo, and confirmed
      consent/deny/withdraw on those Android and iOS builds on device.
- [ ] Purchase product/transaction IDs are not in game-analytics Firestore
      export, and analytics consent does not change product lookup,
      purchase, restore, or continue grants.
- [ ] Product names, descriptions, store screenshots, and review notes
      accurately explain "heroes are balanced sidegrades", "price
      differences are art/presentation differences", "non-consumable", and
      "the free hero can play the whole game".
- [ ] The app's full description states the 7 optional non-consumable IAPs
      and restore, plus grant counts and repurchase possibility for the 3
      consumable Continue Coins, and Google Play's `Contains in-app
      purchases` mark matches the submit build.
- [ ] Prices were set by the selling party in each console. USD and KRW in
      this document are baselines; actual billed price, tax, and sale
      countries follow console settings.

## IAPKit purchase verification

The project uses [hyo-dev/moonlitbeacon](https://kit.openiap.dev/hyo-dev/project/moonlitbeacon/purchases).
The release goal is all 10 sale SKUs on both Android and iOS. IAPKit USD
values are sync-baseline metadata only, not actual billed prices. After
locking price, sale countries, and product state in App Store Connect and
Play Console, run dry-run and pull-sync in IAPKit. Done when all 10 sale
SKUs are active with `failed 0`, and legacy `hero_bundle` keeps its record
while Android purchase option is inactive and Apple is sale-stopped. IAPKit
pull also reads restore legacy records, so `pulled 11` is possible; do not
judge the new 10-product sync complete from the raw pulled count alone.

The local App Store release manifest and Google Play input manifest only
verify readiness and hashes of copy, images, and files to upload. They do
not prove contracts/tax, DSA status, mainland-China approval and sales
region, Data safety/App Privacy legal answers, or console
upload/submit/review completion. Confirm remote completion separately in
each console.

- [x] Made a separate publishable key for app verification only.
- [x] The local key is stored in macOS Keychain service
      `dev.openiap.kit.moonlitbeacon`, account `MoonlitBeacon Mobile`.
- [x] Stored as GitHub Actions repository secret `IAPKIT_API_KEY`.
- [x] `res://iapkit.cfg` is created only during Store AAB and iOS export, and
      deleted after success or failure. The direct-distribution APK contains
      neither the config nor the Billing SDK.
- [x] IAPKit iOS settings include Bundle ID, App Apple ID, Issuer ID, In-App
      Purchase Key ID and `.p8` for purchase verification, and App Store
      Connect API Key ID and `.p8` for product sync.
- [x] IAPKit Android settings have a least-privilege Google service-account
      JSON uploaded.
- [ ] Apple ASN v2 and Google RTDN are sent to the IAPKit webhook URL, and a
      test notification was confirmed on the Purchases/Webhooks screen.
- [ ] IAPKit Purchases shows real Sandbox/Internal Track verification calls
      for the 10 sale SKUs.
- [ ] On each platform, ran `Dry-run` sync first and reviewed product ID,
      product type, localization, and baseline price before real sync.
      `Reset` was not used.

Grant order is `verify → save local ledger and benefits → finish/acknowledge
and consume`.
Non-consumable and legacy-bundle restore allow only Apple `ENTITLED` and
Google `ENTITLED` or `PENDING_ACKNOWLEDGMENT`. Consumables allow
`READY_TO_CONSUME` and already-acknowledged but not-yet-consumed `ENTITLED`,
plus Google transition `PENDING_ACKNOWLEDGMENT`, and the app consumes
according to the product type it holds.
Response `store` and `productId` must also match exactly. On timeout, 429,
or 5xx, hold both grant and finish, and re-verify on app return, restore, or
reconnect. Deterministic 4xx such as 400, 401, 403, 413 are not retried
forever as a transient outage; they are shown as a support-needed error, and
similarly neither granted nor finished.

Finished transactions also keep a minimal JWS/purchase-token original in the
`user://` app-sandbox ledger. Android refunded transactions disappear from
`queryPurchasesAsync` current purchases, so on app return, relaunch, and
restore, completed transactions missing from the list are also re-verified
with IAPKit. Do not revoke on a transient error or simple list absence;
revoke entitlement and IAP source only when exact store, product, and
`CANCELED` are confirmed. Do not print tokens or keys in logs, UI, or
support messages.
A permanent entitlement verified and saved once is kept on offline relaunch.
Restore after a clean reinstall itself needs store and IAPKit connection, and
existing entitlements are not revoked only because the network is down.

Do not put an `openiap-kit_sk_…` secret/admin key in the app, repo, build
logs, or webhook URL. The app and Apple/Google lifecycle webhooks use only
the publishable key.

## App Store Connect · StoreKit Sandbox

- [ ] Confirmed [Apple's official procedure](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)
      that IAP in a TestFlight-installed app always runs in Apple Sandbox.
      Do not insert a separate test-unlock code; use the real lock, purchase,
      and equip flow.
- [x] Created an app record with the same Bundle ID in App Store Connect
      (App Apple ID `6796293839`).
- [x] Confirmed in the real account that this app's Free Apps Agreement,
      Paid Apps Agreement, Korea tax/W-8BEN, and KEB Hana Bank KRW/USD
      accounts are all active.
- [ ] In **In-App Purchases**, made 7 permanent products **Non-Consumable**
      and 3 Continue Coins **Consumable**, and reconfirmed them in the
      remote list.
- [ ] Excluded legacy `hero_bundle` from new sales and version submit, but
      kept the same product-ID record so past-purchase restore still works.
- [ ] Entered 5-language display names and descriptions, baseline price, and
      sale regions for each item.
- [ ] Entered the real purchase, preview, equip, and restore path in each
      item's App Review Note.
- [ ] Entered a review screenshot showing the real purchase screen for each
      IAP.
- [ ] Connected required IAP review information and restore guidance to the
      app version.
- [ ] Made a Sandbox Tester as a real test Apple ID. Do not arbitrarily use
      a developer's personal Apple ID or a customer account as a test
      account.
- [ ] If TestFlight Sandbox control is needed, signed out of the production
      account in the test device's **Media & Purchases**, then signed in as
      the Sandbox Tester under **Settings → Developer → Sandbox Apple
      Account**. TestFlight's own download needs a production Apple Account,
      so confirm account-switch impact on a dedicated test device.
- [ ] On an iOS 17+ device, installed the TestFlight app with a production
      Apple Account, then if needed signed in to IAP testing with a Sandbox
      Apple Account under **Settings → Developer**. The iOS Simulator is not
      a verification target for this project.
- [ ] From 2.1.0 source, newly made an App Store-style Release export and
      `builds/ios-archive/MoonlitBeacon.xcarchive` with `pnpm ios:archive`.
      This command also confirms `export_options.plist` distribution method
      is `app-store`.
      A "development build without asset catalog" warning from
      `ios:build`/`ios:run` means the connected-device play path used the
      legacy-icon bypass; it does not replace success of this archive that
      includes a normal `Assets.car` and AppIcon. Prior 2.0.0-or-earlier
      archives do not count as 2.1.0(9) Validate/TestFlight evidence.
- [ ] Passed a mode-`600` App Store Connect API `.p8` outside the repo plus
      Key ID and Issuer ID as `MOONLIT_ASC_PRIVATE_KEY`,
      `MOONLIT_ASC_KEY_ID`, `MOONLIT_ASC_ISSUER_ID`, and ran
      `pnpm ios:export-appstore`.
- [ ] `builds/ios-app-store/MoonlitBeacon.ipa` satisfies Apple Distribution
      signing, a distribution provisioning profile, `get-task-allow=false`,
      and the exact bundle/version/build numbers, and
      `pnpm ios:validate:dry-run` and `pnpm ios:upload:dry-run` passed.
- [ ] After the user's final confirmation, passed Apple remote Validate with
      `pnpm ios:validate`.
- [ ] After the user's final confirmation, uploaded the same validated IPA
      to TestFlight with `pnpm ios:upload` and confirmed App Store Connect
      Build Uploads is Complete.
- [ ] Confirmed local prices for all 10 items are visible on product lookup.
- [ ] Purchased each item once and confirmed cancel, pending-approval, and
      success results each show correctly.
- [ ] After a Sandbox refund/revoke notification, confirmed only that
      product's IAP source is revoked and other permanent entitlements stay.
- [ ] Confirmed **Restore purchases** recovers entitlements only once after
      quit/relaunch, delete/reinstall, or on another test device.

## Google Play Console · internal testing

- [ ] Created an app with package name `com.crossplatformkorea.moonlitbeacon`
      in Google Play Console, and filled the payment profile and app
      content/IARC items to the actual state.
- [ ] In **Monetize with Play → Products → In-app products**, made each
      product ID a one-time managed product and activated it.
- [ ] Entered each product's name, description, price, and sale countries.
      Confirm the app UI does not copy a price in, and only shows the local
      price Play returned.
- [ ] Uploaded a signed Android App Bundle (AAB) to the internal test track
      and registered tester emails as testers and license testers.
      Repo `pnpm android:bundle` makes a release AAB with the `Android Play`
      preset, and needs a release keystore outside the repo plus Keychain or
      `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars.
      `.godot/export_credentials.cfg` is not required and is not committed.
      Re-verify the final AAB as package/version
      `com.crossplatformkorea.moonlitbeacon` 2.1.0 (14), targetSdk 36,
      arm64, Billing 9.1.0, and release signing. Prior 2.0.0-or-earlier
      products or hashes do not count as 2.1.0 upload evidence.
- [ ] `pnpm android:build` (debug) and `pnpm android:release` (release)
      `Android` presets are itch.io direct-distribution only.
      The `direct_distribution` feature tag hides the shop button and turns
      off the GodotIap plugin, so the APK manifest must have no
      `com.android.vending.BILLING` permission and no BillingClient code.
      For IAP tests, always install the `Android Play` AAB from the internal
      test track.
- [ ] Installed the internal-test build from Play Store with a test account.
      A local APK from `adb install` alone cannot verify real Play product
      lookup and payment.
- [ ] Confirmed each product lookup, purchase cancel, pending approval, and
      purchase success.
- [ ] Connected Google Play subscriptions and one-time products RTDN to
      IAPKit.
      The IAPKit inbound webhook stores state but does not outbound-push to
      the game, so confirm that app return, relaunch, and restore re-verify
      both the current list and stored completed tokens.
- [ ] Confirmed that after a refunded one-time product disappears from
      current purchases, entitlement is revoked on app return by IAPKit
      `CANCELED` on the stored token.
- [ ] Uninstalled and reinstalled the app, pressed **Restore purchases**,
      and confirmed the 7 non-consumable entitlements return without a
      duplicate grant.

## In-game grant and restore checks

- [ ] Entitlement appears only after purchase success. Pending-approval
      transactions do not grant a hero, color, or supporter mark first.
- [ ] Moonlit Supporter only adds the current ladder name (or an anonymous
      mark if none) in credits and does not change combat power.
- [ ] A new save has only Moonlit Warden free; Shadow Dancer, Beacon Keeper,
      Silver Moon Knight, Eclipse Mage, and Constellation Sage each open only
      after their exact non-consumable SKU is verified.
- [ ] Each paid hero can preview portrait and dedicated attack presentation
      before purchase, and a higher-priced hero is not described or granted
      as a higher combat-power tier.
- [ ] Restoring a legacy hero-bundle past purchase opens only Shadow Dancer
      and Beacon Keeper without duplicates, and a confirmed refund revokes
      only the legacy source.
- [ ] Lantern Colors lets you pick ember, moonlight, violet, and jade, and
      remembers the choice across relaunch. Attack, enemy detection, health,
      and reward numbers do not change.
- [ ] The same transaction notification again does not duplicate
      entitlement, credits, or hero source.
- [ ] Confirm grant is kept after quitting right after purchase and
      relaunching, and unfinished transactions finish safely.
- [ ] After purchase verification, turning the network off and relaunching
      still keeps the saved 7 entitlements.
- [ ] On a clean reinstall, Restore purchases while connected recovers each
      SKU exactly once, and disconnecting during restore does not delete
      existing entitlements and shows a retry notice.
- [ ] Confirm restored entitlements on another device or after reinstall
      apply only once.

## Release verdict

If any item below is empty, hold a real IAP release.

- [ ] Confirmed success and cancel of the 10 sale SKUs in Android internal
      testing and iOS Sandbox, plus restore of the 7 non-consumables and
      repurchase after consume of the 3 consumables.
- [ ] Every new grant appears on the IAPKit Purchases screen, and
      product/store/state mismatch and verification failures do not grant or
      finish.
- [ ] Console price, country, tax, and contract state match the selling
      party's final decision.
- [ ] Actual seller, refund, and privacy-policy information is public to
      users.
- [ ] If anonymous analytics is enabled, privacy notices, store labels,
      Firestore rules/indexes/TTL, release config, and both-platform
      on-device send verification are all done, and IAP identifiers are not
      mixed into analytics.
- [ ] If immediate refund revoke is needed even before the app runs, the
      selling party decided to run login or a separate entitlement server.
      Otherwise, app-return re-verification and customer-support scope were
      explicitly approved.
- [ ] Direct-distribution APK and itch.io builds do not advertise store
      payment or display it as if it works.
