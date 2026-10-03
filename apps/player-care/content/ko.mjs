// Korean player-care copy. Translates the English page structure.
import { LINKS, SUPPORT_EMAIL } from './shared.mjs';

const mailto = `mailto:${SUPPORT_EMAIL}`;

export const CONTENT = {
  lang: 'ko',
  gameName: '달빛 봉화',
  homeName: '플레이어 안내',
  skip: '본문으로 건너뛰기',
  navHome: '처음',
  navPrivacy: '개인정보처리방침',
  navSupport: '고객지원',
  mainNavLabel: '페이지',
  navLanguageLabel: '언어',
  languageNames: {
    en: 'English',
    ko: '한국어',
    ja: '日本語',
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
  },

  homeTitle: '달빛 봉화 — 플레이어 안내',
  homeLede: 'Hyo Dev의 달빛 봉화 개인정보와 고객지원 페이지를 다섯 언어로 둡니다.',
  homePrivacyHeading: '개인정보처리방침',
  homeSupportHeading: '고객지원',
  homeContact:
    `문의: <a href="${mailto}">${SUPPORT_EMAIL}</a>. 기록과 대조할 수 있게 플레이어 ID를 함께 보내 주세요.`,

  privacyTitle: '개인정보처리방침 — 달빛 봉화',
  privacyLede: '이 방침은 Hyo Dev의 달빛 봉화가 수집하는 정보와 처리 방식을 설명합니다.',
  updated: '버전 4.0.0 기준입니다.',
  privacySections: [
    {
      id: 'sign-in',
      num: '1',
      h: '로그인 방법',
      html: `<ul class="tight">
<li>게스트 입장에 더해, 준비된 빌드에서는 Google·Apple 로그인을 제공합니다.</li>
<li>게스트 입장은 기기가 지원하면 익명 인증 신원을 만듭니다.</li>
<li>Google과 Apple은 별개의 로그인 신원이며, Play 게임 프로필은 별도의 Android 전용 선택지로 이번 빌드에서 제공하지 않습니다.</li>
</ul>`,
    },
    {
      id: 'sign-in-data',
      num: '2',
      h: '로그인이 처리하는 범위',
      html: `<ul class="tight">
<li>Firebase와 선택한 Google·Apple 제공자는 계정 인증과 복구를 위해 식별자, 로그인·세션 정보, 동의·제공자 설정에 따라 제공되는 프로필 정보를 처리합니다.</li>
<li>게임은 공개 플레이어 ID, 로그인 계정과 ID의 비공개 연결, 체크포인트 저장을 따로 보관합니다.</li>
<li>서버 계정 참조를 해시 형태로 두는 것은 기기 안의 게임 계정 목록뿐이며, 백엔드의 계정·저장 기록은 원본 참조를 담고 계정에 비공개로 남습니다.</li>
<li>게임 자체는 내 기록에 닿는 동안 로그인 토큰을 메모리에 둡니다. 게임플레이 저장 파일에 로그인 토큰은 들어가지 않으며, 토큰이 공개 순위에 오르지도 않습니다. 실행을 넘겨 로그인이 유지되는 것은 Firebase·제공자 SDK가 따로 맡으며, SDK와 OS 저장소에 세션 정보를 따로 둡니다.</li>
<li>이메일과 프로필 정보는 공개 전당 기록에 표시되지 않습니다. 제공자 측 프로필 처리는 각 제공자의 방침을 따릅니다: <a href="${LINKS.firebasePrivacy}">Firebase</a>, <a href="${LINKS.googlePrivacy}">Google</a>, <a href="${LINKS.applePrivacy}">Apple</a>.</li>
</ul>`,
    },
    {
      id: 'player-id',
      num: '3',
      h: '플레이어 ID',
      html: `<ul class="tight">
<li>첫 플레이 전에 <code>MB-</code> + 16진수 32자의 바뀌지 않는 공개 ID를 발급합니다.</li>
<li>저장된 관문과 전당 기록의 이름이 되며, 연결해도 유지됩니다. 기존 게스트에 Google을 연결하면 같은 ID와 같은 체크포인트 소유권이 그대로 이어집니다.</li>
<li>로그아웃하면 기기에 새 게스트 ID가 시작되고 이전 ID와 저장은 보관되며, 같은 제공자로 다시 로그인하면 그 계정의 ID와 보관된 저장으로 돌아갑니다. 따라서 한 기기에는 시간이 지나며 둘 이상의 ID가 남을 수 있습니다.</li>
<li>고객지원에 연락할 때는 게임 계정 화면에 표시되는 플레이어 ID를 함께 보내 주세요.</li>
</ul>`,
    },
    {
      id: 'cloud-saves',
      num: '4',
      h: '클라우드 저장',
      html: `<ul class="tight">
<li>로그인한 계정은 진행 상황(순환, 영웅, 유물, 성장, 점수)을 담은 버전이 붙은 비공개 저장 하나를 가집니다.</li>
<li>저장은 기기에 먼저 되고 업로드는 뒤따릅니다.</li>
<li>저장에 구매·잔액 기록은 들어가지 않습니다.</li>
<li>다운로드는 완전히 검사한 뒤 설치되고, 다른 클라우드 사본은 어느 쪽을 쓸지 선택을 기다립니다.</li>
</ul>`,
    },
    {
      id: 'hall',
      num: '5',
      h: '전당',
      html: `<ul class="tight">
<li>전당은 플레이어 ID마다 최고 기록 하나(플레이어 ID, 영웅, 점수, 진행도, 앱 버전, 갱신 시각)를 보관합니다.</li>
<li>읽기는 공개이며 쓰기는 소유 계정만 가능하고, 점수는 올라가기만 하며 순위는 점수에서 계산되어 동점은 같은 순위를 공유합니다.</li>
<li>전당 기록에 이름, 이메일, 계정 참조, 토큰, 저장은 들어가지 않습니다.</li>
</ul>`,
    },
    {
      id: 'deletion',
      num: '6',
      h: '삭제',
      html: `<ul class="tight">
<li>클라우드 계정은 게임의 계정 설정에서 삭제합니다. 삭제는 전당 기록, 클라우드 저장, 예약, 프로필을 하나의 검증된 단계로 먼저 함께 지우고, 그 확인 뒤에 로그인 자체를 삭제합니다.</li>
<li>iOS에서 Apple 연결 계정을 삭제할 때는 Apple 로그인 화면으로 다시 확인할 수 있습니다.</li>
<li>로그아웃하면 로그인 세션이 끝나고 새 게스트 ID로 바뀝니다. 기기와 클라우드 어디에서도 아무것도 지우지 않습니다.</li>
<li>클라우드 계정을 삭제하면 클라우드 기록과 로그인이 지워지지만, 이미 기기에 있는 파일 — 로컬 저장과 기기 안의 계정 목록 — 은 게임을 지우거나 저장소를 비우기 전까지 남습니다.</li>
<li>계정·체크포인트·전당 기록에는 자동으로 지워지는 기한이 없습니다. 계정을 삭제하기 전까지 남습니다.</li>
<li><a href="${mailto}">${SUPPORT_EMAIL}</a>로 이메일하면 내 정보의 열람·정정·삭제를 요청할 수 있습니다. 플레이어 ID를 함께 보내 주세요.</li>
<li>고객지원 요청은 플레이어 ID로 기록과 대조합니다. 구매 기록에 관한 삭제 요청은 구매 검증 처리 업체에 전달됩니다.</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '7',
      h: '게스트와 오프라인',
      html: `<ul class="tight">
<li>게스트 플레이는 기기 전용 게스트로 오프라인에서도 되며 클라우드 등록 계정으로 표시되지 않습니다.</li>
<li>백그라운드 가입이 실패하거나 로그인 설정이 없는 빌드에서도 플레이는 계속됩니다. 로그인 설정이 없는 빌드는 등록을 시도하지 않고 오류도 내지 않습니다.</li>
<li>로그인, 클라우드 저장, 전당, 상점, 구매 검증에는 인터넷 연결이 필요합니다.</li>
</ul>`,
    },
    {
      id: 'analytics',
      num: '8',
      h: '분석',
      html: `<p>선택형 게임플레이 분석은 출시 빌드의 내보내기 설정과 기본 꺼짐인 설정 명시 동의가 모두 맞아야 동작하며, 그 전까지는 꺼져 있습니다.</p>`,
    },
    {
      id: 'purchases',
      num: '9',
      h: '구매',
      html: `<ul class="tight">
<li>스토어 영수증은 <a href="${LINKS.iapkitDocs}">IAPKit 구매 검증 서비스</a>로 확인합니다. 검증을 위해 스토어·상품 정보와 영수증 또는 토큰(Apple 서명 JWS 또는 Google 구매 토큰)을 보냅니다.</li>
<li>검증 기록에는 거래·주문 식별자, 스토어 응답, 요청 IP, 검증 결과, 처리 시간이 남을 수 있습니다. 처리는 권한 부여·복원·회수, 환불, 부정·증복 방지, 진단, 서비스 통계에 쓰입니다.</li>
<li>서비스 통계를 위해 IAPKit이 프로젝트 첫 유효 영수증 사건과 스토어 종류를 Mixpanel에 보낼 수 있습니다. 그 사건에는 구매 토큰, 거래 ID, IP가 들어가지 않습니다. IAPKit의 기반 시설은 Convex가 맡습니다. 각 방침: <a href="${LINKS.iapkitPrivacy}">IAPKit</a>, <a href="${LINKS.convexPrivacy}">Convex</a>, <a href="${LINKS.mixpanelPrivacy}">Mixpanel</a>. 이 제3자 서비스 통계는 게임의 선택형 게임플레이 분석과 별개이며, 분석은 설정에서 켜야 동작합니다.</li>
<li>앱과 개발자는 카드 정보나 스토어 계정 비밀번호를 받지 않습니다. 키·서명·구매 토큰은 로그나 오류 메시지에 남지 않습니다.</li>
<li>스토어 측 구매 처리는 각 스토어 방침을 따릅니다: <a href="${LINKS.applePrivacy}">Apple</a>, <a href="${LINKS.googlePrivacy}">Google</a>.</li>
</ul>`,
    },
    {
      id: 'support-requests',
      num: '10',
      h: '고객지원 요청',
      html: `<ul class="tight">
<li>고객지원에 이메일하면 요청 해결을 위해 이메일 주소, 메시지, 직접 고른 첨부파일을 이메일 서비스 제공자와 함께 처리합니다.</li>
<li>지원 요청은 해결과 법적 의무에 필요한 동안만 둡니다.</li>
<li>구매와 관련되면 기록을 찾는 데 필요한 최소한의 주문 정보만 묻습니다. 영수증 전체, 비밀번호, 인증 코드는 묻지 않습니다.</li>
<li>제공자는 복원·환불·부정 방지·통계·회계·법적 의무에 필요한 만큼 검증 기록을 둡니다. 일률적인 파기 기한은 없습니다.</li>
<li>법이 두게 한 기록은 남을 수 있고, 처리 업체가 가진 기록에 대한 요청은 업체에 전달할 수 있습니다.</li>
<li>지원 요청과 위의 검증 처리는 거주 국가 밖에서 처리될 수 있습니다.</li>
</ul>`,
    },
    {
      id: 'changes',
      num: '11',
      h: '방침 변경',
      html: `<p>데이터 처리 방식이 바뀌면 이 페이지를 새 버전과 함께 고칩니다. 이 판은 버전 4.0.0을 다룹니다.</p>`,
    },
  ],

  supportTitle: '고객지원 — 달빛 봉화',
  supportLede: '구매, 계정, 저장, 전당에 대한 도움말입니다.',
  supportSections: [
    {
      id: 'contact',
      num: '1',
      h: '문의',
      html: `<ul class="tight">
<li><a href="${mailto}">${SUPPORT_EMAIL}</a>로 이메일해 주세요. 플레이어 ID(<code>MB-</code>&#8230;, 게임 계정 화면에 표시), 기기 종류와 OS 버전, 어떤 일이 있었는지 적어 주세요.</li>
<li>비밀번호, 구매 토큰, 인증 코드는 보내지 마세요. 고객지원이 묻지도 않습니다.</li>
<li>버그 제보는 <a href="${LINKS.issues}">GitHub Issues</a>도 환영합니다.</li>
</ul>`,
    },
    {
      id: 'products',
      num: '2',
      h: '현재 상품',
      html: `<p>상점은 10종을 팝니다. 영구 소장 1회성 7종과 이어하기 코인 묶음 3종입니다.</p>
%%PRODUCT_TABLE%%
<ul class="tight">
<li>영구 상품은 스토어 계정에 남아 재설치 후에도 구매 복원으로 돌아옵니다.</li>
<li>코인 묶음은 1개·5개·10개를 줍니다. 코인 하나를 쓰면 쓰러진 자리에서 점수·레벨·유물을 유지하고 이어갑니다. 사용한 코인은 복원되지 않으며, 검증과 소모 처리가 끝나면 같은 묶음을 다시 살 수 있습니다.</li>
<li>가격과 세금은 각 스토어 표시를 따릅니다.</li>
</ul>`,
    },
    {
      id: 'restore',
      num: '3',
      h: '구매 복원과 게임 계정 로그인',
      html: `<ul class="tight">
<li>구매 복원(상점 하단)은 같은 스토어 계정(같은 Apple 계정, 같은 Google Play 계정)에서 재설치 후나 새 기기에서 영구 7종을 되찾습니다. 스토어와 검증 서비스 연결이 필요합니다.</li>
<li>게임 계정 로그인(달빛 문의 Google·Apple)은 클라우드 저장과 전당 기록을 되찾습니다. 둘은 별개입니다. 로그인해도 구매가 복원되지 않고, 복원해도 로그인되지 않습니다.</li>
<li>상점을 여는 데 로그인은 필요 없습니다. 타이틀에서 상점을 열면 상품이 보이고 구매 복원은 언제나 보입니다.</li>
</ul>`,
    },
    {
      id: 'guests',
      num: '4',
      h: '게스트와 잃은 진행',
      html: `<ul class="tight">
<li>게스트 진행은 기기 전용입니다. 로그인 없이 재설치하거나 기기를 바꾸면 사라집니다.</li>
<li>Google·Apple로 로그인하면 체크포인트의 클라우드 사본이 남습니다.</li>
<li>로그아웃하면 이전 ID와 저장은 기기에 남고 새 게스트가 시작됩니다. 같은 제공자로 다시 로그인하면 그 계정의 ID와 보관된 저장으로 돌아갑니다.</li>
<li>연결하지 않은 로컬 데이터는 재설치하거나 저장소를 지우면 사라질 수 있습니다(약관).</li>
</ul>`,
    },
    {
      id: 'conflicts',
      num: '5',
      h: '클라우드 충돌',
      html: `<p>클라우드 사본이 다르면 양쪽을 보여 주고 덮어쓰기 전에 어느 쪽을 쓸지 묻습니다.</p>`,
    },
    {
      id: 'refunds',
      num: '6',
      h: '환불',
      html: `<ul class="tight">
<li>구매는 각 스토어의 결제·복원·환불 절차를 따르며, 이 게임이 별도 수수료나 환불 기한을 두지 않습니다.</li>
<li>Apple 구매: Apple 공식 <a href="${LINKS.appleRefund}">문제 신고</a> 페이지에서 요청하세요.</li>
<li>Google Play 구매: Google Play 공식 <a href="${LINKS.googleRefund}">환불 도움말</a>에서 요청하세요.</li>
<li>환불이 확정되면 그 구매 권한만 회수되고 다른 영구 상품은 남습니다.</li>
</ul>`,
    },
    {
      id: 'offline',
      num: '7',
      h: '연결과 오프라인',
      html: `<ul class="tight">
<li>기본 플레이와 로컬 기록은 게스트로 오프라인에서도 됩니다.</li>
<li>상품 조회, 구매, 구매 검증, 로그인, 클라우드 저장, 전당에는 인터넷 연결이 필요합니다.</li>
<li>광고는 없습니다.</li>
</ul>`,
    },
    {
      id: 'privacy',
      num: '8',
      h: '개인정보',
      html: `<ul class="tight">
<li>계정·저장·전당 처리 방식: <a href="/ko/privacy">개인정보처리방침</a>.</li>
<li>제공자 방침: <a href="${LINKS.firebasePrivacy}">Firebase</a>, <a href="${LINKS.googlePrivacy}">Google</a>, <a href="${LINKS.applePrivacy}">Apple</a>.</li>
</ul>`,
    },
  ],

  tableCaption: '상점에서 파는 10종 전부입니다.',
  thItem: '상품',
  thType: '종류',
  thGrant: '획득 내용',
  typePermanent: '영구 소장',
  typeConsumable: '소모성',
  grantSupporter: '설정 › 크레딧의 이름 옆에 후원자 표식을 영구히 남깁니다.',
  grantHero: '달빛 제단에서 이 영웅을 영구히 해금합니다. 균형형 대안입니다.',
  grantLantern: '불씨·달빛·보랏빛·비취빛 불꽃. 꾸미기 전용입니다.',
  grantCoins: (count) => `코인 ${count}개를 잔액에 더합니다.`,

  footerContact: '문의',
  footerRights: '\u00a9 2026 Hyo Jang. Hyo Dev의 달빛 봉화.',
};
