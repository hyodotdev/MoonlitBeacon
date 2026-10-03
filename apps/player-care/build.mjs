// Player-care static site generator and checker. No dependencies.
//
//   node apps/player-care/build.mjs              # render dist/
//   node apps/player-care/build.mjs --check      # rebuild to temp, verify, compare with dist/
//   node apps/player-care/build.mjs --out DIR    # render to DIR (tests use this)
//
// Product names/descriptions always come from notes/release/store-localizations.csv,
// so the support tables match the current catalog on every build.
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  COIN_GRANTS,
  CSV_LOCALES,
  DOCS_MOUNT,
  DOCS_PREFIX,
  HREFLANG,
  LINKS,
  LOCALES,
  PERMANENT_IDS,
  PRODUCT_ORDER,
  SITE_BASE,
  SUPPORT_EMAIL,
} from './content/shared.mjs';

const APP_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = dirname(APP_DIR);
const CSV_PATH = join(REPO_ROOT, '..', 'notes', 'release', 'store-localizations.csv');
const DIST_DIR = join(APP_DIR, 'dist');

const CONTENT_MODULES = Object.fromEntries(
  LOCALES.map((locale) => [locale, `./content/${locale}.mjs`]),
);

export async function loadContent() {
  const content = {};
  for (const locale of LOCALES) {
    const module = await import(CONTENT_MODULES[locale]);
    content[locale] = module.CONTENT;
  }
  return content;
}

export function escapeHtml(value) {
  return String(value)
    .replace(/&/gu, '&amp;')
    .replace(/</gu, '&lt;')
    .replace(/>/gu, '&gt;')
    .replace(/"/gu, '&quot;');
}

// Minimal RFC-4180 reader: quoted cells, escaped quotes, embedded newlines.
export function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i += 2;
        } else {
          quoted = false;
          i += 1;
        }
      } else {
        cell += ch;
        i += 1;
      }
    } else if (ch === '"') {
      quoted = true;
      i += 1;
    } else if (ch === ',') {
      row.push(cell);
      cell = '';
      i += 1;
    } else if (ch === '\n') {
      row.push(cell);
      cell = '';
      rows.push(row);
      row = [];
      i += 1;
    } else if (ch === '\r') {
      i += 1;
    } else {
      cell += ch;
      i += 1;
    }
  }
  if (cell !== '' || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }
  return rows.filter((candidate) => candidate.length > 1 || candidate[0] !== '');
}

// Products per site locale from the live catalog. Both platforms must agree
// on name/description/type for the same product and locale.
export function loadProducts(csvText) {
  const rows = parseCsv(csvText);
  const header = rows[0];
  const byName = Object.fromEntries(header.map((name, index) => [name, index]));
  const records = rows.slice(1).map((cells) => Object.fromEntries(
    header.map((name, index) => [name, cells[index] ?? '']),
  ));
  const products = {};
  for (const locale of LOCALES) {
    products[locale] = PRODUCT_ORDER.map((productId) => {
      const matches = records.filter(
        (record) => record.record_type === 'iap'
          && record.product_id === productId
          && CSV_LOCALES[locale].includes(record.locale),
      );
      if (matches.length === 0) {
        throw new Error(`catalog has no ${locale} row for ${productId}`);
      }
      const first = matches[0];
      for (const match of matches) {
        for (const key of ['product_type', 'display_name', 'description']) {
          if (match[key] !== first[key]) {
            throw new Error(`catalog disagrees on ${productId} ${locale} ${key}`);
          }
        }
      }
      return {
        id: productId,
        type: first.product_type,
        name: first.display_name,
        desc: first.description,
      };
    });
  }
  return products;
}

function grantText(content, product) {
  if (product.id.endsWith('.supporter')) return content.grantSupporter;
  if (product.id.endsWith('.lantern_colors')) return content.grantLantern;
  if (product.id.includes('.hero_')) return content.grantHero;
  return content.grantCoins(COIN_GRANTS[product.id]);
}

export function productTable(content, products) {
  const rows = products.map((product) => {
    const type = PERMANENT_IDS.has(product.id)
      ? content.typePermanent
      : content.typeConsumable;
    return `    <tr><td><strong>${escapeHtml(product.name)}</strong><span class="desc">${escapeHtml(product.desc)}</span></td><td>${escapeHtml(type)}</td><td>${escapeHtml(grantText(content, product))}</td></tr>`;
  }).join('\n');
  return `<div class="table-scroll"><table>
<caption>${escapeHtml(content.tableCaption)}</caption>
<thead><tr><th scope="col">${escapeHtml(content.thItem)}</th><th scope="col">${escapeHtml(content.thType)}</th><th scope="col">${escapeHtml(content.thGrant)}</th></tr></thead>
<tbody>
${rows}
</tbody>
</table></div>`;
}

function alternates(kind) {
  // kind: 'privacy' | 'support' | 'index'
  const links = LOCALES.map((locale) => {
    const path = kind === 'index' ? `/${locale}/` : `/${locale}/${kind}`;
    return `<link rel="alternate" hreflang="${HREFLANG[locale]}" href="${SITE_BASE}${path}">`;
  });
  const xDefault = kind === 'index' ? '/' : `/${kind}`;
  links.push(`<link rel="alternate" hreflang="x-default" href="${SITE_BASE}${xDefault}">`);
  return links.join('\n');
}

function navBlock(content, locale, current) {
  // current: 'home' | 'privacy' | 'support'
  const base = locale === null ? '' : `/${locale}`;
  const item = (key, label, path) => {
    const currentAttr = key === current ? ' aria-current="page"' : '';
    return `<li><a href="${base}${path}"${currentAttr}>${escapeHtml(label)}</a></li>`;
  };
  // The course/reference link stays origin-absolute: the docs mount lives at
  // the combined site root, outside every locale subtree.
  const docsItem = `<li><a href="${DOCS_MOUNT}">${escapeHtml(content.navDocs)}</a></li>`;
  return `<nav aria-label="${escapeHtml(content.mainNavLabel)}"><ul>
${item('home', content.navHome, '/')}
${item('privacy', content.navPrivacy, '/privacy')}
${item('support', content.navSupport, '/support')}
${docsItem}
</ul></nav>`;
}

function languageNav(content, locale, pagePath) {
  // pagePath: '' (index) | 'privacy' | 'support'; links to the same page.
  const items = LOCALES.map((target) => {
    const href = pagePath === '' ? `/${target}/` : `/${target}/${pagePath}`;
    const currentAttr = target === locale ? ' aria-current="page"' : '';
    return `<li><a href="${href}"${currentAttr} hreflang="${HREFLANG[target]}">${escapeHtml(content.languageNames[target])}</a></li>`;
  }).join('\n');
  return `<nav class="lang-nav" aria-label="${escapeHtml(content.navLanguageLabel)}"><p>${escapeHtml(content.navLanguageLabel)}</p><ul>
${items}
</ul></nav>`;
}

function footerBlock(content) {
  return `<footer><p>${escapeHtml(content.footerContact)}: <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a></p><p>${escapeHtml(content.footerRights)}</p></footer>`;
}

function sectionsHtml(sections, tableHtml) {
  return sections.map((section) => {
    const body = tableHtml === null
      ? section.html
      : section.html.replace('%%PRODUCT_TABLE%%', tableHtml);
    if (body.includes('%%PRODUCT_TABLE%%')) {
      throw new Error(`unresolved product table in section ${section.id}`);
    }
    return `<section aria-labelledby="${section.id}"><h2 id="${section.id}"><span class="num" aria-hidden="true">${escapeHtml(section.num)}</span>${escapeHtml(section.h)}</h2>
${body}</section>`;
  }).join('\n');
}

function pageShell({
  lang, title, description, canonical, alternatesHtml, skipText,
  brandHref, brandName, brandSub, navHtml, langNavHtml, mainHtml, footerHtml,
}) {
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<link rel="canonical" href="${canonical}">
${alternatesHtml}
<link rel="stylesheet" href="/styles.css">
</head>
<body>
<a class="skip" href="#main">${escapeHtml(skipText)}</a>
<div class="wrap">
<header class="site-head">
<a class="brand" href="${brandHref}"><span class="brand-mark" aria-hidden="true"></span><span><span class="brand-name">${escapeHtml(brandName)}</span><span class="brand-sub">${escapeHtml(brandSub)}</span></span></a>
${navHtml}
${langNavHtml}
</header>
<main id="main">
${mainHtml}
</main>
${footerHtml}
</div>
</body>
</html>
`;
}

function articleMain(content, title, lede, updated, sectionsHtmlText) {
  return `<h1>${escapeHtml(title)}</h1>
<p class="lede">${escapeHtml(lede)}</p>
<p class="updated">${escapeHtml(updated)}</p>
${sectionsHtmlText}`;
}

function chooserMain(content, heading, links) {
  const items = links.map(([href, label]) => (
    `<li><a href="${href}">${escapeHtml(label)}<span class="go" aria-hidden="true">&rarr;</span></a></li>`
  )).join('\n');
  return `<h1>${escapeHtml(heading)}</h1>
<p class="lede">${escapeHtml(content.homeLede)}</p>
<ul class="link-list">
${items}
</ul>
<p>${content.homeContact}</p>`;
}

export async function renderPages() {
  const content = await loadContent();
  const csvText = readFileSync(CSV_PATH, 'utf8');
  const products = loadProducts(csvText);
  const pages = new Map(); // clean route -> { file bodies per output path, lang }

  const emit = (cleanRoute, outputs, body) => {
    pages.set(cleanRoute, { outputs, body });
  };

  // Root chooser (English, x-default).
  {
    const en = content.en;
    const links = [];
    for (const locale of LOCALES) {
      links.push([`/${locale}/privacy`, `${content[locale].navPrivacy} (${content[locale].languageNames[locale]})`]);
    }
    for (const locale of LOCALES) {
      links.push([`/${locale}/support`, `${content[locale].navSupport} (${content[locale].languageNames[locale]})`]);
    }
    const main = chooserMain(en, en.homeTitle, links);
    const nav = navBlock(en, null, 'home');
    const lang = languageNav(en, 'en', '');
    emit('/', ['index.html'], pageShell({
      lang: 'en',
      title: en.homeTitle,
      description: en.homeLede,
      canonical: `${SITE_BASE}/`,
      alternatesHtml: alternates('index'),
      skipText: en.skip,
      brandHref: '/',
      brandName: en.gameName,
      brandSub: en.homeName,
      navHtml: nav,
      langNavHtml: lang,
      mainHtml: main,
      footerHtml: footerBlock(en),
    }));
  }

  // x-default privacy/support: full English policy bodies.
  for (const kind of ['privacy', 'support']) {
    const en = content.en;
    const title = kind === 'privacy' ? en.privacyTitle : en.supportTitle;
    const lede = kind === 'privacy' ? en.privacyLede : en.supportLede;
    const sections = kind === 'privacy' ? en.privacySections : en.supportSections;
    const table = kind === 'support' ? productTable(en, products.en) : null;
    const main = articleMain(en, title, lede, en.updated, sectionsHtml(sections, table));
    const nav = navBlock(en, null, kind);
    const lang = languageNav(en, 'en', kind);
    emit(`/${kind}`, [`${kind}.html`, `${kind}/index.html`], pageShell({
      lang: 'en',
      title,
      description: lede,
      canonical: `${SITE_BASE}/${kind}`,
      alternatesHtml: alternates(kind),
      skipText: en.skip,
      brandHref: '/',
      brandName: en.gameName,
      brandSub: en.homeName,
      navHtml: nav,
      langNavHtml: lang,
      mainHtml: main,
      footerHtml: footerBlock(en),
    }));
  }

  // Locale indexes and the 10 localized pages.
  for (const locale of LOCALES) {
    const strings = content[locale];
    const indexMain = chooserMain(strings, `${strings.gameName} — ${strings.homeName}`, [
      [`/${locale}/privacy`, strings.navPrivacy],
      [`/${locale}/support`, strings.navSupport],
    ]);
    const indexNav = navBlock(strings, locale, 'home');
    const indexLang = languageNav(strings, locale, '');
    emit(`/${locale}/`, [`${locale}.html`, `${locale}/index.html`], pageShell({
      lang: strings.lang,
      title: strings.homeTitle,
      description: strings.homeLede,
      canonical: `${SITE_BASE}/${locale}/`,
      alternatesHtml: alternates('index'),
      skipText: strings.skip,
      brandHref: `/${locale}/`,
      brandName: strings.gameName,
      brandSub: strings.homeName,
      navHtml: indexNav,
      langNavHtml: indexLang,
      mainHtml: indexMain,
      footerHtml: footerBlock(strings),
    }));

    for (const kind of ['privacy', 'support']) {
      const title = kind === 'privacy' ? strings.privacyTitle : strings.supportTitle;
      const lede = kind === 'privacy' ? strings.privacyLede : strings.supportLede;
      const sections = kind === 'privacy' ? strings.privacySections : strings.supportSections;
      const table = kind === 'support' ? productTable(strings, products[locale]) : null;
      const main = articleMain(strings, title, lede, strings.updated, sectionsHtml(sections, table));
      const nav = navBlock(strings, locale, kind);
      const langNav = languageNav(strings, locale, kind);
      emit(`/${locale}/${kind}`, [`${locale}/${kind}.html`, `${locale}/${kind}/index.html`], pageShell({
        lang: strings.lang,
        title,
        description: lede,
        canonical: `${SITE_BASE}/${locale}/${kind}`,
        alternatesHtml: alternates(kind),
        skipText: strings.skip,
        brandHref: `/${locale}/`,
        brandName: strings.gameName,
        brandSub: strings.homeName,
        navHtml: nav,
        langNavHtml: langNav,
        mainHtml: main,
        footerHtml: footerBlock(strings),
      }));
    }
  }

  // Not-found page (English, links every locale index).
  {
    const en = content.en;
    const links = LOCALES.map((locale) => [`/${locale}/`, `${content[locale].gameName} (${content[locale].languageNames[locale]})`]);
    links.unshift(['/', 'Home']);
    const main = `<h1>Page not found</h1>
<p class="lede">This address has no privacy or support page. Start from a language below.</p>
<ul class="link-list">
${links.map(([href, label]) => `<li><a href="${href}">${escapeHtml(label)}<span class="go" aria-hidden="true">&rarr;</span></a></li>`).join('\n')}
</ul>`;
    emit('/404.html', ['404.html'], pageShell({
      lang: 'en',
      title: 'Page not found — Moonlit Beacon',
      description: 'This address has no privacy or support page.',
      canonical: `${SITE_BASE}/404.html`,
      alternatesHtml: alternates('index'),
      skipText: en.skip,
      brandHref: '/',
      brandName: en.gameName,
      brandSub: en.homeName,
      navHtml: navBlock(en, null, 'home'),
      langNavHtml: languageNav(en, 'en', ''),
      mainHtml: main,
      footerHtml: footerBlock(en),
    }));
  }

  return { pages, products, content };
}

export function expectedOutputs(pages) {
  const outputs = ['styles.css'];
  for (const { outputs: pageOutputs } of pages.values()) {
    outputs.push(...pageOutputs);
  }
  return outputs.sort();
}

export async function build(outDir) {
  const { pages } = await renderPages();
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  for (const { outputs, body } of pages.values()) {
    for (const output of outputs) {
      const target = join(outDir, output);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, body, 'utf8');
    }
  }
  const css = readFileSync(join(APP_DIR, 'styles.css'), 'utf8');
  writeFileSync(join(outDir, 'styles.css'), css, 'utf8');
  return pages;
}

// ---------------------------------------------------------------------------
// Checks. checkBuilt() throws one Error listing every problem found.
// ---------------------------------------------------------------------------

// The banned lesson term is spelled with a join so this file does not match
// its own needle (same split-needle trick as check-hygiene.mjs AUTHOR_HOME).
const BANNED_TERM = new RegExp(`\\bphas${'e'}\\b`, 'i');

const FORBIDDEN = [
  [BANNED_TERM, 'banned lesson term'],
  [/no accounts?/i, 'stale no-account framing'],
  [/global (board|ladder)/i, 'stale global board/ladder framing'],
  [/\bdisabl\w*\b/i, 'stale disabled-service framing'],
  [/all [^<>{}]{0,30}non-?consumable/i, 'stale all-nonconsumable framing'],
  [/three permanent items/i, 'stale three-item framing'],
  [/\b3 permanent items/i, 'stale three-item framing'],
  [/bundle/i, 'legacy bundle reference'],
  [/hero_bundle/i, 'legacy bundle SKU'],
  [/audit item/i, 'internal audit note published as player copy'],
  [/device proof/i, 'internal audit note published as player copy'],
  [/proof is pending/i, 'internal audit note published as player copy'],
  [/pending evidence/i, 'internal audit note published as player copy'],
  [/\b\d+\s*-?\s*days?\b/i, 'invented day-count deadline'],
  [/all identifiers/i, 'blanket identifier claim'],
  [/every identifier/i, 'blanket identifier claim'],
  [/never leaves your (device|phone)/i, 'false on-device-only claim'],
  [/we (never|do not) collect/i, 'false no-collection claim'],
  [/TODO|FIXME/i, 'unfinished marker'],
  [/lorem ipsum/i, 'placeholder text'],
  [/placeholder/i, 'placeholder text'],
  [/\{locale\}/, 'unsubstituted locale template'],
  [/<script/i, 'embedded script'],
  [/<form/i, 'embedded form'],
  [/javascript:/i, 'script URL'],
  [/ on[a-z]+=("|')/i, 'inline event handler'],
  [/http:\/\//i, 'insecure link'],
  [/\.chatgpt\.site/i, 'old support site reference'],
  [/web\.app/i, 'default Firebase site URL in player copy'],
  [/moonlitbeacon-778ee/i, 'Firebase project identifier in player copy'],
];

const PRIVACY_COMMON = [
  'MB-',
  'Google',
  'Apple',
  'Firebase',
  'IAPKit',
  SUPPORT_EMAIL,
  '4.0.0',
  LINKS.iapkitDocs,
  LINKS.iapkitPrivacy,
  LINKS.convexPrivacy,
  LINKS.mixpanelPrivacy,
  LINKS.firebasePrivacy,
  LINKS.googlePrivacy,
  LINKS.applePrivacy,
  'Mixpanel',
  'Convex',
];

const PRIVACY_LOCALE = {
  en: ['Hall', 'delet', 'anonymous', 'not offered', 'no configured automatic expiry', 'SDK', 'forwarded to the purchase-verification processor', 'excludes the purchase token, transaction ID, and IP', 'minimum order detail', 'outside your country'],
  ko: ['전당', '삭제', '익명', '제공하지 않습니다', '자동으로 지워지는 기한', 'SDK', '구매 검증 처리 업체', '구매 토큰, 거래 ID, IP가 들어가지 않습니다', '최소한의 주문 정보', '거주 국가 밖'],
  ja: ['殿堂', '削除', '匿名', '提供しません', '自動で消える期限', 'SDK', '購入確認サービスへ渡', '購入トークン、取引ID、IPは入りません', '最小限の注文情報', '国の外'],
  'zh-Hans': ['殿堂', '删除', '匿名', '不提供', '自动到期', 'SDK', '购买验证处理方', '不含购买令牌', '最少订单信息', '国家之外'],
  'zh-Hant': ['殿堂', '刪除', '匿名', '不提供', '自動到期', 'SDK', '購買驗證處理方', '不含購買權杖', '最少訂單資訊', '國家之外'],
};

const SUPPORT_COMMON = [
  SUPPORT_EMAIL,
  LINKS.appleRefund,
  LINKS.googleRefund,
  LINKS.issues,
];

const SUPPORT_LOCALE = {
  en: ['Restore purchases', 'Hall', '1, 5, or 10', 'stay with your store account'],
  ko: ['구매 복원', '전당', '1개·5개·10개', '스토어 계정에 남아'],
  ja: ['購入の復元', '殿堂', '1枚・5枚・10枚', 'ストアのアカウントに残り'],
  'zh-Hans': ['恢复购买', '殿堂', '1、5、10', '归属商店账号'],
  'zh-Hant': ['恢復購買', '殿堂', '1、5、10', '歸屬商店帳號'],
};

const OUTBOUND_ALLOWLIST = new Set(Object.values(LINKS));

const BALANCED_TAGS = ['html', 'head', 'body', 'header', 'main', 'footer', 'nav', 'table', 'ul'];

function routeLang(cleanRoute) {
  if (cleanRoute === '/' || cleanRoute === '/privacy' || cleanRoute === '/support') return 'en';
  if (cleanRoute === '/404.html') return 'en';
  const segment = cleanRoute.split('/')[1];
  return LOCALES.includes(segment) ? segment : null;
}

function resolveLocalLink(fromFile, href) {
  // Returns the dist-relative target path, or null for non-file links.
  if (href.startsWith('#') || href === '') return null;
  const path = href.split('#')[0].split('?')[0];
  if (path === '') return null;
  let target;
  if (path.startsWith('/')) {
    target = path.slice(1);
  } else {
    const fromDir = dirname(fromFile);
    target = fromDir === '.' ? path : `${fromDir}/${path}`;
  }
  const parts = [];
  for (const segment of target.split('/')) {
    if (segment === '' || segment === '.') continue;
    if (segment === '..') {
      if (parts.length === 0) return null;
      parts.pop();
    } else {
      parts.push(segment);
    }
  }
  const normalized = parts.join('/');
  if (normalized === '') return 'index.html';
  if (normalized.endsWith('/')) return `${normalized}index.html`;
  if (normalized.includes('.')) return normalized;
  return `${normalized}.html`;
}

export function isDocsMountTarget(target) {
  // The docs mount ships only in the combined hosting output, where the
  // hosting checker resolves it against the real docs build. Narrow to this
  // one prefix: nothing else skips local resolution here.
  const mountRoot = `${DOCS_PREFIX.slice(0, -1)}.html`;
  return target === mountRoot || target.startsWith(DOCS_PREFIX);
}

export async function checkBuilt(outDir) {
  const problems = [];
  const { pages, products, content } = await renderPages();

  const expected = new Set(expectedOutputs(pages));

  // 1. Every expected file exists; nothing unexpected sits beside them.
  const actualFiles = [];
  const collect = (dir) => {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      if (statSync(full).isDirectory()) collect(full);
      else actualFiles.push(relative(outDir, full).split(sep).join('/'));
    }
  };
  collect(outDir);
  const actual = new Set(actualFiles);
  for (const file of [...expected].sort()) {
    if (!actual.has(file)) problems.push(`missing route file: ${file}`);
  }
  for (const file of [...actual].sort()) {
    if (!expected.has(file)) problems.push(`unexpected file in output: ${file}`);
  }

  // 2. Dual-layout routes are byte-identical.
  for (const [cleanRoute, { outputs, body }] of pages) {
    if (outputs.length < 2) continue;
    const bodies = outputs.map((output) => {
      const full = join(outDir, output);
      return existsSync(full) ? readFileSync(full, 'utf8') : null;
    });
    for (let index = 1; index < bodies.length; index += 1) {
      if (bodies[index] !== bodies[0]) {
        problems.push(`dual layout differs: ${outputs[0]} vs ${outputs[index]} (${cleanRoute})`);
      }
    }
    if (bodies[0] !== null && bodies[0] !== body) {
      problems.push(`stale output: ${outputs[0]} does not match a fresh render`);
    }
  }
  // Single-output routes must also match a fresh render.
  for (const [cleanRoute, { outputs, body }] of pages) {
    if (outputs.length !== 1) continue;
    const full = join(outDir, outputs[0]);
    if (existsSync(full) && readFileSync(full, 'utf8') !== body) {
      problems.push(`stale output: ${outputs[0]} does not match a fresh render (${cleanRoute})`);
    }
  }

  // 3. Per-page structure, forbidden patterns, required content, links.
  const htmlFiles = actualFiles.filter((file) => file.endsWith('.html')).sort();
  for (const file of htmlFiles) {
    const where = `${file}`;
    const text = readFileSync(join(outDir, file), 'utf8');
    const cleanRoute = [...pages].find(([, value]) => value.outputs.includes(file))?.[0] ?? file;
    const expectedLang = routeLang(cleanRoute);
    if (!text.startsWith('<!doctype html>')) {
      problems.push(`${where}: missing doctype`);
    }
    if (expectedLang !== null && !text.includes(`<html lang="${expectedLang}">`)) {
      problems.push(`${where}: expected <html lang="${expectedLang}">`);
    }
    if (!text.includes('<meta name="viewport" content="width=device-width, initial-scale=1">')) {
      problems.push(`${where}: missing viewport meta`);
    }
    if (!/<title>[^<]+<\/title>/u.test(text)) {
      problems.push(`${where}: missing title`);
    }
    if (!text.includes('class="skip"')) {
      problems.push(`${where}: missing skip link`);
    }
    if (!text.includes(`<link rel="canonical" href="${SITE_BASE}`)) {
      problems.push(`${where}: missing canonical URL`);
    }
    for (const tag of BALANCED_TAGS) {
      const opens = (text.match(new RegExp(`<${tag}(\\s|>)`, 'gu')) ?? []).length;
      const closes = (text.match(new RegExp(`</${tag}>`, 'gu')) ?? []).length;
      if (opens !== closes || (tag === 'main' && opens !== 1)) {
        problems.push(`${where}: <${tag}> opens ${opens}, closes ${closes}`);
      }
    }
    for (const [pattern, label] of FORBIDDEN) {
      if (pattern.test(text)) problems.push(`${where}: ${label}`);
    }

    const strings = LOCALES.includes(expectedLang) ? content[expectedLang] : content.en;
    if (/\/privacy(\.html|\/index\.html)$/u.test(`/${file}`)) {
      for (const token of [...PRIVACY_COMMON, ...PRIVACY_LOCALE[strings.lang]]) {
        if (!text.includes(token)) problems.push(`${where}: privacy page lacks "${token}"`);
      }
    }
    if (/support(\.html|\/index\.html)$/u.test(file)) {
      for (const token of [...SUPPORT_COMMON, ...SUPPORT_LOCALE[strings.lang]]) {
        if (!text.includes(token)) problems.push(`${where}: support page lacks "${token}"`);
      }
      for (const product of products[strings.lang]) {
        if (!text.includes(product.name)) {
          problems.push(`${where}: support page lacks product "${product.name}"`);
        }
        if (!text.includes(product.desc)) {
          problems.push(`${where}: support page lacks description for "${product.name}"`);
        }
      }
      for (const count of [1, 5, 10]) {
        const grant = strings.grantCoins(count);
        if (!text.includes(grant)) problems.push(`${where}: support page lacks coin grant "${grant}"`);
      }
      const permanentCount = (text.match(new RegExp(strings.typePermanent.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&'), 'gu')) ?? []).length;
      if (permanentCount < 7) {
        problems.push(`${where}: expected 7 permanent rows, found ${permanentCount}`);
      }
    }

    // Links: local targets must resolve; outbound must be allowlisted.
    for (const match of text.matchAll(/(?:href|src)="([^"]+)"/gu)) {
      const href = match[1];
      if (href.startsWith('#')) continue;
      if (href.startsWith('mailto:')) {
        if (href !== `mailto:${SUPPORT_EMAIL}`) {
          problems.push(`${where}: unexpected mailto ${href}`);
        }
        continue;
      }
      if (href.startsWith(SITE_BASE)) {
        const target = resolveLocalLink(file, href.slice(SITE_BASE.length) || '/');
        if (target !== null && isDocsMountTarget(target)) continue;
        if (target === null || !existsSync(join(outDir, target))) {
          problems.push(`${where}: same-origin link target missing: ${href}`);
        }
        continue;
      }
      if (href.startsWith('https://')) {
        if (!OUTBOUND_ALLOWLIST.has(href)) {
          problems.push(`${where}: outbound link not allowlisted: ${href}`);
        }
        continue;
      }
      const target = resolveLocalLink(file, href);
      if (target !== null && isDocsMountTarget(target)) continue;
      if (target === null) {
        problems.push(`${where}: link escapes output: ${href}`);
      } else if (!existsSync(join(outDir, target))) {
        problems.push(`${where}: local link target missing: ${href} -> ${target}`);
      }
    }
  }

  // 4. Hosting configuration stays narrow and scoped.
  const hostingPath = join(APP_DIR, 'firebase.json');
  const firebasercPath = join(APP_DIR, '.firebaserc');
  if (!existsSync(hostingPath) || !existsSync(firebasercPath)) {
    problems.push('firebase.json or .firebaserc is missing');
  } else {
    let hosting;
    let rc;
    try {
      hosting = JSON.parse(readFileSync(hostingPath, 'utf8'));
      rc = JSON.parse(readFileSync(firebasercPath, 'utf8'));
    } catch {
      problems.push('firebase.json or .firebaserc is not valid JSON');
      hosting = null;
    }
    if (hosting !== null) {
      const topKeys = Object.keys(hosting);
      if (topKeys.length !== 1 || topKeys[0] !== 'hosting') {
        problems.push(`firebase.json must be hosting-only, found keys: ${topKeys.join(',')}`);
      }
      const config = hosting.hosting ?? {};
      if (config.site !== 'moonlitbeacon-778ee') {
        problems.push('firebase.json hosting.site must be moonlitbeacon-778ee');
      }
      if (config.public !== 'dist') {
        problems.push('firebase.json hosting.public must be dist');
      }
      if (config.cleanUrls !== true) {
        problems.push('firebase.json hosting.cleanUrls must be true');
      }
      for (const key of Object.keys(config)) {
        if (!['site', 'public', 'ignore', 'cleanUrls', 'trailingSlash'].includes(key)) {
          problems.push(`firebase.json hosting key not allowed: ${key}`);
        }
      }
      if (rc?.projects?.default !== 'moonlitbeacon-778ee') {
        problems.push('.firebaserc default project must be moonlitbeacon-778ee');
      }
    }
  }

  if (problems.length > 0) {
    throw new Error(`player-care check failed — ${problems.length} problem(s):\n${problems.map((problem) => `  ${problem}`).join('\n')}`);
  }
  return { files: actualFiles.length, pages: pages.size };
}

export function compareTrees(freshDir, distDir, expected) {
  const mismatches = [];
  for (const file of expected) {
    const fresh = readFileSync(join(freshDir, file), 'utf8');
    const distPath = join(distDir, file);
    if (!existsSync(distPath)) {
      mismatches.push(`missing in dist: ${file}`);
    } else if (readFileSync(distPath, 'utf8') !== fresh) {
      mismatches.push(`bytes differ: ${file}`);
    }
  }
  return mismatches;
}

async function main(args) {
  if (args.includes('--check')) {
    const fresh = mkdtempSync(join(tmpdir(), 'player-care-'));
    try {
      const pages = await build(fresh);
      await checkBuilt(fresh);
      const mismatches = compareTrees(fresh, DIST_DIR, expectedOutputs(pages));
      if (mismatches.length > 0) {
        throw new Error(`dist/ is stale — rebuild with pnpm player-care:build:\n${mismatches.map((line) => `  ${line}`).join('\n')}`);
      }
      await checkBuilt(DIST_DIR);
      process.stdout.write(`player-care check ok — ${expectedOutputs(pages).length} files, 10 localized pages\n`);
    } finally {
      rmSync(fresh, { recursive: true, force: true });
    }
    return;
  }
  const outIndex = args.indexOf('--out');
  const outDir = outIndex >= 0 ? args[outIndex + 1] : DIST_DIR;
  if (outIndex >= 0 && !outDir) throw new Error('--out needs a directory');
  const pages = await build(outDir);
  process.stdout.write(`player-care build ok — ${expectedOutputs(pages).length} files -> ${relative(REPO_ROOT, outDir) || outDir}\n`);
}

const invokedAsScript = process.argv[1] !== undefined
  && pathToFileURL(process.argv[1]).href === import.meta.url;

if (invokedAsScript) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}

