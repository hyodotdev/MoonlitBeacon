// Traditional Chinese player-care copy. Translates the English structure.
import { LINKS, SUPPORT_EMAIL } from './shared.mjs';

const mailto = `mailto:${SUPPORT_EMAIL}`;

export const CONTENT = {
  lang: 'zh-Hant',
  gameName: '月光烽火',
  homeName: '玩家服務',
  skip: '跳到正文',
  navHome: '首頁',
  navPrivacy: '隱私權政策',
  navTerms: '使用條款',
  navSupport: '支援',
  navDocs: '課程與文件',
  mainNavLabel: '頁面',
  navLanguageLabel: '語言',
  languageNames: {
    en: 'English',
    ko: '한국어',
    ja: '日本語',
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
  },

  homeTitle: '月光烽火 — 玩家服務',
  homeLede: 'Hyo Dev 出品的月光烽火的隱私、支援與條款頁面，共五種語言。',
  homePrivacyHeading: '隱私權政策',
  homeSupportHeading: '支援',
  homeContact:
    `聯絡：<a href="${mailto}">${SUPPORT_EMAIL}</a>。請附上玩家 ID，以便與紀錄核對。`,

  privacyTitle: '隱私權政策 — 月光烽火',
  privacyLede: '本政策說明 Hyo Dev 出品的月光烽火收集哪些資訊，以及如何處理。',
  updated: '內容對應 4.0.0 版本。',
  privacySections: [
    {
      id: 'sign-in',
      num: '1',
      h: '登入方式',
      html: `<ul class="tight">
<li>訪客入口之外，已設定的版本提供 Google/Apple 登入。</li>
<li>訪客入口在受支援裝置上建立匿名認證身分。</li>
<li>Google 與 Apple 是不同的登入身分；Play 遊戲資料是另一個僅限 Android 的選項，本版本不提供。</li>
</ul>`,
    },
    {
      id: 'sign-in-data',
      num: '2',
      h: '登入處理的範圍',
      html: `<ul class="tight">
<li>為完成認證與找回，Firebase 與所選 Google/Apple 提供方會處理識別碼、登入與工作階段憑證，以及按同意和提供方設定開放的資料欄位。</li>
<li>遊戲另存自己的紀錄：公開玩家 ID、登入帳號與該 ID 的非公開關聯、檢查點存檔。</li>
<li>只有裝置上遊戲自帶的帳號清單以雜湊形式存放伺服器端帳號參照；後端保存的帳號與存檔紀錄攜帶原始參照，僅對本帳號保密。</li>
<li>遊戲本體的登入權杖只在存取本人紀錄期間留在記憶體中。玩法存檔檔案不含登入權杖，權杖也絕不放入公開排行。跨啟動保持登入由 Firebase 與提供方 SDK 另行處理，它們在 SDK 與系統儲存中保留自己的工作階段資料。</li>
<li>信箱與資料資訊不在公開殿堂紀錄中顯示。提供方側的資料處理遵循各提供方自己的政策：<a href="${LINKS.firebasePrivacy}">Firebase</a>、<a href="${LINKS.googlePrivacy}">Google</a>、<a href="${LINKS.applePrivacy}">Apple</a>。</li>
</ul>`,
    },
    {
      id: 'player-id',
      num: '3',
      h: '玩家 ID',
      html: `<ul class="tight">
<li>首次遊玩前簽發 <code>MB-</code> 加 32 位十六進制字元的持久公開 ID，作為已儲存月之門與殿堂紀錄的名稱。</li>
<li>關聯後保持不變：原訪客關聯 Google 後，同一 ID 與同一檢查點歸屬繼續有效。</li>
<li>登出會在裝置上啟用全新訪客 ID，原 ID 與存檔繼續保留；用同一提供方重新登入則回到該帳號的 ID 與保留的存檔。因此一次安裝隨時間可能留下多個 ID。</li>
<li>聯絡支援時，請附上遊戲帳號畫面中顯示的玩家 ID。</li>
</ul>`,
    },
    {
      id: 'cloud-saves',
      num: '4',
      h: '雲存檔',
      html: `<ul class="tight">
<li>已登入帳號擁有一個帶版本號的非公開存檔，保存其進度(輪次、英雄、遺物、成長、分數)。</li>
<li>先落盤再後台上傳。</li>
<li>存檔不含購買或餘額紀錄。</li>
<li>下載須通過完整檢查才會安裝；不一致的雲端副本等待玩家選擇保留哪一側。</li>
</ul>`,
    },
    {
      id: 'hall',
      num: '5',
      h: '殿堂榜',
      html: `<ul class="tight">
<li>殿堂按玩家 ID 保存一條最佳紀錄(玩家 ID、英雄、分數、進度、應用版本、更新時間)。</li>
<li>讀取公開，僅歸屬帳號可寫，分數只增不減，名次由分數推導，同分同名次。</li>
<li>殿堂紀錄不含姓名、信箱、帳號參照、權杖或存檔。</li>
</ul>`,
    },
    {
      id: 'deletion',
      num: '6',
      h: '刪除',
      html: `<ul class="tight">
<li>在遊戲的帳號設定中刪除雲帳號。刪除先以一次已驗證的步驟同時清除殿堂紀錄、雲存檔、預留與資料；確認後再刪除登入本身。</li>
<li>iOS 上刪除 Apple 關聯帳號時，可能要求重開 Apple 登入頁重新確認。</li>
<li>登出會結束登入工作階段並切換到全新訪客 ID；在裝置或雲端都不刪除任何內容。</li>
<li>刪除雲帳號會清除雲端紀錄與登入，但本機已有檔案——本地存檔與裝置上的帳號清單——在重裝遊戲或清除儲存空間前會繼續保留。</li>
<li>帳號、檢查點與殿堂紀錄沒有預設的自動到期：保留至帳號刪除為止。</li>
<li>也可以寫信到 <a href="${mailto}">${SUPPORT_EMAIL}</a>，請求查閱、更正或刪除本人資訊。請附上玩家 ID。</li>
<li>支援請求經玩家 ID 與紀錄核對；涉及購買紀錄的刪除請求會轉交給購買驗證處理方。</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '7',
      h: '訪客與離線',
      html: `<ul class="tight">
<li>訪客可離線以純本機訪客遊玩，不會顯示為已註冊雲帳號。</li>
<li>後台註冊失敗或版本未設定登入，遊玩都會繼續。未設定登入的版本不嘗試註冊，也不報錯。</li>
<li>登入、雲存檔、殿堂、商店與購買驗證需要網路連線。</li>
</ul>`,
    },
    {
      id: 'analytics',
      num: '8',
      h: '分析',
      html: `<p>可選的玩法分析須同時滿足出貨版本的匯出配置與預設關閉的設定明示同意才會啟用，否則保持關閉。</p>`,
    },
    {
      id: 'purchases',
      num: '9',
      h: '購買',
      html: `<ul class="tight">
<li>商店收據經 <a href="${LINKS.iapkitDocs}">IAPKit 購買驗證服務</a>核驗。核驗會傳送商店與商品資訊，以及收據或權杖(Apple 簽章 JWS 或 Google 購買權杖)。</li>
<li>其驗證紀錄可能保留交易與訂單識別碼、商店回應、請求 IP、驗證結果與處理時間。處理用於權益授予、恢復與撤銷、退款、防詐欺與去重、診斷及服務統計。</li>
<li>為服務統計，IAPKit 可能向 Mixpanel 傳送專案首次有效收據事件與商店種類；該事件不含購買權杖、交易 ID 與 IP。Convex 提供 IAPKit 的基礎設施。相關政策：<a href="${LINKS.iapkitPrivacy}">IAPKit</a>、<a href="${LINKS.convexPrivacy}">Convex</a>、<a href="${LINKS.mixpanelPrivacy}">Mixpanel</a>。上述第三方服務統計獨立於遊戲的可選玩法分析；後者須在設定中啟用才會運作。</li>
<li>應用程式與開發者不會收到付款卡資訊或商店帳號密碼。金鑰、簽章與購買權杖不出現在紀錄或錯誤訊息中。</li>
<li>商店側的購買處理遵循各商店自己的政策：<a href="${LINKS.applePrivacy}">Apple</a>、<a href="${LINKS.googlePrivacy}">Google</a>。</li>
</ul>`,
    },
    {
      id: 'support-requests',
      num: '10',
      h: '支援請求的處理',
      html: `<ul class="tight">
<li>寫信聯絡支援時，為解決請求，會與郵件服務提供方共同處理您的信箱地址、留言內容及您主動添加的附件。</li>
<li>支援請求僅在解決請求與履行法定義務所需期間保留。</li>
<li>涉及購買時，支援只索取定位紀錄所需的最少訂單資訊，從不索取完整收據、密碼或驗證碼。</li>
<li>提供方為恢復、退款、防詐欺、統計、會計與法定義務，在必要範圍內保留驗證紀錄；不承諾統一的到期刪除。</li>
<li>法律要求保留的紀錄可以繼續保留；涉及處理方所持紀錄的請求可以轉交處理方。</li>
<li>支援請求與上述核驗可能在您所在國家之外處理。</li>
</ul>`,
    },
    {
      id: 'changes',
      num: '11',
      h: '政策變更',
      html: `<p>資訊處理方式變化時，本頁隨新版本更新。本版對應 4.0.0。</p>`,
    },
  ],

  supportTitle: '支援 — 月光烽火',
  supportLede: '購買、帳號、存檔與殿堂的協助。',
  supportSections: [
    {
      id: 'contact',
      num: '1',
      h: '聯絡我們',
      html: `<ul class="tight">
<li>請寫信到 <a href="${mailto}">${SUPPORT_EMAIL}</a>。請寫明玩家 ID(<code>MB-</code>&#8230;，顯示在遊戲帳號畫面中)、裝置型號與系統版本，以及發生了什麼。</li>
<li>不要傳送密碼、購買權杖或驗證碼；支援不會索取這些。</li>
<li>Bug 回報也歡迎發到 <a href="${LINKS.issues}">GitHub Issues</a>。</li>
</ul>`,
    },
    {
      id: 'products',
      num: '2',
      h: '目前商品',
      html: `<p>商店在售 10 項：7 項永久買斷，3 檔繼續遊戲金幣。</p>
%%PRODUCT_TABLE%%
<ul class="tight">
<li>永久商品歸屬商店帳號，重裝後可經「恢復購買」找回。</li>
<li>金幣檔分別增加 1、5、10 枚金幣。每次使用一枚，可保留分數、等級與遺物，從倒下之處繼續。已使用的金幣不可恢復；完成驗證與消耗處理後可再次購買同一商品。</li>
<li>價格與稅費以各商店標示為準。</li>
</ul>`,
    },
    {
      id: 'restore',
      num: '3',
      h: '恢復購買與遊戲帳號登入',
      html: `<ul class="tight">
<li>「恢復購買」(商店底部)在同一商店帳號(同一 Apple 帳號、同一 Google Play 帳號)下，於重裝後或新裝置上找回 7 項永久商品，需要連接商店與驗證服務。</li>
<li>遊戲帳號登入(月之門中的 Google/Apple)找回雲存檔與殿堂紀錄。兩者相互獨立：登入不會恢復購買，恢復也不會登入帳號。</li>
<li>開啟商店不需要登入：在標題畫面開啟商店即可看到商品，「恢復購買」始終可見。</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '4',
      h: '訪客與遺失的進度',
      html: `<ul class="tight">
<li>訪客進度只保存在本機。未登入就重裝或更換裝置，進度會遺失。</li>
<li>用 Google/Apple 登入後，檢查點的雲端副本會保留。</li>
<li>登出會保留原 ID 與存檔，並啟用全新訪客；用同一提供方重新登入則回到該帳號的 ID 與保留的存檔。</li>
<li>未關聯的本地資料可能在重裝或清除儲存空間後遺失(<a href="/zh-Hant/terms">條款</a>)。</li>
</ul>`,
    },
    {
      id: 'conflicts',
      num: '5',
      h: '雲存檔衝突',
      html: `<p>雲端副本不一致時，遊戲會同時展示兩側，在覆蓋前請玩家選擇保留哪一側。</p>`,
    },
    {
      id: 'refunds',
      num: '6',
      h: '退款',
      html: `<ul class="tight">
<li>購買遵循各商店自己的支付、恢復與退款流程；本遊戲不另設費用或退款期限。</li>
<li>Apple 購買：請經 Apple 官方「<a href="${LINKS.appleRefund}">回報問題</a>」頁面申請。</li>
<li>Google Play 購買：請經 Google Play 官方<a href="${LINKS.googleRefund}">退款協助</a>申請。</li>
<li>退款確認後，只撤銷該筆購買的權益，其他永久商品保留。</li>
</ul>`,
    },
    {
      id: 'offline',
      num: '7',
      h: '連線與離線',
      html: `<ul class="tight">
<li>基礎玩法與本機紀錄，訪客身分可離線使用。</li>
<li>載入商品、購買與購買驗證、登入、雲存檔與殿堂需要網路連線。</li>
<li>遊戲沒有廣告。</li>
</ul>`,
    },
    {
      id: 'privacy',
      num: '8',
      h: '隱私',
      html: `<ul class="tight">
<li>帳號、存檔與殿堂的處理方式見<a href="/zh-Hant/privacy">隱私權政策</a>。</li>
<li>提供方政策：<a href="${LINKS.firebasePrivacy}">Firebase</a>、<a href="${LINKS.googlePrivacy}">Google</a>、<a href="${LINKS.applePrivacy}">Apple</a>。</li>
</ul>`,
    },
  ],

  termsTitle: '使用條款 — 月光烽火',
  termsLede: '與遊戲中顯示的使用條款一致。',
  termsNote: '正文與遊戲內條款相同。',

  tableCaption: '商店在售的全部 10 項。',
  thItem: '商品',
  thType: '類型',
  thGrant: '獲得內容',
  typePermanent: '永久',
  typeConsumable: '消耗型',
  grantSupporter: '在「設定」›「製作名單」的名字旁永久顯示贊助者標記。',
  grantHero: '在月光祭壇永久解鎖該英雄。平衡型替代玩法。',
  grantLantern: '餘燼、月光、紫羅蘭、翡翠四色烽火。僅改變外觀。',
  grantCoins: (count) => `餘額增加 ${count} 枚金幣。`,

  footerContact: '聯絡',
  footerRights: '\u00a9 2026 Hyo Jang。Hyo Dev 出品的月光烽火。',
};
