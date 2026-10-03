// Player-care route/content/local-link regressions. Builds to temp dirs only;
// never reads or writes the committed dist/, so failures prove the generator
// or content wrong, not a dirty checkout.
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { build, checkBuilt, expectedOutputs, loadProducts, renderPages } from './build.mjs';
import { COIN_GRANTS, LINKS, LOCALES, PRODUCT_ORDER, SITE_BASE } from './content/shared.mjs';

const RETENTION_TOKENS = {
  en: 'no configured automatic expiry',
  ko: '자동으로 지워지는 기한',
  ja: '自動で消える期限',
  'zh-Hans': '自动到期',
  'zh-Hant': '自動到期',
};

const HANDLING_TOKENS = {
  en: 'forwarded to the purchase-verification processor',
  ko: '구매 검증 처리 업체',
  ja: '購入確認サービスへ渡',
  'zh-Hans': '购买验证处理方',
  'zh-Hant': '購買驗證處理方',
};

const EXCLUSION_TOKENS = {
  en: 'excludes the purchase token, transaction ID, and IP',
  ko: '구매 토큰, 거래 ID, IP가 들어가지 않습니다',
  ja: '購入トークン、取引ID、IPは入りません',
  'zh-Hans': '不含购买令牌',
  'zh-Hant': '不含購買權杖',
};

const SUPPORT_MINIMUM_TOKENS = {
  en: 'minimum order detail',
  ko: '최소한의 주문 정보',
  ja: '最小限の注文情報',
  'zh-Hans': '最少订单信息',
  'zh-Hant': '最少訂單資訊',
};

function freshBuild() {
  const dir = mkdtempSync(join(tmpdir(), 'player-care-test-'));
  return build(dir).then((pages) => ({ dir, pages }));
}

test('renders every route plus the stylesheet', async () => {
  const { dir, pages } = await freshBuild();
  try {
    const outputs = expectedOutputs(pages);
    // 1 root + 2 x-default x2 + 5 locale indexes x2 + 10 localized x2 + 404 + css
    assert.equal(outputs.length, 1 + 4 + 10 + 20 + 1 + 1);
    assert.ok(outputs.includes('en/privacy.html'));
    assert.ok(outputs.includes('zh-Hant/support/index.html'));
    await checkBuilt(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('dual layouts are byte-identical', async () => {
  const { dir, pages } = await freshBuild();
  try {
    for (const { outputs } of pages.values()) {
      if (outputs.length < 2) continue;
      const first = readFileSync(join(dir, outputs[0]), 'utf8');
      for (const output of outputs.slice(1)) {
        assert.equal(readFileSync(join(dir, output), 'utf8'), first, output);
      }
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('support tables match the live catalog exactly', async () => {
  const { dir } = await freshBuild();
  try {
    const { products } = await renderPages();
    assert.deepEqual(Object.keys(products), LOCALES);
    for (const locale of LOCALES) {
      assert.equal(products[locale].length, 10, `${locale} has 10 products`);
      assert.deepEqual(
        products[locale].map((product) => product.id),
        PRODUCT_ORDER,
      );
      const permanent = products[locale].filter((product) => product.type === 'non_consumable');
      const consumable = products[locale].filter((product) => product.type === 'consumable');
      assert.equal(permanent.length, 7, `${locale} has 7 permanent items`);
      assert.equal(consumable.length, 3, `${locale} has 3 coin packs`);
      const body = readFileSync(join(dir, locale, 'support.html'), 'utf8');
      for (const product of products[locale]) {
        assert.ok(body.includes(product.name), `${locale} names ${product.id}`);
        assert.ok(body.includes(product.desc), `${locale} describes ${product.id}`);
      }
    }
    assert.deepEqual(COIN_GRANTS, {
      'com.crossplatformkorea.moonlitbeacon.continue_coin': 1,
      'com.crossplatformkorea.moonlitbeacon.continue_coin_5': 5,
      'com.crossplatformkorea.moonlitbeacon.continue_coin_10': 10,
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('pins the canonical custom origin on every page', async () => {
  assert.equal(SITE_BASE, 'https://moonlitbeacon.hyo.dev');
  const { dir, pages } = await freshBuild();
  try {
    for (const file of expectedOutputs(pages)) {
      if (!file.endsWith('.html')) continue;
      const body = readFileSync(join(dir, file), 'utf8');
      assert.ok(
        body.includes(`<link rel="canonical" href="${SITE_BASE}`),
        `${file} canonical uses the custom origin`,
      );
      for (const stale of ['chatgpt.site', 'web.app', 'moonlitbeacon-778ee']) {
        assert.ok(!body.includes(stale), `${file} has no ${stale}`);
      }
    }
    const body = readFileSync(join(dir, 'ko', 'privacy.html'), 'utf8');
    assert.ok(body.includes(`${SITE_BASE}/ko/privacy`), 'hreflang uses the custom origin');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('privacy pages disclose retention, native sessions, and request handling', async () => {
  const { dir } = await freshBuild();
  try {
    for (const locale of LOCALES) {
      const body = readFileSync(join(dir, locale, 'privacy.html'), 'utf8');
      assert.ok(body.includes(RETENTION_TOKENS[locale]), `${locale} states no automatic expiry`);
      assert.ok(body.includes('SDK'), `${locale} names native SDK session storage`);
      assert.ok(body.includes(HANDLING_TOKENS[locale]), `${locale} states processor forwarding`);
      const support = readFileSync(join(dir, locale, 'support.html'), 'utf8');
      for (const absolute of ['owned forever', '영원히 소유', '永久に持ち', '永久拥有', '永久擁有']) {
        assert.ok(!support.includes(absolute), `${locale} support promises no ${absolute}`);
      }
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('privacy pages link processor policies and explain support handling', async () => {
  assert.equal(LINKS.iapkitPrivacy, 'https://kit.openiap.dev/privacy-policy');
  assert.equal(LINKS.convexPrivacy, 'https://www.convex.dev/legal/privacy');
  assert.equal(LINKS.mixpanelPrivacy, 'https://mixpanel.com/legal/privacy-policy/');
  const { dir } = await freshBuild();
  try {
    for (const locale of LOCALES) {
      const body = readFileSync(join(dir, locale, 'privacy.html'), 'utf8');
      for (const url of [LINKS.iapkitPrivacy, LINKS.convexPrivacy, LINKS.mixpanelPrivacy]) {
        assert.ok(body.includes(`href="${url}"`), `${locale} links ${url}`);
      }
      assert.ok(body.includes(EXCLUSION_TOKENS[locale]), `${locale} scopes the statistics event`);
      assert.ok(body.includes(SUPPORT_MINIMUM_TOKENS[locale]), `${locale} limits order detail`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('catalog reader rejects cross-platform disagreement', () => {
  const header = 'record_type,platform,locale,product_id,product_type,reference_name,display_name,short_description,subtitle,promotional_text,keywords,description,review_notes';
  const row = (platform, name) => `"iap","${platform}","en-US","com.crossplatformkorea.moonlitbeacon.supporter","non_consumable","Moonlit Supporter","${name}","","","","","","Permanent supporter mark beside your name.",""`;
  // One product mismatched between platforms is enough to fail loudly.
  assert.throws(
    () => loadProducts(`${header}\n${row('google', 'Moonlit Supporter')}\n${row('apple', 'Supporter X')}`),
    /disagrees/,
  );
  assert.throws(
    () => loadProducts(`${header}\n${row('google', 'Moonlit Supporter')}`),
    /no en row for com\.crossplatformkorea\.moonlitbeacon\.hero_dancer/,
  );
});

test('checker fails on a removed route file', async () => {
  const { dir } = await freshBuild();
  try {
    rmSync(join(dir, 'ja', 'privacy.html'));
    await assert.rejects(() => checkBuilt(dir), /missing route file: ja\/privacy\.html/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('checker fails on stale no-account framing', async () => {
  const { dir } = await freshBuild();
  try {
    const target = join(dir, 'en', 'support.html');
    writeFileSync(target, readFileSync(target, 'utf8').replace('Guest progress is device-only.', 'Guest progress needs no account and is device-only.'));
    await assert.rejects(() => checkBuilt(dir), /stale no-account framing/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('checker fails on a broken local link', async () => {
  const { dir } = await freshBuild();
  try {
    const target = join(dir, 'ko', 'privacy.html');
    writeFileSync(target, readFileSync(target, 'utf8').replace('/ko/support', '/ko/missing-page'));
    await assert.rejects(() => checkBuilt(dir), /local link target missing/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('checker fails on a non-allowlisted outbound link', async () => {
  const { dir } = await freshBuild();
  try {
    const target = join(dir, 'en', 'privacy.html');
    writeFileSync(
      target,
      readFileSync(target, 'utf8').replace('https://kit.openiap.dev/docs/api', 'https://example.com/docs'),
    );
    await assert.rejects(() => checkBuilt(dir), /not allowlisted/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
