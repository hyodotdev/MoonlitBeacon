import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  GODOT_ENGINE_PRIVACY_REASONS,
  IDENTITY_APP_PRIVACY_API,
  assertSingleRootPrivacyManifestRegistration,
  mergeAppPrivacyManifest,
  mergeIdentityPrivacyManifestIntoGeneratedExport,
  privacyApiEntries,
  privacyTrackingValue,
  rootPrivacyManifestFileReferences,
} from './identity-export.mjs';
import { renderAndroidPluginProject } from './player-identity-build.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, '../..');
const GAME = join(HERE, '../../apps/game');
const ADDON = join(GAME, 'addons/moonlit-identity');
const ANDROID_SRC = join(ADDON, 'android/src/main');
const PLUGIN_KT = join(
  ANDROID_SRC,
  'kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt',
);
const ALARM_KT = join(
  ANDROID_SRC,
  'kotlin/dev/moonlitbeacon/identity/MoonlitReminderAlarm.kt',
);
const MANIFEST_TMPL = join(ADDON, 'android/AndroidManifest.xml.tmpl');
const IOS_MM = join(ADDON, 'ios/src/MoonlitIdentityIos.mm');
const PLANNER_H = join(ADDON, 'ios/src/MoonlitReminderPlanner.h');
const IOS_H = join(ADDON, 'ios/include/MoonlitIdentityIos.h');
const IOS_PRIVACY = join(ADDON, 'ios/PrivacyInfo.xcprivacy');
const BRIDGE_GD = join(ADDON, 'moonlit_identity.gd');
const EXPORT_MANIFEST_GD = join(ADDON, 'ios_export_manifest.gd');
const EXPORT_PLUGIN_GD = join(ADDON, 'moonlit_identity_plugin.gd');

const REMINDER_METHODS = [
  'moonlitReminderStatus',
  'moonlitReminderRequestPermission',
  'moonlitReminderSchedule',
  'moonlitReminderCancel',
  'moonlitReminderOpenSettings',
  'moonlitReminderPending',
  'moonlitReminderDebugSchedule',
];

function read(path) {
  return readFileSync(path, 'utf8');
}

test('android manifest requests notification plus boot, never exact alarms', () => {
  const manifest = read(MANIFEST_TMPL);
  assert.match(manifest, /POST_NOTIFICATIONS/);
  assert.match(manifest, /RECEIVE_BOOT_COMPLETED/);
  assert.doesNotMatch(manifest, /SCHEDULE_EXACT_ALARM/);
  assert.doesNotMatch(manifest, /USE_EXACT_ALARM/);
  assert.doesNotMatch(manifest, /SCHEDULE_EXACT/);
});

test('android manifest keeps the reminder receiver private with boot re-arm', () => {
  const manifest = read(MANIFEST_TMPL);
  assert.match(manifest, /MoonlitReminderReceiver/);
  assert.match(manifest, /android:exported="false"/);
  assert.match(manifest, /android\.intent\.action\.BOOT_COMPLETED/);
});

test('android plugin exposes all seven reminder entry points', () => {
  const kt = read(PLUGIN_KT);
  for (const method of REMINDER_METHODS) {
    assert.match(
      kt,
      new RegExp(`@UsedByGodot\\s+fun ${method}\\(`),
      `${method} is a Godot entry point`,
    );
  }
});

test('android plugin honors the pinned lifecycle and permission signatures', () => {
  const kt = read(PLUGIN_KT);
  assert.match(kt, /override fun onMainResume\(\)/);
  assert.match(kt, /override fun onMainPause\(\)/);
  // Pinned Godot core declares onMainRequestPermissionsResult as void:
  // the override must return Unit (no Boolean), unlike onMainBackPressed.
  assert.match(
    kt,
    /override fun onMainRequestPermissionsResult\(\s*requestCode: Int,\s*permissions: Array<String>,\s*grantResults: IntArray\s*\)\s*\{/,
  );
  const callback = kt.slice(
    kt.indexOf('override fun onMainRequestPermissionsResult'),
    kt.indexOf('fun moonlitReminderStatus'),
  );
  assert.doesNotMatch(callback, /return (true|false)/);
  assert.match(callback, /REMINDER_PERMISSION_CODE/);
  assert.match(callback, /reminderPermissionOwner\s*=\s*null/);
});

test('android reminder entry points use the live activity or an honest error', () => {
  const kt = read(PLUGIN_KT);
  // Godot is not a Context: no entry point may fabricate one from it.
  assert.doesNotMatch(kt, /\?: godot/);
  assert.match(kt, /CODE_NO_ACTIVITY = "no_activity"/);
  const uses = kt.match(/CODE_NO_ACTIVITY/g) ?? [];
  // Status, schedule, cancel, pending, debug, permission, settings.
  assert.ok(uses.length >= 8, `seven call sites plus the const, saw ${uses.length}`);
  assert.match(kt, /CODE_NO_ACTIVITY, retryable = true/);
});

test('android alarm stays inexact on a twelve-hour cadence', () => {
  const kt = read(ALARM_KT);
  assert.match(kt, /setInexactRepeating\(/);
  assert.match(kt, /REPEAT_MILLIS = 43200000L/);
  const plugin = read(PLUGIN_KT);
  for (const source of [kt, plugin]) {
    assert.doesNotMatch(source, /setExact/);
    assert.doesNotMatch(source, /setWindow/);
    assert.doesNotMatch(source, /SCHEDULE_EXACT/);
  }
});

test('android first trigger stays on the anchor grid', () => {
  const kt = read(ALARM_KT);
  // An overdue anchor must never fire its backlog immediately: the
  // first trigger is the anchor's next future twelve-hour slot.
  assert.match(
    kt,
    /fun firstFutureTrigger\(anchorMillis: Long, nowMillis: Long\): Long/,
  );
  const schedule = kt.slice(
    kt.indexOf('fun schedule(context: Context, eligibleMillis: Long)'),
    kt.indexOf('fun scheduleDebug('),
  );
  assert.match(schedule, /firstFutureTrigger\(/);
  assert.doesNotMatch(kt, /maxOf\(eligible, now\)/);
  const boot = kt.slice(kt.indexOf('private fun onBoot('));
  assert.match(boot, /MoonlitReminderAlarm\.schedule\(\s*context, eligible\s*\)/);
  assert.doesNotMatch(boot, /firstFutureTrigger\(/);
});

test('android intents are all explicit and immutable', () => {
  const kt = read(ALARM_KT);
  const pending = kt.match(/PendingIntent\.(getBroadcast|getActivity)\(/g) ?? [];
  assert.ok(pending.length >= 3, 'alarm, debug, and launch intents exist');
  const immutable = kt.match(/FLAG_IMMUTABLE/g) ?? [];
  assert.ok(
    immutable.length >= pending.length,
    'every PendingIntent carries FLAG_IMMUTABLE',
  );
});

test('android delivery re-checks opt-out, permission, channel, foreground', () => {
  const kt = read(ALARM_KT);
  assert.match(kt, /KEY_ENABLED, false/);
  assert.match(kt, /notificationsAllowed\(context\)/);
  assert.match(kt, /channelOpen\(context\)/);
  assert.match(kt, /appForegrounded\(context\)/);
});

test('android effective status spans the global switch, runtime, channel', () => {
  const kt = read(ALARM_KT);
  // No blanket grant below 33: every version weighs the app-global
  // switch and the attendance channel alongside the runtime grant.
  assert.doesNotMatch(kt, /if \(Build\.VERSION\.SDK_INT < 33\) return true/);
  assert.match(kt, /fun appNotificationsEnabled\(context: Context\): Boolean/);
  assert.match(kt, /areNotificationsEnabled\(\)/);
  // The support-library reflective int-op check: OPSTR_POST_NOTIFICATION
  // is not in this compile SDK, so the op id resolves by name at
  // runtime instead of by direct reference.
  assert.doesNotMatch(kt, /OPSTR_POST_NOTIFICATION/);
  assert.match(kt, /getMethod\("checkOpNoThrow"/);
  assert.match(kt, /getDeclaredField\("OP_POST_NOTIFICATION"\)/);
  assert.match(kt, /MODE_ALLOWED/);
  assert.match(kt, /fun runtimePermissionMissing\(context: Context\): Boolean/);
  const allowed = kt.slice(
    kt.indexOf('fun notificationsAllowed'),
    kt.indexOf('fun runtimePermissionMissing'),
  );
  assert.match(allowed, /appNotificationsEnabled\(context\)/);
  assert.match(allowed, /runtimePermissionMissing\(context\)/);
  assert.match(allowed, /channelOpen\(context\)/);
  const plugin = read(PLUGIN_KT);
  assert.match(plugin, /runtimePermissionMissing\(host\)/);
  assert.match(plugin, /"horizon_end_unix", -1/);
});

test('android retire clears tokens without minting them', () => {
  const kt = read(ALARM_KT);
  assert.doesNotMatch(kt, /fun alarmScheduled\(/);
  assert.match(kt, /fun alarmTokenPresent\(context: Context\): Boolean/);
  assert.match(kt, /fun scheduleIntentPersisted\(context: Context\): Boolean/);
  assert.match(kt, /KEY_ENABLED, false/);
  assert.match(kt, /KEY_ELIGIBLE_MILLIS, 0L/);
  const cancel = kt.slice(
    kt.indexOf('fun cancel(context: Context)'),
    kt.indexOf('fun scheduleIntentPersisted'),
  );
  assert.match(cancel, /cancelToken\(alarms, context, ACTION_ALARM/);
  assert.match(cancel, /cancelToken\(alarms, context, ACTION_DEBUG/);
  assert.match(cancel, /FLAG_NO_CREATE/);
  assert.match(cancel, /alarms\.cancel\(existing\)/);
  assert.match(cancel, /existing\.cancel\(\)/);
  assert.doesNotMatch(cancel, /alarmIntent\(context\)/);
  assert.doesNotMatch(cancel, /debugIntent\(context/);
});

test('android boot re-arms only an enabled stored schedule', () => {
  const kt = read(ALARM_KT);
  assert.match(kt, /ACTION_BOOT_COMPLETED -> onBoot/);
  // The raw anchor reaches schedule(), which moves an overdue first
  // trigger onto the anchor grid instead of firing the backlog now.
  assert.doesNotMatch(kt, /maxOf\(eligible, now\)/);
});

test('android foreground state cannot stick after a crash', () => {
  const kt = read(ALARM_KT);
  assert.match(kt, /RESUMED_FRESH_MILLIS = 600000L/);
  assert.match(kt, /IMPORTANCE_FOREGROUND/);
});

test('android debug schedule stays bounded and permission-gated', () => {
  const kt = read(PLUGIN_KT);
  assert.match(kt, /DEBUG_DELAY_MIN_SECONDS = 5\.0/);
  assert.match(kt, /DEBUG_DELAY_MAX_SECONDS = 600\.0/);
  assert.match(kt, /coerceIn\(DEBUG_DELAY_MIN_SECONDS/);
});

test('android permission slot stays separate from identity mutations', () => {
  const kt = read(PLUGIN_KT);
  assert.match(kt, /private var reminderPermissionOwner: String\? = null/);
  // Claimed on request, released on result, cancel, and finish.
  assert.match(kt, /reminderPermissionOwner = requestId/);
  assert.match(kt, /if \(reminderPermissionOwner == requestId\)/);
});

test('android small icon is a monochrome vector, never the launcher bitmap', () => {
  const icon = join(ANDROID_SRC, 'res/drawable/ic_moonlit_beacon.xml');
  assert.ok(existsSync(icon), 'beacon small icon exists');
  const xml = read(icon);
  assert.match(xml, /<vector/);
  assert.doesNotMatch(xml, /@mipmap\//);
  assert.doesNotMatch(xml, /@drawable\/(?!ic_moonlit_beacon)/);
  // The standalone reminder library links with no app theme behind it,
  // so an app-theme tint (?attr/...) fails release AAPT while debug
  // stays green. The white silhouette stands alone; the system
  // notification presentation styles it.
  assert.doesNotMatch(xml, /\?attr\//);
  const fills = xml.match(/fillColor="([^"]+)"/g) ?? [];
  assert.ok(fills.length > 0, 'icon has filled paths');
  for (const fill of fills) {
    assert.equal(fill, 'fillColor="#FFFFFF"', 'white silhouette only');
  }
});

test('android channel strings exist in the default plus four locales', () => {
  for (const qualifier of ['', '-ko', '-ja', '-zh-rCN', '-zh-rTW']) {
    const strings = join(
      ANDROID_SRC,
      `res/values${qualifier}/strings.xml`,
    );
    assert.ok(existsSync(strings), `${qualifier || 'default'} strings exist`);
    const xml = read(strings);
    const name = xml.match(
      /<string name="moonlit_reminder_channel_name">([^<]+)<\/string>/,
    );
    const desc = xml.match(
      /<string name="moonlit_reminder_channel_desc">([^<]+)<\/string>/,
    );
    assert.ok(name && name[1].length > 0, `${qualifier} channel name`);
    assert.ok(desc && desc[1].length > 0, `${qualifier} channel text`);
  }
});

test('ios links UserNotifications and binds all seven reminder methods', () => {
  const mm = read(IOS_MM);
  assert.match(mm, /#import <UserNotifications\/UserNotifications\.h>/);
  const h = read(IOS_H);
  for (const method of REMINDER_METHODS) {
    assert.match(
      mm,
      new RegExp(`D_METHOD\\("${method}"`),
      `${method} is bound`,
    );
    assert.match(
      h,
      new RegExp(`godot::String ${method}\\(`),
      `${method} is declared`,
    );
  }
});

test('ios permission, diagnostics, and status settle asynchronously', () => {
  const mm = read(IOS_MM);
  assert.match(mm, /requestAuthorizationWithOptions/);
  assert.match(mm, /getPendingNotificationRequestsWithCompletionHandler/);
  assert.match(mm, /getNotificationSettingsWithCompletionHandler/);
  // A cached sync guess cannot converge an open panel after an OS
  // change: status claims its id and finishes with a fresh verdict.
  const status = mm.slice(
    mm.indexOf('- (NSString *)reminderStatus:'),
    mm.indexOf('- (NSString *)reminderRequestPermission:'),
  );
  assert.match(status, /beginRequest:requestId/);
  assert.match(status, /getNotificationSettingsWithCompletionHandler/);
  assert.match(status, /finishRequest:requestId outcome/);
  assert.match(status, /kStatusPending/);
  assert.doesNotMatch(status, /refreshReminderAuthStatus/);
});

test('ios cancels the owned horizon plus legacy ids, nothing else', () => {
  const mm = read(IOS_MM);
  assert.doesNotMatch(mm, /removeAllPendingNotificationRequests/);
  assert.doesNotMatch(mm, /removeAllDeliveredNotifications/);
  assert.match(mm, /reminderSlotIdentifiers/);
  assert.match(mm, /kReminderFirstId, kReminderRepeatId, kReminderDebugId/);
  assert.match(
    mm,
    /removePendingNotificationRequestsWithIdentifiers:owned/,
  );
  assert.match(
    mm,
    /removeDeliveredNotificationsWithIdentifiers:owned/,
  );
  assert.match(mm, /kReminderSlotPrefix =\n?\s*@"dev\.moonlitbeacon\.attendance\.slot-"/);
  assert.match(read(PLANNER_H), /kReminderHorizonSlots = 48/);
});

test('ios horizon carries no repeating attendance trigger', () => {
  const mm = read(IOS_MM);
  assert.doesNotMatch(mm, /repeats:YES/);
  assert.match(mm, /triggerWithTimeInterval:delay\s+repeats:NO/);
  assert.match(read(PLANNER_H), /kReminderRepeatMillis = 43200000LL/);
});

test('ios horizon loop plans future slots on the same anchor', () => {
  const mm = read(IOS_MM);
  // The first future position derives from the anchor and now, so a
  // refill past day 24 still plans a full window instead of an empty
  // fixed 0..47 pass. Integer milliseconds throughout: the equal-time
  // boundary must not depend on floating-point rounding.
  assert.match(mm, /#include "MoonlitReminderPlanner\.h"/);
  assert.match(
    mm,
    /firstFuture = MoonlitReminderFirstFuture\(\s*eligibleMillis, nowMillis\)/s,
  );
  assert.doesNotMatch(mm, /anchorSeconds/);
  assert.doesNotMatch(mm, /kReminderRepeatSeconds/);
  assert.match(mm, /pos < kReminderHorizonSlots; pos\+\+/);
  assert.match(mm, /long long slot = firstFuture \+ pos/);
  assert.match(
    mm,
    /fireMs = MoonlitReminderSlotFireMs\(\s*eligibleMillis, slot\)/s,
  );
  // Strictly elapsed stays out: a slot due exactly now schedules once
  // (the equal-time boundary holds 48), and the past never bursts.
  assert.match(mm, /if \(fireMs < nowMillis\) \{\s+[^}]*continue;/s);
  assert.match(mm, /stringByAppendingFormat:@"%02lld", pos/);
  // The planning loop keys identifiers by ordinal position, not by
  // absolute slot (the cancel helper still enumerates all ordinals).
  const schedule = mm.slice(
    mm.indexOf('- (NSString *)reminderSchedule:'),
    mm.indexOf('- (NSArray<NSString *> *)reminderSlotIdentifiers'),
  );
  assert.doesNotMatch(schedule, /stringByAppendingFormat:@"%02lld", slot/);
});

// The horizon plan is asserted structurally against the production
// Objective-C below, not against a JS reimplementation that could
// diverge: the old simulation tested its own copy and never reached
// an exhausted window.

test('ios refill only fires when the held window runs low', () => {
  const mm = read(IOS_MM);
  const planner = read(PLANNER_H);
  assert.match(planner, /kReminderMinFutureSlots = 8/);
  assert.match(
    planner,
    /\(firstFuture - recordedBase\) \+ kReminderMinFutureSlots\s*<= kReminderHorizonSlots/s,
  );
  const schedule = mm.slice(
    mm.indexOf('- (NSString *)reminderSchedule:'),
    mm.indexOf('- (NSArray<NSString *> *)reminderSlotIdentifiers'),
  );
  // The gate delegates to the numerically proven helper rather than
  // restating its arithmetic.
  assert.match(
    schedule,
    /MoonlitReminderWindowHolds\(recordedBase, firstFuture\)/,
  );
  assert.match(schedule, /@"duplicate" : @YES/);
  // The refill receipt carries the held window so the game side can
  // skip while it holds without a second implementation to diverge.
  assert.match(schedule, /@"base_slot" : @\(firstFuture\)/);
  assert.match(schedule, /@"horizon_end_unix" : @\(lastFire\)/);
  assert.match(schedule, /@"scheduled_slots" : @\(added\)/);
});

test('ios duplicate receipt carries the held window', () => {
  const mm = read(IOS_MM);
  const schedule = mm.slice(
    mm.indexOf('- (NSString *)reminderSchedule:'),
    mm.indexOf('- (NSArray<NSString *> *)reminderSlotIdentifiers'),
  );
  const duplicate = schedule.slice(
    schedule.indexOf('@"duplicate" : @YES'),
    schedule.indexOf('UNUserNotificationCenter *center'),
  );
  // A duplicate without metadata would make the game side record an
  // unknown zero and re-ask on every refresh.
  assert.match(duplicate, /@"base_slot" : @\(recordedBase\)/);
  assert.match(duplicate, /@"horizon_end_unix" : @\(recordedEnd\)/);
  assert.match(
    duplicate,
    /@"scheduled_slots" : @\(MoonlitReminderRemaining\(\s*recordedBase, firstFuture\)\)/s,
  );
});

test('ios persists the held window alongside the anchor', () => {
  const mm = read(IOS_MM);
  assert.match(mm, /dev\.moonlitbeacon\.reminder\.base_slot/);
  assert.match(mm, /dev\.moonlitbeacon\.reminder\.horizon_end/);
  assert.match(mm, /setObject:@\(firstFuture\) forKey:kReminderDefaultsBaseSlot/);
  assert.match(mm, /setDouble:lastFire forKey:kReminderDefaultsHorizonEnd/);
  const cancel = mm.slice(
    mm.indexOf('- (NSString *)reminderCancel:'),
    mm.indexOf('- (NSString *)reminderOpenSettings:'),
  );
  assert.match(cancel, /removeObjectForKey:kReminderDefaultsBaseSlot/);
  assert.match(cancel, /removeObjectForKey:kReminderDefaultsHorizonEnd/);
});

test('ios pending diagnostics report the held window end', () => {
  const mm = read(IOS_MM);
  const pending = mm.slice(
    mm.indexOf('- (NSString *)reminderPending:'),
    mm.indexOf('- (NSString *)reminderDebugSchedule:'),
  );
  assert.match(pending, /@"base_slot" : @\(base\)/);
  assert.match(pending, /@"horizon_end_unix" : @\(windowEnd\)/);
  assert.match(pending, /kReminderDefaultsHorizonEnd/);
});

test('cancel covers every planned slot plus legacy ids', () => {
  const mm = read(IOS_MM);
  const prefix = mm.match(/kReminderSlotPrefix =\n?\s*@"([^"]+)"/)[1];
  const cancelStart = mm.indexOf('- (NSString *)reminderCancel:');
  const cancelEnd = mm.indexOf('- (NSString *)reminderOpenSettings:');
  const cancel = mm.slice(cancelStart, cancelEnd);
  assert.ok(cancel.includes('reminderSlotIdentifiers'));
  assert.ok(cancel.includes('kReminderFirstId'));
  assert.ok(cancel.includes('kReminderRepeatId'));
  assert.ok(cancel.includes('kReminderDebugId'));
  assert.equal(prefix, 'dev.moonlitbeacon.attendance.slot-');
  const helperStart = mm.indexOf('- (NSArray<NSString *> *)reminderSlotIdentifiers');
  const helperEnd = mm.indexOf('- (NSString *)reminderCancel:');
  const helper = mm.slice(helperStart, helperEnd);
  assert.ok(helper.includes('kReminderSlotPrefix'));
  assert.ok(helper.includes('kReminderHorizonSlots'));
});

test('ios skips identical re-schedules without shifting the anchor', () => {
  const mm = read(IOS_MM);
  assert.match(mm, /@"duplicate" : @YES/);
  assert.match(mm, /recordedEligible == eligibleMillis/);
});

test('ios reminder storage stays inside its own defaults keys', () => {
  const mm = read(IOS_MM);
  assert.match(mm, /dev\.moonlitbeacon\.reminder\.account/);
  assert.match(mm, /dev\.moonlitbeacon\.reminder\.eligible_millis/);
  assert.match(mm, /dev\.moonlitbeacon\.reminder\.locale/);
  const keys = mm.match(/ForKey:(kReminderDefaults\w+|@"[^"]+")/g) ?? [];
  assert.ok(keys.length > 0, 'defaults keys are referenced');
  for (const key of keys) {
    assert.match(
      key,
      /kReminderDefaults/,
      `reminder-owned defaults key only: ${key}`,
    );
  }
});

test('ios persists the eligibility anchor through supported defaults types', () => {
  const mm = read(IOS_MM);
  // NSUserDefaults has no longLong accessors: full 64-bit millis ride an NSNumber.
  assert.doesNotMatch(mm, /longLongForKey/);
  assert.doesNotMatch(mm, /setLongLong/);
  assert.match(mm, /setObject:@\(eligibleMillis\)/);
  assert.match(mm, /longLongValue/);
  assert.match(mm, /isKindOfClass:\[NSNumber class\]\]/);
});

test('ios reads trigger dates only from concrete trigger types', () => {
  const mm = read(IOS_MM);
  // Base UNNotificationTrigger has no nextTriggerDate property.
  assert.doesNotMatch(mm, /request\.trigger\.nextTriggerDate/);
  assert.match(mm, /timed\.nextTriggerDate/);
  assert.match(
    mm,
    /\(\(UNCalendarNotificationTrigger \*\)trigger\)\s*\n?\s*\.nextTriggerDate/,
  );
});

test('ios guards the ephemeral grant behind its availability floor', () => {
  const mm = read(IOS_MM);
  // UNAuthorizationStatusEphemeral is iOS 14+; the target stays 13.
  assert.match(mm, /reminderAuthGrantsDelivery/);
  const helper = mm.slice(
    mm.indexOf('- (BOOL)reminderAuthGrantsDelivery'),
    mm.indexOf('- (NSString *)reminderPermissionName'),
  );
  assert.match(helper, /@available\(iOS 14\.0, \*\)/);
  assert.match(helper, /UNAuthorizationStatusEphemeral/);
  assert.doesNotMatch(helper, /UNAuthorizationStatusDenied/);
  const rest =
    mm.slice(0, mm.indexOf('- (BOOL)reminderAuthGrantsDelivery')) +
    mm.slice(mm.indexOf('- (NSString *)reminderPermissionName'));
  assert.doesNotMatch(rest, /UNAuthorizationStatusEphemeral/);
});

test('ios app privacy manifest declares its own UserDefaults reason', () => {
  assert.ok(existsSync(IOS_PRIVACY), 'app PrivacyInfo exists');
  const xml = read(IOS_PRIVACY);
  assert.match(xml, /NSPrivacyAccessedAPICategoryUserDefaults/);
  assert.match(xml, /<string>CA92\.1<\/string>/);
  assert.match(xml, /<key>NSPrivacyTracking<\/key>\s*<false\/>/);
});

// Observed Godot 4.7.1-stable generated iOS export: the engine's own
// app-root manifest, embedded verbatim (reasons before type in each
// entry, tracking last). The merger must not depend on key order.
const GODOT_GENERATED_PRIVACY = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>NSPrivacyAccessedAPITypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>
\t\t\t<array>
\t\t\t\t<string>DDA9.1</string>
\t\t\t\t<string>C617.1</string>
\t\t\t</array>
\t\t\t<key>NSPrivacyAccessedAPIType</key>
\t\t\t<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
\t\t</dict>
\t\t<dict>
\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>
\t\t\t<array>
\t\t\t\t<string>35F9.1</string>
\t\t\t</array>
\t\t\t<key>NSPrivacyAccessedAPIType</key>
\t\t\t<string>NSPrivacyAccessedAPICategorySystemBootTime</string>
\t\t</dict>
\t\t<dict>
\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>
\t\t\t<array>
\t\t\t\t<string>E174.1</string>
\t\t\t\t<string>85F4.1</string>
\t\t\t</array>
\t\t\t<key>NSPrivacyAccessedAPIType</key>
\t\t\t<string>NSPrivacyAccessedAPICategoryDiskSpace</string>
\t\t</dict>
\t</array>
\t<key>NSPrivacyTracking</key>
\t<false/>
</dict>
</plist>
`;

// The exact category block the merge appends for the app-owned
// declaration, in the generated file's own indentation.
const APP_PRIVACY_DICT_BLOCK = `\t\t<dict>
\t\t\t<key>NSPrivacyAccessedAPIType</key>
\t\t\t<string>${IDENTITY_APP_PRIVACY_API}</string>
\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>
\t\t\t<array>
\t\t\t\t<string>CA92.1</string>
\t\t\t</array>
\t\t</dict>
`;

// Observed registration lines, verbatim: the engine root reference plus
// its build file, and one real SDK bundle reference (bundles register
// whole, so their manifests never appear as file references). The last
// line is synthetic but plausible: a bundle-embedded manifest must never
// count as a root registration even if a template lists bundle contents.
const PBXPROJ_SINGLE_ROOT_MANIFEST = `\t\tF965960C2BC2C3A800579C7E /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };
\t\tF965960D2BC2C3A800579C7E /* PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = F965960C2BC2C3A800579C7E /* PrivacyInfo.xcprivacy */; };
589384010000000000000034 = {isa = PBXFileReference; lastKnownFileType = file; name = "FirebaseAuth_Privacy.bundle"; path = "MoonlitBeacon/addons/moonlit-identity/bin/ios/resources/debug/FirebaseAuth_Privacy.bundle"; sourceTree = "<group>"; };
SYNTHETICBUNDLE000000000001 = {isa = PBXFileReference; path = "MoonlitBeacon/FirebaseAuth_Privacy.bundle/PrivacyInfo.xcprivacy"; sourceTree = "<group>"; };
`;

// Observed loose addon registration (the pre-fix duplicate): a second
// root file reference with no `.bundle` in its path.
const PBXPROJ_LOOSE_ADDON_MANIFEST = `589384010000000000000044 = {isa = PBXFileReference; lastKnownFileType = file; name = "PrivacyInfo.xcprivacy"; path = "MoonlitBeacon/addons/moonlit-identity/ios/PrivacyInfo.xcprivacy"; sourceTree = "<group>"; };
`;

test('ios privacy merge keeps every engine reason and adds the app-owned one', () => {
  const merged = mergeAppPrivacyManifest({
    godotPlist: GODOT_GENERATED_PRIVACY,
    appPlist: read(IOS_PRIVACY),
  });
  const expected = GODOT_GENERATED_PRIVACY.replace(
    '\t</array>\n\t<key>NSPrivacyTracking</key>',
    `${APP_PRIVACY_DICT_BLOCK}\t</array>\n\t<key>NSPrivacyTracking</key>`,
  );
  assert.equal(merged, expected, 'merged bytes are exactly the insertion');
  // Every other byte survives: strip the one inserted block and the
  // generated file returns.
  assert.equal(
    merged.replace(APP_PRIVACY_DICT_BLOCK, ''),
    GODOT_GENERATED_PRIVACY,
    'engine bytes preserved verbatim',
  );
  const entries = new Map(
    privacyApiEntries(merged).map((entry) => [entry.type, entry.reasons]),
  );
  for (const [type, reasons] of Object.entries(GODOT_ENGINE_PRIVACY_REASONS)) {
    for (const reason of reasons) {
      assert.ok(
        (entries.get(type) ?? []).includes(reason),
        `engine reason survives: ${type} ${reason}`,
      );
    }
  }
  assert.deepEqual(
    entries.get(IDENTITY_APP_PRIVACY_API),
    ['CA92.1'],
    'app-owned UserDefaults declaration merged once',
  );
  assert.equal(privacyTrackingValue(merged), false, 'tracking retained');
});

test('ios privacy merge is idempotent', () => {
  const merged = mergeAppPrivacyManifest({
    godotPlist: GODOT_GENERATED_PRIVACY,
    appPlist: read(IOS_PRIVACY),
  });
  assert.equal(
    mergeAppPrivacyManifest({ godotPlist: merged, appPlist: read(IOS_PRIVACY) }),
    merged,
    'a merged manifest merges byte-identically',
  );
});

test('ios privacy merge appends to an existing UserDefaults category without duplicating it', () => {
  const futureGodot = GODOT_GENERATED_PRIVACY.replace(
    '\t</array>\n\t<key>NSPrivacyTracking</key>',
    `\t\t<dict>
\t\t\t<key>NSPrivacyAccessedAPIType</key>
\t\t\t<string>${IDENTITY_APP_PRIVACY_API}</string>
\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>
\t\t\t<array>
\t\t\t\t<string>FFFF.1</string>
\t\t\t</array>
\t\t</dict>
\t</array>\n\t<key>NSPrivacyTracking</key>`,
  );
  const merged = mergeAppPrivacyManifest({
    godotPlist: futureGodot,
    appPlist: read(IOS_PRIVACY),
  });
  const dicts = merged.match(
    new RegExp(`<string>${IDENTITY_APP_PRIVACY_API}</string>`, 'g'),
  ) ?? [];
  assert.equal(dicts.length, 1, 'exactly one UserDefaults category');
  const entries = new Map(
    privacyApiEntries(merged).map((entry) => [entry.type, entry.reasons]),
  );
  assert.deepEqual(
    entries.get(IDENTITY_APP_PRIVACY_API),
    ['FFFF.1', 'CA92.1'],
    'template reason kept, app reason appended',
  );
});

test('ios privacy merge refuses a generated manifest that lost an engine reason', () => {
  const dropped = GODOT_GENERATED_PRIVACY.replace('\t\t\t\t<string>C617.1</string>\n', '');
  assert.throws(
    () => mergeAppPrivacyManifest({ godotPlist: dropped, appPlist: read(IOS_PRIVACY) }),
    /lost engine reason C617\.1/,
  );
});

test('ios privacy merge refuses tracking disagreement and unexpected app categories', () => {
  const tracked = GODOT_GENERATED_PRIVACY.replace('<false/>', '<true/>');
  assert.throws(
    () => mergeAppPrivacyManifest({ godotPlist: tracked, appPlist: read(IOS_PRIVACY) }),
    /tracking states disagree/,
  );
  const extra = read(IOS_PRIVACY).replace(
    '\t</array>\n</dict>\n</plist>\n',
    `\t\t<dict>
\t\t\t<key>NSPrivacyAccessedAPIType</key>
\t\t\t<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>
\t\t\t<array>
\t\t\t\t<string>DDA9.1</string>
\t\t\t</array>
\t\t</dict>
\t</array>\n</dict>\n</plist>\n`,
  );
  assert.throws(
    () => mergeAppPrivacyManifest({ godotPlist: GODOT_GENERATED_PRIVACY, appPlist: extra }),
    /unexpected category NSPrivacyAccessedAPICategoryFileTimestamp/,
  );
  assert.throws(
    () => mergeAppPrivacyManifest({ godotPlist: 'not a plist', appPlist: read(IOS_PRIVACY) }),
    /NSPrivacyTracking value must appear exactly once/,
  );
});

test('ios export registers exactly one app-root privacy manifest', () => {
  const refs = rootPrivacyManifestFileReferences(PBXPROJ_SINGLE_ROOT_MANIFEST);
  assert.equal(refs.length, 1, 'one root file reference; bundle and build-file lines excluded');
  assert.equal(
    assertSingleRootPrivacyManifestRegistration(PBXPROJ_SINGLE_ROOT_MANIFEST),
    refs[0],
  );
  const duplicate = `${PBXPROJ_SINGLE_ROOT_MANIFEST}${PBXPROJ_LOOSE_ADDON_MANIFEST}`;
  assert.throws(
    () => assertSingleRootPrivacyManifestRegistration(duplicate),
    /exactly one app-root PrivacyInfo\.xcprivacy: found 2/,
  );
  assert.throws(
    () => assertSingleRootPrivacyManifestRegistration('/* empty project */\n'),
    /exactly one app-root PrivacyInfo\.xcprivacy: found 0/,
  );
});

test('ios privacy merge wrapper merges the generated export in place', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-privacy-merge-'));
  try {
    const scheme = 'MoonlitBeacon';
    // Observed export layout, specified literally (export root,
    // alongside the xcodeproj) rather than derived from the
    // implementation's path helper.
    const manifestPath = join(root, 'PrivacyInfo.xcprivacy');
    mkdirSync(join(root, `${scheme}.xcodeproj`), { recursive: true });
    writeFileSync(manifestPath, GODOT_GENERATED_PRIVACY, { encoding: 'utf8' });
    writeFileSync(
      join(root, `${scheme}.xcodeproj`, 'project.pbxproj'),
      PBXPROJ_SINGLE_ROOT_MANIFEST,
      { encoding: 'utf8' },
    );
    const first = mergeIdentityPrivacyManifestIntoGeneratedExport({
      projectDir: root,
      scheme,
      appManifestPath: IOS_PRIVACY,
    });
    assert.equal(first.merged, true, 'first run merges');
    assert.equal(first.manifestPath, manifestPath);
    assert.equal(first.tracking, false);
    const entries = new Map(
      privacyApiEntries(readFileSync(manifestPath, 'utf8'))
        .map((entry) => [entry.type, entry.reasons]),
    );
    assert.deepEqual(entries.get(IDENTITY_APP_PRIVACY_API), ['CA92.1']);
    const second = mergeIdentityPrivacyManifestIntoGeneratedExport({
      projectDir: root,
      scheme,
      appManifestPath: IOS_PRIVACY,
    });
    assert.equal(second.merged, false, 'second run is a no-op');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('ios privacy merge wrapper fails closed on a missing generated manifest', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-privacy-merge-'));
  try {
    assert.throws(
      () => mergeIdentityPrivacyManifestIntoGeneratedExport({
        projectDir: root,
        scheme: 'MoonlitBeacon',
        appManifestPath: IOS_PRIVACY,
      }),
      /generated app PrivacyInfo\.xcprivacy is missing/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('ios privacy merge wrapper ignores the obsolete nested manifest path', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-privacy-merge-'));
  try {
    const scheme = 'MoonlitBeacon';
    mkdirSync(join(root, scheme), { recursive: true });
    writeFileSync(
      join(root, scheme, 'PrivacyInfo.xcprivacy'),
      GODOT_GENERATED_PRIVACY,
      { encoding: 'utf8' },
    );
    // A nested-only layout must fail: restoring the obsolete nested
    // path as the merge target would silently return to the invented
    // layout instead of opening the real root engine file.
    assert.throws(
      () => mergeIdentityPrivacyManifestIntoGeneratedExport({
        projectDir: root,
        scheme,
        appManifestPath: IOS_PRIVACY,
      }),
      /generated app PrivacyInfo\.xcprivacy is missing.*not the engine manifest/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('ios privacy merge wrapper refuses root-plus-nested ambiguity', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-privacy-merge-'));
  try {
    const scheme = 'MoonlitBeacon';
    mkdirSync(join(root, scheme), { recursive: true });
    writeFileSync(
      join(root, 'PrivacyInfo.xcprivacy'),
      GODOT_GENERATED_PRIVACY,
      { encoding: 'utf8' },
    );
    writeFileSync(
      join(root, scheme, 'PrivacyInfo.xcprivacy'),
      GODOT_GENERATED_PRIVACY,
      { encoding: 'utf8' },
    );
    assert.throws(
      () => mergeIdentityPrivacyManifestIntoGeneratedExport({
        projectDir: root,
        scheme,
        appManifestPath: IOS_PRIVACY,
      }),
      /is ambiguous: both .*PrivacyInfo\.xcprivacy and .*PrivacyInfo\.xcprivacy exist/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('ios suppresses foreground presentation without stealing delegates', () => {
  const mm = read(IOS_MM);
  assert.match(mm, /willPresentNotification/);
  assert.match(
    mm,
    /completionHandler\(UNNotificationPresentationOptionNone\)/,
  );
  assert.match(mm, /if \(center\.delegate == nil\)/);
});

test('ios export links the framework and validates the app declaration source', () => {
  const manifest = read(EXPORT_MANIFEST_GD);
  assert.match(manifest, /"UserNotifications"/);
  assert.match(manifest, /app_privacy_manifest_ready/);
  assert.match(manifest, /NSPrivacyAccessedAPICategoryUserDefaults/);
  assert.match(manifest, /CA92\.1/);
  const plugin = read(EXPORT_PLUGIN_GD);
  assert.match(plugin, /_export_app_privacy_manifest\(\)/);
  // Godot 4.7.1 emits its own app-root manifest: a loose same-basename
  // registration fails Xcode with "Multiple commands produce", so the
  // plugin validates the merge source and the owned pipeline
  // (scripts/ios.mjs) merges it into Godot's generated file.
  const body = plugin.slice(
    plugin.indexOf('func _export_app_privacy_manifest'),
    plugin.indexOf('func _add_ios_project_static_lib'),
  );
  assert.doesNotMatch(body, /_add_ios_bundle_file/);
  assert.match(body, /scripts\/ios\.mjs/);
});

test('android render stages the owned resource tree with the code', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-reminder-'));
  try {
    const outDir = join(root, 'builds/moonlit-identity/android');
    renderAndroidPluginProject({ root: REPO_ROOT, outDir });
    const main = join(outDir, 'MoonlitIdentity/src/main');
    const icon = join(main, 'res/drawable/ic_moonlit_beacon.xml');
    assert.equal(existsSync(icon), true, 'staged beacon icon');
    assert.match(readFileSync(icon, 'utf8'), /<vector/);
    for (const qualifier of ['', '-ko', '-ja', '-zh-rCN', '-zh-rTW']) {
      const strings = join(main, `res/values${qualifier}/strings.xml`);
      assert.equal(existsSync(strings), true, `staged ${qualifier} strings`);
      assert.match(
        readFileSync(strings, 'utf8'),
        /moonlit_reminder_channel_name/,
      );
    }
    assert.equal(
      existsSync(join(
        main,
        'kotlin/dev/moonlitbeacon/identity/MoonlitReminderAlarm.kt',
      )),
      true,
      'staged alarm sources',
    );
    assert.match(
      readFileSync(join(main, 'AndroidManifest.xml'), 'utf8'),
      /MoonlitReminderReceiver/,
      'staged manifest declares the receiver',
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('every generated R reference resolves to a staged resource', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-reminder-'));
  try {
    const outDir = join(root, 'builds/moonlit-identity/android');
    renderAndroidPluginProject({ root: REPO_ROOT, outDir });
    const main = join(outDir, 'MoonlitIdentity/src/main');
    const kotlinDir = join(main, 'kotlin/dev/moonlitbeacon/identity');
    const refs = new Map();
    for (const file of ['MoonlitIdentityPlugin.kt', 'MoonlitReminderAlarm.kt']) {
      const body = readFileSync(join(kotlinDir, file), 'utf8');
      for (const match of body.matchAll(/R\.(drawable|string)\.(\w+)/g)) {
        refs.set(`${match[1]}/${match[2]}`, file);
      }
    }
    assert.ok(refs.size > 0, 'generated code references resources');
    for (const [ref, file] of refs) {
      const [kind, name] = ref.split('/');
      if (kind === 'drawable') {
        assert.equal(
          existsSync(join(main, `res/drawable/${name}.xml`)),
          true,
          `${file} drawable ${name} is staged`,
        );
      } else {
        const found = ['', '-ko', '-ja', '-zh-rCN', '-zh-rTW'].every(
          (qualifier) => {
            const strings = join(main, `res/values${qualifier}/strings.xml`);
            return existsSync(strings)
              && readFileSync(strings, 'utf8').includes(`name="${name}"`);
          },
        );
        assert.equal(found, true, `${file} string ${name} is staged × 5`);
      }
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('ios reminder methods live inside the worker implementation', () => {
  const mm = read(IOS_MM);
  const impl = mm.indexOf('@implementation MoonlitIdentityWorker');
  assert.ok(impl >= 0, 'worker implementation exists');
  const end = mm.indexOf('\n@end', impl);
  assert.ok(end > impl, 'worker implementation ends');
  const body = mm.slice(impl, end);
  for (const selector of [
    'reminderStatus:',
    'reminderRequestPermission:',
    'reminderSchedule:',
    'reminderCancel:',
    'reminderOpenSettings:',
    'reminderPending:',
    'reminderDebugSchedule:',
    'willPresentNotification:',
    'refreshReminderAuthStatus',
    'reminderPermissionName:',
    'reminderSlotIdentifiers',
  ]) {
    assert.ok(
      body.includes(selector),
      `${selector} is defined inside @implementation`,
    );
  }
  const tail = mm.slice(end);
  for (const method of REMINDER_METHODS) {
    assert.ok(
      tail.includes(`MoonlitIdentityIos::${method}`),
      `${method} forwarder follows the implementation`,
    );
  }
});

test('native pending diagnostics separate first delay from repeat', () => {
  const mm = read(IOS_MM);
  assert.match(mm, /@"identifier" : identifier/);
  assert.match(mm, /@"interval_seconds" : @\(interval\)/);
  assert.match(mm, /@"repeats" : @\(repeats\)/);
  assert.match(mm, /@"next_trigger_unix"/);
  const kt = read(PLUGIN_KT);
  // Token existence never stands in for an OS-held alarm: intent and
  // token read as separate honest fields.
  assert.doesNotMatch(kt, /"alarm_scheduled"/);
  assert.match(kt, /"schedule_intent_persisted"/);
  assert.match(kt, /"alarm_token_present"/);
  assert.match(kt, /eligible_millis", store\.getLong/);
});

test('bridge exposes reminders with no cloud gating', () => {
  const gd = read(BRIDGE_GD);
  for (const method of [
    'reminder_status',
    'reminder_request_permission',
    'reminder_schedule',
    'reminder_cancel',
    'reminder_open_settings',
    'reminder_pending_diagnostics',
    'reminder_debug_schedule',
  ]) {
    assert.match(
      gd,
      new RegExp(`func ${method}\\(`),
      `${method} exists on the bridge`,
    );
  }
  const reminderSection = gd.slice(
    gd.indexOf('## Local attendance reminders'),
    gd.indexOf('func cancel_request('),
  );
  assert.doesNotMatch(reminderSection, /_gate_firebase_ready/);
  assert.doesNotMatch(reminderSection, /_gate_provider_ready/);
  assert.match(gd, /or method == "moonlitReminderRequestPermission"/);
});
