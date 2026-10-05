// Behavioral probe for the iOS Apple revoke/delete chain.
//
// The production methods live in MoonlitIdentityIos.mm and normally compile
// against Firebase, GoogleSignIn, and godot-cpp. This probe compiles the
// actual method bodies — extracted verbatim from the bridge source, never
// re-typed — inside a Foundation-only harness with stubbed SDK outcomes,
// then runs seven scenarios: missing code (nil and empty), revocation
// error, revocation success with delete success and delete error, a
// request retired before the revoke starts, and a request retired while
// the revoke is in flight. Restoring the old fail-open delete call in
// either failure branch fails the probe, because the scenarios assert
// Firebase deletion is never invoked there.
//
// On machines without macOS clang + Foundation the caller skips the
// compiled execution and says so; the portable source-contract tests in
// player-identity-build.test.mjs still run everywhere.

import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const IOS_IDENTITY_BRIDGE_PATH =
  'apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm';

export const REVOKE_PROBE_SCENARIOS = [
  'missing-code-nil',
  'missing-code-empty',
  'revoke-error',
  'revoke-success-delete-success',
  'revoke-success-delete-error',
  'retired-at-entry',
  'retired-in-flight',
];

// Production methods compiled verbatim, with the anchor each body must
// carry so a mis-extracted slice fails loudly instead of testing nothing.
const PROBE_METHODS = [
  {
    marker: '- (NSDictionary *)revokeFailedOutcome:',
    anchors: ['sessionOutcome', 'kCodeNetwork'],
  },
  {
    marker: '- (void)revokeAppleGrant:',
    anchors: ['revokeTokenWithAuthorizationCode'],
  },
  {
    marker: '- (void)deleteFirebaseUserAfterReauth:',
    anchors: ['deleteWithCompletion'],
  },
];

const CODE_NETWORK_PATTERN =
  /static NSString \*const kCodeNetwork = @"([^"]*)";/;

// Extracts one Objective-C method starting at `marker`, matching braces
// from its opening brace while skipping strings, character literals, and
// line/block comments so braces inside them never close the scan early.
export function extractObjcMethod(source, marker) {
  const start = source.indexOf(marker);
  if (start < 0) {
    throw new Error(`bridge method not found: ${marker}`);
  }
  const open = source.indexOf('{', start);
  if (open < 0) {
    throw new Error(`bridge method has no body: ${marker}`);
  }
  let depth = 0;
  let i = open;
  let state = 'code';
  while (i < source.length) {
    const ch = source[i];
    const next = source[i + 1];
    if (state === 'code') {
      if (ch === '/' && next === '/') {
        state = 'line';
        i += 2;
        continue;
      }
      if (ch === '/' && next === '*') {
        state = 'block';
        i += 2;
        continue;
      }
      if (ch === '"') {
        state = 'string';
        i += 1;
        continue;
      }
      if (ch === "'") {
        state = 'char';
        i += 1;
        continue;
      }
      if (ch === '{') {
        depth += 1;
      } else if (ch === '}') {
        depth -= 1;
        if (depth === 0) {
          return source.slice(start, i + 1);
        }
      }
      i += 1;
      continue;
    }
    if (state === 'line') {
      if (ch === '\n') {
        state = 'code';
      }
      i += 1;
      continue;
    }
    if (state === 'block') {
      if (ch === '*' && next === '/') {
        state = 'code';
        i += 2;
        continue;
      }
      i += 1;
      continue;
    }
    if (state === 'string' || state === 'char') {
      if (ch === '\\') {
        i += 2;
        continue;
      }
      if ((state === 'string' && ch === '"')
        || (state === 'char' && ch === "'")) {
        state = 'code';
      }
      i += 1;
      continue;
    }
  }
  throw new Error(`bridge method body never closes: ${marker}`);
}

export function extractRevokeProbeMethods(mmSource) {
  const codeMatch = mmSource.match(CODE_NETWORK_PATTERN);
  if (!codeMatch) {
    throw new Error('bridge kCodeNetwork constant not found');
  }
  const methods = PROBE_METHODS.map(({ marker, anchors }) => {
    const body = extractObjcMethod(mmSource, marker);
    for (const anchor of anchors) {
      if (!body.includes(anchor)) {
        throw new Error(`extracted ${marker} lacks ${anchor}`);
      }
    }
    const signature = body.slice(0, body.indexOf('{')).trim();
    return { marker, body, declaration: `${signature};` };
  });
  return { codeNetwork: codeMatch[1], methods };
}

function methodDeclarations(extracted) {
  return extracted.methods
    .map((entry) => entry.declaration)
    .join('\n');
}

// Builds the complete Foundation-only probe source. The stub SDK answers
// with controllable outcomes (a set error or nil), the harness worker
// implements the five collaborators the production bodies call
// (isLive/finishRequest/errorOutcome/sessionOutcome/localSession), and
// main runs one scenario per failure and success branch.
export function buildRevokeProbeSource(extracted) {
  const production = extracted.methods
    .map((entry) => entry.body)
    .join('\n\n');
  return `// Generated by player-identity-revoke-probe.mjs: do not hand-edit.
// The three methods under "production bodies" are extracted verbatim
// from ${IOS_IDENTITY_BRIDGE_PATH}.
#import <Foundation/Foundation.h>

static NSString *const kCodeNetwork = @"${extracted.codeNetwork}";

// --- Stub SDK: controllable outcomes, synchronous by default ---------------
static NSError *gRevokeError = nil;
static NSError *gDeleteError = nil;
static long gDeleteCalls = 0;
static BOOL gDeferRevokeCompletion = NO;
static void (^gDeferredRevokeCompletion)(NSError * _Nullable) = nil;

@interface FIRAuth : NSObject
+ (instancetype)auth;
- (void)revokeTokenWithAuthorizationCode:(NSString *)authCode
  completion:(void (^)(NSError * _Nullable error))completion;
@end

@interface FIRUser : NSObject
- (void)deleteWithCompletion:(void (^)(NSError * _Nullable error))completion;
@end

@implementation FIRAuth

+ (instancetype)auth {
  static FIRAuth *shared = nil;
  if (shared == nil) {
    shared = [[FIRAuth alloc] init];
  }
  return shared;
}

- (void)revokeTokenWithAuthorizationCode:(NSString *)authCode
  completion:(void (^)(NSError * _Nullable error))completion {
  (void)authCode;
  if (gDeferRevokeCompletion) {
    gDeferredRevokeCompletion = [completion copy];
    return;
  }
  completion(gRevokeError);
}

@end

@implementation FIRUser

- (void)deleteWithCompletion:(void (^)(NSError * _Nullable error))completion {
  gDeleteCalls += 1;
  completion(gDeleteError);
}

@end

// --- Harness worker: collaborators plus the production bodies --------------
@interface ProbeWorker : NSObject

@property (nonatomic, strong) NSMutableSet<NSString *> *live;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *terminals;

- (BOOL)isLive:(NSString *)requestId;
- (void)finishRequest:(NSString *)requestId outcome:(NSDictionary *)outcome;
- (NSDictionary *)errorOutcome:(NSString *)requestId
  code:(NSString *)code
  retryable:(BOOL)retryable;
- (NSDictionary *)sessionOutcome:(NSString *)requestId;
- (NSDictionary *)localSession:(NSString *)requestId;
${methodDeclarations(extracted)}

@end

@implementation ProbeWorker

- (instancetype)init {
  if (self = [super init]) {
    _live = [NSMutableSet set];
    _terminals = [NSMutableArray array];
  }
  return self;
}

- (BOOL)isLive:(NSString *)requestId {
  return [_live containsObject:requestId];
}

- (void)finishRequest:(NSString *)requestId outcome:(NSDictionary *)outcome {
  if (![_live containsObject:requestId]) {
    return;
  }
  [_live removeObject:requestId];
  NSMutableDictionary *recorded = [(outcome ?: @{}) mutableCopy];
  recorded[@"request_id"] = requestId;
  [_terminals addObject:recorded];
}

- (NSDictionary *)errorOutcome:(NSString *)requestId
  code:(NSString *)code
  retryable:(BOOL)retryable {
  return @{
    @"status" : @"error",
    @"code" : code,
    @"retryable" : @(retryable),
    @"request_id" : requestId
  };
}

- (NSDictionary *)sessionOutcome:(NSString *)requestId {
  // The stub signed-in Apple session the production failure helper must
  // preserve on its error terminal.
  return @{
    @"status" : @"ok",
    @"request_id" : requestId,
    @"kind" : @"cloud",
    @"uid" : @"probe-uid-7",
    @"provider" : @"apple"
  };
}

- (NSDictionary *)localSession:(NSString *)requestId {
  return @{
    @"status" : @"ok",
    @"request_id" : requestId,
    @"kind" : @"local_guest",
    @"uid" : @"",
    @"provider" : @""
  };
}

// --- Production bodies, extracted verbatim ---------------------------------
${production}

@end

// --- Scenarios -------------------------------------------------------------
static int gFailures = 0;

static void checkProbe(BOOL cond, const char *scenario, NSString *detail) {
  printf("PROBE %s %s\\n", cond ? "PASS" : "FAIL", scenario);
  if (!cond) {
    gFailures += 1;
    printf("PROBE detail %s %s\\n", scenario, [detail UTF8String]);
  }
}

static void resetStubs(void) {
  gRevokeError = nil;
  gDeleteError = nil;
  gDeleteCalls = 0;
  gDeferRevokeCompletion = NO;
  gDeferredRevokeCompletion = nil;
}

static NSString *describeTerminals(ProbeWorker *worker) {
  NSMutableArray *parts = [NSMutableArray array];
  for (NSDictionary *terminal in worker.terminals) {
    [parts addObject:[NSString stringWithFormat:@"<%@ %@ %@ %@>",
      terminal[@"status"] ?: @"?", terminal[@"code"] ?: @"?",
      terminal[@"kind"] ?: @"?", terminal[@"uid"] ?: @"?"]];
  }
  return [NSString stringWithFormat:@"terminals=%lu deletes=%ld [%@]",
    (unsigned long)worker.terminals.count, gDeleteCalls,
    [parts componentsJoinedByString:@" "]];
}

static BOOL terminalIsRecoverableCloudError(NSDictionary *terminal) {
  return [terminal[@"status"] isEqualToString:@"error"]
    && [terminal[@"code"] isEqualToString:kCodeNetwork]
    && [terminal[@"retryable"] boolValue] == YES
    && [terminal[@"kind"] isEqualToString:@"cloud"]
    && [terminal[@"uid"] isEqualToString:@"probe-uid-7"]
    && [terminal[@"provider"] isEqualToString:@"apple"];
}

static void scenarioMissingCodeNil(void) {
  resetStubs();
  ProbeWorker *worker = [[ProbeWorker alloc] init];
  [worker.live addObject:@"probe-missing-nil"];
  [worker revokeAppleGrant:@"probe-missing-nil"
    user:[[FIRUser alloc] init]
    authCode:nil];
  NSDictionary *terminal = worker.terminals.firstObject ?: @{};
  checkProbe(worker.terminals.count == 1
    && terminalIsRecoverableCloudError(terminal)
    && gDeleteCalls == 0, "missing-code-nil",
    describeTerminals(worker));
}

static void scenarioMissingCodeEmpty(void) {
  resetStubs();
  ProbeWorker *worker = [[ProbeWorker alloc] init];
  [worker.live addObject:@"probe-missing-empty"];
  [worker revokeAppleGrant:@"probe-missing-empty"
    user:[[FIRUser alloc] init]
    authCode:@""];
  NSDictionary *terminal = worker.terminals.firstObject ?: @{};
  checkProbe(worker.terminals.count == 1
    && terminalIsRecoverableCloudError(terminal)
    && gDeleteCalls == 0, "missing-code-empty",
    describeTerminals(worker));
}

static void scenarioRevokeError(void) {
  resetStubs();
  gRevokeError = [NSError errorWithDomain:@"probe" code:7 userInfo:nil];
  ProbeWorker *worker = [[ProbeWorker alloc] init];
  [worker.live addObject:@"probe-revoke-error"];
  [worker revokeAppleGrant:@"probe-revoke-error"
    user:[[FIRUser alloc] init]
    authCode:@"fresh-code"];
  NSDictionary *terminal = worker.terminals.firstObject ?: @{};
  checkProbe(worker.terminals.count == 1
    && terminalIsRecoverableCloudError(terminal)
    && gDeleteCalls == 0, "revoke-error",
    describeTerminals(worker));
}

static void scenarioRevokeSuccessDeleteSuccess(void) {
  resetStubs();
  ProbeWorker *worker = [[ProbeWorker alloc] init];
  [worker.live addObject:@"probe-delete-success"];
  [worker revokeAppleGrant:@"probe-delete-success"
    user:[[FIRUser alloc] init]
    authCode:@"fresh-code"];
  NSDictionary *terminal = worker.terminals.firstObject ?: @{};
  checkProbe(worker.terminals.count == 1
    && [terminal[@"status"] isEqualToString:@"ok"]
    && [terminal[@"kind"] isEqualToString:@"local_guest"]
    && gDeleteCalls == 1, "revoke-success-delete-success",
    describeTerminals(worker));
}

static void scenarioRevokeSuccessDeleteError(void) {
  resetStubs();
  gDeleteError = [NSError errorWithDomain:@"probe" code:9 userInfo:nil];
  ProbeWorker *worker = [[ProbeWorker alloc] init];
  [worker.live addObject:@"probe-delete-error"];
  [worker revokeAppleGrant:@"probe-delete-error"
    user:[[FIRUser alloc] init]
    authCode:@"fresh-code"];
  NSDictionary *terminal = worker.terminals.firstObject ?: @{};
  checkProbe(worker.terminals.count == 1
    && [terminal[@"status"] isEqualToString:@"error"]
    && ![terminal[@"kind"] isEqualToString:@"local_guest"]
    && gDeleteCalls == 1, "revoke-success-delete-error",
    describeTerminals(worker));
}

static void scenarioRetiredAtEntry(void) {
  resetStubs();
  ProbeWorker *worker = [[ProbeWorker alloc] init];
  [worker revokeAppleGrant:@"probe-retired-entry"
    user:[[FIRUser alloc] init]
    authCode:@"fresh-code"];
  checkProbe(worker.terminals.count == 0 && gDeleteCalls == 0,
    "retired-at-entry", describeTerminals(worker));
}

static void scenarioRetiredInFlight(void) {
  resetStubs();
  gDeferRevokeCompletion = YES;
  ProbeWorker *worker = [[ProbeWorker alloc] init];
  [worker.live addObject:@"probe-retired-flight"];
  [worker revokeAppleGrant:@"probe-retired-flight"
    user:[[FIRUser alloc] init]
    authCode:@"fresh-code"];
  // The revoke answers after the request retired: the late callback must
  // drop without a terminal and without deleting the Firebase user.
  [worker.live removeObject:@"probe-retired-flight"];
  if (gDeferredRevokeCompletion != nil) {
    void (^completion)(NSError * _Nullable) = gDeferredRevokeCompletion;
    gDeferredRevokeCompletion = nil;
    gDeferRevokeCompletion = NO;
    completion(nil);
  }
  checkProbe(worker.terminals.count == 0 && gDeleteCalls == 0,
    "retired-in-flight", describeTerminals(worker));
}

int main(void) {
  @autoreleasepool {
    scenarioMissingCodeNil();
    scenarioMissingCodeEmpty();
    scenarioRevokeError();
    scenarioRevokeSuccessDeleteSuccess();
    scenarioRevokeSuccessDeleteError();
    scenarioRetiredAtEntry();
    scenarioRetiredInFlight();
    printf("PROBE done failures=%d\\n", gFailures);
    return gFailures == 0 ? 0 : 1;
  }
}
`;
}

export function revokeProbeAvailable() {
  if (process.platform !== 'darwin') {
    return {
      ok: false,
      reason: 'revoke behavior probe needs macOS clang with Foundation'
        + ` (this host is ${process.platform}); the compiled execution did`
        + ' not run here, only the portable source-contract assertions.',
    };
  }
  try {
    execFileSync('clang', ['--version'], { stdio: ['ignore', 'pipe', 'pipe'] });
  } catch {
    return {
      ok: false,
      reason: 'revoke behavior probe needs macOS clang with Foundation'
        + ' (no clang on PATH); the compiled execution did not run here,'
        + ' only the portable source-contract assertions.',
    };
  }
  return { ok: true, reason: '' };
}

// Compiles the generated probe with clang and runs it. `mmSource`
// overrides the bridge file read so the old fail-open text can be
// executed as a negative control without touching the working tree.
export function runRevokeProbe({ repoRoot, mmSource = null, clang = 'clang' }) {
  const source = mmSource
    ?? readFileSync(join(repoRoot, IOS_IDENTITY_BRIDGE_PATH), 'utf8');
  const extracted = extractRevokeProbeMethods(source);
  const probeSource = buildRevokeProbeSource(extracted);
  const workDir = mkdtempSync(join(tmpdir(), 'moonlit-revoke-probe-'));
  try {
    const probePath = join(workDir, 'revoke_probe.m');
    const binPath = join(workDir, 'revoke_probe');
    writeFileSync(probePath, probeSource);
    const compiled = spawnSync(clang,
      ['-fobjc-arc', '-framework', 'Foundation', '-Wall', '-Wextra', '-Werror',
        probePath, '-o', binPath],
      { encoding: 'utf8', timeout: 180000 });
    if (compiled.status !== 0) {
      return {
        ok: false,
        passed: [],
        failed: [...REVOKE_PROBE_SCENARIOS],
        output: `probe compile failed:\n${compiled.stderr ?? ''}\n${compiled.stdout ?? ''}`,
      };
    }
    const ran = spawnSync(binPath, [], { encoding: 'utf8', timeout: 60000 });
    const output = `${ran.stdout ?? ''}${ran.stderr ?? ''}`;
    const passed = [];
    const failed = [];
    for (const line of output.split('\n')) {
      const match = line.match(/^PROBE (PASS|FAIL) (\S+)/);
      if (match && REVOKE_PROBE_SCENARIOS.includes(match[2])) {
        (match[1] === 'PASS' ? passed : failed).push(match[2]);
      }
    }
    for (const name of REVOKE_PROBE_SCENARIOS) {
      if (!passed.includes(name) && !failed.includes(name)) {
        failed.push(name);
      }
    }
    return { ok: ran.status === 0 && failed.length === 0, passed, failed, output };
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
}
