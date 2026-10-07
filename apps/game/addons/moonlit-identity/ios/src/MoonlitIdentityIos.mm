// Native player identity for iOS: ordinary Google sign-in (GoogleSignIn SDK,
// OAuth callback URL scheme) and Sign in with Apple (AuthenticationServices,
// SHA-256 nonce), each exchanged for a Firebase credential. The Google
// provider here is the same Firebase `google.com` identity Android signs
// in with: one Google account carries across platforms.
//
// Callback contract, same as Android: every moonlit* method takes a
// Godot-issued request id plus one JSON argument object and answers
// synchronously with a receipt JSON object. A "pending" receipt is always
// followed by exactly one terminal outcome on the "moonlit_identity_event"
// signal carrying the same request id. Late answers after cancel are dropped,
// and a second terminal for one id is dropped too.
//
// Cancellation boundary: moonlitCancelRequest answers "cancelled" while no
// irreversible SDK mutation began, or "draining" once one did. Draining
// keeps the request tracked and the terminal still arrives on the signal.
// Every stage checks the pending set before invoking the next SDK call.
//
// Firebase is initialized from the staged public client config carried in
// each call's payload. When no configured app exists and the values are
// absent or rejected, calls answer "not_configured" instead of throwing.
//
// The Google OAuth callback arrives as an openURL on the shared
// application delegate (classic AppDelegate lifecycle, which is what the
// Godot export template uses). A chaining forwarder installed once at
// extension init offers the URL to GoogleSignIn first and passes anything
// else to the delegate's previous implementation, so existing app and IAP
// URL handling keeps working untouched.
//
// Privacy: the Google tokens, the Apple identity token, and the Apple
// authorization code are consumed inside the Firebase calls and never leave
// this file, except that the ID token is returned as the "id_token" field
// of a moonlitGetIdToken answer only. The Apple sheet requests no personal
// scopes. Google's SDK authenticates under its own default account scopes
// (openid/email/profile): game code adds no scopes of its own and never
// reads, stores, or logs a name, email, profile, or token. Diagnostics
// name the request id, the status, and the code only.

#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonCrypto.h>
#import <FirebaseAuth/FirebaseAuth.h>
#import <GoogleSignIn/GoogleSignIn.h>
#import <objc/runtime.h>
// FirebaseAuth 11 is Swift-implemented: the ObjC-visible FIRAuth/FIRUser
// interfaces and the FIRAuthErrorCode enum live in the generated header.
// It carries @imports, so the SCons build enables Clang modules with -F
// on the discovered frameworks (measured against the real built products).
#import <FirebaseAuth/FirebaseAuth-Swift.h>
#import <FirebaseCore/FIRApp.h>
#import <FirebaseCore/FIROptions.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

#include "MoonlitIdentityIos.h"
#include "MoonlitReminderPlanner.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

static NSString *const kSignalEvent = @"moonlit_identity_event";
static NSString *const kProviderGoogle = @"google";
static NSString *const kProviderApple = @"apple";
static NSString *const kProviderAnonymous = @"anonymous";

static NSString *const kStatusOk = @"ok";
static NSString *const kStatusPending = @"pending";
static NSString *const kStatusCancelled = @"cancelled";
static NSString *const kStatusConflict = @"conflict";
static NSString *const kStatusError = @"error";
static NSString *const kStatusDraining = @"draining";
static NSString *const kStatusNotConfigured = @"not_configured";

static NSString *const kCodeUserCancelled = @"user_cancelled";
static NSString *const kCodeAlreadyLinkedElsewhere = @"already_linked_elsewhere";
static NSString *const kCodeMissingConfig = @"identity_not_configured";
static NSString *const kCodeNetwork = @"network_error";
static NSString *const kCodeRecentLoginRequired = @"recent_login_required";
static NSString *const kCodeNoSignedInUser = @"no_signed_in_user";
static NSString *const kCodeAlreadyPending = @"request_already_pending";
static NSString *const kCodeMutationInProgress = @"mutation_in_progress";
static NSString *const kCodeAppleUnavailable = @"apple_sign_in_unavailable";
static NSString *const kCodeGoogleUnavailable = @"google_sign_in_unavailable";
static NSString *const kCodeSignOutFailed = @"sign_out_failed";
static NSString *const kCodePermissionDenied = @"permission_denied";
static NSString *const kCodeInvalidArgs = @"invalid_args";
static NSString *const kCodeRequestBusy = @"request_busy";
static NSString *const kStatusDenied = @"denied";

// Attendance-reminder request identifiers. Deliveries are a bounded
// horizon of owned non-repeating slots at the server eligibility plus
// N * 43200 seconds; cancellation names exactly these plus the legacy
// ids below and never touches unrelated pending requests.
static NSString *const kReminderSlotPrefix =
	@"dev.moonlitbeacon.attendance.slot-";
// The horizon refills from the same anchor on a genuine foreground
// visit and resets on the next attendance claim. Slot counts and the
// refill math live in MoonlitReminderPlanner.h, shared with the
// host-side numeric test so the shipped computation is the proven one.
// Legacy one-shot/repeat shape plus the QA one-shot: scheduling
// replaces their pending copies (no double delivery across the
// migration) and cancellation removes them with the horizon.
static NSString *const kReminderFirstId =
	@"dev.moonlitbeacon.attendance.first";
static NSString *const kReminderRepeatId =
	@"dev.moonlitbeacon.attendance.repeat";
static NSString *const kReminderDebugId =
	@"dev.moonlitbeacon.attendance.debug";
// App-only scheduling metadata in standardUserDefaults (declared in the
// app PrivacyInfo.xcprivacy as CA92.1): the requested account, eligible
// time, and locale, so identical re-schedules skip without shifting the
// repeat anchor, plus the held window's base slot and end time and the
// diagnostics baseline. No token, email, name, or wallet value is
// stored here.
static NSString *const kReminderDefaultsAccount =
	@"dev.moonlitbeacon.reminder.account";
static NSString *const kReminderDefaultsEligibleMillis =
	@"dev.moonlitbeacon.reminder.eligible_millis";
static NSString *const kReminderDefaultsLocale =
	@"dev.moonlitbeacon.reminder.locale";
static NSString *const kReminderDefaultsScheduledAt =
	@"dev.moonlitbeacon.reminder.scheduled_at";
static NSString *const kReminderDefaultsBaseSlot =
	@"dev.moonlitbeacon.reminder.base_slot";
static NSString *const kReminderDefaultsHorizonEnd =
	@"dev.moonlitbeacon.reminder.horizon_end";
static const NSTimeInterval kReminderDebugMinSeconds = 5.0;
static const NSTimeInterval kReminderDebugMaxSeconds = 600.0;

// GoogleSignIn dismissal, from GIDSignInError (the canceled code in the
// com.google.GIDSignIn domain). Spelled as literals because the SDK's ObjC
// constant names changed across major versions while the domain string and
// the code are stable API.
static NSString *const kGoogleSignInErrorDomain = @"com.google.GIDSignIn";
static const NSInteger kGoogleSignInCanceledCode = -5;

static const NSUInteger kSettledCap = 64;

typedef NS_ENUM(NSInteger, MoonlitApplePurpose) {
	MoonlitApplePurposeSignIn,
	MoonlitApplePurposeLink,
	MoonlitApplePurposeDelete,
};

// ---------------------------------------------------------------------------
// Google OAuth callback forwarder. Installed once, it offers every incoming
// openURL to GoogleSignIn and passes anything Google does not claim to the
// delegate's previous implementation, so existing app and IAP URL handling
// keeps working untouched. No concrete delegate class is assumed: the
// forwarder patches whatever class the shared delegate has at install time,
// and re-running the install (first Google sign-in) covers an install that
// raced delegate creation.
// ---------------------------------------------------------------------------

typedef BOOL (*MoonlitOpenURLIMP)(id, SEL, UIApplication *, NSURL *,
	NSDictionary *);

static MoonlitOpenURLIMP s_originalOpenURL = NULL;

static BOOL MoonlitForwardOpenURL(id self, SEL cmd, UIApplication *app,
	NSURL *url, NSDictionary *options) {
	if ([[GIDSignIn sharedInstance] handleURL:url]) {
		return YES;
	}
	if (s_originalOpenURL != NULL) {
		return s_originalOpenURL(self, cmd, app, url, options);
	}
	return NO;
}

@interface MoonlitGoogleURLForwarder : NSObject
+ (void)installOnce;
@end

@implementation MoonlitGoogleURLForwarder

+ (void)installOnce {
	// A flag, not dispatch_once: when the delegate does not exist yet the
	// install stays pending and the next call (first Google sign-in)
	// retries it.
	static BOOL installed = NO;
	@synchronized(self) {
		if (installed) {
			return;
		}
		id delegate = [UIApplication sharedApplication].delegate;
		Class cls = [delegate class];
		if (cls == Nil) {
			return;
		}
		SEL sel = @selector(application:openURL:options:);
		Method existing = class_getInstanceMethod(cls, sel);
		if (existing == NULL) {
			// The delegate implements no URL handling (the usual Godot
			// template): add ours. Foreign URLs answer NO.
			class_addMethod(cls, sel, (IMP)MoonlitForwardOpenURL,
				"B@:@@@");
		} else {
			// Chain: Google callbacks are handled, everything else
			// reaches the previous implementation unchanged.
			s_originalOpenURL =
				(MoonlitOpenURLIMP)method_getImplementation(existing);
			method_setImplementation(existing, (IMP)MoonlitForwardOpenURL);
		}
		installed = YES;
	}
}

@end

// ---------------------------------------------------------------------------
// Worker: owns the Apple controller delegate, the Firebase calls, and the
// pending/settled request books. All entry points run on the main queue;
// outcomes go back through the owning GDExtension object's call_deferred.
// ---------------------------------------------------------------------------

@interface MoonlitIdentityWorker : NSObject <ASAuthorizationControllerDelegate,
	ASAuthorizationControllerPresentationContextProviding,
	UNUserNotificationCenterDelegate>

@property(nonatomic, assign) MoonlitIdentityIos *owner;
@property(nonatomic, strong) NSMutableSet<NSString *> *pending;
@property(nonatomic, strong) NSMutableSet<NSString *> *settled;
@property(nonatomic, strong) NSMutableArray<NSString *> *settledOrder;
@property(nonatomic, strong) NSMutableSet<NSString *> *mutations;
// Owner of the single native mutation slot: at most one sign-in/link/
// delete/sign-out request runs at a time. The slot releases only on SDK
// completion or pre-mutation cancel, never on a GDScript timeout.
@property(nonatomic, copy) NSString *mutationOwner;
@property(nonatomic, strong) ASAuthorizationController *appleController;
@property(nonatomic, copy) NSString *appleRequestId;
@property(nonatomic, copy) NSString *appleRawNonce;
@property(nonatomic, assign) MoonlitApplePurpose applePurpose;
// Owner of the single in-flight reminder-permission request. Separate
// from the identity mutation slot: permission is not a Firebase
// mutation and must never block (or be blocked by) sign-in work.
@property(nonatomic, copy) NSString *reminderPermissionOwner;
// Cached notification authorization status: getNotificationSettings is
// async-only, so the synchronous status answer reads this while every
// status call also refreshes it in the background.
@property(nonatomic, assign) NSInteger reminderAuthStatus;
@property(nonatomic, assign) BOOL reminderAuthKnown;

@end

@implementation MoonlitIdentityWorker

- (instancetype)initWithOwner:(MoonlitIdentityIos *)owner {
	if (self = [super init]) {
		_owner = owner;
		_pending = [NSMutableSet set];
		_settled = [NSMutableSet set];
		_settledOrder = [NSMutableArray array];
		_mutations = [NSMutableSet set];
		_reminderAuthStatus = UNAuthorizationStatusNotDetermined;
		_reminderAuthKnown = NO;
		// Install the foreground-suppression delegate (only when no
		// other delegate owns the center) and warm the cached
		// authorization status, both on the main queue. Returning
		// UNNotificationPresentationOptionNone matches the no-delegate
		// default exactly, so installs that never enable reminders
		// behave as if this delegate did not exist.
		dispatch_async(dispatch_get_main_queue(), ^{
			UNUserNotificationCenter *center =
				[UNUserNotificationCenter currentNotificationCenter];
			if (center.delegate == nil) {
				center.delegate = self;
			}
			[self refreshReminderAuthStatus];
		});
	}
	return self;
}

// --- request bookkeeping ----------------------------------------------------

- (BOOL)beginRequest:(NSString *)requestId {
	@synchronized(self) {
		if ([_pending containsObject:requestId] || [_settled containsObject:requestId]) {
			return NO;
		}
		[_pending addObject:requestId];
		return YES;
	}
}

// Claims the single mutation slot: 0 claimed, 1 duplicate id, 2 busy. Busy
// means another mutation is still draining its SDK work; the caller must
// answer mutation_in_progress without touching any SDK state.
- (NSInteger)beginMutating:(NSString *)requestId {
	@synchronized(self) {
		if ([_pending containsObject:requestId] || [_settled containsObject:requestId]) {
			return 1;
		}
		if (_mutationOwner != nil) {
			return 2;
		}
		[_pending addObject:requestId];
		_mutationOwner = [requestId copy];
		return 0;
	}
}

- (void)releaseMutationOwner:(NSString *)requestId {
	@synchronized(self) {
		if ([_mutationOwner isEqualToString:requestId]) {
			_mutationOwner = nil;
		}
	}
}

- (NSString *)busyReceipt:(NSString *)requestId {
	return [self jsonString:@{
		@"status" : kStatusError,
		@"code" : kCodeMutationInProgress,
		@"retryable" : @YES,
		@"request_id" : requestId
	}];
}

- (BOOL)isLive:(NSString *)requestId {
	@synchronized(self) {
		return [_pending containsObject:requestId];
	}
}

- (void)markMutation:(NSString *)requestId {
	@synchronized(self) {
		[_mutations addObject:requestId];
	}
}

- (void)rememberSettled:(NSString *)requestId {
	@synchronized(self) {
		if ([_settled containsObject:requestId]) {
			return;
		}
		[_settled addObject:requestId];
		[_settledOrder addObject:requestId];
		while (_settledOrder.count > kSettledCap) {
			NSString *oldest = _settledOrder.firstObject;
			[_settledOrder removeObjectAtIndex:0];
			[_settled removeObject:oldest];
		}
	}
}

- (NSString *)cancelRequest:(NSString *)requestId {
	@synchronized(self) {
		if (![_pending containsObject:requestId]) {
			return [self jsonString:@{
				@"status" : kStatusCancelled,
				@"code" : kCodeUserCancelled,
				@"request_id" : requestId ?: @""
			}];
		}
		if ([_mutations containsObject:requestId]) {
			return [self jsonString:@{
				@"status" : kStatusDraining,
				@"request_id" : requestId
			}];
		}
		[_pending removeObject:requestId];
		if ([_mutationOwner isEqualToString:requestId]) {
			_mutationOwner = nil;
		}
		if ([_appleRequestId isEqualToString:requestId]) {
			_appleController.delegate = nil;
			_appleController.presentationContextProvider = nil;
			_appleController = nil;
			_appleRequestId = nil;
			_appleRawNonce = nil;
		}
		if ([_reminderPermissionOwner isEqualToString:requestId]) {
			_reminderPermissionOwner = nil;
		}
	}
	[self rememberSettled:requestId];
	return [self jsonString:@{
		@"status" : kStatusCancelled,
		@"code" : kCodeUserCancelled,
		@"request_id" : requestId
	}];
}

// --- JSON helpers -----------------------------------------------------------

- (NSString *)jsonString:(NSDictionary *)dict {
	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
	if (data == nil) {
		return @"{\"status\":\"error\",\"code\":\"network_error\"}";
	}
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSDictionary *)parseArgs:(NSString *)argsJson {
	if (argsJson == nil || argsJson.length == 0) {
		return @{};
	}
	NSData *data = [argsJson dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error = nil;
	id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if ([parsed isKindOfClass:[NSDictionary class]]) {
		return parsed;
	}
	return @{};
}

- (NSDictionary *)notConfiguredOutcome:(NSString *)requestId {
	return @{
		@"status" : kStatusNotConfigured,
		@"code" : kCodeMissingConfig,
		@"retryable" : @NO,
		@"request_id" : requestId
	};
}

// Uses the already configured app when one exists (normal export path);
// otherwise builds one from the staged public values in `args`. Never
// throws: a missing or rejected config settles the request as not_configured.
- (BOOL)ensureApp:(NSString *)requestId args:(NSDictionary *)args {
	if ([FIRApp defaultApp] != nil) {
		return YES;
	}
	NSString *apiKey = args[@"firebase_api_key"];
	NSString *appId = args[@"firebase_app_id"];
	NSString *projectId = args[@"firebase_project_id"];
	NSString *senderId = args[@"firebase_sender_id"];
	if (![apiKey isKindOfClass:[NSString class]] || apiKey.length == 0
		|| ![appId isKindOfClass:[NSString class]] || appId.length == 0
		|| ![projectId isKindOfClass:[NSString class]] || projectId.length == 0
		|| ![senderId isKindOfClass:[NSString class]] || senderId.length == 0) {
		[self finishRequest:requestId
			outcome:[self notConfiguredOutcome:requestId]];
		return NO;
	}
	@try {
		// ObjC spellings from the real FIROptions.h: APIKey and
		// GCMSenderID (the lowercase names are Swift-only).
		FIROptions *options = [[FIROptions alloc]
			initWithGoogleAppID:appId
			GCMSenderID:senderId];
		options.APIKey = apiKey;
		options.projectID = projectId;
		// The staged iOS OAuth client id, when this export carries one:
		// GoogleSignIn is configured from it for the `google.com` flow.
		NSString *clientId = args[@"ios_client_id"];
		if ([clientId isKindOfClass:[NSString class]]
			&& clientId.length > 0) {
			options.clientID = clientId;
		}
		[FIRApp configureWithOptions:options];
		return YES;
	} @catch (NSException *exception) {
		NSLog(@"[MoonlitIdentity] firebase-init %@ rejected: %@", requestId,
			exception.name);
		[self finishRequest:requestId
			outcome:[self notConfiguredOutcome:requestId]];
		return NO;
	}
}

// Synchronous Firebase init for cold-start session reads: uses the already
// configured app when one exists, otherwise builds one from the staged
// public values in `args`. Never touches request bookkeeping and emits no
// signal: a missing or rejected config answers NO so the caller falls
// through to its guarded local session. Never throws.
- (BOOL)ensureSessionApp:(NSString *)requestId args:(NSDictionary *)args {
	if ([FIRApp defaultApp] != nil) {
		return YES;
	}
	NSString *apiKey = args[@"firebase_api_key"];
	NSString *appId = args[@"firebase_app_id"];
	NSString *projectId = args[@"firebase_project_id"];
	NSString *senderId = args[@"firebase_sender_id"];
	if (![apiKey isKindOfClass:[NSString class]] || apiKey.length == 0
		|| ![appId isKindOfClass:[NSString class]] || appId.length == 0
		|| ![projectId isKindOfClass:[NSString class]] || projectId.length == 0
		|| ![senderId isKindOfClass:[NSString class]] || senderId.length == 0) {
		return NO;
	}
	@try {
		FIROptions *options = [[FIROptions alloc]
			initWithGoogleAppID:appId
			GCMSenderID:senderId];
		options.APIKey = apiKey;
		options.projectID = projectId;
		NSString *clientId = args[@"ios_client_id"];
		if ([clientId isKindOfClass:[NSString class]]
			&& clientId.length > 0) {
			options.clientID = clientId;
		}
		[FIRApp configureWithOptions:options];
		return YES;
	} @catch (NSException *exception) {
		NSLog(@"[MoonlitIdentity] firebase-init %@ rejected: %@", requestId,
			exception.name);
		return NO;
	}
}

- (NSString *)pendingReceipt:(NSString *)requestId {
	return [self jsonString:@{@"status" : kStatusPending, @"request_id" : requestId}];
}

- (NSString *)notConfiguredReceipt:(NSString *)requestId {
	return [self jsonString:[self notConfiguredOutcome:requestId]];
}

- (NSString *)cancelledReceipt:(NSString *)requestId {
	return [self jsonString:@{
		@"status" : kStatusCancelled,
		@"code" : kCodeUserCancelled,
		@"request_id" : requestId
	}];
}

- (NSString *)alreadyPendingReceipt:(NSString *)requestId {
	return [self jsonString:@{
		@"status" : kStatusError,
		@"code" : kCodeAlreadyPending,
		@"request_id" : requestId
	}];
}

- (NSString *)unknownProviderReceipt:(NSString *)requestId {
	return [self jsonString:@{
		@"status" : kStatusError,
		@"code" : @"unknown_provider",
		@"request_id" : requestId
	}];
}

- (NSDictionary *)localSession:(NSString *)requestId {
	return @{
		@"status" : kStatusOk,
		@"request_id" : requestId,
		@"kind" : @"local_guest",
		@"uid" : @"",
		@"provider" : @""
	};
}

- (NSDictionary *)cloudSession:(NSString *)requestId
	uid:(NSString *)uid
	provider:(NSString *)provider {
	return @{
		@"status" : kStatusOk,
		@"request_id" : requestId,
		@"kind" : @"cloud",
		@"uid" : uid ?: @"",
		@"provider" : provider ?: @""
	};
}

- (NSDictionary *)errorOutcome:(NSString *)requestId
	code:(NSString *)code
	retryable:(BOOL)retryable {
	return @{
		@"status" : kStatusError,
		@"code" : code,
		@"retryable" : @(retryable),
		@"request_id" : requestId
	};
}

- (NSString *)providerOfUser:(FIRUser *)user {
	if (user == nil || user.uid.length == 0) {
		return @"";
	}
	if (user.isAnonymous) {
		return kProviderAnonymous;
	}
	// Mapped from the linked provider data, never a constant. A user who
	// explicitly linked both social providers reports a deterministic
	// priority; each link was its own consented call.
	BOOL sawGoogle = NO;
	BOOL sawApple = NO;
	for (id<FIRUserInfo> info in user.providerData) {
		if ([info.providerID isEqualToString:@"google.com"]) {
			sawGoogle = YES;
		} else if ([info.providerID isEqualToString:@"apple.com"]) {
			sawApple = YES;
		}
	}
	if (sawGoogle) {
		return kProviderGoogle;
	}
	if (sawApple) {
		return kProviderApple;
	}
	return kProviderApple;
}

// --- outcome delivery -------------------------------------------------------

- (void)finishRequest:(NSString *)requestId outcome:(NSDictionary *)outcome {
	BOOL live = NO;
	@synchronized(self) {
		live = [_pending containsObject:requestId];
		[_pending removeObject:requestId];
		[_mutations removeObject:requestId];
		if ([_mutationOwner isEqualToString:requestId]) {
			_mutationOwner = nil;
		}
		if ([_reminderPermissionOwner isEqualToString:requestId]) {
			_reminderPermissionOwner = nil;
		}
	}
	if (!live) {
		return;
	}
	[self rememberSettled:requestId];
	if (_owner == NULL) {
		return;
	}
	// Marshal onto the Godot thread. Apple and Firebase completions arrive
	// on the main queue; call_deferred is the documented safe hop into the
	// engine, and the deferred method emits the signal exactly once.
	std::string json = std::string([[self jsonString:outcome] UTF8String]);
	_owner->call_deferred("_emit_outcome",
		godot::String(json.c_str()));
}

// --- Firebase anonymous guest -----------------------------------------------

- (NSString *)signInGuest:(NSString *)requestId args:(NSDictionary *)args {
	NSInteger claim = [self beginMutating:requestId];
	if (claim == 1) {
		return [self alreadyPendingReceipt:requestId];
	}
	if (claim == 2) {
		return [self busyReceipt:requestId];
	}
	if (![self ensureApp:requestId args:args]) {
		return [self notConfiguredReceipt:requestId];
	}
	if (![self isLive:requestId]) {
		return [self cancelledReceipt:requestId];
	}
	[self markMutation:requestId];
	[[FIRAuth auth] signInAnonymouslyWithCompletion:^(
		FIRAuthDataResult *_Nullable result, NSError *_Nullable error) {
		if (error != nil || result.user == nil || result.user.uid.length == 0) {
			NSLog(@"[MoonlitIdentity] guest %@ failed: %@", requestId,
				error == nil ? @"no-user" : @(error.code));
			[self finishRequest:requestId
				outcome:[self errorOutcome:requestId
					code:kCodeNetwork
					retryable:YES]];
			return;
		}
		[self finishRequest:requestId
			outcome:[self cloudSession:requestId
				uid:result.user.uid
				provider:kProviderAnonymous]];
	}];
	return [self pendingReceipt:requestId];
}

// --- Ordinary Google sign-in ------------------------------------------------
// GoogleSignIn SDK exchanged for a Firebase `google.com` credential: the
// same provider Android signs in with. The OAuth callback returns through
// the staged reversed-client-ID URL scheme into the chaining forwarder
// above, which offers it to GoogleSignIn and passes anything else to the
// delegate's previous implementation.

- (NSString *)beginGoogleFlow:(NSString *)requestId
	wantsLink:(BOOL)wantsLink
	args:(NSDictionary *)args {
	NSInteger claim = [self beginMutating:requestId];
	if (claim == 1) {
		return [self alreadyPendingReceipt:requestId];
	}
	if (claim == 2) {
		return [self busyReceipt:requestId];
	}
	if (![self ensureApp:requestId args:args]) {
		return [self notConfiguredReceipt:requestId];
	}
	if (![self isLive:requestId]) {
		return [self cancelledReceipt:requestId];
	}
	NSString *clientId = args[@"ios_client_id"];
	if (![clientId isKindOfClass:[NSString class]]
		|| clientId.length == 0) {
		// The GDScript gate refused this first; the native side stays
		// fail-closed when a misrouted call arrives without one.
		[self finishRequest:requestId
			outcome:[self notConfiguredOutcome:requestId]];
		return [self notConfiguredReceipt:requestId];
	}
	UIViewController *presenter = [self topViewController];
	if (presenter == nil) {
		[self finishRequest:requestId
			outcome:[self errorOutcome:requestId
				code:kCodeGoogleUnavailable
				retryable:NO]];
		return [self jsonString:[self errorOutcome:requestId
			code:kCodeGoogleUnavailable
			retryable:NO]];
	}
	[MoonlitGoogleURLForwarder installOnce];
	GIDConfiguration *config =
		[[GIDConfiguration alloc] initWithClientID:clientId];
	[GIDSignIn sharedInstance].configuration = config;
	// Pre-mutation: cancel drops the tracking and the completion below
	// drops itself. GoogleSignIn offers no programmatic dismiss, so a
	// cancelled sheet lingers until the player closes it; its answer is
	// then ignored, exactly like a detached Apple sheet.
	[[GIDSignIn sharedInstance]
		signInWithPresentingViewController:presenter
		completion:^(GIDSignInResult *_Nullable result,
			NSError *_Nullable error) {
		if (![self isLive:requestId]) {
			return;
		}
		if (error != nil) {
			[self finishGoogleSignIn:requestId error:error];
			return;
		}
		// Only the tokens are consumed, inside the Firebase call. The
		// result's profile is deliberately never touched.
		NSString *idToken = result.user.idToken.tokenString;
		NSString *accessToken = result.user.accessToken.tokenString;
		if (idToken == nil || idToken.length == 0) {
			[self finishRequest:requestId
				outcome:[self errorOutcome:requestId
					code:kCodeNetwork
					retryable:YES]];
			return;
		}
		FIRAuthCredential *credential = [FIRGoogleAuthProvider
			credentialWithIDToken:idToken
			accessToken:accessToken];
		if (wantsLink) {
			[self firebaseLink:requestId
				credential:credential
				provider:kProviderGoogle];
		} else {
			[self firebaseSignIn:requestId
				credential:credential
				provider:kProviderGoogle];
		}
	}];
	return [self pendingReceipt:requestId];
}

- (void)finishGoogleSignIn:(NSString *)requestId
	error:(NSError *)error {
	// Dismissing the Google sheet fails the completion without touching
	// the Firebase user, so a cancelled link keeps the guest.
	if ([error.domain isEqualToString:kGoogleSignInErrorDomain]
		&& error.code == kGoogleSignInCanceledCode) {
		[self finishRequest:requestId
			outcome:@{
				@"status" : kStatusCancelled,
				@"code" : kCodeUserCancelled,
				@"request_id" : requestId
			}];
		return;
	}
	NSLog(@"[MoonlitIdentity] google-sheet %@ failed: %ld", requestId,
		(long)error.code);
	[self finishRequest:requestId
		outcome:[self errorOutcome:requestId
			code:kCodeNetwork
			retryable:YES]];
}

- (UIWindow *)keyWindow {
	NSArray<UIScene *> *scenes =
		[[UIApplication sharedApplication] connectedScenes].allObjects;
	for (UIScene *scene in scenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (window.isKeyWindow) {
				return window;
			}
		}
	}
	return nil;
}

- (UIViewController *)topViewController {
	UIViewController *top = [self keyWindow].rootViewController;
	while (top.presentedViewController != nil) {
		top = top.presentedViewController;
	}
	return top;
}

// --- Sign in with Apple -----------------------------------------------------

- (NSString *)randomNonce:(NSUInteger)length {
	static NSString *const kAlphabet =
		@"0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._";
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	for (NSUInteger i = 0; i < length; i++) {
		uint8_t index = 0;
		if (SecRandomCopyBytes(kSecRandomDefault, 1, &index) != errSecSuccess) {
			index = (uint8_t)arc4random_uniform((uint32_t)kAlphabet.length);
		}
		[result appendFormat:@"%C", [kAlphabet characterAtIndex:index % kAlphabet.length]];
	}
	return result;
}

- (NSString *)sha256Hex:(NSString *)input {
	NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
		[hex appendFormat:@"%02x", digest[i]];
	}
	return hex;
}

- (NSString *)beginAppleFlow:(NSString *)requestId
	purpose:(MoonlitApplePurpose)purpose
	args:(NSDictionary *)args {
	NSInteger claim = [self beginMutating:requestId];
	if (claim == 1) {
		return [self alreadyPendingReceipt:requestId];
	}
	if (claim == 2) {
		return [self busyReceipt:requestId];
	}
	if (![self ensureApp:requestId args:args]) {
		return [self notConfiguredReceipt:requestId];
	}
	if (![self isLive:requestId]) {
		return [self cancelledReceipt:requestId];
	}
	return [self launchAppleSheet:requestId purpose:purpose];
}

- (NSString *)launchAppleSheet:(NSString *)requestId
	purpose:(MoonlitApplePurpose)purpose {
	if (_appleController != nil) {
		[self finishRequest:requestId
			outcome:[self errorOutcome:requestId
				code:kCodeAlreadyPending
				retryable:NO]];
		return [self jsonString:[self errorOutcome:requestId
			code:kCodeAlreadyPending
			retryable:NO]];
	}
	ASAuthorizationAppleIDProvider *provider = [[ASAuthorizationAppleIDProvider alloc] init];
	ASAuthorizationAppleIDRequest *request = [provider createRequest];
	// The Apple sheet requests no personal scopes: names and emails are
	// never used, so they are never requested. Only identityToken and
	// authorizationCode are consumed, and both stay inside the Firebase
	// calls.
	request.requestedScopes = @[];
	NSString *rawNonce = [self randomNonce:32];
	request.nonce = [self sha256Hex:rawNonce];
	_appleController =
		[[ASAuthorizationController alloc] initWithAuthorizationRequests:@[ request ]];
	_appleController.delegate = self;
	_appleController.presentationContextProvider = self;
	_appleRequestId = [requestId copy];
	_appleRawNonce = [rawNonce copy];
	_applePurpose = purpose;
	[_appleController performRequests];
	return [self pendingReceipt:requestId];
}

- (void)authorizationController:(ASAuthorizationController *)controller
	didCompleteWithAuthorization:(ASAuthorization *)authorization {
	NSString *requestId = _appleRequestId;
	NSString *rawNonce = _appleRawNonce;
	MoonlitApplePurpose purpose = _applePurpose;
	_appleController = nil;
	_appleRequestId = nil;
	_appleRawNonce = nil;
	if (requestId == nil || ![self isLive:requestId]) {
		return;
	}
	// ASAuthorization carries exactly one credential; there is no
	// per-type credential lookup selector (a lookup-by-type call was
	// checked against the real iPhoneOS SDK with clang -fsyntax-only and
	// does not compile, so read .credential with a class check).
	ASAuthorizationAppleIDCredential *credential = nil;
	if ([authorization.credential
			isKindOfClass:[ASAuthorizationAppleIDCredential class]]) {
		credential = (ASAuthorizationAppleIDCredential *)authorization.credential;
	}
	NSString *identityToken = nil;
	NSString *authCode = nil;
	if (credential != nil) {
		if (credential.identityToken != nil) {
			identityToken = [[NSString alloc] initWithData:credential.identityToken
				encoding:NSUTF8StringEncoding];
		}
		if (credential.authorizationCode != nil) {
			authCode = [[NSString alloc] initWithData:credential.authorizationCode
				encoding:NSUTF8StringEncoding];
		}
	}
	// The credential's fullName and email are deliberately never touched.
	if (identityToken == nil || identityToken.length == 0 || rawNonce == nil) {
		[self finishRequest:requestId
			outcome:[self errorOutcome:requestId
				code:kCodeNetwork
				retryable:YES]];
		return;
	}
	FIROAuthCredential *firebaseCredential = [FIROAuthProvider
		appleCredentialWithIDToken:identityToken
		rawNonce:rawNonce
		fullName:nil];
	switch (purpose) {
	case MoonlitApplePurposeSignIn:
		[self firebaseSignIn:requestId
			credential:firebaseCredential
			provider:kProviderApple];
		break;
	case MoonlitApplePurposeLink:
		[self firebaseLink:requestId
			credential:firebaseCredential
			provider:kProviderApple];
		break;
	case MoonlitApplePurposeDelete:
		[self firebaseDelete:requestId
			credential:firebaseCredential
			authCode:authCode];
		break;
	}
}

- (void)authorizationController:(ASAuthorizationController *)controller
	didCompleteWithError:(NSError *)error {
	NSString *requestId = _appleRequestId;
	_appleController = nil;
	_appleRequestId = nil;
	_appleRawNonce = nil;
	if (requestId == nil) {
		return;
	}
	if (error.code == ASAuthorizationErrorCanceled) {
		// The user closed the Apple sheet. The Firebase user, if any, is
		// untouched: a cancelled link keeps the guest account.
		[self finishRequest:requestId
			outcome:@{
				@"status" : kStatusCancelled,
				@"code" : kCodeUserCancelled,
				@"request_id" : requestId
			}];
		return;
	}
	NSLog(@"[MoonlitIdentity] apple-sheet %@ failed: %ld", requestId, (long)error.code);
	NSString *code = kCodeNetwork;
	if (error.code == ASAuthorizationErrorNotHandled ||
		error.code == ASAuthorizationErrorUnknown) {
		code = kCodeAppleUnavailable;
	}
	[self finishRequest:requestId
		outcome:[self errorOutcome:requestId code:code retryable:YES]];
}

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:
	(ASAuthorizationController *)controller {
	return [self keyWindow];
}

// --- Firebase credential exchange --------------------------------------------
// Shared by the Google and Apple flows. A link keeps the Firebase UID
// (the credential links onto the signed-in user); a sign-in takes the
// credential account's UID. The same collision rule holds for both: an
// account already linked elsewhere surfaces as a conflict naming the
// attempted provider, and neither account is touched.

- (void)firebaseSignIn:(NSString *)requestId
	credential:(FIRAuthCredential *)credential
	provider:(NSString *)provider {
	if (![self isLive:requestId]) {
		return;
	}
	[self markMutation:requestId];
	[[FIRAuth auth] signInWithCredential:credential
		completion:^(FIRAuthDataResult *_Nullable result, NSError *_Nullable error) {
		if (error != nil) {
			[self finishRequest:requestId
				outcome:[self classifyCredentialError:requestId
					error:error
					provider:provider]];
			return;
		}
		if (result.user == nil || result.user.uid.length == 0) {
			[self finishRequest:requestId
				outcome:[self errorOutcome:requestId
					code:kCodeNetwork
					retryable:YES]];
			return;
		}
		[self finishRequest:requestId
			outcome:[self cloudSession:requestId
				uid:result.user.uid
				provider:provider]];
	}];
}

- (void)firebaseLink:(NSString *)requestId
	credential:(FIRAuthCredential *)credential
	provider:(NSString *)provider {
	if (![self isLive:requestId]) {
		return;
	}
	FIRUser *user = [FIRAuth auth].currentUser;
	if (user == nil) {
		[self finishRequest:requestId
			outcome:[self errorOutcome:requestId
				code:kCodeNoSignedInUser
				retryable:NO]];
		return;
	}
	[self markMutation:requestId];
	[user linkWithCredential:credential
		completion:^(FIRAuthDataResult *_Nullable result, NSError *_Nullable error) {
		if (error != nil) {
			[self finishRequest:requestId
				outcome:[self classifyCredentialError:requestId
					error:error
					provider:provider]];
			return;
		}
		FIRUser *linked = result.user ?: user;
		[self finishRequest:requestId
			outcome:[self cloudSession:requestId
				uid:linked.uid
				provider:provider]];
	}];
}

- (NSDictionary *)classifyCredentialError:(NSString *)requestId
	error:(NSError *)error
	provider:(NSString *)provider {
	// A provider account already linked to a different Firebase user must
	// surface as a conflict the UI resolves. Neither account is touched
	// here: no overwrite, no merge, no silent switch.
	if (error.code == FIRAuthErrorCodeCredentialAlreadyInUse) {
		NSLog(@"[MoonlitIdentity] credential %@ conflict", requestId);
		return @{
			@"status" : kStatusConflict,
			@"code" : kCodeAlreadyLinkedElsewhere,
			@"provider" : provider,
			@"request_id" : requestId
		};
	}
	NSLog(@"[MoonlitIdentity] credential %@ failed: %ld", requestId, (long)error.code);
	return [self errorOutcome:requestId code:kCodeNetwork retryable:YES];
}

// --- Session, token, sign-out, deletion --------------------------------------

// The SDK-backed session as a dictionary: re-reads the live Firebase user
// so both the session answer and the sign-out failure terminal share one
// source. Serialized answers wrap this in jsonString; dictionary mergers
// use it directly — describeSession's JSON string must never be read as
// a dictionary.
- (NSDictionary *)sessionOutcome:(NSString *)requestId {
	if ([FIRApp defaultApp] == nil) {
		// No configured app: never touch FIRAuth. Its Swift missing-app
		// fatalError is uncatchable from Objective-C, so this guard is
		// the safety — not a try/catch. Cold-start callers initialize
		// from staged config first; when config is absent this local
		// session is the honest synchronous answer.
		return [self localSession:requestId];
	}
	FIRUser *user = [FIRAuth auth].currentUser;
	if (user == nil || user.uid.length == 0) {
		return [self localSession:requestId];
	}
	return [self cloudSession:requestId
		uid:user.uid
		provider:[self providerOfUser:user]];
}

- (NSString *)describeSession:(NSString *)requestId {
	return [self jsonString:[self sessionOutcome:requestId]];
}

- (NSString *)fetchIdToken:(NSString *)requestId
	forceRefresh:(BOOL)forceRefresh
	args:(NSDictionary *)args {
	if (![self beginRequest:requestId]) {
		return [self alreadyPendingReceipt:requestId];
	}
	if (![self ensureApp:requestId args:args]) {
		return [self notConfiguredReceipt:requestId];
	}
	if (![self isLive:requestId]) {
		return [self cancelledReceipt:requestId];
	}
	FIRUser *user = [FIRAuth auth].currentUser;
	if (user == nil) {
		[self finishRequest:requestId
			outcome:[self errorOutcome:requestId
				code:kCodeNoSignedInUser
				retryable:NO]];
		return [self jsonString:[self errorOutcome:requestId
			code:kCodeNoSignedInUser
			retryable:NO]];
	}
	// The raw token is handed to this call's answer only. It is never
	// written to disk, never logged, and never attached to any signal
	// except this request's own outcome.
	[user getIDTokenResultForcingRefresh:forceRefresh
		completion:^(FIRAuthTokenResult *_Nullable tokenResult,
			NSError *_Nullable error) {
		if (error != nil || tokenResult.token.length == 0) {
			NSLog(@"[MoonlitIdentity] token %@ failed: %ld", requestId,
				(long)(error == nil ? 0 : error.code));
			[self finishRequest:requestId
				outcome:[self errorOutcome:requestId
					code:kCodeNetwork
					retryable:YES]];
			return;
		}
		long long expiresMs =
			(long long)([tokenResult.expirationDate timeIntervalSince1970] * 1000.0);
		[self finishRequest:requestId
			outcome:@{
				@"status" : kStatusOk,
				@"request_id" : requestId,
				@"id_token" : tokenResult.token,
				@"token_expires_at" : @(expiresMs)
			}];
	}];
	return [self pendingReceipt:requestId];
}

- (NSString *)signOut:(NSString *)requestId {
	// Fully synchronous: records no bookkeeping and emits no signal. While
	// another mutation drains, sign-out waits: clearing the user under live
	// SDK work would let the completion resurrect a session this call just
	// reported as cleared.
	@synchronized(self) {
		if (_mutationOwner != nil) {
			return [self busyReceipt:requestId];
		}
	}
	if ([FIRApp defaultApp] == nil) {
		// No configured app: nothing to sign out of, which is the same
		// local session either way.
		[[GIDSignIn sharedInstance] signOut];
		return [self jsonString:[self localSession:requestId]];
	}
	NSError *error = nil;
	[[FIRAuth auth] signOut:&error];
	if (error != nil) {
		// A real sign-out failure (persistence): report it truthfully and
		// keep the actual session — never declare a guest success, and
		// never clear Google state the failed sign-out did not release.
		NSLog(@"[MoonlitIdentity] sign-out %@ failed: %ld", requestId,
			(long)error.code);
		return [self jsonString:[self signOutFailedOutcome:requestId]];
	}
	// Firebase sign-out leaves the Google SDK state behind; clear it too so
	// the next Google sign-in shows the account chooser fresh instead of
	// silently reusing the previous session.
	[[GIDSignIn sharedInstance] signOut];
	return [self jsonString:[self localSession:requestId]];
}

- (NSDictionary *)signOutFailedOutcome:(NSString *)requestId {
	// The error terminal carries the re-read session so the caller sees
	// both the failure and the preserved truth; the adapter applies the
	// session fields while surfacing the error status.
	NSMutableDictionary *outcome = [[self errorOutcome:requestId
		code:kCodeSignOutFailed
		retryable:YES] mutableCopy];
	NSDictionary *session = [self sessionOutcome:requestId];
	outcome[@"kind"] = session[@"kind"];
	outcome[@"uid"] = session[@"uid"];
	outcome[@"provider"] = session[@"provider"];
	return outcome;
}

- (NSString *)deleteAccount:(NSString *)requestId
	keepProviderGrant:(BOOL)keepGrant
	args:(NSDictionary *)args {
	NSInteger claim = [self beginMutating:requestId];
	if (claim == 1) {
		return [self alreadyPendingReceipt:requestId];
	}
	if (claim == 2) {
		return [self busyReceipt:requestId];
	}
	if (![self ensureApp:requestId args:args]) {
		return [self notConfiguredReceipt:requestId];
	}
	if (![self isLive:requestId]) {
		return [self cancelledReceipt:requestId];
	}
	FIRUser *user = [FIRAuth auth].currentUser;
	if (user == nil) {
		[self finishRequest:requestId
			outcome:[self errorOutcome:requestId
				code:kCodeNoSignedInUser
				retryable:NO]];
		return [self jsonString:[self errorOutcome:requestId
			code:kCodeNoSignedInUser
			retryable:NO]];
	}
	if (keepGrant || ![[self providerOfUser:user] isEqualToString:kProviderApple]) {
		// Anonymous, Google-linked, and grant-kept deletes run the
		// Firebase delete directly. A Google session gone stale answers
		// `recent_login_required` so the UI re-runs the Google sheet and
		// retries the delete.
		return [self deleteFirebaseUser:requestId user:user];
	}
	// Apple-linked delete: re-run the Apple sheet for a fresh authorization
	// code, then revoke the grant and delete the Firebase user. The sheet is
	// also the user's explicit confirmation of the delete.
	return [self launchAppleSheet:requestId purpose:MoonlitApplePurposeDelete];
}

- (NSString *)deleteFirebaseUser:(NSString *)requestId user:(FIRUser *)user {
	if (![self isLive:requestId]) {
		return [self cancelledReceipt:requestId];
	}
	[self markMutation:requestId];
	[user deleteWithCompletion:^(NSError *_Nullable error) {
		if (error != nil) {
			NSString *code = kCodeNetwork;
			BOOL retryable = YES;
			if (error.code == FIRAuthErrorCodeRequiresRecentLogin) {
				// Firebase needs a fresh sign-in before a delete. Say so
				// explicitly so the UI can re-run the Apple sheet.
				code = kCodeRecentLoginRequired;
				retryable = NO;
			} else {
				NSLog(@"[MoonlitIdentity] delete %@ failed: %ld", requestId,
					(long)error.code);
			}
			[self finishRequest:requestId
				outcome:[self errorOutcome:requestId
					code:code
					retryable:retryable]];
			return;
		}
		[self finishRequest:requestId
			outcome:[self localSession:requestId]];
	}];
	return [self pendingReceipt:requestId];
}

- (void)firebaseDelete:(NSString *)requestId
	credential:(FIROAuthCredential *)credential
	authCode:(NSString *)authCode {
	if (![self isLive:requestId]) {
		return;
	}
	FIRUser *user = [FIRAuth auth].currentUser;
	if (user == nil) {
		[self finishRequest:requestId
			outcome:[self errorOutcome:requestId
				code:kCodeNoSignedInUser
				retryable:NO]];
		return;
	}
	// The whole re-auth/revoke/delete chain counts as the mutation from here:
	// once the fresh sheet completed, cancel reports draining and this chain
	// runs to its truthful terminal.
	[self markMutation:requestId];
	// Re-authenticate with the fresh Apple credential first: without a
	// recent login the delete below is rejected.
	[user reauthenticateWithCredential:credential
		completion:^(FIRAuthDataResult *_Nullable _result, NSError *_Nullable error) {
		if (![self isLive:requestId]) {
			return;
		}
		if (error != nil) {
			NSLog(@"[MoonlitIdentity] reauth %@ failed: %ld", requestId,
				(long)error.code);
			[self finishRequest:requestId
				outcome:[self errorOutcome:requestId
					code:kCodeRecentLoginRequired
					retryable:NO]];
			return;
		}
		[self revokeAppleGrant:requestId user:user authCode:authCode];
	}];
}

// A failed Apple grant revocation (missing fresh code or an SDK error)
// answers a recoverable error carrying the re-read session, like the
// sign-out failure: the Firebase user is untouched, the native account
// stays signed in, and the UI retries the whole delete for a fresh code.
- (NSDictionary *)revokeFailedOutcome:(NSString *)requestId {
	NSMutableDictionary *outcome = [[self errorOutcome:requestId
		code:kCodeNetwork
		retryable:YES] mutableCopy];
	NSDictionary *session = [self sessionOutcome:requestId];
	outcome[@"kind"] = session[@"kind"];
	outcome[@"uid"] = session[@"uid"];
	outcome[@"provider"] = session[@"provider"];
	return outcome;
}

- (void)revokeAppleGrant:(NSString *)requestId
	user:(FIRUser *)user
	authCode:(NSString *)authCode {
	if (![self isLive:requestId]) {
		return;
	}
	if (authCode == nil || authCode.length == 0) {
		// No fresh code (should not happen after a successful sheet):
		// fail closed. The Firebase user is never deleted without a
		// successful revocation; the terminal keeps the cloud session so
		// the UI can retry the delete for a fresh code.
		NSLog(@"[MoonlitIdentity] revoke %@ failed: no fresh auth code", requestId);
		[self finishRequest:requestId
			outcome:[self revokeFailedOutcome:requestId]];
		return;
	}
	[[FIRAuth auth] revokeTokenWithAuthorizationCode:authCode
		completion:^(NSError *_Nullable error) {
		if (![self isLive:requestId]) {
			return;
		}
		if (error != nil) {
			NSLog(@"[MoonlitIdentity] revoke %@ failed: %ld", requestId,
				(long)error.code);
			[self finishRequest:requestId
				outcome:[self revokeFailedOutcome:requestId]];
			return;
		}
		[self deleteFirebaseUserAfterReauth:requestId user:user];
	}];
}

- (void)deleteFirebaseUserAfterReauth:(NSString *)requestId user:(FIRUser *)user {
	// The delete-flow request is still the pending one; settle it here.
	if (![self isLive:requestId]) {
		return;
	}
	[user deleteWithCompletion:^(NSError *_Nullable error) {
		if (error != nil) {
			NSLog(@"[MoonlitIdentity] delete %@ failed: %ld", requestId,
				(long)error.code);
			[self finishRequest:requestId
				outcome:[self errorOutcome:requestId
					code:kCodeNetwork
					retryable:YES]];
			return;
		}
		[self finishRequest:requestId
			outcome:[self localSession:requestId]];
	}];
}

// ---------------------------------------------------------------------------
// --- attendance reminders (local notifications; no Firebase) -------------------
//
// A bounded horizon of owned non-repeating requests at the
// server-confirmed eligibility plus N * 43200 seconds. Every delivery
// is anchored to eligibility, so a fresh reward and a halfway enable
// both land on twelve-hour boundaries; a short first delay is simply
// the first slot, never a short repeat. Elapsed slots are skipped,
// never burst. Identical re-schedules skip while the recorded horizon
// still covers the future, so a locale or status refresh neither
// duplicates nor shifts deliveries; a nearly consumed horizon refills
// from the same anchor, and a new claim resets it. Cancellation names
// exactly the owned slots plus the legacy ids.

// Reminders are for a player who is away: while the game is
// foregrounded nothing presents. Returning none matches the no-delegate
// default exactly, so other notifications keep their default behavior.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
	   willPresentNotification:(UNNotification *)notification
		 withCompletionHandler:
			 (void (^)(UNNotificationPresentationOptions))completionHandler {
	(void)center;
	(void)notification;
	completionHandler(UNNotificationPresentationOptionNone);
}

- (BOOL)reminderAuthGrantsDelivery:(NSInteger)status {
	if (status == UNAuthorizationStatusAuthorized ||
		status == UNAuthorizationStatusProvisional) {
		return YES;
	}
	if (@available(iOS 14.0, *)) {
		if (status == UNAuthorizationStatusEphemeral) {
			return YES;
		}
	}
	return NO;
}

- (NSString *)reminderPermissionName:(NSInteger)status {
	if ([self reminderAuthGrantsDelivery:status]) {
		return @"granted";
	}
	if (status == UNAuthorizationStatusDenied) {
		return @"denied";
	}
	return @"unknown";
}

- (void)refreshReminderAuthStatus {
	UNUserNotificationCenter *center =
		[UNUserNotificationCenter currentNotificationCenter];
	[center getNotificationSettingsWithCompletionHandler:^(
		UNNotificationSettings *settings) {
		@synchronized(self) {
			self.reminderAuthStatus = settings.authorizationStatus;
			self.reminderAuthKnown = YES;
		}
	}];
}

- (NSString *)reminderStatus:(NSString *)requestId {
	// The OS read is async-only, so the verdict arrives as a bounded
	// outcome instead of a stale cached guess: the game converges an
	// open panel when it lands rather than reopening twice. The cache
	// still gates the synchronous schedule path below.
	if (![self beginRequest:requestId]) {
		return [self alreadyPendingReceipt:requestId];
	}
	UNUserNotificationCenter *center =
		[UNUserNotificationCenter currentNotificationCenter];
	[center getNotificationSettingsWithCompletionHandler:^(
		UNNotificationSettings *settings) {
		NSInteger fresh = settings.authorizationStatus;
		@synchronized(self) {
			self.reminderAuthStatus = fresh;
			self.reminderAuthKnown = YES;
		}
		[self finishRequest:requestId outcome:@{
			@"status" : kStatusOk,
			@"permission" : [self reminderPermissionName:fresh],
			@"request_id" : requestId
		}];
	}];
	return [self jsonString:@{
		@"status" : kStatusPending,
		@"request_id" : requestId
	}];
}

- (NSString *)reminderRequestPermission:(NSString *)requestId {
	if (![self beginRequest:requestId]) {
		return [self jsonString:@{
			@"status" : kStatusError,
			@"code" : kCodeAlreadyPending,
			@"request_id" : requestId
		}];
	}
	@synchronized(self) {
		if (_reminderPermissionOwner != nil) {
			[_pending removeObject:requestId];
			return [self jsonString:@{
				@"status" : kStatusError,
				@"code" : kCodeRequestBusy,
				@"retryable" : @YES,
				@"request_id" : requestId
			}];
		}
		_reminderPermissionOwner = [requestId copy];
	}
	UNUserNotificationCenter *center =
		[UNUserNotificationCenter currentNotificationCenter];
	[center requestAuthorizationWithOptions:
		(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
		completionHandler:^(BOOL granted, NSError *_Nullable error) {
		(void)error;
		@synchronized(self) {
			self.reminderAuthStatus = granted
				? UNAuthorizationStatusAuthorized
				: UNAuthorizationStatusDenied;
			self.reminderAuthKnown = YES;
		}
		[self finishRequest:requestId outcome:@{
			@"status" : kStatusOk,
			@"permission" : granted ? @"granted" : @"denied",
			@"request_id" : requestId
		}];
	}];
	return [self jsonString:@{
		@"status" : kStatusPending,
		@"request_id" : requestId
	}];
}

- (NSString *)reminderSchedule:(NSString *)requestId
	args:(NSDictionary *)args {
	long long eligibleMillis =
		[args[@"eligible_utc_millis"] longLongValue];
	NSString *title = [args[@"title"] isKindOfClass:[NSString class]]
		? [args[@"title"] stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]]
		: @"";
	NSString *body = [args[@"body"] isKindOfClass:[NSString class]]
		? [args[@"body"] stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]]
		: @"";
	NSString *account = [args[@"account"] isKindOfClass:[NSString class]]
		? [args[@"account"] stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]]
		: @"";
	NSString *locale = [args[@"locale"] isKindOfClass:[NSString class]]
		? [args[@"locale"] stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]]
		: @"";
	if (eligibleMillis <= 0 || title.length == 0 ||
		body.length == 0 || account.length == 0) {
		return [self jsonString:@{
			@"status" : kStatusError,
			@"code" : kCodeInvalidArgs,
			@"retryable" : @NO,
			@"request_id" : requestId
		}];
	}
	NSInteger auth = UNAuthorizationStatusNotDetermined;
	@synchronized(self) {
		auth = _reminderAuthStatus;
	}
	if (![self reminderAuthGrantsDelivery:auth]) {
		[self refreshReminderAuthStatus];
		return [self jsonString:@{
			@"status" : kStatusDenied,
			@"permission" : [self reminderPermissionName:auth],
			@"code" : kCodePermissionDenied,
			@"request_id" : requestId
		}];
	}
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *recordedAccount =
		[defaults stringForKey:kReminderDefaultsAccount];
	NSNumber *recordedEligibleNumber =
		[defaults objectForKey:kReminderDefaultsEligibleMillis];
	long long recordedEligible =
		[recordedEligibleNumber isKindOfClass:[NSNumber class]]
		? [recordedEligibleNumber longLongValue]
		: -1;
	NSString *recordedLocale =
		[defaults stringForKey:kReminderDefaultsLocale];
	NSNumber *recordedBaseNumber =
		[defaults objectForKey:kReminderDefaultsBaseSlot];
	long long recordedBase =
		[recordedBaseNumber isKindOfClass:[NSNumber class]]
		? [recordedBaseNumber longLongValue]
		: 0;
	double recordedEnd =
		[defaults objectForKey:kReminderDefaultsHorizonEnd] != nil
		? [defaults doubleForKey:kReminderDefaultsHorizonEnd]
		: 0.0;
	NSTimeInterval now =
		[[NSDate date] timeIntervalSince1970];
	// Integer milliseconds throughout: the game side derives the
	// same window from the same anchor, and the equal-time boundary
	// must not depend on floating-point rounding.
	long long nowMillis = (long long)(now * 1000.0);
	// First slot not yet elapsed on this anchor (due-now counts):
	// a refill exactly 25 days out plans from slot 50 with a full
	// 48 future slots, never an empty window.
	long long firstFuture = MoonlitReminderFirstFuture(
		eligibleMillis, nowMillis);
	BOOL identical = [recordedAccount isEqualToString:account] &&
		recordedEligible == eligibleMillis &&
		[recordedLocale isEqualToString:locale];
	if (identical && recordedEnd > 0.0 &&
		MoonlitReminderWindowHolds(recordedBase, firstFuture)) {
		// Identical inputs with an adequate horizon: the center
		// already holds these absolute slots, so touching them
		// would only churn. A nearly consumed or exhausted window
		// falls through to the refill below, still anchored to
		// the same deadline. The receipt carries the held window
		// so the game side keeps its known metadata instead of
		// recording an unknown zero and re-asking forever.
		return [self jsonString:@{
			@"status" : kStatusOk,
			@"eligible_millis" : @(eligibleMillis),
			@"duplicate" : @YES,
			@"scheduled_slots" : @(MoonlitReminderRemaining(
				recordedBase, firstFuture)),
			@"base_slot" : @(recordedBase),
			@"horizon_end_unix" : @(recordedEnd),
			@"request_id" : requestId
		}];
	}
	UNUserNotificationCenter *center =
		[UNUserNotificationCenter currentNotificationCenter];
	// Replace the whole owned horizon plus any legacy pending copies,
	// so a device migrating from the one-shot/repeat shape cannot
	// double-deliver. Identifiers are stable ordinals 0..47 while
	// timestamps stay eligibility + N * 43200: a refill never shifts
	// the anchor, and re-added slots keep absolute times.
	NSMutableArray<NSString *> *replaced =
		[[self reminderSlotIdentifiers] mutableCopy];
	[replaced addObjectsFromArray:@[
		kReminderFirstId, kReminderRepeatId
	]];
	[center removePendingNotificationRequestsWithIdentifiers:replaced];
	UNMutableNotificationContent *content =
		[[UNMutableNotificationContent alloc] init];
	content.title = title;
	content.body = body;
	content.sound = [UNNotificationSound defaultSound];
	long long added = 0;
	double lastFire = 0.0;
	for (long long pos = 0; pos < kReminderHorizonSlots; pos++) {
		long long slot = firstFuture + pos;
		long long fireMs = MoonlitReminderSlotFireMs(
			eligibleMillis, slot);
		if (fireMs < nowMillis) {
			// Strictly elapsed slots stay unscheduled: the past
			// must never burst as immediate deliveries, even if
			// the clock jumped between the window computation and
			// this loop. A slot due exactly now schedules once;
			// the next computation already counts it as past.
			continue;
		}
		NSTimeInterval delay =
			(NSTimeInterval)(fireMs - nowMillis) / 1000.0;
		if (delay < 1.0) {
			delay = 1.0;
		}
		UNTimeIntervalNotificationTrigger *trigger =
			[UNTimeIntervalNotificationTrigger
				triggerWithTimeInterval:delay
				repeats:NO];
		NSString *identifier = [kReminderSlotPrefix
			stringByAppendingFormat:@"%02lld", pos];
		UNNotificationRequest *request =
			[UNNotificationRequest requestWithIdentifier:identifier
				content:content
				trigger:trigger];
		[center addNotificationRequest:request
			withCompletionHandler:nil];
		added++;
		lastFire = (double)fireMs / 1000.0;
	}
	[defaults setObject:account forKey:kReminderDefaultsAccount];
	[defaults setObject:@(eligibleMillis)
		forKey:kReminderDefaultsEligibleMillis];
	[defaults setObject:locale forKey:kReminderDefaultsLocale];
	[defaults setDouble:now forKey:kReminderDefaultsScheduledAt];
	[defaults setObject:@(firstFuture) forKey:kReminderDefaultsBaseSlot];
	[defaults setDouble:lastFire forKey:kReminderDefaultsHorizonEnd];
	return [self jsonString:@{
		@"status" : kStatusOk,
		@"eligible_millis" : @(eligibleMillis),
		@"scheduled_slots" : @(added),
		@"base_slot" : @(firstFuture),
		@"horizon_end_unix" : @(lastFire),
		@"request_id" : requestId
	}];
}

- (NSArray<NSString *> *)reminderSlotIdentifiers {
	NSMutableArray<NSString *> *ids = [NSMutableArray
		arrayWithCapacity:(NSUInteger)kReminderHorizonSlots];
	for (long long slot = 0; slot < kReminderHorizonSlots; slot++) {
		[ids addObject:[kReminderSlotPrefix
			stringByAppendingFormat:@"%02lld", slot]];
	}
	return ids;
}

- (NSString *)reminderCancel:(NSString *)requestId {
	UNUserNotificationCenter *center =
		[UNUserNotificationCenter currentNotificationCenter];
	// The whole owned horizon plus every legacy identifier. Other
	// app notifications are never named here.
	NSMutableArray<NSString *> *owned =
		[[self reminderSlotIdentifiers] mutableCopy];
	[owned addObjectsFromArray:@[
		kReminderFirstId, kReminderRepeatId, kReminderDebugId
	]];
	[center removePendingNotificationRequestsWithIdentifiers:owned];
	[center removeDeliveredNotificationsWithIdentifiers:owned];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:kReminderDefaultsAccount];
	[defaults removeObjectForKey:kReminderDefaultsEligibleMillis];
	[defaults removeObjectForKey:kReminderDefaultsLocale];
	[defaults removeObjectForKey:kReminderDefaultsScheduledAt];
	[defaults removeObjectForKey:kReminderDefaultsBaseSlot];
	[defaults removeObjectForKey:kReminderDefaultsHorizonEnd];
	return [self jsonString:@{
		@"status" : kStatusOk,
		@"request_id" : requestId
	}];
}

- (NSString *)reminderOpenSettings:(NSString *)requestId {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSURL *url = [NSURL
			URLWithString:UIApplicationOpenSettingsURLString];
		if (url != nil) {
			[[UIApplication sharedApplication] openURL:url
				options:@{}
				completionHandler:nil];
		}
	});
	return [self jsonString:@{
		@"status" : kStatusOk,
		@"request_id" : requestId
	}];
}

- (NSString *)reminderPending:(NSString *)requestId {
	if (![self beginRequest:requestId]) {
		return [self jsonString:@{
			@"status" : kStatusError,
			@"code" : kCodeAlreadyPending,
			@"request_id" : requestId
		}];
	}
	UNUserNotificationCenter *center =
		[UNUserNotificationCenter currentNotificationCenter];
	[center getPendingNotificationRequestsWithCompletionHandler:^(
		NSArray<UNNotificationRequest *> *requests) {
		NSMutableArray *held = [NSMutableArray array];
		long long heldSlots = 0;
		for (UNNotificationRequest *request in requests) {
			NSString *identifier = request.identifier;
			BOOL owned = [identifier
				hasPrefix:kReminderSlotPrefix] ||
				[identifier isEqualToString:kReminderFirstId] ||
				[identifier isEqualToString:kReminderRepeatId] ||
				[identifier isEqualToString:kReminderDebugId];
			if (!owned) {
				continue;
			}
			if ([identifier hasPrefix:kReminderSlotPrefix]) {
				heldSlots++;
			}
			UNNotificationTrigger *trigger = request.trigger;
			NSTimeInterval interval = -1;
			BOOL repeats = NO;
			NSDate *next = nil;
			if ([trigger
				isKindOfClass:[UNTimeIntervalNotificationTrigger class]]) {
				UNTimeIntervalNotificationTrigger *timed =
					(UNTimeIntervalNotificationTrigger *)trigger;
				interval = timed.timeInterval;
				repeats = timed.repeats;
				next = timed.nextTriggerDate;
			} else if ([trigger
				isKindOfClass:[UNCalendarNotificationTrigger class]]) {
				next = ((UNCalendarNotificationTrigger *)trigger)
					.nextTriggerDate;
			}
			[held addObject:@{
				@"identifier" : identifier,
				@"interval_seconds" : @(interval),
				@"repeats" : @(repeats),
				@"next_trigger_unix" : next != nil
					? @([next timeIntervalSince1970])
					: @(-1)
			}];
		}
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSNumber *anchorNumber =
			[defaults objectForKey:kReminderDefaultsEligibleMillis];
		long long anchor =
			[anchorNumber isKindOfClass:[NSNumber class]]
			? [anchorNumber longLongValue]
			: -1;
		NSNumber *baseNumber =
			[defaults objectForKey:kReminderDefaultsBaseSlot];
		long long base =
			[baseNumber isKindOfClass:[NSNumber class]]
			? [baseNumber longLongValue]
			: 0;
		double windowEnd =
			[defaults objectForKey:kReminderDefaultsHorizonEnd]
				!= nil
			? [defaults doubleForKey:kReminderDefaultsHorizonEnd]
			: 0.0;
		[self finishRequest:requestId outcome:@{
			@"status" : kStatusOk,
			@"held" : held,
			@"recorded" : @{
				@"account" : [defaults
					stringForKey:kReminderDefaultsAccount] ?: @"",
				@"eligible_millis" : @(anchor),
				@"locale" : [defaults
					stringForKey:kReminderDefaultsLocale] ?: @""
			},
			@"horizon" : @{
				@"anchor_eligible_millis" : @(anchor),
				@"slot_count" : @(kReminderHorizonSlots),
				@"base_slot" : @(base),
				@"held_slots" : @(heldSlots),
				@"horizon_end_unix" : @(windowEnd)
			},
			@"request_id" : requestId
		}];
	}];
	return [self jsonString:@{
		@"status" : kStatusPending,
		@"request_id" : requestId
	}];
}

- (NSString *)reminderDebugSchedule:(NSString *)requestId
	args:(NSDictionary *)args {
	NSInteger auth = UNAuthorizationStatusNotDetermined;
	@synchronized(self) {
		auth = _reminderAuthStatus;
	}
	if (![self reminderAuthGrantsDelivery:auth]) {
		[self refreshReminderAuthStatus];
		return [self jsonString:@{
			@"status" : kStatusDenied,
			@"permission" : [self reminderPermissionName:auth],
			@"code" : kCodePermissionDenied,
			@"request_id" : requestId
		}];
	}
	NSTimeInterval delay = [args[@"delay_seconds"] doubleValue];
	if (delay < kReminderDebugMinSeconds) {
		delay = kReminderDebugMinSeconds;
	}
	if (delay > kReminderDebugMaxSeconds) {
		delay = kReminderDebugMaxSeconds;
	}
	UNUserNotificationCenter *center =
		[UNUserNotificationCenter currentNotificationCenter];
	[center removePendingNotificationRequestsWithIdentifiers:@[
		kReminderDebugId
	]];
	UNMutableNotificationContent *content =
		[[UNMutableNotificationContent alloc] init];
	content.title = @"Moonlit Beacon QA";
	content.body = @"QA reminder";
	content.sound = [UNNotificationSound defaultSound];
	UNTimeIntervalNotificationTrigger *trigger =
		[UNTimeIntervalNotificationTrigger
			triggerWithTimeInterval:delay
			repeats:NO];
	UNNotificationRequest *request =
		[UNNotificationRequest requestWithIdentifier:kReminderDebugId
			content:content
			trigger:trigger];
	[center addNotificationRequest:request withCompletionHandler:nil];
	return [self jsonString:@{
		@"status" : kStatusOk,
		@"fire_in_seconds" : @(delay),
		@"request_id" : requestId
	}];
}
@end

// GDExtension binding.
// ---------------------------------------------------------------------------

MoonlitIdentityIos::MoonlitIdentityIos() {
	// ARC: retain the worker across the void * boundary here, release it in
	// the destructor. A direct assignment does not compile under ARC.
	MoonlitIdentityWorker *worker =
		[[MoonlitIdentityWorker alloc] initWithOwner:this];
	_worker = (__bridge_retained void *)worker;
}

MoonlitIdentityIos::~MoonlitIdentityIos() {
	MoonlitIdentityWorker *worker = (__bridge_transfer MoonlitIdentityWorker *)_worker;
	worker.owner = NULL;
	worker.appleController.delegate = nil;
	worker.appleController.presentationContextProvider = nil;
	_worker = nullptr;
	(void)worker;
}

static godot::String ns_to_godot(NSString *value) {
	if (value == nil) {
		return godot::String();
	}
	return godot::String([value UTF8String]);
}

static NSString *godot_to_ns(const godot::String &value) {
	return [NSString stringWithUTF8String:value.utf8().get_data()];
}

void MoonlitIdentityIos::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitSignInGuest",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitSignInGuest);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitSignInProvider",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitSignInProvider);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitLinkProvider",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitLinkProvider);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitGetSession",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitGetSession);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitGetIdToken",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitGetIdToken);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitSignOut",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitSignOut);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitDeleteAccount",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitDeleteAccount);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitCancelRequest",
		"request_id"), &MoonlitIdentityIos::moonlitCancelRequest);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitReminderStatus",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitReminderStatus);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitReminderRequestPermission",
		"request_id", "args_json"),
		&MoonlitIdentityIos::moonlitReminderRequestPermission);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitReminderSchedule",
		"request_id", "args_json"),
		&MoonlitIdentityIos::moonlitReminderSchedule);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitReminderCancel",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitReminderCancel);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitReminderOpenSettings",
		"request_id", "args_json"),
		&MoonlitIdentityIos::moonlitReminderOpenSettings);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitReminderPending",
		"request_id", "args_json"), &MoonlitIdentityIos::moonlitReminderPending);
	godot::ClassDB::bind_method(godot::D_METHOD("moonlitReminderDebugSchedule",
		"request_id", "args_json"),
		&MoonlitIdentityIos::moonlitReminderDebugSchedule);
	godot::ClassDB::bind_method(godot::D_METHOD("_emit_outcome",
		"outcome_json"), &MoonlitIdentityIos::_emit_outcome);
	ADD_SIGNAL(godot::MethodInfo("moonlit_identity_event",
		godot::PropertyInfo(godot::Variant::STRING, "outcome_json")));
}

godot::String MoonlitIdentityIos::moonlitSignInGuest(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot([worker signInGuest:godot_to_ns(p_request_id)
		args:[worker parseArgs:godot_to_ns(p_args_json)]]);
}

godot::String MoonlitIdentityIos::moonlitSignInProvider(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	NSString *requestId = godot_to_ns(p_request_id);
	NSDictionary *args = [worker parseArgs:godot_to_ns(p_args_json)];
	// The GDScript gate already refused unknown providers; this dispatch
	// double-checks the name so a misrouted call fails loudly instead of
	// running the wrong SDK flow.
	if ([args[@"provider"] isEqualToString:@"google"]) {
		return ns_to_godot([worker beginGoogleFlow:requestId
			wantsLink:NO
			args:args]);
	}
	if ([args[@"provider"] isEqualToString:@"apple"]) {
		return ns_to_godot([worker beginAppleFlow:requestId
			purpose:MoonlitApplePurposeSignIn
			args:args]);
	}
	NSLog(@"[MoonlitIdentity] provider %@ unknown", requestId);
	return ns_to_godot([worker unknownProviderReceipt:requestId]);
}

godot::String MoonlitIdentityIos::moonlitLinkProvider(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	NSString *requestId = godot_to_ns(p_request_id);
	NSDictionary *args = [worker parseArgs:godot_to_ns(p_args_json)];
	if ([args[@"provider"] isEqualToString:@"google"]) {
		return ns_to_godot([worker beginGoogleFlow:requestId
			wantsLink:YES
			args:args]);
	}
	if ([args[@"provider"] isEqualToString:@"apple"]) {
		return ns_to_godot([worker beginAppleFlow:requestId
			purpose:MoonlitApplePurposeLink
			args:args]);
	}
	NSLog(@"[MoonlitIdentity] provider %@ unknown", requestId);
	return ns_to_godot([worker unknownProviderReceipt:requestId]);
}

godot::String MoonlitIdentityIos::moonlitGetSession(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	NSString *requestId = godot_to_ns(p_request_id);
	NSDictionary *args = [worker parseArgs:godot_to_ns(p_args_json)];
	// Cold-start: configure the default app from the staged public config
	// before the first session read so a saved Firebase user restores
	// instead of answering local guest. Absent or rejected config falls
	// through to the guarded local session below — FIRAuth is never
	// touched without a configured FIRApp. Synchronous: no bookkeeping,
	// no signal.
	[worker ensureSessionApp:requestId args:args];
	return ns_to_godot([worker describeSession:requestId]);
}

godot::String MoonlitIdentityIos::moonlitGetIdToken(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	NSDictionary *args = [worker parseArgs:godot_to_ns(p_args_json)];
	BOOL forceRefresh = [args[@"force_refresh"] boolValue];
	return ns_to_godot([worker fetchIdToken:godot_to_ns(p_request_id)
		forceRefresh:forceRefresh
		args:args]);
}

godot::String MoonlitIdentityIos::moonlitSignOut(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	(void)p_args_json;
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot([worker signOut:godot_to_ns(p_request_id)]);
}

godot::String MoonlitIdentityIos::moonlitDeleteAccount(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	NSDictionary *args = [worker parseArgs:godot_to_ns(p_args_json)];
	BOOL keepGrant = [args[@"keep_provider_grant"] boolValue];
	return ns_to_godot([worker deleteAccount:godot_to_ns(p_request_id)
		keepProviderGrant:keepGrant
		args:args]);
}

godot::String MoonlitIdentityIos::moonlitCancelRequest(
	const godot::String &p_request_id) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot([worker cancelRequest:godot_to_ns(p_request_id)]);
}

godot::String MoonlitIdentityIos::moonlitReminderStatus(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	(void)p_args_json;
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot([worker reminderStatus:godot_to_ns(p_request_id)]);
}

godot::String MoonlitIdentityIos::moonlitReminderRequestPermission(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	(void)p_args_json;
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot(
		[worker reminderRequestPermission:godot_to_ns(p_request_id)]);
}

godot::String MoonlitIdentityIos::moonlitReminderSchedule(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot([worker reminderSchedule:godot_to_ns(p_request_id)
		args:[worker parseArgs:godot_to_ns(p_args_json)]]);
}

godot::String MoonlitIdentityIos::moonlitReminderCancel(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	(void)p_args_json;
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot([worker reminderCancel:godot_to_ns(p_request_id)]);
}

godot::String MoonlitIdentityIos::moonlitReminderOpenSettings(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	(void)p_args_json;
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot(
		[worker reminderOpenSettings:godot_to_ns(p_request_id)]);
}

godot::String MoonlitIdentityIos::moonlitReminderPending(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	(void)p_args_json;
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot([worker reminderPending:godot_to_ns(p_request_id)]);
}

godot::String MoonlitIdentityIos::moonlitReminderDebugSchedule(
	const godot::String &p_request_id, const godot::String &p_args_json) {
	MoonlitIdentityWorker *worker = (__bridge MoonlitIdentityWorker *)_worker;
	return ns_to_godot(
		[worker reminderDebugSchedule:godot_to_ns(p_request_id)
			args:[worker parseArgs:godot_to_ns(p_args_json)]]);
}

void MoonlitIdentityIos::_emit_outcome(
	const godot::String &p_outcome_json) {
	emit_signal("moonlit_identity_event", p_outcome_json);
}

// ---------------------------------------------------------------------------
// GDExtension entry point.
// ---------------------------------------------------------------------------

using namespace godot;

static void initialize_moonlit_identity(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(MoonlitIdentityIos);
	// Offer Google OAuth callbacks to GoogleSignIn from the first launch.
	// The install hops to the main queue (UIKit-owned delegate), stays
	// pending when the delegate does not exist yet, and chains to the
	// previous implementation so app/IAP URL handling is preserved.
	dispatch_async(dispatch_get_main_queue(), ^{
		[MoonlitGoogleURLForwarder installOnce];
	});
}

static void uninitialize_moonlit_identity(ModuleInitializationLevel p_level) {
	(void)p_level;
}

extern "C" {
GDExtensionBool moonlit_identity_ios_entry(
	GDExtensionInterfaceGetProcAddress p_get_proc_address,
	GDExtensionClassLibraryPtr p_library,
	GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(
		p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_moonlit_identity);
	init_obj.register_terminator(uninitialize_moonlit_identity);
	init_obj.set_minimum_library_initialization_level(
		MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
