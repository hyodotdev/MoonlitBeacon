# Privacy change draft for 4.0.0 (accounts, saves, Hall)

Status: **draft for review only**. Nothing here is published. The public
privacy site lives outside this repo; this draft proposes the text delta
its owner reviews before any website edit. Every statement cites
production source below. Anything without a citation is listed under
`Release audit items`, never promised.

The current site describes a launch build with no accounts and a disabled
ladder. All eight items below replace that account-free framing. The
player-facing translations avoid developer terms; the source-citation
table stays as internal review support.

## Shared statement inventory (English master)

- **S1 — Sign-in.** Entry offers a guest door plus Google and Apple
  sign-in where the build genuinely configures them. Guest entry creates
  an anonymous auth identity where the device supports it. Google and
  Apple are separate provider identities; the Play Games gaming profile
  is a distinct Android-only option and is not offered in this build.
- **S2 — What sign-in processing covers.** Firebase and the Google or
  Apple provider you choose process identifiers, sign-in and session
  credentials, and the profile fields your consent and provider
  settings make available, to authenticate and recover the account.
  The game keeps its own records: your public player ID, the private
  link between your signed-in account and that ID, and your checkpoint
  saves. Only the game's on-device account list stores the server
  account reference in hashed form; account and save records held by
  the backend carry the raw account reference and stay private to your
  account. Sign-in tokens live in memory while the game reaches your
  own records; the game does not write them into its save files, and
  they are never placed in public ranking. Email and profile
  information is not shown in public Hall rows. Provider profile
  handling, retention, and SDK-side storage follow the provider's own
  behavior and remain audit items.
- **S3 — Player ID.** Each install mints a durable public player ID of
  the form `MB-` plus 32 hex characters before first play. It names
  the saved gate and the Hall rows, and it survives linking:
  connecting Google to the original guest keeps the same ID and the
  same checkpoint ownership. Signing out starts a fresh guest ID on
  the device while the previous ID and its saves stay kept; signing
  back in with the same provider returns to that account's ID and
  kept saves. One install can therefore hold more than one ID over
  time.
- **S4 — Cloud saves.** A signed-in account owns one private versioned
  save holding its progress (cycle, hero, relics, growth, scores).
  Saves land on the device first; uploads follow in the background.
  Saves never carry purchase or balance records. Downloads are fully
  checked before install, and a differing cloud copy waits for you to
  choose which side to keep.
- **S5 — Hall board.** The Hall keeps one best entry per player ID:
  player ID, hero, score, progress, app version, and update time.
  Board reads are public; only the owning account may write its entry,
  scores only increase, and standing is derived from scores so equal
  scores share one rank. No name, email, account reference, token, or
  save appears in a Hall entry.
- **S6 — Deletion and re-confirmation.** Deleting a cloud account first
  removes its Hall entry, cloud save, reservation, and profile together
  in one verified step; only after that confirmation is the sign-in
  itself deleted. On iOS, Apple-account deletion is designed to
  re-confirm through the Apple sign-in sheet for a fresh revocation
  code; device proof of that branch is still pending. Signing out only
  switches to a fresh guest ID; nothing is deleted by signing out.
- **S7 — Guest and offline notes.** Guest play works offline as a
  device-only guest and is never shown as a registered cloud account.
  If background sign-up fails, or the build has no sign-in setup, play
  continues anyway. Builds without sign-in setup make no registration
  attempt and show no error.
- **S8 — Analytics off unless enabled, purchases unchanged.** Optional
  gameplay analytics stays off unless two switches agree: the shipped
  build's export configuration and your explicit Settings consent,
  which defaults to off. The final export configuration is inspected
  before release; this draft does not declare it from defaults alone.
  Purchase verification is unchanged from 3.0.0: store receipts verify
  through the existing verification service, and keys, signatures, and
  purchase tokens are kept out of logs and error messages.

## Korean draft (`ko`)

```text
4.0.0 개인정보 변경 안내(초안)

1. 로그인: 게스트 입장에 더해, 준비된 빌드에서는 Google·Apple
로그인을 제공합니다. 게스트 입장은 기기가 지원하면 익명 인증
신원을 만듭니다. Google과 Apple은 별개의 제공자 신원이며, Play
게임 프로필은 별도의 Android 전용 선택지로 이번 빌드에서
제공하지 않습니다.
2. 로그인이 처리하는 범위: Firebase와 선택한 Google·Apple
제공자는 계정 인증과 복구를 위해 식별자, 로그인·세션 자격,
동의·제공자 설정에 따라 제공되는 프로필 정보를 처리합니다.
게임은 공개 플레이어 ID, 로그인 계정과 ID의 비공개 연결,
체크포인트 저장을 따로 보관합니다. 서버 계정 참조를 해시
형태로 두는 것은 기기 안의 게임 계정 목록뿐이며, 백엔드의
계정·저장 기록은 원본 참조를 담고 계정에 비공개로 남습니다.
로그인 토큰은 내 기록에 닿는 동안 메모리에만 머물고 게임 저장
파일에 쓰지 않으며, 공개 순위에는 오르지 않습니다. 이메일과
프로필 정보는 공개 전당 기록에 표시되지 않습니다. 제공자의
프로필 처리·보관·SDK 저장은 제공자 동작을 따르며 감사 항목으로
남습니다.
3. 플레이어 ID: 첫 플레이 전에 `MB-` + 16진수 32자의 내구성
공개 ID를 발급합니다. 저장된 관문과 전당 기록의 이름이 되며,
연결해도 유지됩니다. 기존 게스트에 Google을 연결하면 같은 ID와
같은 체크포인트 소유권이 그대로 이어집니다. 로그아웃하면 기기에
새 게스트 ID가 시작되고 이전 ID와 저장은 보관되며, 같은 제공자로
다시 로그인하면 그 계정의 ID와 보관된 저장으로 돌아갑니다.
따라서 한 기기에는 시간이 지나며 둘 이상의 ID가 남을 수 있습니다.
4. 클라우드 저장: 로그인한 계정은 진행 상황(순환, 영웅, 유물,
성장, 점수)을 담은 비공개 버전 저장 하나를 가집니다. 저장은
기기에 먼저 되고 업로드는 뒤따릅니다. 저장에 구매·잔액 기록은
들어가지 않습니다. 다운로드는 완전히 검사한 뒤 설치되고, 다른
클라우드 사본은 어느 쪽을 쓸지 선택을 기다립니다.
5. 전당: 전당은 플레이어 ID마다 최고 기록 하나(플레이어 ID,
영웅, 점수, 진행도, 앱 버전, 갱신 시각)를 보관합니다. 읽기는
공개이며 쓰기는 소유 계정만 가능하고, 점수는 올라가기만 하며
순위는 점수에서 계산되어 동점은 같은 순위를 공유합니다. 전당
기록에 이름, 이메일, 계정 참조, 토큰, 저장은 들어가지 않습니다.
6. 삭제와 재확인: 클라우드 계정 삭제는 전당 기록, 클라우드 저장,
예약, 프로필을 하나의 검증된 단계로 먼저 함께 지우고, 그 확인
뒤에 로그인 자체를 삭제합니다. iOS에서 Apple 계정 삭제는 Apple
로그인 화면으로 다시 확인해 새 해지 코드를 받도록 설계되어
있으며, 해당 분기의 기기 증거는 아직 없습니다. 로그아웃은 새
게스트 ID로 바뀌기만 하며 아무것도 삭제하지 않습니다.
7. 게스트·오프라인 안내: 게스트 플레이는 기기 전용 게스트로
오프라인에서도 되며 클라우드 등록 계정으로 표시되지 않습니다.
백그라운드 가입이 실패하거나 로그인 설정이 없는 빌드에서도
플레이는 계속됩니다. 로그인 설정이 없는 빌드는 등록을 시도하지
않고 오류도 내지 않습니다.
8. 분석은 켜야 동작, 구매 검증 유지: 선택형 게임플레이 분석은
출시 빌드의 내보내기 설정과 기본 꺼짐인 설정 명시 동의가 모두
맞아야 동작하며, 그 전까지는 꺼져 있습니다. 최종 내보내기
설정은 출시 전에 직접 확인하며, 기본값만으로 단정하지 않습니다.
구매 검증 처리는 3.0.0과 동일하며, 키·서명·구매 토큰은 로그나
오류 메시지에 남지 않습니다.
```

## English draft (`en-US`)

```text
4.0.0 privacy changes (draft)

1. Sign-in: entry offers a guest door plus Google and Apple sign-in
where the build configures them. Guest entry creates an anonymous
auth identity where the device supports it. Google and Apple are
separate provider identities; the Play Games gaming profile is a
distinct Android-only option and is not offered in this build.
2. What sign-in processing covers: Firebase and the Google or Apple
provider you choose process identifiers, sign-in and session
credentials, and the profile fields your consent and provider
settings make available, to authenticate and recover the account.
The game keeps its own records: your public player ID, the private
link between your signed-in account and that ID, and your checkpoint
saves. Only the game's on-device account list stores the server
account reference in hashed form; account and save records held by
the backend carry the raw account reference and stay private to your
account. Sign-in tokens live in memory while the game reaches your
own records; the game does not write them into its save files, and
they are never placed in public ranking. Email and profile
information is not shown in public Hall rows. Provider profile
handling, retention, and SDK-side storage follow the provider's own
behavior and remain audit items.
3. Player ID: each install mints a durable public player ID of the
form `MB-` plus 32 hex characters before first play. It names the
saved gate and the Hall rows, and it survives linking: connecting
Google to the original guest keeps the same ID and the same
checkpoint ownership. Signing out starts a fresh guest ID on the
device while the previous ID and its saves stay kept; signing back
in with the same provider returns to that account's ID and kept
saves. One install can therefore hold more than one ID over time.
4. Cloud saves: a signed-in account owns one private versioned save
holding its progress (cycle, hero, relics, growth, scores). Saves
land on the device first; uploads follow in the background. Saves
never carry purchase or balance records. Downloads are fully checked
before install, and a differing cloud copy waits for you to choose
which side to keep.
5. Hall board: the Hall keeps one best entry per player ID (player
ID, hero, score, progress, app version, update time). Reads are
public; only the owning account may write its entry, scores only
increase, and standing derives from scores so equal scores share one
rank. No name, email, account reference, token, or save appears in a
Hall entry.
6. Deletion and re-confirmation: deleting a cloud account first
removes its Hall entry, cloud save, reservation, and profile together
in one verified step; only after that confirmation is the sign-in
itself deleted. On iOS, Apple-account deletion is designed to
re-confirm through the Apple sign-in sheet for a fresh revocation
code; device proof of that branch is still pending. Signing out only
switches to a fresh guest ID; nothing is deleted by signing out.
7. Guest and offline notes: guest play works offline as a
device-only guest and is never shown as a registered cloud account.
If background sign-up fails, or the build has no sign-in setup, play
continues anyway. Builds without sign-in setup make no registration
attempt and show no error.
8. Analytics off unless enabled, purchases unchanged: optional
gameplay analytics stays off unless two switches agree — the shipped
build's export configuration and your explicit Settings consent,
which defaults to off. The final export configuration is inspected
before release; this draft does not declare it from defaults alone.
Purchase verification is unchanged from 3.0.0: store receipts verify
through the existing verification service, and keys, signatures, and
purchase tokens are kept out of logs and error messages.
```

## Japanese draft (`ja`)

```text
4.0.0 プライバシー変更(草案)

1. ログイン: ゲスト入場に加え、設定済みのビルドではGoogle・
Appleログインを提供します。ゲスト入場は対応端末では匿名の
認証IDを作ります。GoogleとAppleは別の認証IDで、Playゲーム
プロフィールは別のAndroid専用選択肢として今回のビルドでは
提供しません。
2. ログイン処理の範囲: Firebaseと選んだGoogle・Apple提供者は、
認証と回復のため識別子、ログイン・セッション資格、同意と提供
者設定で開かれたプロフィール情報を処理します。ゲームは公開
プレイヤーID、ログイン済みアカウントとIDの非公開の紐付け、
チェックポイント保存を別に保ちます。サーバー側のアカウント
参照をハッシュで置くのは端末内のゲームのアカウント一覧だけ
で、サーバー側の記録は原文の参照を持ち自分のアカウントに非
公開のままです。ログイントークンは自分の記録に届く間だけ
メモリに置き、ゲームの保存ファイルには書かず、公開順位にも
載せません。メールと
プロフィール情報は公開の殿堂記録に表示しません。提供者の
取扱い・保持・SDK側の保存は提供者自身の動作に従い、監査項目
として残します。
3. プレイヤーID: 初回プレイ前に`MB-`+16進32文字の恒久的な
公開IDを発行します。保存した関門と殿堂の記録の名になり、
連携しても維持されます。元のゲストにGoogleを連携しても同じ
IDと同じチェックポイントの所有権が引き継がれます。ログアウト
すると端末に新しいゲストIDが始まり以前のIDと保存は保管され、
同じ提供者で入り直すとそのアカウントのIDと保管された保存に
戻ります。そのため一つの導入に複数のIDが残ることがあります。
4. クラウド保存: ログイン済みアカウントは進行状況(巡回、英雄、
遺物、成長、スコア)を持つ非公開の版付き保存を一つ持ちます。
保存は端末が先で、送信は後から追います。保存に購入・残高の
記録は入りません。受信は十分に検査してから入り、異なる
クラウド写しはどちらを残すか選択を待ちます。
5. 殿堂: 殿堂はプレイヤーIDごとに最良記録一つ(プレイヤーID、
英雄、スコア、進行度、アプリ版、更新時刻)を保ちます。読み
取りは公開で、書き込みは所有アカウントのみ、スコアは上がる
一方で、順位はスコアから求めるため同点は同順位になります。
殿堂の記録に名前、メール、アカウント参照、トークン、保存は
入りません。
6. 削除と再確認: クラウドアカウントの削除は殿堂記録、クラウド
保存、予約、プロフィールを一つの検証済み手順で先にまとめて
消し、その確認後にログイン自体を消します。iOSのApple
アカウント削除はAppleログイン画面で再確認して新しい取消
コードを受ける設計で、その分岐の端末証拠はまだありません。
ログアウトは新しいゲストIDへの切替えだけで、何も消しません。
7. ゲスト・オフラインの注意: ゲストプレイは端末専用ゲスト
としてオフラインでも動き、クラウド登録済みとして表示され
ません。裏側の加入に失敗しても、ログイン設定のないビルド
でも、プレイは続きます。ログイン設定のないビルドは登録を
試みず、誤りも出しません。
8. 分析は有効化まで停止、購入確認は維持: 任意のゲームプレイ
分析は、出荷ビルドの書出し設定と初期停止の設定明示同意の
両方がそろわない限り停止のままです。最終の書出し設定は
発売前に直接確かめ、初期値だけで断定しません。購入確認の
処理は3.0.0と同じで、鍵・署名・購入トークンはログや誤り
表示に残しません。
```

## Simplified Chinese draft (`zh-Hans`)

```text
4.0.0 隐私变更(草案)

1. 登录:游客入口之外，已配置的版本提供 Google/Apple 登录。
游客入口在受支持设备上创建匿名认证身份。Google 与 Apple
是不同的认证身份；Play 游戏资料是另一个仅限 Android 的
选项，本版本不提供。
2. 登录处理的范围:为完成认证与找回，Firebase 与所选 Google/
Apple 提供方会处理标识符、登录与会话凭证，以及按同意和
提供方设置开放的资料字段。游戏另存自己的记录：公开玩家 ID、
登录账号与该 ID 的非公开关联、检查点存档。只有设备上游戏
自带的账号列表以哈希形式存放服务端账号引用；后端保存的
账号与存档记录携带原始引用，仅对本账号保密。登录令牌只在
访问本人记录期间留在内存中，游戏不将其写入存档文件，也
绝不放入公开排行。邮箱与资料信息不在公开殿堂记录中显示。
提供方的资料处理、留存与 SDK 侧存储遵循提供方自身行为，
列为待审计项。
3. 玩家 ID:首次游玩前签发 `MB-` 加 32 位十六进制字符的持久
公开 ID，作为已保存月之门与殿堂记录的名称。关联后保持不变：
原游客关联 Google 后，同一 ID 与同一检查点归属继续有效。
退出登录会在设备上启用全新游客 ID，原 ID 与存档继续保留；
用同一提供方重新登录则回到该账号的 ID 与保留的存档。因此
一次安装随时间可能留下多个 ID。
4. 云存档:已登录账号拥有一个带版本号的非公开存档，保存其
进度(轮次、英雄、遗物、成长、分数)。先落盘再后台上传。
存档不含购买或余额记录。下载须通过完整检查才会安装；不
一致的云端副本等待玩家选择保留哪一侧。
5. 殿堂榜:殿堂按玩家 ID 保存一条最佳记录(玩家 ID、英雄、
分数、进度、应用版本、更新时间)。读取公开，仅归属账号
可写，分数只增不减，名次由分数推导，同分同名次。殿堂记录
不含姓名、邮箱、账号引用、令牌或存档。
6. 删除与重新确认:删除云账号先以一次已验证的步骤同时清除
殿堂记录、云存档、预留与资料；确认后再删除登录本身。
iOS 上 Apple 账号删除按设计会重开 Apple 登录页重新确认
以获取新的撤销码，该分支尚无设备证据。退出登录只是切换
到全新游客 ID，不删除任何内容。
7. 游客与离线说明:游客可离线以纯本机游客游玩，不会显示为
已注册云账号。后台注册失败或版本未配置登录，游玩都会继续。
未配置登录的版本不尝试注册，也不报错。
8. 分析默认关闭、购买验证不变:可选的玩法分析须同时满足出
货版本的导出配置与默认关闭的设置明示同意才会启用，否则
保持关闭。最终导出配置在发布前实地检查，不只凭默认值断言。
购买验证处理与 3.0.0 一致，密钥、签名与购买令牌不出现在
日志或错误信息中。
```

## Traditional Chinese draft (`zh-Hant`)

```text
4.0.0 隱私變更(草案)

1. 登入:訪客入口之外，已設定的版本提供 Google/Apple 登入。
訪客入口在受支援裝置上建立匿名認證身分。Google 與 Apple
是不同的認證身分；Play 遊戲資料是另一個僅限 Android 的
選項，本版本不提供。
2. 登入處理的範圍:為完成認證與找回，Firebase 與所選 Google/
Apple 提供方會處理識別碼、登入與工作階段憑證，以及按同意
和提供方設定開放的資料欄位。遊戲另存自己的紀錄：公開玩家
ID、登入帳號與該 ID 的非公開關聯、檢查點存檔。只有裝置上
遊戲自帶的帳號清單以雜湊形式存放伺服器端帳號參照；後端
保存的帳號與存檔紀錄攜帶原始參照，僅對本帳號保密。登入
權杖只在存取本人紀錄期間留在記憶體中，遊戲不將其寫入存檔
檔案，也絕不放入公開排行。信箱與資料資訊不在公開殿堂紀錄
中顯示。提供方的資料處理、留存與 SDK 側儲存遵循提供方自身
行為，列為待稽核項。
3. 玩家 ID:首次遊玩前簽發 `MB-` 加 32 位十六進制字元的持久
公開 ID，作為已儲存月之門與殿堂紀錄的名稱。關聯後保持不變：
原訪客關聯 Google 後，同一 ID 與同一檢查點歸屬繼續有效。
登出會在裝置上啟用全新訪客 ID，原 ID 與存檔繼續保留；用
同一提供方重新登入則回到該帳號的 ID 與保留的存檔。因此
一次安裝隨時間可能留下多個 ID。
4. 雲存檔:已登入帳號擁有一個帶版本號的非公開存檔，保存其
進度(輪次、英雄、遺物、成長、分數)。先落盤再後台上傳。
存檔不含購買或餘額紀錄。下載須通過完整檢查才會安裝；不
一致的雲端副本等待玩家選擇保留哪一側。
5. 殿堂榜:殿堂按玩家 ID 保存一條最佳紀錄(玩家 ID、英雄、
分數、進度、應用版本、更新時間)。讀取公開，僅歸屬帳號
可寫，分數只增不減，名次由分數推導，同分同名次。殿堂紀錄
不含姓名、信箱、帳號參照、權杖或存檔。
6. 刪除與重新確認:刪除雲帳號先以一次已驗證的步驟同時
清除殿堂紀錄、雲存檔、預留與資料；確認後再刪除登入本身。
iOS 上 Apple 帳號刪除按設計會重開 Apple 登入頁重新確認以
取得新的撤銷碼，該分支尚無裝置證據。登出只是切換到全新
訪客 ID，不刪除任何內容。
7. 訪客與離線說明:訪客可離線以純本機訪客遊玩，不會顯示為
已註冊雲帳號。後台註冊失敗或版本未配置登入，遊玩都會繼續。
未配置登入的版本不嘗試註冊，也不報錯。
8. 分析預設關閉、購買驗證不變:可選的玩法分析須同時滿足出
貨版本的匯出配置與預設關閉的設定明示同意才會啟用，否則
保持關閉。最終匯出配置在發布前實地檢查，不只憑預設值斷言。
購買驗證處理與 3.0.0 一致，金鑰、簽章與購買權杖不出現在
紀錄或錯誤訊息中。
```

## Source citations (statement → production source)

| Statement | Production source |
| --- | --- |
| S1 guest door + configured providers | `apps/game/scripts/net/production_host.gd` `begin_guest()`, `providers_for_entry()`; `apps/game/addons/moonlit-identity/moonlit_identity.gd` `get_capabilities()`, `_ready_providers()` |
| S1 anonymous auth identity | `apps/game/addons/moonlit-identity/android/src/main/kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt` (`signInAnonymously`); `apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm` (`signInAnonymouslyWithCompletion`) |
| S1 Google/Apple separate, Play Games distinct + unoffered | `apps/game/scripts/net/identity_adapter.gd` header (`google` = `google.com`, `apple` = `apple.com`, `play_games` = `playgames.google.com`, never merged); `moonlit_identity.gd` `_ready_providers()` (Play Games listed only with staged `play_app_id`; this build stages none) |
| S2 sign-in/session credentials leave the native calls | `apps/game/scripts/net/native_identity_adapter.gd` `_emit_token_session()` (token answers ride `session_changed`); `apps/game/scripts/net/player_account.gd` `_on_session_changed()` re-emits once via `id_token_ready`; `apps/game/scripts/net/production_host.gd` header (tokens in memory only, never logged, saved, or in state dicts); `apps/game/scripts/cloud/cloud_transport.gd` (Bearer header from the in-memory supplier, held only for the request) |
| S2 game does not write tokens to its saves | `player_account.gd` `_on_session_changed()` comment ("never written anywhere by this service"); `cloud_transport.gd` header (token never written to a result Dictionary) |
| S2 hashed reference only in the on-device list | `apps/game/scripts/net/player_account.gd` `uid_binding_hash()` + bindings header (only the hash is ever written; raw UID stays in memory) |
| S2 raw reference in private backend records | `apps/game/scripts/cloud/cloud_schema.gd` (`PROFILE_FIELDS`, `RESERVATION_FIELDS`, `CHECKPOINT_FIELDS` all contain raw `uid`); `cloud_identity.gd` `profile_body()`/`reservation_body()` and `cloud_checkpoint.gd` `checkpoint_body()` (raw uid encoded into owner-private documents); `firestore.cloud.addition.rules` (profile/checkpoint/reservation reads restricted to the owning signed-in account, list denied) |
| S2 provider profile scope behavior | `MoonlitIdentityPlugin.kt` header + `MoonlitIdentityIos.mm` header (Google SDK authenticates under its own default account scopes `openid/email/profile`; game code adds no scopes and never reads/stores/logs profile fields itself); Apple: game code requests no personal scopes (`requestedScopes = @[]` on iOS, no custom scopes on Android) while provider-default scope behavior follows provider documentation — audit item 1 |
| S2 no email/profile in public Hall rows | `firestore.cloud.addition.rules` (`mb_hall_v1` key list forbids email/UID/credential); `cloud_hall.gd` `hall_body()` (entry carries only ID, hero, score, progress, app version, stamp) |
| S3 durable `MB-` ID; linking keeps ID + ownership | `apps/game/scripts/net/player_account.gd` (`PUBLIC_ID_PREFIX`, `PUBLIC_ID_PATTERN`, `ensure_public_id()`, `generate_public_id()`); `apps/game/scripts/cloud/cloud_identity.gd` header + `fetch_canonical_id()` (linking keeps UID, same ID returns, no new registration) |
| S3 fresh guest on sign-out; sign back in restores | `production_host.gd` `sign_out()` + `player_account.gd` `rotate_to_fresh_guest()` (old ID, binding, save stay on disk); `player_account.gd` `adopt_canonical_id()` + `Journey.use_account()` (returning account re-adopts its ID and save slot) |
| S4 one private versioned save per account | `apps/game/scripts/cloud/cloud_checkpoint.gd` header (`mb_checkpoints_v1/{uid}`, revision + bounded progress record, compare-and-swap); `apps/game/scripts/cloud/cloud_schema.gd` (`CHECKPOINT_FIELDS`, `MAX_CHECKPOINT_BYTES`) |
| S4 local-first, checked download, explicit choice | `apps/game/scripts/cloud/cloud_coordinator.gd` header + `restore_from_cloud()` + `resolve_conflict()`; `apps/game/scripts/gameplay/journey.gd` (`Journey.validate()`) |
| S4 no purchase data in saves | `apps/game/scripts/cloud/cloud_schema.gd` `checkpoint_has_forbidden_ledger_keys()`; `cloud_checkpoint.gd` (`ledger-keys-rejected`) |
| S5 one public entry per player ID | `apps/game/scripts/cloud/cloud_hall.gd` header + `hall_body()`; `apps/game/scripts/cloud/cloud_schema.gd` (`HALL_FIELDS`, `HERO_PATHS`, `MAX_SCORE`, `MAX_CYCLES`) |
| S5 reads open, writes owned, monotonic, derived rank | `firestore.cloud.addition.rules` (`mb_hall_v1`: `allow get, list: if true`, ownership pair + `score >=` guard); `cloud_hall.gd` (`not-best`, `fetch_rank()` count + 1, ties share) |
| S6 verified cloud-first deletion order | `apps/game/scripts/cloud/cloud_account.gd` (`deletion_plan()`: hall, checkpoint, reservation, profile; native deletes the sign-in only after acknowledgement) |
| S6 iOS Apple re-confirmation is designed, proof pending | `apps/game/scripts/net/player_account.gd` `delete_account()` (`keep_provider_grant`, native re-runs Apple sheet for fresh revocation code) — intended behavior from code; iPad delete/re-confirm proof is audit item 5 |
| S6 sign-out deletes nothing | `production_host.gd` `sign_out()` (switches to a fresh guest; deletes nothing) |
| S7 guest offline, play continues without setup | `production_host.gd` `begin_guest()` (`local_only` escape, no attempt when unconfigured); `apps/docs/docs/game.md` § "The moon gate" (guest labeled device-only, never as registered cloud account) |
| S8 analytics needs export config + consent | `apps/game/scripts/net/firebase_config.gd` (`analytics_enabled` defaults false; `configured_for_analytics()` needs enabled + hardened + key); `apps/game/scripts/analytics/analytics.gd` (`enabled()` needs consent + config); final export configuration inspected before release — audit item 4 |
| S8 purchase verification unchanged | `apps/game/scripts/iap/iapkit_http_transport.gd` header (only the public purchase-verification API; key/JWS/token never in errors or logs); `apps/game/scripts/iap/iap_store.gd` (verify → grant → finish; IAPKit replay guard) |

## Release audit items (missing information, not promises)

1. Provider SDK profile processing, logs, and session persistence:
   game code adds no Google scopes beyond the SDK defaults and
   requests no Apple personal scopes itself, but what the provider
   sheets and SDKs process, log, or persist — including observed
   FirebaseAuth listener logs carrying the UID, and the
   provider-documented default Apple name/email scope behavior — must
   be verified against current provider documentation during the
   store privacy review, not inferred from the adapter.
2. Retention deadlines: source states no cloud retention deadline for
   profiles, reservations, checkpoints, or Hall rows. Do not invent
   one; the site owner sets and publishes it. The 90-day TTL in the
   store-page checklist applies only to optional analytics events and
   is never a mandatory TTL on persistent account checkpoints, saves,
   or Hall rows.
3. Remote ruleset readback: the director already holds owned-cloud
   deployment and native server ownership proof. An independent
   current-ruleset readback before submit remains appropriate to
   confirm the deployed account/save/Hall rules match the repo
   addition (`firestore.cloud.addition.rules` via
   `tests/cloud-rules/`); the store-page checklist item stays
   unchecked until then.
4. Final export configuration: analytics-related answers must be
   confirmed against the inspected final export config, not from
   code defaults alone. Operator and legal details (seller identity,
   DSA status, per-country notices, site support contacts) stay with
   the actual selling party. Public contact values already sourced in
   the repo are unchanged by this draft.
5. Pending evidence that can still move copy: Apple Services ID/key
   setup, iPad authentication tests including delete/re-confirm
   proof, actual store purchases on the final build, and the 4.0.0
   store upload itself. See `four-zero-copy-review.md`.
