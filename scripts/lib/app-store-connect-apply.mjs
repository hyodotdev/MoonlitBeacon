import { createHash } from 'node:crypto';
import { lstatSync, readFileSync, realpathSync } from 'node:fs';
import { isAbsolute, relative, resolve, sep } from 'node:path';
import {
  APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
  APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
  IAP_PRODUCT_IDS,
  auditAppStoreConnectRelease,
  canonicalJson,
  createAppStoreConnectToken,
  createGetOnlyAppStoreConnectClient,
  isAdoptableAppVersionState,
  normalizeAppVersionState,
  summarizeRemotePlan,
  verifyAppStoreReleaseManifest,
} from './app-store-release.mjs';
import { readAppStoreCredentials } from './ios-distribution.mjs';

const ASC_ORIGIN = 'https://api.appstoreconnect.apple.com';
const MAX_JSON_BYTES = 2 * 1024 * 1024;
const JWT_LIFETIME_SECONDS = 1199;
const JWT_SAFETY_MARGIN_SECONDS = 120;
const EXPECTED_RELEASE = Object.freeze({ buildNumber: '9', version: '2.1.0' });
const INTERNAL_BETA_GROUP_NAME = 'Moonlit Beacon Internal';
const REVIEWABLE_IAP_VERSION_STATES = new Set([
  'PREPARE_FOR_SUBMISSION',
  'READY_FOR_REVIEW',
  'DEVELOPER_REJECTED',
]);
const EDITABLE_IAP_VERSION_STATES = new Set([
  'PREPARE_FOR_SUBMISSION',
]);
const CURRENT_IAP_VERSION_STATES = new Set([
  'PREPARE_FOR_SUBMISSION',
  'READY_FOR_REVIEW',
]);
const SUBMITTED_REVIEW_STATES = new Set([
  'WAITING_FOR_REVIEW',
  'IN_REVIEW',
  'COMPLETING',
  'COMPLETE',
]);
const SOFT_IAP_GATE = 'IAP_REMOTE_STATE_NOT_RELEASE_READY';
// Apple moved asset upload targets to regional object-storage. As of
// 2026-08-04 it returns northamerica-1.object-storage.apple.com. Keep the
// allowlist narrow rather than all of apple.com: this guard exists to stop
// signed assets from going anywhere that is not Apple.
const ASSET_UPLOAD_HOST_PATTERNS = Object.freeze([
  /(^|\.)blobstore\.apple\.com$/u,
  /(^|\.)object-storage\.apple\.com$/u,
]);

const ALLOWED_JSON_ROUTES = Object.freeze({
  DELETE: Object.freeze([
    /^\/v1\/appScreenshots\/[^/]+$/u,
    /^\/v1\/inAppPurchaseAppStoreReviewScreenshots\/[^/]+$/u,
  ]),
  PATCH: Object.freeze([
    /^\/v1\/appStoreVersions\/[^/]+$/u,
    /^\/v1\/appStoreReviewDetails\/[^/]+$/u,
    /^\/v1\/appInfoLocalizations\/[^/]+$/u,
    /^\/v1\/appStoreVersionLocalizations\/[^/]+$/u,
    /^\/v1\/appScreenshots\/[^/]+$/u,
    /^\/v1\/appScreenshotSets\/[^/]+\/relationships\/appScreenshots$/u,
    /^\/v1\/appStoreVersions\/[^/]+\/relationships\/build$/u,
    /^\/v1\/inAppPurchaseAppStoreReviewScreenshots\/[^/]+$/u,
    /^\/v1\/reviewSubmissions\/[^/]+$/u,
    /^\/v2\/inAppPurchases\/[^/]+$/u,
    /^\/v2\/inAppPurchaseLocalizations\/[^/]+$/u,
  ]),
  POST: Object.freeze([
    /^\/v1\/appStoreVersions$/u,
    /^\/v1\/appInfoLocalizations$/u,
    /^\/v1\/appStoreVersionLocalizations$/u,
    /^\/v1\/appScreenshotSets$/u,
    /^\/v1\/appScreenshots$/u,
    /^\/v1\/inAppPurchaseVersions$/u,
    /^\/v1\/inAppPurchaseAppStoreReviewScreenshots$/u,
    /^\/v1\/reviewSubmissions$/u,
    /^\/v1\/reviewSubmissionItems$/u,
    /^\/v1\/betaGroups\/[^/]+\/relationships\/builds$/u,
    /^\/v2\/inAppPurchases$/u,
    /^\/v2\/inAppPurchaseLocalizations$/u,
  ]),
});

function sha256(contents) {
  return createHash('sha256').update(contents).digest('hex');
}

function md5(contents) {
  return createHash('md5').update(contents).digest('hex');
}

function fail(code, message) {
  const error = new Error(`${code}: ${message}`);
  error.code = code;
  return error;
}

export function isReviewableIapVersionState(state) {
  return typeof state === 'string'
    && REVIEWABLE_IAP_VERSION_STATES.has(state);
}

export function assertEditableAppStoreVersionState(state) {
  const normalized = normalizeAppVersionState(state);
  if (!isAdoptableAppVersionState(normalized)) {
    throw fail(
      'ASC_VERSION_NOT_EDITABLE',
      `App Store version state ${normalized ?? 'UNKNOWN'} cannot be mutated.`,
    );
  }
  return normalized;
}

function requireString(value, label) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw fail('ASC_INVALID_INPUT', `${label} value is required.`);
  }
  return value;
}

function encodeSegment(value, label) {
  const text = requireString(value, label);
  if (/[/\u0000-\u001f\u007f]/u.test(text)) {
    throw fail('ASC_INVALID_ID', `${label} ID is invalid.`);
  }
  return encodeURIComponent(text);
}

function queryPath(pathname, entries) {
  return `${pathname}?${new URLSearchParams(entries).toString()}`;
}

function remoteAttributes(resource) {
  return resource?.attributes ?? {};
}

function changesBetween(desired, actual) {
  return Object.fromEntries(Object.entries(desired)
    .filter(([, value]) => value !== null && value !== undefined)
    .filter(([key, value]) => actual?.[key] !== value)
    .map(([key, value]) => [key, {
      current: actual?.[key] ?? null,
      desired: value,
    }]));
}

function desiredFromEntry(entry) {
  if (entry.desired) return { ...entry.desired };
  return Object.fromEntries(Object.entries(entry.changes ?? {})
    .map(([name, change]) => [name, change.desired]));
}

function normalizeApiUrl(pathOrUrl) {
  const url = new URL(pathOrUrl, ASC_ORIGIN);
  if (
    url.origin !== ASC_ORIGIN
    || url.username !== ''
    || url.password !== ''
    || url.hash !== ''
    || (!url.pathname.startsWith('/v1/') && !url.pathname.startsWith('/v2/'))
  ) {
    throw fail('ASC_API_URL_NOT_ALLOWED', 'App Store Connect API URL is outside the allowlist.');
  }
  return url;
}

function assertJsonRoute(method, url) {
  if (!ALLOWED_JSON_ROUTES[method]?.some((pattern) => pattern.test(url.pathname))) {
    throw fail(
      'ASC_MUTATION_NOT_ALLOWED',
      `${method} ${url.pathname} is not on the explicit allowlist.`,
    );
  }
}

async function boundedFetch(fetchImpl, url, options, label, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchImpl(url, { ...options, redirect: 'error', signal: controller.signal });
  } catch (error) {
    throw fail('ASC_NETWORK_FAILURE', `${label} request failed (${error.name ?? 'Error'}).`);
  } finally {
    clearTimeout(timer);
  }
}

async function responseJson(response, label, { allowEmpty = false } = {}) {
  const declared = Number(response.headers?.get?.('content-length') ?? 0);
  if (Number.isFinite(declared) && declared > MAX_JSON_BYTES) {
    throw fail('ASC_RESPONSE_TOO_LARGE', `${label} response size exceeds the limit.`);
  }
  const text = await response.text();
  if (Buffer.byteLength(text) > MAX_JSON_BYTES) {
    throw fail('ASC_RESPONSE_TOO_LARGE', `${label} response size exceeds the limit.`);
  }
  let body = null;
  if (text !== '') {
    try {
      body = JSON.parse(text);
    } catch {
      throw fail('ASC_INVALID_RESPONSE', `${label} response is not JSON.`);
    }
  }
  if (!response.ok) {
    const remoteCode = body?.errors?.[0]?.code;
    const safeCode = typeof remoteCode === 'string'
      ? remoteCode.replace(/[^A-Z0-9_.-]/giu, '').slice(0, 80)
      : 'HTTP_ERROR';
    throw fail(
      'ASC_REMOTE_REJECTED',
      `${label} failed: HTTP ${response.status} ${safeCode}.`,
    );
  }
  if (!allowEmpty && body === null) {
    throw fail('ASC_INVALID_RESPONSE', `${label} response body is missing.`);
  }
  return body;
}

function validateUploadOperations(operations, fileSize) {
  if (!Array.isArray(operations) || operations.length === 0) {
    throw fail('ASC_UPLOAD_CONTRACT_INVALID', 'asset uploadOperations are missing.');
  }
  const ranges = operations.map((operation) => {
    const offset = Number(operation?.offset);
    const length = Number(operation?.length);
    if (
      operation?.method !== 'PUT'
      || !Number.isSafeInteger(offset)
      || offset < 0
      || !Number.isSafeInteger(length)
      || length < 1
      || offset + length > fileSize
      || !Array.isArray(operation.requestHeaders)
    ) {
      throw fail('ASC_UPLOAD_CONTRACT_INVALID', 'asset upload operation range is invalid.');
    }
    const url = new URL(operation.url);
    // Keep the rejection reason. Never log upload URL query strings (they hold
    // signatures); only record the host and which condition failed.
    const urlViolations = [
      url.protocol !== 'https:' ? `protocol=${url.protocol}` : null,
      url.username !== '' || url.password !== '' ? 'contains userinfo' : null,
      url.port !== '' ? `port=${url.port}` : null,
      url.hash !== '' ? 'contains fragment' : null,
      !ASSET_UPLOAD_HOST_PATTERNS.some((pattern) => pattern.test(url.hostname))
        ? `host=${url.hostname}`
        : null,
    ].filter(Boolean);
    if (urlViolations.length > 0) {
      throw fail(
        'ASC_UPLOAD_URL_NOT_ALLOWED',
        `rejected a non-Apple-blobstore upload URL (${urlViolations.join(', ')}).`,
      );
    }
    const headers = {};
    for (const header of operation.requestHeaders) {
      const name = String(header?.name ?? '').toLowerCase();
      const value = String(header?.value ?? '');
      if (
        !/^[a-z0-9-]+$/u.test(name)
        || name === 'authorization'
        || /[\r\n]/u.test(value)
      ) {
        throw fail('ASC_UPLOAD_HEADER_NOT_ALLOWED', 'asset upload header is not safe.');
      }
      headers[name] = value;
    }
    return { headers, length, offset, url };
  }).sort((left, right) => left.offset - right.offset);
  let cursor = 0;
  for (const range of ranges) {
    if (range.offset !== cursor) {
      throw fail('ASC_UPLOAD_CONTRACT_INVALID', 'asset upload ranges overlap or are empty.');
    }
    cursor += range.length;
  }
  if (cursor !== fileSize) {
    throw fail('ASC_UPLOAD_CONTRACT_INVALID', 'asset upload ranges do not cover the whole file.');
  }
  return ranges;
}

export function createAppStoreConnectMutationClient({
  fetchImpl = globalThis.fetch,
  timeoutMs = 60_000,
  token,
  tokenProvider = null,
} = {}) {
  if (typeof fetchImpl !== 'function') throw new TypeError('fetch function is required');
  if (tokenProvider !== null && typeof tokenProvider !== 'function') {
    throw new TypeError('App Store Connect tokenProvider must be a function');
  }
  if (!tokenProvider) requireString(token, 'App Store Connect JWT');
  const provideToken = tokenProvider ?? (() => token);
  const requests = [];

  async function json(method, pathOrUrl, body) {
    const url = normalizeApiUrl(pathOrUrl);
    assertJsonRoute(method, url);
    requests.push({ method, path: url.pathname });
    const requestToken = await provideToken();
    requireString(requestToken, 'App Store Connect JWT');
    const response = await boundedFetch(fetchImpl, url, {
      body: body === undefined ? undefined : JSON.stringify(body),
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${requestToken}`,
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      method,
    }, `App Store Connect ${method} ${url.pathname}`, timeoutMs);
    return responseJson(response, `App Store Connect ${method} ${url.pathname}`, {
      allowEmpty: method === 'DELETE'
        || url.pathname.includes('/relationships/'),
    });
  }

  async function upload(validated, contents) {
    requests.push({ method: 'PUT', path: `${validated.url.hostname}${validated.url.pathname}` });
    const response = await boundedFetch(fetchImpl, validated.url, {
      body: contents,
      headers: validated.headers,
      method: 'PUT',
    }, 'App Store Connect asset PUT', timeoutMs);
    if (!response.ok) {
      throw fail('ASC_ASSET_UPLOAD_FAILED', `asset PUT failed: HTTP ${response.status}.`);
    }
  }

  return Object.freeze({
    delete: (path) => json('DELETE', path),
    patch: (path, body) => json('PATCH', path, body),
    post: (path, body) => json('POST', path, body),
    get requests() {
      return requests.map((request) => ({ ...request }));
    },
    async uploadOperations(operations, contents) {
      const ranges = validateUploadOperations(operations, contents.length);
      for (const range of ranges) {
        await upload(
          range,
          contents.subarray(range.offset, range.offset + range.length),
        );
      }
    },
  });
}

export function createRotatingAppStoreConnectTokenProvider({
  issuerId,
  keyId,
  now = Date.now,
  privateKey,
  safetyMarginSeconds = JWT_SAFETY_MARGIN_SECONDS,
} = {}) {
  if (typeof now !== 'function') {
    throw new TypeError('App Store Connect token clock must be a function');
  }
  if (
    !Number.isSafeInteger(safetyMarginSeconds)
    || safetyMarginSeconds < 1
    || safetyMarginSeconds >= JWT_LIFETIME_SECONDS
  ) {
    throw new TypeError('App Store Connect JWT safety margin is invalid');
  }
  let cachedToken = null;
  let expiresAtSeconds = 0;
  return () => {
    const nowMilliseconds = Number(now());
    if (!Number.isFinite(nowMilliseconds) || nowMilliseconds < 0) {
      throw fail('ASC_CLOCK_INVALID', 'App Store Connect token clock value is invalid.');
    }
    const nowSeconds = Math.floor(nowMilliseconds / 1000);
    if (
      cachedToken === null
      || nowSeconds >= expiresAtSeconds - safetyMarginSeconds
    ) {
      cachedToken = createAppStoreConnectToken({
        issuerId,
        keyId,
        now: nowMilliseconds,
        privateKey,
      });
      expiresAtSeconds = nowSeconds + JWT_LIFETIME_SECONDS;
    }
    return cachedToken;
  };
}

export function appStoreConfirmationToken(manifest, purpose = 'apply') {
  verifyAppStoreReleaseManifest(manifest);
  if (!['apply', 'review'].includes(purpose)) {
    throw fail('ASC_CONFIRMATION_PURPOSE_INVALID', 'confirmation token purpose is invalid.');
  }
  const release = manifest.payload.release;
  return [
    'app-store',
    purpose,
    release.appId,
    release.version,
    release.buildNumber,
    manifest.payloadChecksums.sha256.slice(0, 20),
  ].join(':');
}

export function assertAppStoreApplyAuthorization({
  confirmation,
  manifest,
  payload,
  reviewConfirmation = null,
  submitReview = false,
} = {}) {
  verifyAppStoreReleaseManifest(manifest, payload);
  const release = payload.release;
  if (
    release.version !== EXPECTED_RELEASE.version
    || release.buildNumber !== EXPECTED_RELEASE.buildNumber
  ) {
    throw fail(
      'ASC_TARGET_RELEASE_MISMATCH',
      `this applier only allows ${EXPECTED_RELEASE.version}(${EXPECTED_RELEASE.buildNumber}).`,
    );
  }
  if (confirmation !== appStoreConfirmationToken(manifest, 'apply')) {
    throw fail('ASC_APPLY_CONFIRMATION_MISMATCH', 'remote-apply token bound to the manifest differs.');
  }
  if (submitReview) {
    if (reviewConfirmation !== appStoreConfirmationToken(manifest, 'review')) {
      throw fail('ASC_REVIEW_CONFIRMATION_MISMATCH', 'review-submission-only confirmation token differs.');
    }
  } else if (reviewConfirmation !== null) {
    throw fail('ASC_REVIEW_CONFIRMATION_WITHOUT_FLAG', 'cannot use a review confirmation token without submitting for review.');
  }
  return true;
}

function uniqueResource(resources, predicate, label) {
  const matches = resources.filter(predicate);
  if (matches.length > 1) throw fail('ASC_REMOTE_DUPLICATE', `${label} is duplicated.`);
  return matches[0] ?? null;
}

export async function auditBuildAssociation(payload, client, baseAudit) {
  const { appId, buildNumber, version } = payload.release;
  if (!/^\d+$/u.test(buildNumber)) {
    throw fail('ASC_BUILD_NUMBER_INVALID', 'manifest iOS buildNumber is not a number.');
  }
  const buildsResponse = await client.get(queryPath('/v1/builds', [
    ['filter[app]', appId],
    ['filter[version]', buildNumber],
    ['filter[preReleaseVersion.version]', version],
    ['filter[preReleaseVersion.platform]', 'IOS'],
    ['filter[processingState]', 'VALID'],
    ['filter[expired]', 'false'],
    ['fields[builds]',
      'version,expired,processingState,buildAudienceType,preReleaseVersion'],
    ['fields[preReleaseVersions]', 'version,platform'],
    ['include', 'preReleaseVersion'],
    ['limit', '2'],
  ]));
  if (buildsResponse?.links?.next) {
    throw fail('ASC_EXACT_BUILD_PAGINATED', 'exact iOS build lookup spans more than one page.');
  }
  const builds = Array.isArray(buildsResponse?.data) ? buildsResponse.data : [];
  if (builds.length > 1) {
    throw fail('ASC_EXACT_BUILD_DUPLICATE', `iOS ${version}(${buildNumber}) build is duplicated.`);
  }
  const target = builds[0] ?? null;
  if (!target) {
    return {
      action: 'unresolved',
      code: 'ASC_EXACT_BUILD_NOT_FOUND',
      identifier: `IOS/${version}(${buildNumber})`,
      reason: 'could not find an exact VALID, unexpired, App Store-targeted build.',
      remoteMutationPlanned: false,
      target: 'buildAssociation',
    };
  }
  const targetAttrs = remoteAttributes(target);
  const preReleaseVersionId = relationshipId(target, 'preReleaseVersion');
  const preReleaseVersion = (buildsResponse?.included ?? []).find((resource) => (
    resource.type === 'preReleaseVersions'
    && resource.id === preReleaseVersionId
  ));
  const preReleaseAttrs = remoteAttributes(preReleaseVersion);
  if (
    targetAttrs.version !== buildNumber
    || targetAttrs.processingState !== 'VALID'
    || targetAttrs.expired === true
    || targetAttrs.buildAudienceType !== 'APP_STORE_ELIGIBLE'
    || preReleaseAttrs.platform !== 'IOS'
    || preReleaseAttrs.version !== version
  ) {
    throw fail('ASC_EXACT_BUILD_NOT_ELIGIBLE', 'exact iOS build is not eligible for App Store submission.');
  }
  if (!baseAudit.remote.versionId) {
    return {
      action: 'update',
      buildId: target.id,
      desiredBuildId: target.id,
      identifier: `IOS/${version}(${buildNumber})`,
      prerequisites: [`appStoreVersion:${version}`],
      remoteId: null,
      target: 'buildAssociation',
    };
  }
  const attached = await client.get(
    queryPath(`/v1/appStoreVersions/${baseAudit.remote.versionId}/build`, [
      ['fields[builds]', 'version,expired,processingState,buildAudienceType'],
    ]),
    { allowNotFound: true },
  );
  const attachedBuild = attached?.data ?? null;
  return {
    action: attachedBuild?.id === target.id ? 'none' : 'update',
    buildId: target.id,
    currentBuildId: attachedBuild?.id ?? null,
    desiredBuildId: target.id,
    identifier: `IOS/${version}(${buildNumber})`,
    prerequisites: [`appStoreVersion:${version}`],
    remoteId: baseAudit.remote.versionId,
    target: 'buildAssociation',
  };
}

export async function auditInternalBetaGroup(payload, client, buildPlan) {
  if (!buildPlan.buildId) {
    return {
      action: 'unresolved',
      code: 'ASC_INTERNAL_BETA_BUILD_UNAVAILABLE',
      identifier: INTERNAL_BETA_GROUP_NAME,
      reason: 'cannot verify internal TestFlight group linkage without an exact iOS build.',
      remoteMutationPlanned: false,
      target: 'internalBetaGroupAssignment',
    };
  }
  const groups = await client.getAll(queryPath(
    `/v1/apps/${encodeSegment(payload.release.appId, 'app')}/betaGroups`,
    [
      ['fields[betaGroups]', 'name,isInternalGroup'],
      ['limit', '200'],
    ],
  ));
  const targetGroups = groups.filter((group) => (
    remoteAttributes(group).name === INTERNAL_BETA_GROUP_NAME
    && remoteAttributes(group).isInternalGroup === true
  ));
  if (targetGroups.length !== 1) {
    return {
      action: 'unresolved',
      code: 'ASC_INTERNAL_BETA_GROUP_NOT_UNIQUE',
      identifier: INTERNAL_BETA_GROUP_NAME,
      reason: 'could not select exactly one internal TestFlight group with the exact name.',
      remoteMutationPlanned: false,
      target: 'internalBetaGroupAssignment',
    };
  }
  const groupBuilds = new Map();
  for (const group of groups) {
    groupBuilds.set(group.id, await client.getAll(queryPath(
      `/v1/betaGroups/${encodeSegment(group.id, 'beta group')}/builds`,
      [
        ['fields[builds]', 'version,expired,processingState,buildAudienceType'],
        ['limit', '200'],
      ],
    )));
  }
  const external = groups.filter((group) => (
    remoteAttributes(group).isInternalGroup !== true
    && groupBuilds.get(group.id).some((build) => build.id === buildPlan.buildId)
  ));
  if (external.length > 0) {
    return {
      action: 'unresolved',
      code: 'ASC_EXTERNAL_BETA_GROUP_PRESENT',
      identifier: INTERNAL_BETA_GROUP_NAME,
      reason: 'exact build is linked to an external TestFlight group; not changing automatically.',
      remoteMutationPlanned: false,
      target: 'internalBetaGroupAssignment',
    };
  }
  const group = targetGroups[0];
  return {
    action: groupBuilds.get(group.id).some((build) => build.id === buildPlan.buildId)
      ? 'none'
      : 'update',
    buildId: buildPlan.buildId,
    identifier: INTERNAL_BETA_GROUP_NAME,
    remoteId: group.id,
    target: 'internalBetaGroupAssignment',
  };
}

function baseProductEntry(baseAudit, productId) {
  return baseAudit.plan.find((entry) => (
    entry.target === 'inAppPurchase'
    && entry.identifier === productId
    && ['create', 'update', 'none'].includes(entry.action)
  )) ?? null;
}

function iapVersionNumber(resource, productId) {
  const value = remoteAttributes(resource).version;
  const number = typeof value === 'string' && /^[1-9][0-9]*$/u.test(value)
    ? Number(value)
    : value;
  if (!Number.isSafeInteger(number) || number < 1) {
    throw fail(
      'ASC_IAP_VERSION_NUMBER_INVALID',
      `${productId} IAP version number is not a positive integer.`,
    );
  }
  return number;
}

function nextIapVersionNumber(versions, productId) {
  if (versions.length === 0) return 1;
  const numbers = versions.map((resource) => (
    iapVersionNumber(resource, productId)
  ));
  if (new Set(numbers).size !== numbers.length) {
    throw fail(
      'ASC_IAP_VERSION_NUMBER_DUPLICATE',
      `${productId} IAP version number is duplicated.`,
    );
  }
  const next = Math.max(...numbers) + 1;
  if (!Number.isSafeInteger(next)) {
    throw fail(
      'ASC_IAP_VERSION_NUMBER_INVALID',
      `${productId} next IAP version number exceeds the safe range.`,
    );
  }
  return next;
}

function versionLocalizationPlan(product, draft, localizations) {
  return product.localizations.map((desired) => {
    const remote = uniqueResource(
      localizations,
      (resource) => remoteAttributes(resource).locale === desired.locale,
      `${product.productId}/${desired.locale} IAP version localization`,
    );
    const attributes = {
      description: desired.description,
      name: desired.name,
    };
    const changes = remote
      ? changesBetween(attributes, remoteAttributes(remote))
      : null;
    const action = remote
      ? Object.keys(changes).length === 0 ? 'none' : 'update'
      : 'create';
    return {
      action,
      ...(remote ? { changes, remoteId: remote.id } : {
        desired: { locale: desired.locale, ...attributes },
      }),
      identifier: `${product.productId}/${desired.locale}`,
      parentId: draft.id,
      prerequisites: [`inAppPurchaseVersion:${product.productId}`],
      target: 'inAppPurchaseVersionLocalization',
    };
  });
}

export async function auditVersionedIapLocalizations(payload, client, baseAudit) {
  const plan = [];
  const versionIds = {};
  const versionStates = {};
  for (const product of payload.inAppPurchases.products) {
    const baseProduct = baseProductEntry(baseAudit, product.productId);
    if (!baseProduct || baseProduct.action === 'create') continue;
    const remoteProductId = baseProduct.remoteId;
    const versions = await client.getAll(queryPath(
      `/v2/inAppPurchases/${remoteProductId}/versions`,
      [
        ['fields[inAppPurchaseVersions]', 'version,state'],
        ['limit', '200'],
      ],
    ));
    const reviewableVersions = versions.filter((resource) => (
      isReviewableIapVersionState(remoteAttributes(resource).state)
    ));
    const currentVersions = reviewableVersions.filter((resource) => (
      CURRENT_IAP_VERSION_STATES.has(remoteAttributes(resource).state)
    ));
    if (currentVersions.length > 1) {
      throw fail('ASC_IAP_DRAFT_DUPLICATE', `${product.productId} active version is duplicated.`);
    }
    const rejectedVersions = reviewableVersions.filter((resource) => (
      remoteAttributes(resource).state === 'DEVELOPER_REJECTED'
    ));
    if (currentVersions.length === 0 && rejectedVersions.length > 1) {
      plan.push({
        action: 'unresolved',
        code: 'ASC_IAP_REJECTED_VERSION_AMBIGUOUS',
        identifier: product.productId,
        reason:
          'more than one resubmittable DEVELOPER_REJECTED IAP version exists, '
          + 'so it is not selected automatically.',
        remoteMutationPlanned: false,
        remoteVersionIds: rejectedVersions.map((resource) => resource.id),
        target: 'inAppPurchaseVersion',
      });
      continue;
    }
    const draft = currentVersions[0] ?? rejectedVersions[0] ?? null;
    if (!draft && versions.length > 0) {
      plan.push({
        action: 'unresolved',
        code: 'ASC_IAP_VERSION_STATE_UNSUPPORTED',
        identifier: product.productId,
        reason: 'cannot safely continue the existing IAP version state, so a new version is not created automatically.',
        remoteMutationPlanned: false,
        remoteStates: versions.map((resource) => (
          remoteAttributes(resource).state ?? 'UNKNOWN'
        )),
        target: 'inAppPurchaseVersion',
      });
      continue;
    }
    if (!draft) {
      plan.push({
        action: 'create',
        capturesCurrentReviewImage: true,
        desired: { version: nextIapVersionNumber(versions, product.productId) },
        identifier: product.productId,
        parentId: remoteProductId,
        prerequisites: [
          `inAppPurchase:${product.productId}`,
          `inAppPurchaseReviewImage:${product.productId}`,
        ],
        target: 'inAppPurchaseVersion',
      });
      continue;
    }
    const localizations = await client.getAll(queryPath(
      `/v1/inAppPurchaseVersions/${draft.id}/localizations`,
      [
        ['fields[inAppPurchaseLocalizations]', 'name,locale,description'],
        ['limit', '200'],
      ],
    ));
    const localizationPlan = versionLocalizationPlan(
      product,
      draft,
      localizations,
    );
    if (
      remoteAttributes(draft).state === 'DEVELOPER_REJECTED'
      && localizationPlan.some((entry) => entry.action !== 'none')
    ) {
      plan.push({
        action: 'create',
        capturesCurrentReviewImage: true,
        desired: { version: nextIapVersionNumber(versions, product.productId) },
        identifier: product.productId,
        localizationChanges: localizationPlan
          .filter((entry) => entry.action !== 'none')
          .map((entry) => ({
            action: entry.action,
            identifier: entry.identifier,
          })),
        parentId: remoteProductId,
        prerequisites: [
          `inAppPurchase:${product.productId}`,
          `inAppPurchaseReviewImage:${product.productId}`,
        ],
        rejectedVersionId: draft.id,
        target: 'inAppPurchaseVersion',
      });
      continue;
    }
    versionIds[product.productId] = draft.id;
    versionStates[product.productId] = remoteAttributes(draft).state;
    for (const entry of localizationPlan) {
      if (
        entry.action !== 'none'
        && !EDITABLE_IAP_VERSION_STATES.has(remoteAttributes(draft).state)
      ) {
        plan.push({
          action: 'unresolved',
          code: 'ASC_IAP_VERSION_NOT_EDITABLE',
          identifier: entry.identifier,
          reason:
            `IAP version state ${remoteAttributes(draft).state ?? 'UNKNOWN'} does not `
            + 'allow direct localization edits. A new IAP version is required.',
          remoteMutationPlanned: false,
          target: 'inAppPurchaseVersionLocalization',
        });
        continue;
      }
      plan.push(entry);
    }
  }
  return { plan, versionIds, versionStates };
}

function normalizeMoney(value) {
  const text = String(value ?? '');
  if (!/^\d+(?:\.\d+)?$/u.test(text)) return null;
  const [integer, fraction = ''] = text.split('.');
  const normalizedInteger = integer.replace(/^0+(?=\d)/u, '');
  const normalizedFraction = fraction.replace(/0+$/u, '');
  return normalizedFraction === ''
    ? normalizedInteger
    : `${normalizedInteger}.${normalizedFraction}`;
}

function relationshipId(resource, name) {
  const data = resource?.relationships?.[name]?.data;
  return data && !Array.isArray(data) ? data.id ?? null : null;
}

export async function auditIapPricing(payload, client, baseAudit) {
  const plan = [];
  for (const product of payload.inAppPurchases.products) {
    const entry = baseProductEntry(baseAudit, product.productId);
    if (!entry || entry.action === 'create') continue;
    const remoteId = encodeSegment(entry.remoteId, 'IAP');
    const expected = product.pricing;
    const baseTerritoryResponse = await client.get(queryPath(
      `/v1/inAppPurchasePriceSchedules/${remoteId}/baseTerritory`,
      [['fields[territories]', 'currency']],
    ), { allowNotFound: true });
    const baseTerritory = baseTerritoryResponse?.data ?? null;
    const pricesResponse = await client.get(queryPath(
      `/v1/inAppPurchasePriceSchedules/${remoteId}/manualPrices`,
      [
        ['filter[territory]', expected.territory],
        ['fields[inAppPurchasePrices]',
          'startDate,endDate,manual,inAppPurchasePricePoint,territory'],
        ['fields[inAppPurchasePricePoints]', 'customerPrice,territory'],
        ['fields[territories]', 'currency'],
        ['include', 'inAppPurchasePricePoint,territory'],
        ['limit', '200'],
      ],
    ), { allowNotFound: true });
    if (pricesResponse?.links?.next) {
      throw fail(
        'ASC_IAP_PRICE_RESPONSE_PAGINATED',
        `${product.productId} price response cannot be fully verified in one page.`,
      );
    }
    const prices = Array.isArray(pricesResponse?.data) ? pricesResponse.data : [];
    const included = Array.isArray(pricesResponse?.included)
      ? pricesResponse.included
      : [];
    const currentPrices = prices.filter((price) => {
      const attrs = remoteAttributes(price);
      return attrs.manual === true
        && (attrs.startDate === null || attrs.startDate === undefined)
        && (attrs.endDate === null || attrs.endDate === undefined)
        && relationshipId(price, 'territory') === expected.territory;
    });
    const price = currentPrices.length === 1 && prices.length === 1
      ? currentPrices[0]
      : null;
    const pricePointId = price
      ? relationshipId(price, 'inAppPurchasePricePoint')
      : null;
    const pricePoint = included.find((resource) => (
      resource.type === 'inAppPurchasePricePoints'
      && resource.id === pricePointId
    )) ?? null;
    const territory = included.find((resource) => (
      resource.type === 'territories'
      && resource.id === expected.territory
    )) ?? null;
    const actualPrice = normalizeMoney(remoteAttributes(pricePoint).customerPrice);
    const expectedPrice = normalizeMoney(expected.customerPrice);
    const matches = expected.strategy === 'VERIFY_EXISTING_MANUAL_BASE_PRICE'
      && baseTerritory?.id === expected.territory
      && remoteAttributes(baseTerritory).currency === expected.currency
      && territory?.id === expected.territory
      && remoteAttributes(territory).currency === expected.currency
      && actualPrice !== null
      && actualPrice === expectedPrice;
    plan.push(matches ? {
      action: 'none',
      identifier: product.productId,
      remoteId: entry.remoteId,
      target: 'inAppPurchasePricing',
      verified: {
        currency: expected.currency,
        customerPrice: expected.customerPrice,
        pricePointId,
        territory: expected.territory,
      },
    } : {
      action: 'unresolved',
      actual: {
        baseTerritory: baseTerritory?.id ?? null,
        currency: remoteAttributes(baseTerritory).currency
          ?? remoteAttributes(territory).currency
          ?? null,
        customerPrice: actualPrice,
        manualPriceCount: prices.length,
      },
      code: 'ASC_IAP_PRICE_SCHEDULE_MISMATCH',
      expected,
      identifier: product.productId,
      reason: 'existing manual base price schedule does not exactly match the verified manifest; not changing prices.',
      remoteId: entry.remoteId,
      remoteMutationPlanned: false,
      target: 'inAppPurchasePricing',
    });
  }
  return plan;
}

export async function auditAppAvailability(payload, client) {
  const requirements = payload.release.availability;
  const authoritativeResponse = await client.get(queryPath(
    '/v1/territories',
    [
      ['fields[territories]', 'currency'],
      ['limit', '200'],
    ],
  ));
  if (authoritativeResponse?.links?.next) {
    throw fail(
      'ASC_TERRITORY_CATALOG_PAGINATED',
      'authoritative territory list cannot be fully verified in one page.',
    );
  }
  const authoritativeTerritories = Array.isArray(authoritativeResponse?.data)
    ? authoritativeResponse.data
    : [];
  const authoritativeTotal = Number(authoritativeResponse?.meta?.paging?.total);
  const authoritativeIds = authoritativeTerritories.map((territory) => territory.id);
  if (
    !Number.isSafeInteger(authoritativeTotal)
    || authoritativeTotal < 1
    || authoritativeTotal !== authoritativeTerritories.length
    || authoritativeIds.some((id) => typeof id !== 'string' || id === '')
    || new Set(authoritativeIds).size !== authoritativeIds.length
  ) {
    throw fail(
      'ASC_TERRITORY_CATALOG_INCOMPLETE',
      'authoritative territory list does not exactly match the paging total.',
    );
  }
  const response = await client.get(queryPath(
    `/v1/apps/${encodeSegment(payload.release.appId, 'app')}/appAvailabilityV2`,
    [['fields[appAvailabilities]', 'availableInNewTerritories']],
  ));
  const availability = response?.data;
  if (!availability?.id) {
    throw fail('ASC_APP_AVAILABILITY_NOT_FOUND', 'app availability-country settings were not found.');
  }
  const territoriesResponse = await client.get(queryPath(
    `/v2/appAvailabilities/${encodeSegment(availability.id, 'app availability')}/territoryAvailabilities`,
    [
      ['fields[territoryAvailabilities]', 'available,territory'],
      ['include', 'territory'],
      ['limit', '200'],
    ],
  ));
  if (territoriesResponse?.links?.next) {
    throw fail(
      'ASC_APP_AVAILABILITY_PAGINATED',
      'availability countries cannot be fully verified in one page.',
    );
  }
  const resources = Array.isArray(territoriesResponse?.data)
    ? territoriesResponse.data
    : [];
  const availabilityTotal = Number(territoriesResponse?.meta?.paging?.total);
  if (
    !Number.isSafeInteger(availabilityTotal)
    || availabilityTotal !== resources.length
    || availabilityTotal !== authoritativeTotal
  ) {
    throw fail(
      'ASC_APP_AVAILABILITY_INCOMPLETE',
      'availability-country response does not exactly match the authoritative territory total.',
    );
  }
  const availabilityByTerritory = new Map();
  for (const resource of resources) {
    const territoryId = relationshipId(resource, 'territory');
    if (!territoryId || availabilityByTerritory.has(territoryId)) {
      throw fail(
        'ASC_APP_AVAILABILITY_INVALID',
        'availability-country response is missing a territory or has duplicates.',
      );
    }
    availabilityByTerritory.set(
      territoryId,
      remoteAttributes(resource).available === true,
    );
  }
  const unavailable = [...availabilityByTerritory]
    .filter(([, available]) => !available)
    .map(([territory]) => territory)
    .sort();
  const expectedUnavailable = [...requirements.excludedTerritories].sort();
  const requiredIncluded = requirements.requiredIncludedTerritories;
  const availabilityIds = [...availabilityByTerritory.keys()].sort();
  const matches = canonicalJson(availabilityIds)
      === canonicalJson([...authoritativeIds].sort())
    && remoteAttributes(availability).availableInNewTerritories
      === requirements.availableInNewTerritories
    && canonicalJson(unavailable) === canonicalJson(expectedUnavailable)
    && requiredIncluded.every((territory) => (
      availabilityByTerritory.get(territory) === true
    ));
  return matches ? {
    action: 'none',
    identifier: payload.release.appId,
    remoteId: availability.id,
    target: 'appAvailability',
    verified: {
      availableInNewTerritories: true,
      availableTerritoryCount: [...availabilityByTerritory.values()]
        .filter(Boolean).length,
      excludedTerritories: unavailable,
      territoryCount: availabilityByTerritory.size,
    },
  } : {
    action: 'unresolved',
    actual: {
      availableInNewTerritories:
        remoteAttributes(availability).availableInNewTerritories ?? null,
      excludedTerritories: unavailable,
      requiredIncluded: Object.fromEntries(requiredIncluded.map((territory) => (
        [territory, availabilityByTerritory.get(territory) ?? null]
      ))),
    },
    code: 'ASC_APP_AVAILABILITY_MISMATCH',
    expected: requirements,
    identifier: payload.release.appId,
    reason: 'mainland China exclusion and major-country inclusion differ from the verified manifest; automatic change is unsupported.',
    remoteId: availability.id,
    remoteMutationPlanned: false,
    target: 'appAvailability',
  };
}

export async function auditAppStoreConnectApplyReadiness({ payload, client } = {}) {
  const base = await auditAppStoreConnectRelease({ payload, client });
  const build = await auditBuildAssociation(payload, client, base);
  const internalBetaGroup = await auditInternalBetaGroup(payload, client, build);
  const iap = await auditVersionedIapLocalizations(payload, client, base);
  const pricing = await auditIapPricing(payload, client, base);
  const availability = await auditAppAvailability(payload, client);
  const plan = [
    ...base.plan.filter((entry) => entry.target !== 'inAppPurchaseLocalization'),
    ...(base.remote.excludedIapProducts ?? []).map((product) => ({
      action: 'none',
      identifier: product.productId,
      remoteId: product.remoteId,
      submissionEligible: false,
      target: 'legacyInAppPurchaseExclusion',
    })),
    ...iap.plan,
    ...pricing,
    availability,
    build,
    internalBetaGroup,
  ];
  return {
    ...base,
    mode: 'GET_ONLY_REMOTE_APPLY_PREFLIGHT',
    plan,
    remote: {
      ...base.remote,
      iapVersionIds: iap.versionIds,
      iapVersionStates: iap.versionStates,
    },
    requests: client.requests,
    summary: summarizeRemotePlan(plan),
    remoteMutationImplemented: true,
  };
}

function isInside(parent, child) {
  const relation = relative(resolve(parent), resolve(child));
  return relation === '' || (
    relation !== '..'
    && !relation.startsWith(`..${sep}`)
    && !isAbsolute(relation)
  );
}

function readVerifiedArtifact(repoRoot, artifact, label) {
  if (
    !artifact
    || typeof artifact.path !== 'string'
    || isAbsolute(artifact.path)
    || artifact.path.split(/[\\/]/u).some((part) => part === '' || part === '..')
  ) {
    throw fail('ASC_ASSET_PATH_INVALID', `${label} path is not safe.`);
  }
  const root = realpathSync(resolve(repoRoot));
  const path = resolve(root, artifact.path);
  if (!isInside(root, path)) {
    throw fail('ASC_ASSET_PATH_INVALID', `${label} points outside the repository.`);
  }
  const relativeParts = relative(root, path).split(sep).filter(Boolean);
  let current = root;
  for (const part of relativeParts) {
    current = resolve(current, part);
    if (lstatSync(current).isSymbolicLink()) {
      throw fail('ASC_ASSET_SYMLINK_REJECTED', `${label} path contains a symbolic link.`);
    }
  }
  const info = lstatSync(path);
  if (!info.isFile() || info.size !== artifact.size) {
    throw fail('ASC_ASSET_CHANGED', `${label} size differs from the verified manifest.`);
  }
  const contents = readFileSync(path);
  if (sha256(contents) !== artifact.sha256 || md5(contents) !== artifact.md5) {
    throw fail('ASC_ASSET_CHANGED', `${label} checksum differs from the verified manifest.`);
  }
  return contents;
}

export function verifyAppStoreReleaseSourceArtifacts({
  payload,
  repoRoot,
} = {}) {
  if (!Array.isArray(payload?.sources)) {
    throw fail(
      'ASC_RELEASE_SOURCES_INVALID',
      'verified manifest has no source artifact list.',
    );
  }
  for (const [path, label] of [
    [
      APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
      'App Store screenshot provenance',
    ],
    [
      APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
      'canonical Android capture report',
    ],
  ]) {
    const matches = payload.sources.filter((artifact) => (
      artifact?.path === path
    ));
    if (matches.length !== 1) {
      throw fail(
        'ASC_RELEASE_SOURCE_MISSING',
        `${label} artifact must appear exactly once in the verified manifest.`,
      );
    }
    readVerifiedArtifact(repoRoot, matches[0], label);
  }
  return true;
}

function findScreenshotSet(payload, identifier) {
  const [locale, displayType] = identifier.split('/');
  const localization = payload.appLocalizations.find((entry) => entry.locale === locale);
  const set = localization?.screenshots.find((entry) => entry.displayType === displayType);
  if (!set) throw fail('ASC_PLAN_PAYLOAD_MISMATCH', `${identifier} screenshot payload is missing.`);
  return set;
}

function findIapProduct(payload, productId) {
  const product = payload.inAppPurchases.products.find((entry) => entry.productId === productId);
  if (!product) throw fail('ASC_PLAN_PAYLOAD_MISMATCH', `${productId} IAP payload is missing.`);
  return product;
}

function assetState(resource) {
  return remoteAttributes(resource).assetDeliveryState?.state ?? null;
}

async function waitForAsset({
  client,
  path,
  sleepImpl,
  attempts = 30,
  delayMs = 2_000,
}) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const response = await client.get(path);
    const state = assetState(response?.data);
    if (state === 'COMPLETE') return response.data;
    if (state === 'FAILED') {
      throw fail('ASC_ASSET_PROCESSING_FAILED', `${path} asset processing failed.`);
    }
    if (!['AWAITING_UPLOAD', 'UPLOAD_COMPLETE', 'PROCESSING'].includes(state)) {
      throw fail('ASC_ASSET_STATE_UNKNOWN', `${path} asset state cannot be trusted: ${state ?? 'null'}.`);
    }
    if (attempt + 1 < attempts) await sleepImpl(delayMs);
  }
  throw fail('ASC_ASSET_PROCESSING_TIMEOUT', `${path} asset processing did not finish in time.`);
}

async function reserveAndUpload({
  artifact,
  client,
  commitPath,
  createBody,
  createPath,
  getClient,
  repoRoot,
  resourceType,
  sleepImpl,
  useChecksum,
  verifiedContents = null,
}) {
  const contents = verifiedContents
    ?? readVerifiedArtifact(repoRoot, artifact, artifact.path);
  if (
    !Buffer.isBuffer(contents)
    || contents.length !== artifact.size
    || sha256(contents) !== artifact.sha256
    || md5(contents) !== artifact.md5
  ) {
    throw fail(
      'ASC_ASSET_SNAPSHOT_INVALID',
      `${artifact.fileName} in-memory snapshot differs from the verified manifest.`,
    );
  }
  const reservation = await client.post(createPath, createBody);
  const resource = reservation?.data;
  const operations = remoteAttributes(resource).uploadOperations;
  if (!resource?.id || remoteAttributes(resource).fileSize !== artifact.size) {
    throw fail('ASC_ASSET_RESERVATION_INVALID', `${artifact.fileName} reservation response differs.`);
  }
  await client.uploadOperations(operations, contents);
  await client.patch(`${commitPath}/${encodeSegment(resource.id, 'asset')}`, {
    data: {
      attributes: {
        uploaded: true,
        ...(useChecksum ? { sourceFileChecksum: artifact.md5 } : {}),
      },
      id: resource.id,
      type: resourceType,
    },
  });
  await waitForAsset({
    client: getClient,
    path: `${commitPath}/${encodeSegment(resource.id, 'asset')}`,
    sleepImpl,
  });
  return resource.id;
}

export async function uploadScreenshotSet({
  client,
  getClient,
  remoteFiles = [],
  repoRoot,
  setId,
  screenshotSet,
  sleepImpl,
}) {
  const ids = Array(screenshotSet.files.length).fill(null);
  const obsolete = remoteFiles.map((file) => ({ ...file }));
  for (const [index, artifact] of screenshotSet.files.entries()) {
    const matchIndex = obsolete.findIndex((file) => (
      file.fileName === artifact.fileName
      && Number(file.fileSize) === artifact.size
      && file.sourceFileChecksum === artifact.md5
      && (
        file.assetDeliveryState === null
        || file.assetDeliveryState === 'COMPLETE'
      )
    ));
    if (matchIndex < 0) continue;
    ids[index] = obsolete[matchIndex].id;
    obsolete.splice(matchIndex, 1);
  }
  let remoteCount = remoteFiles.length;
  for (const [index, artifact] of screenshotSet.files.entries()) {
    if (ids[index]) continue;
    while (remoteCount >= 10) {
      const safeDelete = obsolete.shift();
      if (!safeDelete?.id) {
        throw fail(
          'ASC_SCREENSHOT_CAPACITY_UNSAFE',
          'no room to upload new screenshots first, so existing assets cannot be replaced safely.',
        );
      }
      await client.delete(
        `/v1/appScreenshots/${encodeSegment(safeDelete.id, 'screenshot')}`,
      );
      remoteCount -= 1;
    }
    const id = await reserveAndUpload({
      artifact,
      client,
      commitPath: '/v1/appScreenshots',
      createBody: {
        data: {
          attributes: { fileName: artifact.fileName, fileSize: artifact.size },
          relationships: {
            appScreenshotSet: {
              data: { id: setId, type: 'appScreenshotSets' },
            },
          },
          type: 'appScreenshots',
        },
      },
      createPath: '/v1/appScreenshots',
      getClient,
      repoRoot,
      resourceType: 'appScreenshots',
      sleepImpl,
      useChecksum: true,
    });
    ids[index] = id;
    remoteCount += 1;
    const replaced = obsolete.shift();
    if (replaced) {
      await client.delete(
        `/v1/appScreenshots/${encodeSegment(replaced.id, 'screenshot')}`,
      );
      remoteCount -= 1;
    }
  }
  if (ids.some((id) => !id)) {
    throw fail('ASC_SCREENSHOT_RECONCILE_INCOMPLETE', 'screenshot ID set is incomplete.');
  }
  for (const extra of obsolete) {
    await client.delete(
      `/v1/appScreenshots/${encodeSegment(extra.id, 'screenshot')}`,
    );
  }
  await client.patch(
    `/v1/appScreenshotSets/${encodeSegment(setId, 'screenshot set')}/relationships/appScreenshots`,
    { data: ids.map((id) => ({ id, type: 'appScreenshots' })) },
  );
}

function assertParentId(entry) {
  return requireString(entry.parentId, `${entry.target} parentId`);
}

export async function applyPlanEntry({
  client,
  entry,
  getClient,
  payload,
  repoRoot,
  sleepImpl,
}) {
  if (!['create', 'update', 'replace'].includes(entry.action)) {
    throw fail('ASC_PLAN_ACTION_NOT_MUTABLE', `${entry.action} plan cannot be applied.`);
  }
  if (entry.target === 'appStoreVersion') {
    if (entry.action === 'create') {
      await client.post('/v1/appStoreVersions', {
        data: {
          attributes: entry.desired,
          relationships: {
            app: { data: { id: payload.release.appId, type: 'apps' } },
          },
          type: 'appStoreVersions',
        },
      });
      return;
    }
    const desired = desiredFromEntry(entry);
    if (Object.hasOwn(desired, 'platform')) {
      throw fail(
        'ASC_APP_STORE_VERSION_PLATFORM_IMMUTABLE',
        'App Store version platform can only be set when creating.',
      );
    }
    await client.patch(`/v1/appStoreVersions/${encodeSegment(entry.remoteId, 'version')}`, {
      data: {
        attributes: desired,
        id: entry.remoteId,
        type: 'appStoreVersions',
      },
    });
    return;
  }
  if (entry.target === 'appStoreReviewDetail') {
    if (entry.action !== 'update') {
      throw fail(
        'ASC_APP_STORE_REVIEW_DETAIL_CREATE_UNSAFE',
        'only notes on an existing App Review Detail can be changed automatically.',
      );
    }
    const desired = desiredFromEntry(entry);
    if (
      Object.keys(desired).length !== 1
      || typeof desired.notes !== 'string'
      || desired.notes.trim() === ''
    ) {
      throw fail(
        'ASC_APP_STORE_REVIEW_DETAIL_PATCH_UNSAFE',
        'App Review Detail can only change the notes field.',
      );
    }
    await client.patch(
      `/v1/appStoreReviewDetails/${encodeSegment(entry.remoteId, 'review detail')}`,
      {
        data: {
          attributes: { notes: desired.notes },
          id: entry.remoteId,
          type: 'appStoreReviewDetails',
        },
      },
    );
    return;
  }
  if (entry.target === 'appInfoLocalization') {
    const attributes = desiredFromEntry(entry);
    if (entry.action === 'create') {
      await client.post('/v1/appInfoLocalizations', {
        data: {
          attributes: { locale: entry.identifier, ...attributes },
          relationships: {
            appInfo: { data: { id: assertParentId(entry), type: 'appInfos' } },
          },
          type: 'appInfoLocalizations',
        },
      });
    } else {
      await client.patch(`/v1/appInfoLocalizations/${encodeSegment(entry.remoteId, 'app info localization')}`, {
        data: { attributes, id: entry.remoteId, type: 'appInfoLocalizations' },
      });
    }
    return;
  }
  if (entry.target === 'appStoreVersionLocalization') {
    const attributes = desiredFromEntry(entry);
    if (entry.action === 'create') {
      const locale = entry.identifier.split('/').at(-1);
      await client.post('/v1/appStoreVersionLocalizations', {
        data: {
          attributes: { locale, ...attributes },
          relationships: {
            appStoreVersion: {
              data: { id: assertParentId(entry), type: 'appStoreVersions' },
            },
          },
          type: 'appStoreVersionLocalizations',
        },
      });
    } else {
      await client.patch(
        `/v1/appStoreVersionLocalizations/${encodeSegment(entry.remoteId, 'version localization')}`,
        { data: { attributes, id: entry.remoteId, type: 'appStoreVersionLocalizations' } },
      );
    }
    return;
  }
  if (entry.target === 'appScreenshotSet') {
    const screenshotSet = findScreenshotSet(payload, entry.identifier);
    // Validate every local byte before deleting or reserving any remote asset.
    for (const artifact of screenshotSet.files) {
      readVerifiedArtifact(repoRoot, artifact, artifact.path);
    }
    let setId = entry.remoteId;
    if (entry.action === 'create') {
      const response = await client.post('/v1/appScreenshotSets', {
        data: {
          attributes: { screenshotDisplayType: screenshotSet.displayType },
          relationships: {
            appStoreVersionLocalization: {
              data: {
                id: assertParentId(entry),
                type: 'appStoreVersionLocalizations',
              },
            },
          },
          type: 'appScreenshotSets',
        },
      });
      setId = response?.data?.id;
      requireString(setId, 'created screenshot set ID');
    } else {
      if (!Array.isArray(entry.remoteFiles) || entry.remoteFiles.some((file) => !file.id)) {
        throw fail('ASC_SCREENSHOT_DELETE_IDS_MISSING', 'remote screenshot IDs to replace are incomplete.');
      }
    }
    await uploadScreenshotSet({
      client,
      getClient,
      remoteFiles: entry.action === 'replace' ? entry.remoteFiles : [],
      repoRoot,
      screenshotSet,
      setId,
      sleepImpl,
    });
    return;
  }
  if (entry.target === 'inAppPurchase') {
    if (entry.action === 'create') {
      await client.post('/v2/inAppPurchases', {
        data: {
          attributes: entry.desired,
          relationships: {
            app: { data: { id: payload.release.appId, type: 'apps' } },
          },
          type: 'inAppPurchases',
        },
      });
      return;
    }
    const attributes = desiredFromEntry(entry);
    if (Object.hasOwn(attributes, 'inAppPurchaseType')) {
      delete attributes.inAppPurchaseType;
    }
    await client.patch(`/v2/inAppPurchases/${encodeSegment(entry.remoteId, 'IAP')}`, {
      data: { attributes, id: entry.remoteId, type: 'inAppPurchases' },
    });
    return;
  }
  if (entry.target === 'inAppPurchaseVersion') {
    if (entry.action !== 'create' || typeof getClient?.getAll !== 'function') {
      throw fail(
        'ASC_IAP_VERSION_CREATE_PREFLIGHT_REQUIRED',
        'creating an IAP version requires a GET preflight client.',
      );
    }
    const parentId = assertParentId(entry);
    const expectedVersion = entry.desired?.version;
    if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 1) {
      throw fail(
        'ASC_IAP_VERSION_NUMBER_INVALID',
        'IAP version number to create must be a positive integer.',
      );
    }
    const versionsPath = queryPath(
      `/v2/inAppPurchases/${encodeSegment(parentId, 'IAP')}/versions`,
      [
        ['fields[inAppPurchaseVersions]', 'version,state'],
        ['limit', '200'],
      ],
    );
    const before = await getClient.getAll(versionsPath);
    const activeBefore = before.filter((resource) => (
      CURRENT_IAP_VERSION_STATES.has(remoteAttributes(resource).state)
    ));
    if (activeBefore.length > 0) {
      throw fail(
        'ASC_IAP_VERSION_CREATE_RACE',
        `${entry.identifier} IAP already has an active version; not creating a new one.`,
      );
    }
    if (
      entry.rejectedVersionId
      && !before.some((resource) => (
        resource.id === entry.rejectedVersionId
        && remoteAttributes(resource).state === 'DEVELOPER_REJECTED'
      ))
    ) {
      throw fail(
        'ASC_IAP_REJECTED_VERSION_CHANGED',
        `${entry.identifier} rejected version changed between preflight checks.`,
      );
    }
    const nextVersion = nextIapVersionNumber(before, entry.identifier);
    if (nextVersion !== expectedVersion) {
      throw fail(
        'ASC_IAP_VERSION_CREATE_RACE',
        `${entry.identifier} next IAP version changed from ${expectedVersion} `
          + `to ${nextVersion}.`,
      );
    }
    const response = await client.post('/v1/inAppPurchaseVersions', {
      data: {
        relationships: {
          inAppPurchase: {
            data: { id: parentId, type: 'inAppPurchases' },
          },
        },
        type: 'inAppPurchaseVersions',
      },
    });
    const createdId = requireString(
      response?.data?.id,
      'created IAP version ID',
    );
    const after = await getClient.getAll(versionsPath);
    const created = after.filter((resource) => resource.id === createdId);
    const activeAfter = after.filter((resource) => (
      CURRENT_IAP_VERSION_STATES.has(remoteAttributes(resource).state)
    ));
    if (
      created.length !== 1
      || activeAfter.length !== 1
      || activeAfter[0].id !== createdId
      || iapVersionNumber(created[0], entry.identifier) !== expectedVersion
      || remoteAttributes(created[0]).state !== 'PREPARE_FOR_SUBMISSION'
    ) {
      throw fail(
        'ASC_IAP_VERSION_CREATE_READBACK_FAILED',
        `${entry.identifier} new IAP version ${expectedVersion} create result `
          + 'does not match GET readback.',
      );
    }
    return;
  }
  if (entry.target === 'inAppPurchaseVersionLocalization') {
    const attributes = desiredFromEntry(entry);
    if (entry.action === 'create') {
      await client.post('/v2/inAppPurchaseLocalizations', {
        data: {
          attributes,
          relationships: {
            version: {
              data: { id: assertParentId(entry), type: 'inAppPurchaseVersions' },
            },
          },
          type: 'inAppPurchaseLocalizations',
        },
      });
    } else {
      await client.patch(
        `/v2/inAppPurchaseLocalizations/${encodeSegment(entry.remoteId, 'IAP localization')}`,
        { data: { attributes, id: entry.remoteId, type: 'inAppPurchaseLocalizations' } },
      );
    }
    return;
  }
  if (entry.target === 'inAppPurchaseReviewImage') {
    const product = findIapProduct(payload, entry.identifier);
    const verifiedContents = readVerifiedArtifact(
      repoRoot,
      product.reviewImage,
      product.reviewImage.path,
    );
    if (entry.action === 'replace') {
      requireString(entry.remoteId, 'IAP review screenshot ID');
      await client.delete(
        `/v1/inAppPurchaseAppStoreReviewScreenshots/${encodeSegment(entry.remoteId, 'IAP review screenshot')}`,
      );
    }
    await reserveAndUpload({
      artifact: product.reviewImage,
      client,
      commitPath: '/v1/inAppPurchaseAppStoreReviewScreenshots',
      createBody: {
        data: {
          attributes: {
            fileName: product.reviewImage.fileName,
            fileSize: product.reviewImage.size,
          },
          relationships: {
            inAppPurchaseV2: {
              data: { id: assertParentId(entry), type: 'inAppPurchases' },
            },
          },
          type: 'inAppPurchaseAppStoreReviewScreenshots',
        },
      },
      createPath: '/v1/inAppPurchaseAppStoreReviewScreenshots',
      getClient,
      repoRoot,
      resourceType: 'inAppPurchaseAppStoreReviewScreenshots',
      sleepImpl,
      useChecksum: true,
      verifiedContents,
    });
    return;
  }
  if (entry.target === 'buildAssociation') {
    const versionId = entry.remoteId;
    if (!versionId) {
      throw fail('ASC_BUILD_VERSION_ID_MISSING', 'App Store version ID to attach the build is missing.');
    }
    await client.patch(
      `/v1/appStoreVersions/${encodeSegment(versionId, 'version')}/relationships/build`,
      { data: { id: entry.desiredBuildId, type: 'builds' } },
    );
    return;
  }
  if (entry.target === 'internalBetaGroupAssignment') {
    await client.post(
      `/v1/betaGroups/${encodeSegment(entry.remoteId, 'beta group')}/relationships/builds`,
      { data: [{ id: requireString(entry.buildId, 'build ID'), type: 'builds' }] },
    );
    return;
  }
  throw fail('ASC_PLAN_TARGET_UNSUPPORTED', `${entry.target} remote apply is unsupported.`);
}

const TARGET_ORDER = Object.freeze([
  'appStoreVersion',
  'appStoreReviewDetail',
  'appInfoLocalization',
  'appStoreVersionLocalization',
  'appScreenshotSet',
  'inAppPurchase',
  'inAppPurchaseReviewImage',
  'inAppPurchaseVersion',
  'inAppPurchaseVersionLocalization',
  'buildAssociation',
  'internalBetaGroupAssignment',
]);

function actionableEntries(audit) {
  return audit.plan.filter((entry) => ['create', 'update', 'replace'].includes(entry.action))
    .sort((left, right) => {
      const target = TARGET_ORDER.indexOf(left.target) - TARGET_ORDER.indexOf(right.target);
      return target || left.identifier.localeCompare(right.identifier, 'en');
    });
}

function hardBlockers(audit) {
  return audit.plan.filter((entry) => (
    entry.action === 'unresolved' && entry.code !== SOFT_IAP_GATE
  ));
}

function mutationFingerprint(entry) {
  return canonicalJson({
    action: entry.action,
    desired: desiredFromEntry(entry),
    identifier: entry.identifier,
    target: entry.target,
  });
}

function assertEditableState(audit, entry) {
  if (
    audit.remote.versionId
    && [
      'appStoreVersion',
      'appStoreReviewDetail',
      'appInfoLocalization',
      'appStoreVersionLocalization',
      'appScreenshotSet',
      'buildAssociation',
    ].includes(entry.target)
  ) {
    assertEditableAppStoreVersionState(audit.remote.versionState);
  }
}

export async function applyAppStoreConnectRelease({
  client,
  confirmation,
  getClient,
  manifest,
  maxSteps = 200,
  payload,
  repoRoot,
  reviewConfirmation = null,
  sleepImpl = (milliseconds) => new Promise((resolvePromise) => {
    setTimeout(resolvePromise, milliseconds);
  }),
  submitReview = false,
} = {}) {
  assertAppStoreApplyAuthorization({
    confirmation,
    manifest,
    payload,
    reviewConfirmation,
    submitReview,
  });
  if (
    !client?.post
    || !client?.patch
    || !client?.delete
    || !getClient?.get
    || !getClient?.getAll
  ) {
    throw new TypeError('both ASC GET client and mutation client are required');
  }
  // Provenance and its canonical capture report authorize the screenshot
  // bytes in this release. Refuse all network work if either local artifact
  // has changed since the confirmation token was issued.
  verifyAppStoreReleaseSourceArtifacts({ payload, repoRoot });
  const applied = [];
  const appliedFingerprints = new Set();
  let audit;
  for (let step = 0; step <= maxSteps; step += 1) {
    audit = await auditAppStoreConnectApplyReadiness({ payload, client: getClient });
    const hard = hardBlockers(audit);
    if (hard.length > 0) {
      return {
        applied,
        blockers: hard,
        complete: false,
        finalAudit: audit,
        reviewSubmitted: false,
      };
    }
    const actions = actionableEntries(audit);
    if (actions.length === 0) break;
    if (step === maxSteps) {
      throw fail('ASC_RECONCILE_LIMIT', `remote apply did not converge within ${maxSteps} steps.`);
    }
    const entry = actions[0];
    const fingerprint = mutationFingerprint(entry);
    if (appliedFingerprints.has(fingerprint)) {
      return {
        applied,
        blockers: [{
          action: 'unresolved',
          code: 'ASC_REMOTE_READBACK_NOT_CONVERGED',
          identifier: entry.identifier,
          reason: 'the same change reappeared on GET revalidation; stopped duplicate writes.',
          remoteMutationPlanned: false,
          target: entry.target,
        }],
        complete: false,
        finalAudit: audit,
        reviewSubmitted: false,
      };
    }
    assertEditableState(audit, entry);
    // GET reconciliation can take time. Re-read both approval artifacts at
    // the last local boundary before every remote mutation.
    verifyAppStoreReleaseSourceArtifacts({ payload, repoRoot });
    await applyPlanEntry({
      client,
      entry,
      getClient,
      payload,
      repoRoot,
      sleepImpl,
    });
    applied.push({
      action: entry.action,
      identifier: entry.identifier,
      target: entry.target,
    });
    appliedFingerprints.add(fingerprint);
  }
  const unresolved = audit.plan.filter((entry) => entry.action === 'unresolved');
  if (unresolved.length > 0) {
    return {
      applied,
      blockers: unresolved,
      complete: false,
      finalAudit: audit,
      reviewSubmitted: false,
    };
  }
  let review = null;
  if (submitReview) {
    verifyAppStoreReleaseSourceArtifacts({ payload, repoRoot });
    review = await submitAppStoreConnectReview({
      audit,
      client,
      getClient,
      manifest,
      reviewConfirmation,
      sleepImpl,
    });
  }
  return {
    applied,
    blockers: [],
    complete: true,
    finalAudit: audit,
    reviewSubmitted: review?.submitted ?? false,
    review,
  };
}

function reviewItemTarget(item) {
  for (const [relationship, type] of [
    ['appStoreVersion', 'appStoreVersions'],
    ['inAppPurchaseVersion', 'inAppPurchaseVersions'],
  ]) {
    const data = item?.relationships?.[relationship]?.data;
    if (data?.id && data?.type === type) return `${type}:${data.id}`;
  }
  return null;
}

async function readReviewItems(getClient, submissionId) {
  return getClient.getAll(queryPath(
    `/v1/reviewSubmissions/${encodeSegment(submissionId, 'review submission')}/items`,
    [
      ['fields[reviewSubmissionItems]', 'state,appStoreVersion,inAppPurchaseVersion'],
      ['limit', '200'],
    ],
  ));
}

async function addReviewItem(client, submissionId, relationship, type, id) {
  await client.post('/v1/reviewSubmissionItems', {
    data: {
      relationships: {
        [relationship]: { data: { id, type } },
        reviewSubmission: {
          data: { id: submissionId, type: 'reviewSubmissions' },
        },
      },
      type: 'reviewSubmissionItems',
    },
  });
}

function reviewTargets(items, expectedTargets, { exact }) {
  const itemTargets = items.map(reviewItemTarget);
  if (itemTargets.some((target) => target === null)) {
    throw fail(
      'ASC_REVIEW_SUBMISSION_ITEM_UNSUPPORTED',
      'review submission has an unidentified item; not changing automatically.',
    );
  }
  const targets = new Set(itemTargets);
  if (targets.size !== items.length) {
    throw fail(
      'ASC_REVIEW_SUBMISSION_ITEMS_DUPLICATE',
      'review submission has duplicate items; not changing automatically.',
    );
  }
  const unexpected = [...targets].filter((target) => !expectedTargets.has(target));
  const missing = [...expectedTargets].filter((target) => !targets.has(target));
  if (unexpected.length > 0 || (exact && missing.length > 0)) {
    throw fail(
      exact
        ? 'ASC_REVIEW_ITEMS_NOT_VERIFIED'
        : 'ASC_REVIEW_SUBMISSION_HAS_UNEXPECTED_ITEMS',
      exact
        ? 'review-item GET revalidation does not exactly match the manifest.'
        : `existing review submission has items outside the manifest: ${unexpected.join(', ')}.`,
    );
  }
  return targets;
}

export async function pollAppStoreReviewSubmission({
  attempts = 30,
  delayMs = 2_000,
  getClient,
  sleepImpl = (milliseconds) => new Promise((resolvePromise) => {
    setTimeout(resolvePromise, milliseconds);
  }),
  submissionId,
} = {}) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const response = await getClient.get(queryPath(
      `/v1/reviewSubmissions/${encodeSegment(submissionId, 'review submission')}`,
      [['fields[reviewSubmissions]', 'platform,state,submittedDate']],
    ));
    const state = remoteAttributes(response?.data).state;
    if (SUBMITTED_REVIEW_STATES.has(state)) return response.data;
    if (state === 'UNRESOLVED_ISSUES') {
      throw fail(
        'ASC_REVIEW_UNRESOLVED_ISSUES',
        'review submission transitioned to UNRESOLVED_ISSUES.',
      );
    }
    if (state !== 'READY_FOR_REVIEW') {
      throw fail(
        'ASC_REVIEW_STATE_NOT_SUBMITTABLE',
        `review submission state ${state ?? 'UNKNOWN'} is not treated as success.`,
      );
    }
    if (attempt + 1 < attempts) await sleepImpl(delayMs);
  }
  throw fail(
    'ASC_REVIEW_SUBMISSION_TIMEOUT',
    'review submission did not leave READY_FOR_REVIEW; not treating as complete.',
  );
}

export async function verifySubmittedRelease({
  audit,
  expectedTargets,
  getClient,
  submissionId,
  versionId,
}) {
  const items = await readReviewItems(getClient, submissionId);
  reviewTargets(items, expectedTargets, { exact: true });
  const buildEntry = audit.plan.find((entry) => (
    entry.target === 'buildAssociation'
  ));
  const expectedBuildId = requireString(
    buildEntry?.buildId ?? buildEntry?.desiredBuildId,
    'verified build ID',
  );
  const buildResponse = await getClient.get(queryPath(
    `/v1/appStoreVersions/${encodeSegment(versionId, 'version')}/build`,
    [['fields[builds]', 'version,expired,processingState,buildAudienceType']],
  ));
  if (buildResponse?.data?.id !== expectedBuildId) {
    throw fail(
      'ASC_REVIEW_BUILD_NOT_VERIFIED',
      `build attached to the review version differs from verified ${buildEntry.identifier}.`,
    );
  }
  return { buildId: expectedBuildId, items: items.length };
}

export async function submitAppStoreConnectReview({
  audit,
  client,
  getClient,
  manifest,
  reviewConfirmation,
  reviewPollAttempts = 30,
  reviewPollDelayMs = 2_000,
  sleepImpl = (milliseconds) => new Promise((resolvePromise) => {
    setTimeout(resolvePromise, milliseconds);
  }),
} = {}) {
  if (reviewConfirmation !== appStoreConfirmationToken(manifest, 'review')) {
    throw fail('ASC_REVIEW_CONFIRMATION_MISMATCH', 'review-submission-only confirmation token differs.');
  }
  if (
    audit?.mode !== 'GET_ONLY_REMOTE_APPLY_PREFLIGHT'
    || actionableEntries(audit).length > 0
    || audit.plan.some((entry) => entry.action === 'unresolved')
  ) {
    throw fail('ASC_REVIEW_PREFLIGHT_NOT_CONVERGED', 'cannot submit for review before GET preflight fully converges.');
  }
  const versionId = requireString(audit.remote.versionId, 'App Store version ID');
  const desiredProductIds = manifest.payload.inAppPurchases.products
    .map((product) => product.productId);
  if (
    desiredProductIds.length !== IAP_PRODUCT_IDS.length
    || desiredProductIds.some((productId) => productId.endsWith('.hero_bundle'))
  ) {
    throw fail(
      'ASC_REVIEW_IAP_SET_INVALID',
      `review-submission IAP set must be the verified ${IAP_PRODUCT_IDS.length} products excluding hero_bundle.`,
    );
  }
  const versionIds = audit.remote.iapVersionIds ?? {};
  const versionStates = audit.remote.iapVersionStates ?? {};
  const versionProductIds = Object.keys(versionIds).sort();
  const stateProductIds = Object.keys(versionStates).sort();
  const expectedProductIds = [...desiredProductIds].sort();
  const invalidVersionStates = desiredProductIds.filter((productId) => (
    !isReviewableIapVersionState(versionStates[productId])
  ));
  if (
    canonicalJson(versionProductIds) !== canonicalJson(expectedProductIds)
    || canonicalJson(stateProductIds) !== canonicalJson(expectedProductIds)
    || desiredProductIds.some((productId) => (
      typeof versionIds[productId] !== 'string'
      || versionIds[productId] === ''
    ))
    || new Set(Object.values(versionIds)).size !== desiredProductIds.length
    || invalidVersionStates.length > 0
  ) {
    throw fail(
      'ASC_REVIEW_IAP_VERSION_SET_INVALID',
      `manifest IAP ${IAP_PRODUCT_IDS.length} products and active draft version ID/state set do not match exactly.`,
    );
  }
  const expectedTargets = new Set([
    `appStoreVersions:${versionId}`,
    ...desiredProductIds.map((productId) => versionIds[productId])
      .map((id) => `inAppPurchaseVersions:${id}`),
  ]);
  const submissions = await getClient.getAll(queryPath(
    `/v1/apps/${encodeSegment(audit.appId, 'app')}/reviewSubmissions`,
    [
      ['fields[reviewSubmissions]', 'platform,state,submittedDate'],
      ['limit', '50'],
    ],
  ));
  const active = submissions.filter((resource) => [
    'READY_FOR_REVIEW',
    'WAITING_FOR_REVIEW',
    'IN_REVIEW',
    'COMPLETING',
    'UNRESOLVED_ISSUES',
  ].includes(remoteAttributes(resource).state));
  if (active.length > 1) {
    throw fail('ASC_REVIEW_SUBMISSION_DUPLICATE', 'more than one active review submission exists; not selecting automatically.');
  }
  let submission = active[0] ?? null;
  if (submission && remoteAttributes(submission).platform !== 'IOS') {
    throw fail('ASC_REVIEW_PLATFORM_MISMATCH', 'active review submission is not iOS.');
  }
  if (!submission) {
    const created = await client.post('/v1/reviewSubmissions', {
      data: {
        attributes: { platform: 'IOS' },
        relationships: {
          app: { data: { id: audit.appId, type: 'apps' } },
        },
        type: 'reviewSubmissions',
      },
    });
    submission = created?.data;
    requireString(submission?.id, 'created review submission ID');
  }
  const state = remoteAttributes(submission).state;
  const items = await readReviewItems(getClient, submission.id);
  const existingTargets = reviewTargets(items, expectedTargets, { exact: false });
  if (state === 'UNRESOLVED_ISSUES') {
    throw fail(
      'ASC_REVIEW_UNRESOLVED_ISSUES',
      'existing review submission is in UNRESOLVED_ISSUES state.',
    );
  }
  if (SUBMITTED_REVIEW_STATES.has(state)) {
    await verifySubmittedRelease({
      audit,
      expectedTargets,
      getClient,
      submissionId: submission.id,
      versionId,
    });
    return { id: submission.id, idempotent: true, state, submitted: true };
  }
  if (state !== 'READY_FOR_REVIEW') {
    throw fail('ASC_REVIEW_STATE_NOT_SUBMITTABLE', `review submission state ${state} is not handled automatically.`);
  }
  for (const target of expectedTargets) {
    if (existingTargets.has(target)) continue;
    const [type, id] = target.split(':');
    await addReviewItem(
      client,
      submission.id,
      type === 'appStoreVersions' ? 'appStoreVersion' : 'inAppPurchaseVersion',
      type,
      id,
    );
  }
  const verifiedItems = await readReviewItems(getClient, submission.id);
  reviewTargets(verifiedItems, expectedTargets, { exact: true });
  await client.patch(
    `/v1/reviewSubmissions/${encodeSegment(submission.id, 'review submission')}`,
    {
      data: {
        attributes: { submitted: true },
        id: submission.id,
        type: 'reviewSubmissions',
      },
    },
  );
  const submittedResource = await pollAppStoreReviewSubmission({
    attempts: reviewPollAttempts,
    delayMs: reviewPollDelayMs,
    getClient,
    sleepImpl,
    submissionId: submission.id,
  });
  const verified = await verifySubmittedRelease({
    audit,
    expectedTargets,
    getClient,
    submissionId: submission.id,
    versionId,
  });
  return {
    buildId: verified.buildId,
    id: submission.id,
    idempotent: false,
    reviewItemCount: verified.items,
    state: remoteAttributes(submittedResource).state,
    submitted: true,
  };
}

export async function createAuthenticatedAppStoreApply({
  confirmation,
  env = process.env,
  fetchImpl = globalThis.fetch,
  manifest,
  now = Date.now,
  payload,
  repoRoot,
  reviewConfirmation = null,
  submitReview = false,
} = {}) {
  // Authorization is intentionally checked before reading credentials or
  // making even a GET request, so a stale/mistyped approval has no network side effect.
  assertAppStoreApplyAuthorization({
    confirmation,
    manifest,
    payload,
    reviewConfirmation,
    submitReview,
  });
  const credentials = readAppStoreCredentials({ env, root: resolve(repoRoot) });
  const clock = typeof now === 'function' ? now : () => now;
  const tokenProvider = createRotatingAppStoreConnectTokenProvider({
    issuerId: credentials.issuerId,
    keyId: credentials.keyId,
    now: clock,
    privateKey: readFileSync(credentials.privateKeyPath),
  });
  const getClient = createGetOnlyAppStoreConnectClient({ fetchImpl, tokenProvider });
  const client = createAppStoreConnectMutationClient({ fetchImpl, tokenProvider });
  return applyAppStoreConnectRelease({
    client,
    confirmation,
    getClient,
    manifest,
    payload,
    repoRoot,
    reviewConfirmation,
    submitReview,
  });
}

export async function createAuthenticatedAppStoreApplyAudit({
  env = process.env,
  fetchImpl = globalThis.fetch,
  now = Date.now,
  payload,
  repoRoot,
} = {}) {
  const credentials = readAppStoreCredentials({ env, root: resolve(repoRoot) });
  const clock = typeof now === 'function' ? now : () => now;
  const tokenProvider = createRotatingAppStoreConnectTokenProvider({
    issuerId: credentials.issuerId,
    keyId: credentials.keyId,
    now: clock,
    privateKey: readFileSync(credentials.privateKeyPath),
  });
  const client = createGetOnlyAppStoreConnectClient({ fetchImpl, tokenProvider });
  return auditAppStoreConnectApplyReadiness({ payload, client });
}

export function formatAppStoreApplyReport(result) {
  const lines = [
    result.complete
      ? 'App Store Connect remote apply converged through GET revalidation.'
      : 'App Store Connect remote apply stopped at a safety gate.',
    `applied mutations: ${result.applied.length}`,
    `review submitted: ${result.reviewSubmitted ? 'yes' : 'no'}`,
  ];
  for (const blocker of result.blockers) {
    lines.push(`- ${blocker.code ?? 'UNRESOLVED'} ${blocker.target} ${blocker.identifier}`);
  }
  return lines.join('\n');
}

export function appStoreApplyCheckSummary(manifest) {
  verifyAppStoreReleaseManifest(manifest);
  return {
    applyConfirmation: appStoreConfirmationToken(manifest, 'apply'),
    buildNumber: manifest.payload.release.buildNumber,
    manifestSha256: manifest.payloadChecksums.sha256,
    reviewConfirmation: appStoreConfirmationToken(manifest, 'review'),
    version: manifest.payload.release.version,
  };
}
