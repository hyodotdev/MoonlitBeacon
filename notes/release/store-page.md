# Store-page copy

Release copy for Google Play, App Store, and itch.io is managed in one place.
Pass the length check below before pasting into a console.

```bash
node scripts/check-store-metadata.mjs
```

Record confirmed public support information in this document. Do not guess
seller address or legal confirmations. If any `TODO` below remains, hold
store-review submit.

## itch.io file info

| Item | Value |
| --- | --- |
| Title | 달빛 봉화 (Moonlit Beacon) |
| Version | 3.0.0 |
| Platform | Android (arm64-v8a, Android 7.0+) |
| File | `MoonlitBeacon-3.0.0.apk` |
| Category | Action · Arcade |
| Tags | `pixel-art`, `top-down`, `survivor`, `roguelite`, `mobile`, `godot` |
| Price | Free |

Upload steps are in [checklist](./checklist.md) section 9.

## Google Play · App Store base metadata

As of 2026-07-30, Google Play allows 30 characters for the app name, 80 for
the short description, and 4,000 for the full description. App Store allows
30 characters each for app name and subtitle, 170 for promotional text,
4,000 for description, and 100 bytes for keywords. The source of the short
fields is [`store-localizations.csv`](./store-localizations.csv). Recheck
official limits at
[Google Play app settings](https://support.google.com/googleplay/android-developer/answer/9859152)
and
[App Store platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

| Item | Korean (`ko`) | English (`en-US`) |
| --- | --- | --- |
| App name | 달빛 봉화 | Moonlit Beacon |
| Google Play short description | 유물을 모아 무기를 키우고 봉화 셋을 밝혀 변화하는 수호자에 맞서세요 | Power up with relics, light three beacons, and face a changing Guardian |
| App Store subtitle | 봉화를 밝히는 무한 생존 액션 | Relic-powered survival |
| App Store promotional text | 나리의 신호를 따라 불씨와 유물로 무기를 키우고, 두 갈래 달빛 문으로 여섯 지형을 오가며 봉화를 밝히고 수호자에 도전하세요. | Keep the road home lit for Nari: grow weapons with embers and relics, choose roads through six regions, light beacons, face a Guardian each Wave. |
| App Store keywords | 서바이벌,로그라이트,픽셀,액션,봉화,수호자,오프라인 | survival,roguelite,pixel,action,beacon,guardian,offline |

| Item | Japanese (`ja`) | Simplified Chinese (`zh-Hans`) | Traditional Chinese (`zh-Hant`) |
| --- | --- | --- | --- |
| App name | 月明かりの烽火 | 月光烽火 | 月光烽火 |
| Google Play short description | 遺物で武器を育て、三つの烽火を灯し、変化する守護者に挑もう | 收集遗物强化武器，点燃三座烽火，迎战不断变化的守护者 | 收集遺物強化武器，點燃三座烽火，迎戰不斷變化的守護者 |
| App Store subtitle | 烽火を灯すエンドレスサバイバル | 点燃烽火的无尽生存动作 | 點燃烽火的無盡生存動作 |
| App Store promotional text | ナリの信号を追って火種と遺物で武器を育て、二つの門から選ぶ六地域で烽火を灯し、守護者に挑もう。 | 跟随娜莉的信号，用火种与遗物强化武器，在分叉月门间选择道路，穿越六片区域点燃烽火，迎战不同的守护者。 | 跟隨娜莉的信號，用火種與遺物強化武器，在分叉月門間選擇道路，穿越六片區域點燃烽火，迎戰不同的守護者。 |
| App Store keywords | サバイバル,ローグライト,ドット,アクション,烽火,オフライン | 生存,类幸存者,像素,动作,烽火,守护者,离线 | 生存,類倖存者,像素,動作,烽火,守護者,離線 |

| Shared item | Value |
| --- | --- |
| Category | Games · Action |
| Ads | None |
| Account | No required account |
| In-app purchases | 7 non-consumables (permanent, restorable) + 3 consumable Continue Coins |
| Public ladder intro | Local top 10 stored on-device only |

Screenshots and public copy show only the local ladder. Confirm
`firebase.cfg` inclusion and privacy answers against the actual submit
build, and do not market Firebase, a global ladder, online competition, or
analytics in copy or images until the global ladder and optional anonymous
analytics are verified in the release environment.

### Values the actual seller fills before submit

- [x] Privacy-policy URL —
      `https://moonlit-beacon-support.hyodev.chatgpt.site/{locale}/privacy`
- [x] Customer-support URL —
      `https://moonlit-beacon-support.hyodev.chatgpt.site/{locale}/support`
- [x] Customer-support email — `hyo@hyo.dev`
- [x] After public URLs are locked, run `configure-store-contact.mjs`
      dry-run and an explicit apply so Korean, English, Japanese, Simplified
      Chinese, and Traditional Chinese links in game settings each open a
      real page.
      The site value is an HTTPS origin with no path, and the App Store
      manifest uses the same `MOONLIT_PUBLIC_SITE_URL` ·
      `MOONLIT_SUPPORT_EMAIL` pair.
- [x] App Review contact — Hyo Jang · phone in the password manager ·
      `hyo@hyo.dev`. Do not commit the phone number.
- [ ] Seller name/address and per-country legal notices — App Store Connect
      currently shows non-trader. Do not mark this item done or submit for
      review until the actual selling party finally confirms DSA status and
      per-country display duties.
- [x] App Store copyright — `2026 Hyo Jang`
- [ ] Re-audit Google Play Data safety answers — a build with no analytics
      config, like this 3.0.0 submit, keeps only existing purchase-
      verification Purchase history and Diagnostics matched to real
      behavior, and does not add `App activity > App interactions` as
      analytics collection. Only a later build that turns protected
      analytics collection on also reflects collected, not shared,
      optional, encrypted in transit, plus Analytics purpose and 90-day TTL.
- [ ] Re-audit App Store App Privacy labels — this 3.0.0 analytics-disabled
      build keeps only existing Purchase History/Diagnostic Data matched to
      real purchase-verification behavior, and does not add Analytics-
      purpose `Usage Data > Product Interaction`. Declare not linked to the
      user, not used for tracking, and Analytics purpose together only when
      protected analytics collection is turned on later.
- [ ] Before enabling protected analytics collection, disclose in the
      5-language privacy policy: optional consent, allowed event categories,
      anonymous play metrics excluding permanent IDs/names/purchase IDs, max
      200-item · 14-day offline queue, 90-day server TTL, and local deletion
      on withdraw.
- [ ] Deploy `firestore.rules` · `firestore.indexes.json` · TTL remotely.
      Schema checks on public create alone do not stop spam/cost attacks, so
      inject a release `firebase.cfg` with `ingestion_hardened=true` only
      after verifying App Check enforcement + valid tokens, or an
      authenticated quota collection proxy. Do not submit an analytics-
      enabled build until actual consent/deny/withdraw requests are
      confirmed on the later Android and iOS builds that first turn
      protected analytics on.

The App Store release manifest and Google Play local input manifest are work
products that only confirm readiness and integrity of copy, images, and
files. They do not prove DSA status, mainland-China game approval and sales-
region choice, contract/tax/privacy legal answers, or console
upload/submit/review completion.
Those items are recorded separately from the actual selling party's
confirmation and each console's remote state.

## Short blurb

```text
유물을 모아 무기를 키우고 봉화 셋을 밝혀 변화하는 수호자에 맞서세요
```

```text
Power up with relics, light three beacons, and face a changing Guardian
```

## Korean description

```text
등불마을의 신호지기 나리는 봉화길을 고치러 떠났다가 돌아오지 못했다. 집으로 가는 길을 밝혀달라는 부탁, 주전자는 식지 않게 지켜 주세요.

한 순환에 봉화 셋을 밝혀 그녀의 길을 되찾으세요. 봉화마다 그 장소의 기억 — 오솔길 리본, 풀잎 풍경, 주전자, 눈 속 종, 종이배, 돌무지 렌즈 — 가 한 줄로 깨어납니다.
정령을 쓰러뜨리고, 그들이 남긴 달빛 불씨와 유물로 무기를 키우세요.
봉화 셋을 밝히면 그 지형의 수호자가 깨어납니다. 수호자를 쓰러뜨려 전리품을 얻고,
현재 기록을 정산해 귀환할지 더 거센 다음 순환으로 들어갈지 직접 고르세요.
두 번째 순환부터 문은 두 갈래로 열립니다. 두 달빛 문이 가는 곳을 알려 주면,
길은 당신이 고릅니다.

새 단장한 화면에서, 다시 그린 영웅·정령·수호자와 달빛 조명 아래의 밤을 만나세요.

■ 조작
우하단 대시 버튼을 제외한 화면 어디든 누르면 이동 스틱이 그 자리에 생깁니다.
공격은 가까운 정령을 향해 자동으로 나갑니다. 위험할 때 우하단 버튼을 눌러
걷던 방향으로 대시하세요.

■ 전투와 성장
정령이 남긴 불씨 열 개를 모으면 6.5초 동안 월광이 각성해 모든 무기가 강해집니다.
처치가 쌓여 레벨이 오르면 유물 셋 중 하나를 고릅니다. 같은 유물을 다시 골라
베기, 월륜, 달빛 고리와 파문을 계속 강화할 수 있습니다.
같은 공격 경로의 서로 다른 효과 두 종류를 모으면 먼저 공명이 열려 대시 뒤 다음
공격 한 번이 달라집니다. 더 투자하면 추적 유성우, 360도 만월참, 대시 경로를 베는
월영무로 진화합니다. 카드와 HUD가 각 경로의 남은 재료를 알려 줍니다.
순환이 쌓일수록 새 스킬 아홉 가지가 열립니다. 수호자와 정령은 느린
탄막을 뿌립니다. 그 사이를 헤치며 나아가세요.
다쳤을 때는 달빛 이슬로 회복하고, 피격으로 튀어나간 코어는 다시 주워 되찾으세요.
일반 이슬은 전장 전체에서 12초에 한 번만 떨어집니다. 하트가 한 칸이고 전장에
이슬이 없을 때 정예를 쓰러뜨리면 구제 이슬 하나가 보장됩니다.

■ 봉화와 수호자
봉화 곁에 1.3초 서서 충전을 마치면 안정 점화와 과충전 중 하나를 고릅니다.
과충전은 봉화 곁에서 6.5초 동안 지형별 습격을 버티는 대신 무기 코어와 추가 불씨를
노립니다. 한 순환의 봉화 셋을 모두 과충전하면 수호자 전리품을 두 단계 받습니다.
앞의 두 봉화는 월광을 채우고 다음 지형으로 가는 달빛 문을 엽니다. 추격대를 뚫고
다음 지형으로 오가세요. 세 번째 봉화는 지형마다 다른 수호자를 부릅니다.
수호자를 쓰러뜨리면 세 공격 경로 중 하나를 강화하고 체력이 한 칸 회복됩니다.
봉화를 켤 때마다 밤은 푸른 새벽과 여명을 지나 낮으로 밝아집니다.

■ 이야기
등불마을은 신호지기를 잃었다. 나리는 돌아오지 못했다. 1·3·6·9순환에 3막과
에필로그가 흐른다. 쫓는 것은 미움이 아니라 길잃음이며, 봉화는 서로를 기억해야
길이 되고, 8순환을 마치면 나리의 신호가 답하고 나리가 돌아온다. 영웅마다 제
목소리로 말하고, 되살린 장소마다 기억 한 줄을 연대기에 남긴다. 이른 귀환은
등불이 기다린 채 남고, 본 줄기는 순환만으로 이어진다.

■ 기록과 다음 판
수호자 뒤마다 점수와 조각을 정산해 귀환하거나 다음 순환을 고릅니다. 8순환 귀환은
정식 승리이며, 원하면 지도 밖 잊힌 길을 찾아 계속할 수 있습니다. 그곳에서는 심층을
세고, 지형마다 징조가 하나씩 걸리며, 수호자는 새로운 변이를 얻습니다.
완료한 순환, 밝힌 봉화, 생존 시간, 레벨과 처치로 점수와 S~D 랭크를 계산합니다.
죽어도 달빛 조각을 얻어 영구 은혜 6종을 올릴 수 있습니다. 달빛 제단에서는 다시
그린 영웅 6명의 고유한 색과 공격 연출을 미리 볼 수 있습니다.
최고 기록과 로컬 상위 10개는 기기에 남습니다.

■ 언어
한국어, 영어, 일본어, 중국어 간체와 번체를 지원합니다. 설정에서 그 자리에서
바꿉니다.

■ 선택형 인앱 구매
스토어 배포본에는 한 번 구매하면 영구히 소유하고 복원할 수 있는 선택형 인앱 구매
7종이 있습니다. 달빛 후원자, 영웅 5명의 개별 해금, 봉화 색상 꾸러미입니다. 유료 영웅은
각자 다른 색·투사체·충돌 연출과 플레이 감각을 주는 균형형 대안입니다. 가격 차이는
캐릭터 디자인과 연출 스타일 차이이며 전투력 등급이 아닙니다. 무료 달빛 파수꾼만으로
모든 지형·수호자·순환을 플레이할 수 있습니다. 봉화 색상은 전투 수치에 영향이 없습니다.
소모성 이어하기 코인은 1개·5개·10개 묶음입니다. 코인 하나를 쓰면 쓰러진 자리에서
점수·레벨·유물을 유지하고 이어가며, 사용한 코인은 복원되지 않습니다. 검증과 consume
처리가 끝나면 같은 묶음을 다시 살 수 있습니다.

기본 플레이와 로컬 상위 10개 기록은 오프라인에서도 동작합니다. 스토어 상품 조회,
구매와 구매 검증에는 인터넷 연결이 필요합니다. 광고와 필수 계정은 없습니다.
```

## English description

```text
Nari, signal keeper of Lantern Hollow, went to mend the beacon road and never came home. Keep the road home lit — and the kettle warm.

Light three beacons a Wave to take back her trail across six places. Each beacon restores its place's memory — ribbons, chimes, kettle, bell, boat, lens — with one line. Grow weapons with embers and relics, wake that Guardian, then cash out or face a fiercer Wave. From Wave 2 each gate is a fork: two gates name their destinations.

Redrawn heroes, spirits, and guardians under moonlit lighting.

■ Controls
Touch anywhere except the bottom-right dash button and a movement stick appears there.
Attacks target nearby spirits automatically. Press Dash to burst where you move.

■ Combat and growth
Collect ten spirit embers to awaken Moonfire for 6.5 seconds and empower every weapon.
Scatter spirits to level up and choose one of three relics. Stack the same relic to grow
slash, arrows, orbiting rings, and ripples.
Two distinct effects on one route unlock Resonance first: your next attack after a dash
changes once. Invest further for homing Starfall, 360-degree Full Moon, or Moon Dance
along your dash. Cards and the HUD show progress.
Nine skills join the level-up cards as the Waves pass. Guardians and spirits fill the air
with slow readable bullets — weave through.
Moon Dew heals; a core knocked loose can be reclaimed. Dew shares a 12-second cooldown;
at one heart, an elite guarantees one rescue Dew when none is on the field.

■ Beacons and the Guardian
Charge a beacon 1.3 seconds, then safe light or Overcharge. Overcharge defends 6.5 seconds
against that region's raid for a weapon core and embers. Overcharge all three for two
Guardian tiers. The first two beacons open Moon Gates; the third summons the Guardian.
Defeat it for one of three routes and one heart. Each Wave starts in a rotated region.

■ Story
Three acts and an epilogue follow Waves 1, 3, 6, 9: the lost, the road that remembers,
and at Wave 8 her signal answers — Nari is home. Each hero speaks in their own voice.
Each restored place speaks one memory for the Chronicle, which gathers every beat,
memory, and ending seen. Early returns keep her lamp waiting; the arc runs on Waves alone.

■ Records and the next run
After each Guardian, cash out or continue. Wave 8 is a formal victory; past the map
the count is Depth, each zone an omen, guardians new mutations.
Completed Waves, lit beacons, survival time, level, and spirits scattered set score and
S–D rank. Every run grants Moon Shards for six permanent boons. Moon Shrine lets you
preview six redrawn heroes with distinct colors and attack effects.
Your personal best and local top 10 stay on the device.

■ Language
Korean, English, Japanese, Simplified Chinese, and Traditional Chinese.
Switch language in Settings without restarting.

■ Optional in-app purchases
Store builds include seven optional, restorable non-consumable purchases: Moonlit
Supporter, five individually unlocked heroes, and Lantern Colors. Paid heroes are
balanced sidegrades with distinct character art, projectile colors, motion, and impact
effects. Price differences reflect visual style, not combat power tiers. The free
Moonlit Warden can play every region, Guardian, and Wave. Lantern Colors is cosmetic.
Three consumable Continue Coin packs grant 1, 5, or 10 coins. Spending one resumes at
the spot where you fell while keeping score, level, and relics. Spent coins are not
restored, and each pack can be purchased again after verification and consumption.

Core play and the local top 10 work offline. Loading store products, purchasing, and
purchase verification require an internet connection. There are no ads or required
accounts.
```

## Japanese description

```text
灯の里の信号守りナリは、灯の道を直しに出て帰らなかった。家への道を灯してほしいという書き置き、やかんは冷まさないでください。

一巡回に三つの烽火を灯して彼女の足跡を取り戻しましょう。烽火ごとにその場所の記憶 — 小道のリボン、草むらの風鈴、やかん、雪の下の鐘、紙の舟、石積みのレンズ — が一言で目覚めます。
精霊を倒し、残された月の火種と遺物で武器を育てましょう。
三つの烽火を灯すと、その地域の守護者が目覚めます。守護者を倒して戦利品を受け取り、
現在の記録を精算して帰還するか、より激しい次の巡回へ進むかを選びましょう。
二巡回目からは門が二つに分かれます。二つの月の門が行き先を示し、進む道は
あなたが選びます。

新しい画面で、描き直した英雄・精霊・守護者と月光に照らされた夜が待っています。

■ 操作
右下のダッシュボタン以外なら、画面のどこに触れてもその場所に移動スティックが
現れます。攻撃は近くの精霊へ自動で放たれます。危険な時は右下のボタンを押し、
移動方向へダッシュしてください。

■ 戦闘と成長
月の火種を10個集めると、6.5秒間「月光覚醒」が発動し、すべての武器が強化されます。
撃破でレベルを上げ、三つの遺物から一つを選択。同じ遺物を重ねれば、斬撃、月輪、
月光の輪と波紋を段階的に強くできます。
同じ攻撃経路で異なる効果を二つ集めると、まず共鳴が開き、ダッシュ後の次の攻撃が
一度だけ変化します。さらに育てると、追尾する流星雨、360度を斬る満月斬り、
ダッシュの軌跡を斬る月影舞へ進化します。
巡回を重ねるほど、新しいスキル九つが開きます。守護者と精霊は遅い弾を放ちます。
その弾幕の間を縫って進みましょう。
傷ついた時は月露で回復し、被弾で落としたコアは時間内に拾い直せます。
通常の月露は戦場全体で12秒のドロップ間隔があります。残り体力が1で、戦場に
月露がない時だけ、精鋭を倒すと救済の月露が一つ確定します。

■ 烽火と守護者
烽火を1.3秒充填したら、安定点火か過充填を選びます。過充填では6.5秒間、地域固有の
襲撃から烽火を守る代わりに、武器コアと追加の火種を狙えます。三つすべてに成功すると
守護者の戦利品が二段階になります。最初の二つは月の門を開き、三つ目は地域ごとに
異なる守護者を呼び出します。守護者を倒すと攻撃経路を一つ強化し、体力を1回復します。
巡回ごとに開始地域と襲撃が変わり、敵はさらに強くなります。烽火を灯すたび、夜は
蒼い夜明けと暁を経て昼へ移り変わります。

■ 物語
灯の里は信号守りを失った。ナリは帰らなかった。第1・3・6・9巡回に三幕と
エピローグが流れる。追うものは憎しみではなく迷いであり、烽火は互いを覚えて
道となり、第8巡回を終えればナリの信号が応えてナリは帰る。英雄はそれぞれの
声で語り、蘇った場所ごとに記憶の一言が年代記に残る。早い帰還はランプを
待たせたまま、本筋は巡回だけで進む。

■ 記録と次の挑戦
守護者を倒すたびに、スコアと欠片を精算して帰還するか、次の巡回へ進むかを選びます。
第8巡回で帰還すると正式勝利となり、その後も望めば地図の外の忘れられた道へ進めます。
そこでは深層を数え、地域ごとに前兆がかかり、守護者は新たな変異を得ます。
巡回数、烽火、生存時間、レベル、撃破数からスコアとS〜Dランクを算出します。
倒れても月光の欠片を獲得し、六つの永続加護を強化できます。月光の祭壇では、
描き直され、色と攻撃演出が異なる六人の英雄を購入前に確認できます。
自己ベストとローカル上位10件は端末に保存されます。

■ 言語
韓国語、英語、日本語、簡体字中国語、繁体字中国語に対応。設定から再起動せずに
切り替えられます。

■ 任意のアプリ内購入
ストア版には、購入を復元できる任意の買い切り型アプリ内購入が7種類あります。
月明かりの支援者、英雄5人の個別解放、烽火カラーパックです。有料英雄は色・弾道・
着弾演出と遊び方が異なる性能均衡型の選択肢です。価格差はキャラクターデザインと
演出スタイルの差であり、強さの段階ではありません。無料の月光の番人だけで全地域、
守護者、巡回を遊べます。烽火の色は戦闘性能を変えません。
消耗型のコンティニューコインは1枚・5枚・10枚の3種類です。1枚使うと、スコア・
レベル・遺物を維持して倒れた場所から再開できます。使用済みコインは復元されず、
検証と消費処理の完了後は同じ商品を再購入できます。

基本プレイとローカル上位10件はオフラインでも動作します。商品の読み込み、購入、
購入確認にはインターネット接続が必要です。広告や必須アカウントはありません。
```

## Simplified Chinese description

```text
灯村的信号守望者娜莉去修灯路，一去就没有回来。请点亮回家的路，别让炉上的水壶凉了。

每轮点亮三座烽火，找回她走过的路。每座烽火唤醒一处地方记忆 — 小径彩带、草丛风铃、水壶、雪下钟、纸船、石堆透镜 — 各留一句话。
击败精灵，用它们留下的月火种与遗物强化武器。
点燃三座烽火会唤醒当前区域的守护者。击败守护者取得战利品后，
选择结算当前记录返回，或前往更激烈的下一轮。从第二轮起，每道门都会分叉：
两扇月之门标出目的地，道路由你选择。

在焕然一新的界面中，与重绘的英雄、精灵、守护者相遇，漫步月光照亮的夜色。

■ 操作
触摸右下角冲刺按钮以外的任意位置，移动摇杆就会出现在那里。
攻击会自动瞄准附近的精灵。遇到危险时点击右下角按钮，向移动方向冲刺。

■ 战斗与成长
收集10个月火种，可让“月光觉醒”持续6.5秒并强化所有武器。
通过击败敌人升级，再从三件遗物中选择一件。重复选择相同遗物，
可以继续强化斩击、月轮、月光环与月光波纹。
在同一攻击路线收集两种不同效果，会先解锁共鸣，使冲刺后的下一次攻击变化一次。
继续投入后，可进化为追踪敌人的流星雨、360度满月斩，或沿冲刺轨迹斩击的月影舞。
随着轮次推进，九种新技能会在升级时出现。守护者与精灵会射出缓慢的子弹，
在弹幕中穿行。
受伤时可用月露恢复生命，被击中后掉落的核心也能在限时内找回。
普通月露在整个战场共享12秒掉落冷却。生命只剩1点且场上没有月露时，
击败精英才会保证掉落1个月露。

■ 烽火与守护者
为烽火充能1.3秒后，可选择稳定点燃或过载。过载需要在烽火旁抵御6.5秒区域袭击，
成功可获得武器核心和额外火种。三座全部过载成功，守护者战利品会提升两级。
前两座开启月之门，第三座召唤区域守护者。击败后可强化一条攻击路线并恢复1点生命。
下一轮的起始区域与袭击会发生变化，敌人也会更加强大。
每点燃一座烽火，世界都会从夜晚经过蓝色黎明与破晓，逐渐亮至白昼。

■ 故事
灯村失去了信号守望者，娜莉没有回来。第1、3、6、9轮展开三幕加尾声：追来的不是恨而是迷路，灯必须记住彼此才成路，第8轮结束时娜莉的信号回应、娜莉回家。每位英雄用自己的声音说话，每处复苏的地方留一句记忆记入编年史。提前返回时灯仍在等待，主线只随轮次推进。

■ 记录与下一局
每次击败守护者后，可结算分数与碎片返回，或继续下一轮。第8轮返回是正式胜利，
也可以继续前往地图之外被遗忘的路。在那里以深度计数，每个区域带有一个预兆，
守护者会获得新的变异。
完成轮数、点燃烽火、存活时间、等级与击败数将决定分数和S至D评级。
每局结束都会获得月光碎片，可升级六种永久祝福。月光祭坛可在购买前预览重绘的
六名英雄，他们拥有不同配色与攻击特效。
个人最佳与本地前10名记录会保存在设备中。

■ 语言
支持韩语、英语、日语、简体中文和繁体中文，可在设置中即时切换，无需重启。

■ 可选内购
商店版本包含7项可选的一次性永久内购，均支持恢复购买：月光支持者、5名英雄的
单独解锁与烽火颜色包。付费英雄是平衡型替代玩法，拥有不同角色美术、弹道颜色、
运动与命中特效。价格差异代表视觉风格，不代表战斗力等级。免费的月光守望者可游玩
全部区域、守护者与轮次。烽火颜色只改变外观。
另有1枚、5枚和10枚三种消耗型继续游戏金币。每次使用一枚，可保留分数、等级与遗物，
从倒下之处继续。已使用的金币不可恢复；完成验证与消耗处理后可再次购买同一商品。

基础玩法与本地前10名记录可离线使用。加载商品、购买与购买验证需要网络连接。
游戏没有广告，也不要求账号。
```

## Traditional Chinese description

```text
燈村的信號守望者娜莉去修燈路，一去就沒有回來。請點亮回家的路，別讓爐上的水壺涼了。

每輪點亮三座烽火，找回她走過的路。每座烽火喚醒一處地方記憶 — 小徑綵帶、草叢風鈴、水壺、雪下鐘、紙船、石堆透鏡 — 各留一句話。
擊敗精靈，用它們留下的月火種與遺物強化武器。
點燃三座烽火會喚醒目前區域的守護者。擊敗守護者取得戰利品後，
選擇結算目前紀錄返回，或前往更激烈的下一輪。從第二輪起，每道門都會分叉：
兩扇月之門標出目的地，道路由你選擇。

在煥然一新的介面中，與重繪的英雄、精靈、守護者相遇，漫步月光照亮的夜色。

■ 操作
觸碰右下角衝刺按鈕以外的任意位置，移動搖桿就會出現在那裡。
攻擊會自動瞄準附近的精靈。遇到危險時點擊右下角按鈕，向移動方向衝刺。

■ 戰鬥與成長
收集10個月火種，可讓「月光覺醒」持續6.5秒並強化所有武器。
透過擊敗敵人升級，再從三件遺物中選擇一件。重複選擇相同遺物，
可以繼續強化斬擊、月輪、月光環與月光波紋。
在同一攻擊路線收集兩種不同效果，會先解鎖共鳴，使衝刺後的下一次攻擊變化一次。
繼續投入後，可進化為追蹤敵人的流星雨、360度滿月斬，或沿衝刺軌跡斬擊的月影舞。
隨著輪次推進，九種新技能會在升級時出現。守護者與精靈會射出緩慢的子彈，
在彈幕中穿行。
受傷時可用月露恢復生命，被擊中後掉落的核心也能在限時內找回。
普通月露在整個戰場共用12秒掉落冷卻。生命只剩1點且場上沒有月露時，
擊敗菁英才會保證掉落1個月露。

■ 烽火與守護者
為烽火充能1.3秒後，可選擇穩定點燃或過載。過載需要在烽火旁抵禦6.5秒區域襲擊，
成功可獲得武器核心和額外火種。三座全部過載成功，守護者戰利品會提升兩階。
前兩座開啟月之門，第三座召喚區域守護者。擊敗後可強化一條攻擊路線並恢復1點生命。
下一輪的起始區域與襲擊會發生變化，敵人也會更加強大。
每點燃一座烽火，世界都會從夜晚經過藍色黎明與破曉，逐漸亮至白晝。

■ 故事
燈村失去了信號守望者，娜莉沒有回來。第1、3、6、9輪展開三幕加尾聲：追來的不是恨而是迷路，燈必須記住彼此才成路，第8輪結束時娜莉的信號回應、娜莉回家。每位英雄用自己的聲音說話，每處復甦的地方留一句記憶記入編年史。提前返回時燈仍在等待，主線只隨輪次推進。

■ 紀錄與下一局
每次擊敗守護者後，可結算分數與碎片返回，或繼續下一輪。第8輪返回是正式勝利，
也可以繼續前往地圖之外被遺忘的路。在那裡以深度計數，每個區域帶有一個預兆，
守護者會獲得新的變異。
完成輪數、點燃烽火、存活時間、等級與擊敗數將決定分數和S至D評級。
每局結束都會獲得月光碎片，可升級六種永久祝福。月光祭壇可在購買前預覽重繪的
六名英雄，他們擁有不同配色與攻擊特效。
個人最佳與本機前10名紀錄會儲存在裝置中。

■ 語言
支援韓語、英語、日語、簡體中文和繁體中文，可在設定中即時切換，無須重新啟動。

■ 可選內購
商店版本包含7項可選的一次性永久內購，皆支援恢復購買：月光贊助者、5名英雄的
單獨解鎖與烽火顏色包。付費英雄是平衡型替代玩法，擁有不同角色美術、彈道顏色、
運動與命中特效。價格差異代表視覺風格，不代表戰鬥力等級。免費的月光守望者可遊玩
全部區域、守護者與輪次。烽火顏色只改變外觀。
另有1枚、5枚和10枚三種消耗型繼續遊戲金幣。每次使用一枚，可保留分數、等級與遺物，
從倒下之處繼續。已使用的金幣不可恢復；完成驗證與消耗處理後可再次購買同一商品。

基礎玩法與本機前10名紀錄可離線使用。載入商品、購買與購買驗證需要網路連線。
遊戲沒有廣告，也不要求帳號。
```

### Last paragraph to swap on the itch.io direct-distribution APK

On itch.io, do not include the `Optional in-app purchases` section (and its
Korean counterpart) and the connection notes below it; replace that slot with
the paragraph below. Do not put this paragraph in Google Play or App Store
descriptions.

```text
itch.io에서 직접 배포하는 APK는 무료이며 광고·결제·계정이 없습니다.
기본 플레이와 로컬 기록은 오프라인에서도 동작합니다.

The APK distributed directly on itch.io is free and has no ads, purchases, or account.
Core play and local records work offline.
```

## Controls (on the page with a picture)

```text
화면을 눌러 이동  ·  우하단 버튼으로 대시  ·  공격은 자동
불씨로 월광 각성  ·  봉화 셋 뒤에는 수호자
Move: touch anywhere   ·   Dash: bottom-right button   ·   Attacks: automatic
```

## Screenshots

Google Play uses six shots per locale and device under
`builds/release/play/{en-US,ko-KR,ja-JP,zh-CN,zh-TW}/`
phone `screenshots` (1920×1080), `seven-inch-tablet` (1920×1080, 16:9),
`ten-inch-tablet` (2560×1440, 16:9). App Store uses six shots per device and
locale under
`builds/release/app-store/{en-US,ko,ja,zh-Hans,zh-Hant}/{iphone-6.5,ipad-13}/`.
For this submit with no physical iPhone proof, `iphone-6.5` is an
**Android-AVD-sourced marketing composite** of Pixel 10 AVD's 2424×1080
Android runtime, aspect preserved, not stretched.
`ipad-13` uses only physical iPad captures. Source, transform, and hashes of
both sets are recorded separately in
`builds/release/app-store/screenshot-provenance.json`.
Do not reuse finished shots that show an old free hero or debug UI.

| File | What |
| --- | --- |
| `01-moonlight-barrage.png` | Homing moonlight-missile barrage unfolding in a cycle-3 camp |
| `02-field-guardian.png` | Daytime field region Guardian and missile fight |
| `03-missile-core-drop.png` | Missile core dropped after a hit, plus reclaim guidance |
| `04-title.png` | Title with a lit beacon |
| `05-moonlit-shrine.png` | Shrine showing six heroes and permanent boons together |
| `06-hero-preview.png` | Paid-hero full body and dedicated presentation before select/purchase |

App Store IAP review screenshots for the 10 sale products use 10 shots under
`builds/release/app-store/iap-review/` that 1:1 match product IDs.
Each image is the real shop UI scrolled to that card; legacy `hero_bundle` is
excluded from new review images and the manifest.

The cover image is `builds/release/cover-630x500.jpg`.

:::tip To remake
Start the Pixel 10 AVD, then `pnpm store:capture-screenshots` actually
switches the five languages on the settings screen and captures title,
shrine, hero detail, late barrage, hit core, and Guardian in order. After
preparing physical iPad 5-locale proofs, run
`pnpm store:screenshots:app-store:android-pixel-avd` and
`pnpm check:store-screenshots:app-store`. Use default
`pnpm store:screenshots:app-store` only when both physical iPhone and iPad
are used.
:::

## Credits (page footer)

```text
Engine         Godot Engine 4.7.1 — MIT License
Art and UI     Moonlit Beacon — Original assets
Music, sound   Ninja Adventure Asset Pack — Pixel-Boy and AAA — CC0
                Kenney UI Audio — Kenney — CC0
Font           Maplestory — ⓒ NEXON Korea; Noto Sans CJK SC — Google — SIL Open Font License 1.1
Store SDK      godot-iap 3.6.1 — OpenIAP contributors — MIT License
Made by        Hyo Dev

Source and course: https://github.com/hyodotdev/MoonlitBeacon
```

## Google Play release notes — English (`en-US`)

```text
Moonlit Beacon 3.0.0

- Follow Nari's signal home: keep the road home lit, kettle warm.
- Six places, forked gates from Wave 2, each beacon one memory.
- Three acts, an epilogue, and a Chronicle of all seen.
- Redrawn heroes, spirits, guardians under moonlight.
- Nine skills as the Waves pass; weave slow readable bullets.
```

## Google Play release notes — Korean (`ko-KR`)

```text
달빛 봉화 3.0.0

- 나리의 신호를 따라 집으로: 길을 밝히고 주전자를 지키세요.
- 여섯 지형, 2순환부터 갈래 문, 봉화마다 기억 하나.
- 3막과 에필로그, 본 것을 모으는 연대기.
- 다시 그린 영웅·정령·수호자와 달빛 조명.
- 순환마다 스킬 아홉 가지, 느린 탄막을 헤치세요.
```

## Google Play release notes — Japanese (`ja-JP`)

```text
月明かりの烽火 3.0.0

- ナリの信号を追って家へ: 道を灯し、やかんを守ろう。
- 六地域、二巡回目から分岐の門、烽火ごとに記憶一つ。
- 三幕とエピローグ、見たものを集める年代記。
- 描き直した英雄・精霊・守護者と月光。
- 巡回ごとにスキル九つ、遅い弾幕を縫おう。
```

## Google Play release notes — Simplified Chinese (`zh-CN`)

```text
月光烽火 3.0.0

- 跟着娜莉的信号回家：点亮归路，别让水壶凉了。
- 六片区域，第2轮起分叉门，每座烽火一处记忆。
- 三幕加尾声，配上收集所见的编年史。
- 重绘的英雄、精灵与守护者，月光下的夜。
- 随轮次解锁九种技能，在缓慢弹幕中穿行。
```

## Google Play release notes — Traditional Chinese (`zh-TW`)

```text
月光烽火 3.0.0

- 跟著娜莉的信號回家：點亮歸路，別讓水壺涼了。
- 六片區域，第2輪起分叉門，每座烽火一處記憶。
- 三幕加尾聲，配上收集所見的編年史。
- 重繪的英雄、精靈與守護者，月光下的夜。
- 隨輪次解鎖九種技能，在緩慢彈幕中穿行。
```

## App Store What's New — English (`en-US`)

```text
Moonlit Beacon 3.0.0

- Follow Nari's signal home: keep the road home lit, kettle warm.
- Six places, forked gates from Wave 2, each beacon one memory.
- Three acts, an epilogue, and a Chronicle of all seen.
- Redrawn heroes, spirits, guardians under moonlight.
- Nine skills as the Waves pass; weave slow readable bullets.
```

## App Store What's New — Korean (`ko`)

```text
달빛 봉화 3.0.0

- 나리의 신호를 따라 집으로: 길을 밝히고 주전자를 지키세요.
- 여섯 지형, 2순환부터 갈래 문, 봉화마다 기억 하나.
- 3막과 에필로그, 본 것을 모으는 연대기.
- 다시 그린 영웅·정령·수호자와 달빛 조명.
- 순환마다 스킬 아홉 가지, 느린 탄막을 헤치세요.
```

## App Store What's New — Japanese (`ja`)

```text
月明かりの烽火 3.0.0

- ナリの信号を追って家へ: 道を灯し、やかんを守ろう。
- 六地域、二巡回目から分岐の門、烽火ごとに記憶一つ。
- 三幕とエピローグ、見たものを集める年代記。
- 描き直した英雄・精霊・守護者と月光。
- 巡回ごとにスキル九つ、遅い弾幕を縫おう。
```

## App Store What's New — Simplified Chinese (`zh-Hans`)

```text
月光烽火 3.0.0

- 跟着娜莉的信号回家：点亮归路，别让水壶凉了。
- 六片区域，第2轮起分叉门，每座烽火一处记忆。
- 三幕加尾声，配上收集所见的编年史。
- 重绘的英雄、精灵与守护者，月光下的夜。
- 随轮次解锁九种技能，在缓慢弹幕中穿行。
```

## App Store What's New — Traditional Chinese (`zh-Hant`)

```text
月光烽火 3.0.0

- 跟著娜莉的信號回家：點亮歸路，別讓水壺涼了。
- 六片區域，第2輪起分叉門，每座烽火一處記憶。
- 三幕加尾聲，配上收集所見的編年史。
- 重繪的英雄、精靈與守護者，月光下的夜。
- 隨輪次解鎖九種技能，在緩慢彈幕中穿行。
```

## Bug reports

```text
버그를 찾으셨으면 GitHub Issues 로 알려 주세요.
https://github.com/hyodotdev/MoonlitBeacon/issues

기기 이름과 안드로이드 버전을 함께 적어 주시면 도움이 됩니다.
```

## Install notes (download description)


```text
itch.io 에서 받은 APK 는 플레이스토어를 거치지 않으므로
"출처를 알 수 없는 앱" 설치를 한 번 허용해야 합니다.

설정 ▸ 앱 ▸ 특별한 접근 권한 ▸ 알 수 없는 앱 설치
→ 파일 관리자(또는 브라우저)에 허용
```
