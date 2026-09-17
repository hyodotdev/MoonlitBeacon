import './lib/load-env.mjs';

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
function inputPath(environmentKey, ...defaultSegments) {
  const override = process.env[environmentKey]?.trim();
  if (override && process.env.MOONLIT_STORE_METADATA_TEST_MODE !== "1") {
    throw new Error(
      `${environmentKey} can only be used in explicit test mode`,
    );
  }
  return override
    ? path.resolve(override)
    : path.join(repoRoot, ...defaultSegments);
}

const csvPath = inputPath(
  "MOONLIT_STORE_LOCALIZATIONS_PATH",
  "notes",
  "release",
  "store-localizations.csv",
);
const storePagePath = inputPath(
  "MOONLIT_STORE_PAGE_PATH",
  "notes",
  "release",
  "store-page.md",
);
const iapSetupPath = inputPath(
  "MOONLIT_IAP_STORE_SETUP_PATH",
  "notes",
  "release",
  "iap-store-setup.md",
);

const PRODUCTS = [
  "com.crossplatformkorea.moonlitbeacon.supporter",
  "com.crossplatformkorea.moonlitbeacon.hero_dancer",
  "com.crossplatformkorea.moonlitbeacon.hero_keeper",
  "com.crossplatformkorea.moonlitbeacon.hero_knight",
  "com.crossplatformkorea.moonlitbeacon.hero_eclipse",
  "com.crossplatformkorea.moonlitbeacon.hero_sage",
  "com.crossplatformkorea.moonlitbeacon.lantern_colors",
  "com.crossplatformkorea.moonlitbeacon.continue_coin",
  "com.crossplatformkorea.moonlitbeacon.continue_coin_5",
  "com.crossplatformkorea.moonlitbeacon.continue_coin_10",
];

// Must be the same list as the app's `IapStore.CONSUMABLE_PRODUCT_IDS`.
const CONSUMABLE_PRODUCTS = new Set([
  "com.crossplatformkorea.moonlitbeacon.continue_coin",
  "com.crossplatformkorea.moonlitbeacon.continue_coin_5",
  "com.crossplatformkorea.moonlitbeacon.continue_coin_10",
]);
const APP_LOCALES = {
  google: ["en-US", "ko-KR", "ja-JP", "zh-CN", "zh-TW"],
  apple: ["en-US", "ko", "ja", "zh-Hans", "zh-Hant"],
};
const LOCALE_PAIRS = [
  ["en", "en-US", "en-US"],
  ["ko", "ko-KR", "ko"],
  ["ja", "ja-JP", "ja"],
  ["zh-Hans", "zh-CN", "zh-Hans"],
  ["zh-Hant", "zh-TW", "zh-Hant"],
];
const PUBLIC_FIELDS = [
  "display_name",
  "short_description",
  "subtitle",
  "promotional_text",
  "keywords",
  "description",
];
const SUBMISSION_FIELDS = [
  "reference_name",
  ...PUBLIC_FIELDS,
  "review_notes",
];
const UNRESOLVED_PLACEHOLDER =
  /\b(?:TODO|TBD|TBC|FIXME|XXX|CHANGEME|PLACEHOLDER)\b|<[^>\r\n]{1,120}>|\b(?:example\.com|example@example\.com)\b|(?:미정|추후\s*(?:입력|확정|작성))/iu;

const errors = [];

function length(value) {
  return [...value].length;
}

function fail(message) {
  errors.push(message);
}

function parseCsv(source) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    if (quoted) {
      if (char === '"' && source[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
      continue;
    }

    if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }

  if (quoted) {
    throw new Error("Unclosed CSV quote");
  }
  if (field !== "" || row.length > 0) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }
  return rows.filter((entry) => entry.some((value) => value !== ""));
}

function rowsAsObjects(source) {
  const parsed = parseCsv(source);
  const [header, ...body] = parsed;
  if (!header) {
    throw new Error("CSV header is missing");
  }
  return body.map((row, index) => {
    if (row.length !== header.length) {
      throw new Error(
        `CSV row ${index + 2} has ${row.length} columns; expected ${header.length}`,
      );
    }
    return Object.fromEntries(header.map((key, column) => [key, row[column]]));
  });
}

function findRow(rows, recordType, platform, locale, productId = "") {
  return rows.find(
    (row) =>
      row.record_type === recordType &&
      row.platform === platform &&
      row.locale === locale &&
      row.product_id === productId,
  );
}

function requireWithin(row, field, maximum, label, minimum = 1) {
  const value = row[field] ?? "";
  const size = length(value);
  if (size < minimum || size > maximum) {
    fail(`${label}: ${field} ${size} chars; allowed ${minimum}~${maximum}`);
  }
}

function rejectUnresolvedPlaceholder(value, label) {
  const match = value.match(UNRESOLVED_PLACEHOLDER);
  if (match) {
    fail(`${label}: unresolved placeholder ${JSON.stringify(match[0])}`);
  }
}

function extractMarkdownSection(markdown, heading) {
  const headingIndex = markdown.indexOf(heading);
  if (headingIndex < 0) {
    fail(`${heading} heading was not found`);
    return "";
  }
  const contentStart = markdown.indexOf("\n", headingIndex);
  if (contentStart < 0) {
    return "";
  }
  const remaining = markdown.slice(contentStart + 1);
  const nextHeading = remaining.search(/^#{1,3}\s+/mu);
  return nextHeading < 0 ? remaining : remaining.slice(0, nextHeading);
}

function extractAllTextBlocks(markdown) {
  return [...markdown.matchAll(/^```text\r?\n([\s\S]*?)\r?\n```$/gmu)]
    .map((match) => match[1]);
}

function extractTextBlock(markdown, heading) {
  const headingIndex = markdown.indexOf(heading);
  if (headingIndex < 0) {
    fail(`${heading} heading was not found`);
    return "";
  }
  const fenceStart = markdown.indexOf("```text\n", headingIndex);
  if (fenceStart < 0) {
    fail(`${heading} has no text code block underneath`);
    return "";
  }
  const contentStart = fenceStart + "```text\n".length;
  const fenceEnd = markdown.indexOf("\n```", contentStart);
  if (fenceEnd < 0) {
    fail(`${heading} code block is not closed`);
    return "";
  }
  return markdown.slice(contentStart, fenceEnd);
}

const csvSource = readFileSync(csvPath, "utf8");
const rows = rowsAsObjects(csvSource);
const seen = new Set();
const expectedRows = new Set();
for (const [platform, locales] of Object.entries(APP_LOCALES)) {
  for (const locale of locales) {
    expectedRows.add(["app", platform, locale, ""].join("|"));
    for (const productId of PRODUCTS) {
      expectedRows.add(["iap", platform, locale, productId].join("|"));
    }
  }
}

for (const row of rows) {
  const key = [
    row.record_type,
    row.platform,
    row.locale,
    row.product_id,
  ].join("|");
  if (seen.has(key)) {
    fail(`duplicate localization row: ${key}`);
  }
  seen.add(key);
  if (!expectedRows.has(key)) {
    fail(`unsupported or stale localization row: ${key}`);
  }

  const publicCopy = PUBLIC_FIELDS.map((field) => row[field]).join(" ");
  if (/(firebase|global leaderboard|전역 순위)/iu.test(publicCopy)) {
    fail(`global-leaderboard copy that launch 1 does not promote: ${key}`);
  }
  for (const field of SUBMISSION_FIELDS) {
    const value = row[field] ?? "";
    if (value !== "") {
      rejectUnresolvedPlaceholder(value, `${key}/${field}`);
    }
  }
}

for (const [platform, locales] of Object.entries(APP_LOCALES)) {
  for (const locale of locales) {
    const row = findRow(rows, "app", platform, locale);
    if (!row) {
      fail(`missing app localization: ${platform}/${locale}`);
      continue;
    }
    requireWithin(row, "display_name", 30, `${platform}/${locale} app name`);
    if (platform === "google") {
      requireWithin(row, "short_description", 80, `${platform}/${locale}`);
    } else {
      requireWithin(row, "subtitle", 30, `${platform}/${locale}`);
      if (row.subtitle.trim().toLocaleLowerCase(locale) ===
          row.display_name.trim().toLocaleLowerCase(locale)) {
        fail(`${platform}/${locale}: App Store subtitle duplicates the app name`);
      }
      requireWithin(row, "promotional_text", 170, `${platform}/${locale}`);
      const keywordBytes = Buffer.byteLength(row.keywords, "utf8");
      if (keywordBytes < 1 || keywordBytes > 100) {
        fail(
          `${platform}/${locale}: keywords ${keywordBytes} bytes; allowed 1~100 bytes`,
        );
      }
    }
  }
}

for (const platform of Object.keys(APP_LOCALES)) {
  for (const locale of APP_LOCALES[platform]) {
    for (const productId of PRODUCTS) {
      const row = findRow(rows, "iap", platform, locale, productId);
      const label = `${platform}/${locale}/${productId}`;
      if (!row) {
        fail(`missing IAP localization: ${label}`);
        continue;
      }
      // Consumables and non-consumables have different store lifecycles. A mismatch
      // with the app catalog can grant nothing after purchase or block repurchase, so
      // do not hard-code one type; compare each product to its expected type.
      const expectedType = CONSUMABLE_PRODUCTS.has(productId)
        ? "consumable"
        : "non_consumable";
      if (row.product_type !== expectedType) {
        fail(`${label}: product_type must be ${expectedType}`);
      }
      if (!/^[a-z0-9][a-z0-9._]*$/.test(productId)) {
        fail(`${label}: not a Google Play-compatible product ID`);
      }

      if (platform === "google") {
        requireWithin(row, "display_name", 55, label);
        requireWithin(row, "description", 200, label);
        if (row.review_notes !== "") {
          fail(`${label}: do not put review_notes on a Google Play product`);
        }
      } else {
        requireWithin(row, "reference_name", 64, label);
        requireWithin(row, "display_name", 30, label, 2);
        requireWithin(row, "description", 45, label);
        requireWithin(row, "review_notes", 4000, label);
      }
    }
  }
}

for (const productId of PRODUCTS) {
  for (const [language, googleLocale, appleLocale] of LOCALE_PAIRS) {
    const google = findRow(
      rows,
      "iap",
      "google",
      googleLocale,
      productId,
    );
    const apple = findRow(rows, "iap", "apple", appleLocale, productId);
    if (
      google &&
      apple &&
      (google.display_name !== apple.display_name ||
        google.description !== apple.description)
    ) {
      fail(`IAP copy mismatch across platforms: ${language}/${productId}`);
    }
  }
}

const storePage = readFileSync(storePagePath, "utf8");
const iapSetup = readFileSync(iapSetupPath, "utf8");
const requiredReleaseMetadata = extractMarkdownSection(
  storePage,
  "### Values the actual seller fills before submit",
);
rejectUnresolvedPlaceholder(
  requiredReleaseMetadata,
  "store-page.md required pre-submission metadata",
);
for (const [index, reviewCopy] of extractAllTextBlocks(iapSetup).entries()) {
  rejectUnresolvedPlaceholder(
    reviewCopy,
    `iap-store-setup.md review copy ${index + 1}`,
  );
}
const koreanDescription = extractTextBlock(storePage, "## Korean description");
const englishDescription = extractTextBlock(storePage, "## English description");
const japaneseDescription = extractTextBlock(storePage, "## Japanese description");
const simplifiedChineseDescription = extractTextBlock(
  storePage,
  "## Simplified Chinese description",
);
const traditionalChineseDescription = extractTextBlock(
  storePage,
  "## Traditional Chinese description",
);
for (const [locale, description] of [
  ["ko", koreanDescription],
  ["en-US", englishDescription],
  ["ja", japaneseDescription],
  ["zh-Hans", simplifiedChineseDescription],
  ["zh-Hant", traditionalChineseDescription],
]) {
  rejectUnresolvedPlaceholder(description, `${locale} full description`);
  if (length(description) > 4000) {
    fail(`${locale} full description ${length(description)} chars; max 4000`);
  }
  if (/(firebase|global leaderboard|전역 순위)/iu.test(description)) {
    fail(`${locale} full description promotes a global leaderboard at launch 1`);
  }
}

for (const [locale, description, required] of [
  [
    "ko",
    koreanDescription,
    ["선택형 인앱 구매", "7종", "소모성 이어하기 코인", "1개·5개·10개"],
  ],
  [
    "en-US",
    englishDescription,
    [
      "seven optional, restorable non-consumable",
      "Three consumable Continue Coin packs",
      "1, 5, or 10 coins",
    ],
  ],
  [
    "ja",
    japaneseDescription,
    ["任意のアプリ内購入", "7種類", "消耗型のコンティニューコイン", "1枚・5枚・10枚"],
  ],
  [
    "zh-Hans",
    simplifiedChineseDescription,
    ["7项可选的一次性永久内购", "三种消耗型继续游戏金币", "1枚、5枚和10枚"],
  ],
  [
    "zh-Hant",
    traditionalChineseDescription,
    ["7項可選的一次性永久內購", "三種消耗型繼續遊戲金幣", "1枚、5枚和10枚"],
  ],
]) {
  for (const phrase of required) {
    if (!description.includes(phrase)) {
      fail(`${locale} full description is missing required IAP copy: ${phrase}`);
    }
  }
}

for (const row of rows.filter((entry) => entry.record_type === "app")) {
  for (const field of PUBLIC_FIELDS) {
    const value = row[field];
    if (value && !storePage.includes(value)) {
      fail(
        `store-page.md is missing ${row.platform}/${row.locale} ${field} copy`,
      );
    }
  }
}

for (const row of rows.filter(
  (entry) => entry.record_type === "iap" && entry.platform === "apple",
)) {
  for (const field of ["display_name", "description"]) {
    if (!iapSetup.includes(row[field])) {
      fail(
        `iap-store-setup.md is missing ${row.locale}/${row.product_id} ${field} copy`,
      );
    }
  }
}

if (errors.length > 0) {
  for (const error of errors) {
    console.error(`Store metadata error: ${error}`);
  }
  process.exitCode = 1;
} else {
  const appRows = rows.filter((row) => row.record_type === "app").length;
  const iapRows = rows.filter((row) => row.record_type === "iap").length;
  console.log(
    `Store metadata check passed — ${appRows} app row(s) · ${iapRows} IAP row(s)`,
  );
}
