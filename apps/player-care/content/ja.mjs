// Japanese player-care copy. Translates the English page structure.
import { LINKS, SUPPORT_EMAIL } from './shared.mjs';

const mailto = `mailto:${SUPPORT_EMAIL}`;

export const CONTENT = {
  lang: 'ja',
  gameName: '月明かりの烽火',
  homeName: 'プレイヤー案内',
  skip: '本文へ進む',
  navHome: '最初',
  navPrivacy: 'プライバシーポリシー',
  navTerms: '利用規約',
  navSupport: 'サポート',
  navDocs: '講座・ドキュメント',
  mainNavLabel: '頁',
  navLanguageLabel: '言語',
  languageNames: {
    en: 'English',
    ko: '한국어',
    ja: '日本語',
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
  },

  homeTitle: '月明かりの烽火 — プレイヤー案内',
  homeLede: 'Hyo Devの月明かりの烽火の個人情報とサポートと利用規約の頁を五つの言語で置きます。',
  homePrivacyHeading: 'プライバシーポリシー',
  homeSupportHeading: 'サポート',
  homeContact:
    `問合せ: <a href="${mailto}">${SUPPORT_EMAIL}</a>. 記録と照らせるようプレイヤーIDを添えてください。`,

  privacyTitle: 'プライバシーポリシー — 月明かりの烽火',
  privacyLede: 'この方針は、Hyo Devの月明かりの烽火が集める情報とその取扱いを説明します。',
  updated: 'バージョン4.0.0時点の内容です。',
  privacySections: [
    {
      id: 'sign-in',
      num: '1',
      h: 'ログイン方法',
      html: `<ul class="tight">
<li>ゲスト入場に加え、設定済みのビルドではGoogle・Appleログインを提供します。</li>
<li>ゲスト入場は対応端末では匿名の認証IDを作ります。</li>
<li>GoogleとAppleは別のログインIDで、Playゲームプロフィールは別のAndroid専用選択肢として今回のビルドでは提供しません。</li>
</ul>`,
    },
    {
      id: 'sign-in-data',
      num: '2',
      h: 'ログイン処理の範囲',
      html: `<ul class="tight">
<li>Firebaseと選んだGoogle・Apple提供者は、認証と回復のため識別子、ログイン・セッション資格、同意と提供者設定で開かれたプロフィール情報を処理します。</li>
<li>ゲームは公開プレイヤーID、ログイン済みアカウントとIDの非公開の紐付け、チェックポイント保存を別に保ちます。</li>
<li>サーバー側のアカウント参照をハッシュで置くのは端末内のゲームのアカウント一覧だけで、サーバー側の記録は原文の参照を持ち自分のアカウントに非公開のままです。</li>
<li>ゲーム自体は自分の記録に届く間だけログイントークンをメモリに置きます。ゲームプレイの保存ファイルにログイントークンは入らず、公開順位にも載せません。起動をまたいで入ったままにするのはFirebase・提供者のSDKが別に担い、SDKとOSの保存場所に自らのセッション情報を置きます。</li>
<li>メールとプロフィール情報は公開の殿堂記録に表示しません。提供者側の取扱いは各提供者の方針に従います: <a href="${LINKS.firebasePrivacy}">Firebase</a>、<a href="${LINKS.googlePrivacy}">Google</a>、<a href="${LINKS.applePrivacy}">Apple</a>。</li>
</ul>`,
    },
    {
      id: 'player-id',
      num: '3',
      h: 'プレイヤーID',
      html: `<ul class="tight">
<li>初回プレイ前に<code>MB-</code>+16進32文字の恒久的な公開IDを発行します。</li>
<li>保存した関門と殿堂の記録の名になり、連携しても維持されます。元のゲストにGoogleを連携しても同じIDと同じチェックポイントの所有権が引き継がれます。</li>
<li>ログアウトすると端末に新しいゲストIDが始まり以前のIDと保存は保管され、同じ提供者で入り直すとそのアカウントのIDと保管された保存に戻ります。そのため一つの導入に複数のIDが残ることがあります。</li>
<li>サポートに連絡するときはゲームのアカウント画面に表示されるプレイヤーIDを添えてください。</li>
</ul>`,
    },
    {
      id: 'cloud-saves',
      num: '4',
      h: 'クラウド保存',
      html: `<ul class="tight">
<li>ログイン済みアカウントは進行状況(巡回、英雄、遺物、成長、スコア)を持つ非公開の版付き保存を一つ持ちます。</li>
<li>保存は端末が先で、送信は後から追います。</li>
<li>保存に購入・残高の記録は入りません。</li>
<li>受信は十分に検査してから入り、異なるクラウド写しはどちらを残すか選択を待ちます。</li>
</ul>`,
    },
    {
      id: 'hall',
      num: '5',
      h: '殿堂',
      html: `<ul class="tight">
<li>殿堂はプレイヤーIDごとに最良記録一つ(プレイヤーID、英雄、スコア、進行度、アプリ版、更新時刻)を保ちます。</li>
<li>読み取りは公開で、書き込みは所有アカウントのみ、スコアは上がる一方で、順位はスコアから求めるため同点は同順位になります。</li>
<li>殿堂の記録に名前、メール、アカウント参照、トークン、保存は入りません。</li>
</ul>`,
    },
    {
      id: 'deletion',
      num: '6',
      h: '削除',
      html: `<ul class="tight">
<li>クラウドアカウントはゲームのアカウント設定から消します。削除は殿堂記録、クラウド保存、予約、プロフィールを一つの検証済み手順で先にまとめて消し、その確認後にログイン自体を消します。</li>
<li>iOSでApple連携のアカウントを消すときはAppleログイン画面での再確認を求めることがあります。</li>
<li>出るとログインの続きは終わり新しいゲストIDに替わります。端末とクラウドのどちらからも何も消しません。</li>
<li>クラウドアカウントを消すとクラウドの記録とログインは消えますが、端末にすでにあるもの — ローカル保存と端末内のアカウント一覧 — は入れ直しや消去まで残ります。</li>
<li>アカウント・チェックポイント・殿堂の記録に、自動で消える期限はありません。アカウントを消すまで残ります。</li>
<li><a href="${mailto}">${SUPPORT_EMAIL}</a>へのメールでも自分の情報の開示・訂正・削除を求められます。プレイヤーIDを添えてください。</li>
<li>問合せはプレイヤーIDで記録と照らします。購入記録にかかる削除の求めは購入確認サービスへ渡します。</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '7',
      h: 'ゲストとオフライン',
      html: `<ul class="tight">
<li>ゲストプレイは端末専用ゲストとしてオフラインでも動き、クラウド登録済みとして表示されません。</li>
<li>裏側の加入に失敗しても、ログイン設定のないビルドでも、プレイは続きます。ログイン設定のないビルドは登録を試みず、誤りも出しません。</li>
<li>ログイン、クラウド保存、殿堂、ストア、購入確認にはインターネット接続が必要です。</li>
</ul>`,
    },
    {
      id: 'analytics',
      num: '8',
      h: '分析',
      html: `<p>任意のゲームプレイ分析は、出荷ビルドの書出し設定と初期停止の設定明示同意の両方がそろわない限り停止のままです。</p>`,
    },
    {
      id: 'purchases',
      num: '9',
      h: '購入',
      html: `<ul class="tight">
<li>ストアの領収書は<a href="${LINKS.iapkitDocs}">IAPKit購入確認サービス</a>で確かめます。確認のためストア・商品情報と領収書またはトークン(Apple署名JWSまたはGoogle購入トークン)を送ります。</li>
<li>確認記録には取引・注文の識別子、ストア応答、要求元IP、確認結果、処理時間が残ることがあります。処理は権利の付与・復元・取消、返金、不正・重複防止、診断、サービス統計に使います。</li>
<li>サービス統計のためIAPKitがプロジェクト初回有効領収書イベントとストア種別をMixpanelに送ることがあります。その出来事に購入トークン、取引ID、IPは入りません。IAPKitの基盤はConvexが担います。各方針: <a href="${LINKS.iapkitPrivacy}">IAPKit</a>、<a href="${LINKS.convexPrivacy}">Convex</a>、<a href="${LINKS.mixpanelPrivacy}">Mixpanel</a>。この第三者サービス統計はゲームの任意のゲームプレイ分析とは別で、分析は設定で有効にして初めて動きます。</li>
<li>アプリと開発者はカード情報やストアのパスワードを受け取りません。鍵・署名・購入トークンはログや誤り表示に残しません。</li>
<li>ストア側の購入処理は各ストアの方針に従います: <a href="${LINKS.applePrivacy}">Apple</a>、<a href="${LINKS.googlePrivacy}">Google</a>。</li>
</ul>`,
    },
    {
      id: 'support-requests',
      num: '10',
      h: '問合せの取扱い',
      html: `<ul class="tight">
<li>サポートへメールすると解決のためメールアドレス、文面、選んだ添付をメールサービス提供者とともに処理します。</li>
<li>問合せは解決と法令対応に要る間だけ置きます。</li>
<li>購入がかかるときは記録を探す最小限の注文情報だけを尋ねます。領収書全体、パスワード、確認コードは尋ねません。</li>
<li>提供者は復元・返金・不正防止・統計・経理・法令対応に要る限り確認記録を置きます。一律の消去期限はありません。</li>
<li>法が置かせる記録は残ることがあり、処理者の持つ記録への求めは処理者へ渡せます。</li>
<li>問合せと上記の確認処理はあなたの国の外で行われることがあります。</li>
</ul>`,
    },
    {
      id: 'changes',
      num: '11',
      h: '方針の変更',
      html: `<p>情報の取扱いが変わるときはこの頁を新しい版とともに直します。この版は4.0.0を扱います。</p>`,
    },
  ],

  supportTitle: 'サポート — 月明かりの烽火',
  supportLede: '購入、アカウント、保存、殿堂の助けになります。',
  supportSections: [
    {
      id: 'contact',
      num: '1',
      h: '問合せ',
      html: `<ul class="tight">
<li><a href="${mailto}">${SUPPORT_EMAIL}</a>へメールしてください。プレイヤーID(<code>MB-</code>&#8230;、ゲームのアカウント画面に表示)、端末とOS版、何が起きたかを書いてください。</li>
<li>パスワード、購入トークン、確認コードは送らないでください。サポートが尋ねることもありません。</li>
<li>不具合の報告は<a href="${LINKS.issues}">GitHub Issues</a>も歓迎します。</li>
</ul>`,
    },
    {
      id: 'products',
      num: '2',
      h: '今の商品',
      html: `<p>ストアは10品を売ります。永続の買い切り7品とコンティニューコイン3品です。</p>
%%PRODUCT_TABLE%%
<ul class="tight">
<li>永続の品はストアのアカウントに残り、入れ直し後も購入の復元で戻ります。</li>
<li>コインは1枚・5枚・10枚を足します。1枚使うとスコア・レベル・遺物を保って倒れた場所から続けられます。使ったコインは戻らず、確認と消費の処理が済めば同じ品を買い直せます。</li>
<li>価格と税は各ストアの表示に従います。</li>
</ul>`,
    },
    {
      id: 'restore',
      num: '3',
      h: '購入の復元とゲームのログイン',
      html: `<ul class="tight">
<li>購入の復元(ストアの下部)は同じストアのアカウント(同じApple Account、同じGoogle Playアカウント)で入れ直し後や新しい端末に永続7品を戻します。ストアと確認サービスへの接続が必要です。</li>
<li>ゲームのログイン(月の門のGoogle・Apple)はクラウド保存と殿堂の記録を戻します。二つは別です。入っても購入は戻らず、戻しても入りません。</li>
<li>ストアを開くのにログインはいりません。タイトルからストアを開けば品が見え、購入の復元はいつも見えます。</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '4',
      h: 'ゲストと失った進行',
      html: `<ul class="tight">
<li>ゲストの進行は端末専用です。入らずに入れ直したり端末を替えたりすると失われます。</li>
<li>Google・Appleで入ればチェックポイントのクラウド写しが残ります。</li>
<li>出ると以前のIDと保存は端末に残り新しいゲストが始まります。同じ提供者で入り直せばそのアカウントのIDと保管された保存に戻ります。</li>
<li>連携していないローカル情報は入れ直しや消去で失われることがあります(<a href="/ja/terms">規約</a>)。</li>
</ul>`,
    },
    {
      id: 'conflicts',
      num: '5',
      h: 'クラウドの競合',
      html: `<p>クラウド写しが違うときは両側を見せ、上書きの前にどちらを残すか尋ねます。</p>`,
    },
    {
      id: 'refunds',
      num: '6',
      h: '返金',
      html: `<ul class="tight">
<li>購入は各ストアの支払いと復元と返金の手続きに従い、このゲーム独自の手数料や返金期限はありません。</li>
<li>Appleの購入: Apple公式の<a href="${LINKS.appleRefund}">問題報告</a>頁から求めてください。</li>
<li>Google Playの購入: Google Play公式の<a href="${LINKS.googleRefund}">返金案内</a>から求めてください。</li>
<li>返金が定まればその購入の権利だけが消え、他の永続の品は残ります。</li>
</ul>`,
    },
    {
      id: 'offline',
      num: '7',
      h: '接続とオフライン',
      html: `<ul class="tight">
<li>基本プレイとローカル記録はゲストとしてオフラインでも動きます。</li>
<li>商品の読み込み、購入、購入確認、ログイン、クラウド保存と殿堂にはインターネット接続が必要です。</li>
<li>広告はありません。</li>
</ul>`,
    },
    {
      id: 'privacy',
      num: '8',
      h: '個人情報',
      html: `<ul class="tight">
<li>アカウント・保存・殿堂の取扱い: <a href="/ja/privacy">プライバシーポリシー</a>。</li>
<li>提供者の方針: <a href="${LINKS.firebasePrivacy}">Firebase</a>、<a href="${LINKS.googlePrivacy}">Google</a>、<a href="${LINKS.applePrivacy}">Apple</a>。</li>
</ul>`,
    },
  ],

  termsTitle: '利用規約 — 月明かりの烽火',
  termsLede: 'ゲーム内に表示される利用規約そのままです。',
  termsNote: 'ゲーム内の利用規約と同じ文章です。',

  tableCaption: 'ストアで売る10品の全部です。',
  thItem: '商品',
  thType: '種類',
  thGrant: '得られるもの',
  typePermanent: '永続',
  typeConsumable: '消耗型',
  grantSupporter: '設定 › クレジットの名前の横に支援者印を永久表示します。',
  grantHero: '月光の祭壇でこの英雄を永久解放します。性能均衡型です。',
  grantLantern: '残り火・月光・紫・翡翠の炎。見た目だけです。',
  grantCoins: (count) => `コイン${count}枚を残高に足します。`,

  footerContact: '問合せ',
  footerRights: '\u00a9 2026 Hyo Jang. Hyo Devの月明かりの烽火。',
};
