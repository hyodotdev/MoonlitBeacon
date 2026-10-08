// Simplified Chinese player-care copy. Translates the English structure.
import { LINKS, SUPPORT_EMAIL } from './shared.mjs';

const mailto = `mailto:${SUPPORT_EMAIL}`;

export const CONTENT = {
  lang: 'zh-Hans',
  gameName: '月光烽火',
  homeName: '玩家服务',
  skip: '跳到正文',
  navHome: '首页',
  navPrivacy: '隐私政策',
  navTerms: '使用条款',
  navSupport: '支持',
  navDocs: '课程与文档',
  mainNavLabel: '页面',
  navLanguageLabel: '语言',
  languageNames: {
    en: 'English',
    ko: '한국어',
    ja: '日本語',
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
  },

  homeTitle: '月光烽火 — 玩家服务',
  homeLede: 'Hyo Dev 出品的月光烽火的隐私、支持与条款页面，共五种语言。',
  homePrivacyHeading: '隐私政策',
  homeSupportHeading: '支持',
  homeContact:
    `联系：<a href="${mailto}">${SUPPORT_EMAIL}</a>。请附上玩家 ID，以便与记录核对。`,

  privacyTitle: '隐私政策 — 月光烽火',
  privacyLede: '本政策说明 Hyo Dev 出品的月光烽火收集哪些信息，以及如何处理。',
  updated: '内容对应 4.0.0 版本。',
  privacySections: [
    {
      id: 'sign-in',
      num: '1',
      h: '登录方式',
      html: `<ul class="tight">
<li>游客入口之外，已配置的版本提供 Google/Apple 登录。</li>
<li>游客入口在受支持设备上创建匿名认证身份。</li>
<li>Google 与 Apple 是不同的登录身份；Play 游戏资料是另一个仅限 Android 的选项，本版本不提供。</li>
</ul>`,
    },
    {
      id: 'sign-in-data',
      num: '2',
      h: '登录处理的范围',
      html: `<ul class="tight">
<li>为完成认证与找回，Firebase 与所选 Google/Apple 提供方会处理标识符、登录与会话凭证，以及按同意和提供方设置开放的资料字段。</li>
<li>游戏另存自己的记录：公开玩家 ID、登录账号与该 ID 的非公开关联、检查点存档。</li>
<li>只有设备上游戏自带的账号列表以哈希形式存放服务端账号引用；后端保存的账号与存档记录携带原始引用，仅对本账号保密。</li>
<li>游戏本体的登录令牌只在访问本人记录期间留在内存中。玩法存档文件不含登录令牌，令牌也绝不放入公开排行。跨启动保持登录由 Firebase 与提供方 SDK 另行处理，它们在 SDK 与系统存储中保留自己的会话数据。</li>
<li>邮箱与资料信息不在公开殿堂记录中显示。提供方侧的资料处理遵循各提供方自己的政策：<a href="${LINKS.firebasePrivacy}">Firebase</a>、<a href="${LINKS.googlePrivacy}">Google</a>、<a href="${LINKS.applePrivacy}">Apple</a>。</li>
</ul>`,
    },
    {
      id: 'player-id',
      num: '3',
      h: '玩家 ID',
      html: `<ul class="tight">
<li>首次游玩前签发 <code>MB-</code> 加 32 位十六进制字符的持久公开 ID，作为已保存月之门与殿堂记录的名称。</li>
<li>关联后保持不变：原游客关联 Google 后，同一 ID 与同一检查点归属继续有效。</li>
<li>退出登录会在设备上启用全新游客 ID，原 ID 与存档继续保留；用同一提供方重新登录则回到该账号的 ID 与保留的存档。因此一次安装随时间可能留下多个 ID。</li>
<li>联系支持时，请附上游戏账号画面中显示的玩家 ID。</li>
</ul>`,
    },
    {
      id: 'cloud-saves',
      num: '4',
      h: '云存档',
      html: `<ul class="tight">
<li>已登录账号拥有一个带版本号的非公开存档，保存其进度(轮次、英雄、遗物、成长、分数)。</li>
<li>先落盘再后台上传。</li>
<li>存档不含购买或余额记录。</li>
<li>下载须通过完整检查才会安装；不一致的云端副本等待玩家选择保留哪一侧。</li>
<li>已登录账号还持有一条非公开出勤记录（上次领取时间），用于限定免费继续金币奖励的间隔；它绝不会显示在殿堂中。</li>
<li>在手机上，可在设置中开启本地提醒，在下次签到币可领取时通知您。通知根据上次签到时间在设备上安排，不包含账号信息、令牌或个人数据，也不会直接发放金币。在设置中关闭后，所有已安排的提醒都会取消。通知在您离开期间大约每十二小时重复一次，最多安排24天的通知，每次打开游戏时都会刷新。</li>
</ul>`,
    },
    {
      id: 'hall',
      num: '5',
      h: '殿堂榜',
      html: `<ul class="tight">
<li>殿堂按玩家 ID 保存一条最佳记录(玩家 ID、英雄、分数、进度、应用版本、更新时间，以及已认领时的账号公开游戏名)。</li>
<li>读取公开，仅归属账号可写，分数只增不减，名次由分数推导，同分同名次。</li>
<li>每个账号可认领一个 2–12 字的永久公开名：字母、数字或中日韩文字。认领需要联网；认领后，该名会显示在所有设备的殿堂记录中。公开名不可改名，也不可转移到其他账号。</li>
<li>该名是游戏名而非真实姓名，是殿堂记录中唯一的名称。殿堂记录不含邮箱、账号引用、令牌或存档。</li>
</ul>`,
    },
    {
      id: 'deletion',
      num: '6',
      h: '删除',
      html: `<ul class="tight">
<li>在游戏的账号设置中删除云账号。删除先以一次已验证的步骤同时清除殿堂记录、已认领的名称与冒险者记录、出勤记录、云存档、预留与资料；确认后再删除登录本身。</li>
<li>iOS 上删除 Apple 关联账号时，可能要求重开 Apple 登录页重新确认。</li>
<li>退出登录会结束登录会话并切换到全新游客 ID；在设备或云端都不删除任何内容。</li>
<li>删除云账号会清除其云端记录与登录，以及其本地旅程存档文件和设备上的账号绑定；其他账号的本地存档，以及购买、Vault、设置等单独的设备文件会继续保留。</li>
<li>账号、名称、检查点、出勤与殿堂记录没有预设的自动到期：保留至账号删除为止。</li>
<li>也可以发邮件到 <a href="${mailto}">${SUPPORT_EMAIL}</a>，请求查阅、更正或删除本人信息。请附上玩家 ID。</li>
<li>支持请求经玩家 ID 与记录核对；涉及购买记录的删除请求会转交给购买验证处理方。</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '7',
      h: '游客与离线',
      html: `<ul class="tight">
<li>游客可离线以纯本机游客游玩，不会显示为已注册云账号。</li>
<li>后台注册失败或版本未配置登录，游玩都会继续。未配置登录的版本不尝试注册，也不报错。</li>
<li>登录、云存档、殿堂、出勤领取、商店与购买验证需要网络连接。</li>
</ul>`,
    },
    {
      id: 'analytics',
      num: '8',
      h: '分析',
      html: `<p>可选的玩法分析须同时满足出货版本的导出配置与默认关闭的设置明示同意才会启用，否则保持关闭。</p>`,
    },
    {
      id: 'purchases',
      num: '9',
      h: '购买',
      html: `<ul class="tight">
<li>商店收据经 <a href="${LINKS.iapkitDocs}">IAPKit 购买验证服务</a>核验。核验会发送商店与商品信息，以及收据或令牌(Apple 签名 JWS 或 Google 购买令牌)。</li>
<li>其验证记录可能保留交易与订单标识符、商店响应、请求 IP、验证结果与处理时长。处理用于权益授予、恢复与撤销、退款、防欺诈与去重、诊断及服务统计。</li>
<li>为服务统计，IAPKit 可能向 Mixpanel 发送项目首次有效收据事件与商店种类；该事件不含购买令牌、交易 ID 与 IP。Convex 提供 IAPKit 的基础设施。相关政策：<a href="${LINKS.iapkitPrivacy}">IAPKit</a>、<a href="${LINKS.convexPrivacy}">Convex</a>、<a href="${LINKS.mixpanelPrivacy}">Mixpanel</a>。上述第三方服务统计独立于游戏的可选玩法分析；后者须在设置中启用才会运行。</li>
<li>应用与开发者不会收到付款卡信息或商店账号密码。密钥、签名与购买令牌不出现在日志或错误信息中。</li>
<li>商店侧的购买处理遵循各商店自己的政策：<a href="${LINKS.applePrivacy}">Apple</a>、<a href="${LINKS.googlePrivacy}">Google</a>。</li>
</ul>`,
    },
    {
      id: 'support-requests',
      num: '10',
      h: '支持请求的处理',
      html: `<ul class="tight">
<li>发邮件联系支持时，为解决请求，会与邮件服务提供方共同处理您的邮箱地址、留言内容及您主动添加的附件。</li>
<li>支持请求仅在解决请求与履行法定义务所需期间保留。</li>
<li>涉及购买时，支持只索取定位记录所需的最少订单信息，从不索取完整收据、密码或验证码。</li>
<li>提供方为恢复、退款、防欺诈、统计、会计与法定义务，在必要范围内保留验证记录；不承诺统一的到期删除。</li>
<li>法律要求保留的记录可以继续保留；涉及处理方所持记录的请求可以转交处理方。</li>
<li>支持请求与上述核验可能在您所在国家之外处理。</li>
</ul>`,
    },
    {
      id: 'changes',
      num: '11',
      h: '政策变更',
      html: `<p>信息处理方式变化时，本页随新版本更新。本版对应 4.0.0。</p>`,
    },
  ],

  supportTitle: '支持 — 月光烽火',
  supportLede: '购买、账号、存档与殿堂的帮助。',
  supportSections: [
    {
      id: 'contact',
      num: '1',
      h: '联系我们',
      html: `<ul class="tight">
<li>请发邮件到 <a href="${mailto}">${SUPPORT_EMAIL}</a>。请写明玩家 ID(<code>MB-</code>&#8230;，显示在游戏账号画面中)、设备型号与系统版本，以及发生了什么。</li>
<li>不要发送密码、购买令牌或验证码；支持不会索取这些。</li>
<li>Bug 报告也欢迎发到 <a href="${LINKS.issues}">GitHub Issues</a>。</li>
</ul>`,
    },
    {
      id: 'products',
      num: '2',
      h: '当前商品',
      html: `<p>商店在售 10 项：7 项永久买断，3 档继续游戏金币。</p>
%%PRODUCT_TABLE%%
<ul class="tight">
<li>永久商品归属商店账号，重装后可经“恢复购买”找回。</li>
<li>金币档分别增加 1、5、10 枚金币。每次使用一枚，可保留分数、等级与遗物，从倒下之处继续。已使用的金币不可恢复；完成验证与消耗处理后可再次购买同一商品。</li>
<li>价格与税费以各商店标示为准。</li>
</ul>`,
    },
    {
      id: 'restore',
      num: '3',
      h: '恢复购买与游戏账号登录',
      html: `<ul class="tight">
<li>“恢复购买”(商店底部)在同一商店账号(同一 Apple 账号、同一 Google Play 账号)下，于重装后或新设备上找回 7 项永久商品，需要连接商店与验证服务。</li>
<li>游戏账号登录(月之门中的 Google/Apple)找回云存档与殿堂记录。两者相互独立：登录不会恢复购买，恢复也不会登录账号。</li>
<li>打开商店不需要登录：在标题画面打开商店即可看到商品，“恢复购买”始终可见。</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '4',
      h: '游客与丢失的进度',
      html: `<ul class="tight">
<li>游客进度只保存在本机。未登录就重装或更换设备，进度会丢失。</li>
<li>用 Google/Apple 登录后，检查点的云端副本会保留。</li>
<li>退出登录会保留原 ID 与存档，并启用全新游客；用同一提供方重新登录则回到该账号的 ID 与保留的存档。</li>
<li>未关联的本地数据可能在重装或清除存储后丢失(<a href="/zh-Hans/terms">条款</a>)。</li>
</ul>`,
    },
    {
      id: 'conflicts',
      num: '5',
      h: '云存档冲突',
      html: `<p>云端副本不一致时，游戏会同时展示两侧，在覆盖前请玩家选择保留哪一侧。</p>`,
    },
    {
      id: 'refunds',
      num: '6',
      h: '退款',
      html: `<ul class="tight">
<li>购买遵循各商店自己的支付、恢复与退款流程；本游戏不另设费用或退款期限。</li>
<li>Apple 购买：请经 Apple 官方“<a href="${LINKS.appleRefund}">报告问题</a>”页面申请。</li>
<li>Google Play 购买：请经 Google Play 官方<a href="${LINKS.googleRefund}">退款帮助</a>申请。</li>
<li>退款确认后，只撤销该笔购买的权益，其他永久商品保留。</li>
</ul>`,
    },
    {
      id: 'offline',
      num: '7',
      h: '联网与离线',
      html: `<ul class="tight">
<li>基础玩法与本地记录可以游客身份离线使用。</li>
<li>加载商品、购买与购买验证、登录、云存档与殿堂需要网络连接。</li>
<li>相隔十二小时后回归可领取两枚继续金币；领取需要联网，离线也可继续游玩，只是领不到奖励。</li>
<li>在手机上，可在设置中开启本地提醒，在下次2枚金币可领取时通知您；关闭后即取消。通知本身不会发放金币。</li>
<li>游戏没有广告。</li>
</ul>`,
    },
    {
      id: 'privacy',
      num: '8',
      h: '隐私',
      html: `<ul class="tight">
<li>账号、存档与殿堂的处理方式见<a href="/zh-Hans/privacy">隐私政策</a>。</li>
<li>提供方政策：<a href="${LINKS.firebasePrivacy}">Firebase</a>、<a href="${LINKS.googlePrivacy}">Google</a>、<a href="${LINKS.applePrivacy}">Apple</a>。</li>
</ul>`,
    },
  ],

  termsTitle: '使用条款 — 月光烽火',
  termsLede: '与游戏中显示的使用条款一致。',
  termsNote: '正文与游戏内条款相同。',

  tableCaption: '商店在售的全部 10 项。',
  thItem: '商品',
  thType: '类型',
  thGrant: '获得内容',
  typePermanent: '永久',
  typeConsumable: '消耗型',
  grantSupporter: '在“设置”›“制作名单”的名字旁永久显示支持者标记。',
  grantHero: '在月光祭坛永久解锁该英雄。平衡型替代玩法。',
  grantLantern: '余烬、月光、紫罗兰、翡翠四色烽火。仅改变外观。',
  grantCoins: (count) => `余额增加 ${count} 枚金币。`,

  footerContact: '联系',
  footerRights: '\u00a9 2026 Hyo Jang。Hyo Dev 出品的月光烽火。',
};
