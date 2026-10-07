package dev.moonlitbeacon.identity

import android.Manifest
import android.app.ActivityManager
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build

/**
 * SharedPreferences mirror of the reminder delivery this install asked
 * the OS to hold. The game keeps the authoritative intent in its own
 * settings; this mirror lets the alarm receiver and the boot receiver
 * enforce the opt-out and re-arm after reboot without waking Godot.
 */
object MoonlitReminderStore {
    const val PREFS = "moonlit_reminder"
    const val KEY_ENABLED = "enabled"
    const val KEY_ACCOUNT = "account"
    const val KEY_ELIGIBLE_MILLIS = "eligible_millis"
    const val KEY_TITLE = "title"
    const val KEY_BODY = "body"
    const val KEY_LOCALE = "locale"
    const val KEY_PERMISSION_ASKED = "permission_asked"
    const val KEY_RESUMED = "resumed"
    const val KEY_RESUMED_AT_MILLIS = "resumed_at_millis"
    const val KEY_LAUNCHED = "launched_from_reminder"

    fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }
}

/**
 * Battery-conscious twelve-hour attendance alarm. One inexact repeating
 * `RTC_WAKEUP` alarm (batched with the system's other alarms under Doze;
 * no exact-alarm privilege, no foreground service) plus a boot receiver
 * that re-arms it from the persisted mirror. Delivery re-checks the
 * persisted opt-out, the OS permission, the channel state, and whether
 * the game is foregrounded; reminders are for a player who is away, so
 * a foregrounded fire is skipped while the repeat cadence continues.
 *
 * All intents are explicit and immutable. The launch intent opens the
 * ordinary game entry with a `moonlit_reminder` extra the plugin reads
 * on resume; tapping never grants or spends anything by itself.
 */
object MoonlitReminderAlarm {
    const val ACTION_ALARM = "dev.moonlitbeacon.identity.REMINDER_ALARM"
    const val ACTION_DEBUG = "dev.moonlitbeacon.identity.REMINDER_DEBUG"
    const val CHANNEL_ID = "moonlit_attendance"
    const val NOTIFICATION_ID = 4102
    const val REPEAT_MILLIS = 43200000L
    const val REQUEST_ALARM = 4102
    const val REQUEST_DEBUG = 4103
    const val REQUEST_LAUNCH = 4104
    const val EXTRA_LAUNCHED = "moonlit_reminder"
    const val EXTRA_TITLE = "debug_title"
    const val EXTRA_BODY = "debug_body"

    /** A stuck resumed flag expires: a crash without `onPause` must not
     * silence reminders forever. */
    const val RESUMED_FRESH_MILLIS = 600000L

    /** Effective posting verdict: the app-global switch, the runtime
     * permission on 33+, and the attendance channel must all allow.
     * A bare POST_NOTIFICATIONS check is not enough on any version:
     * a global block or a closed channel refuses delivery the same
     * way a missing runtime permission does. */
    fun notificationsAllowed(context: Context): Boolean {
        if (!appNotificationsEnabled(context)) return false
        if (runtimePermissionMissing(context)) return false
        return channelOpen(context)
    }

    /** True only on 33+ while POST_NOTIFICATIONS is not granted. On
     * older versions no runtime permission exists to be missing. */
    fun runtimePermissionMissing(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        return context.checkSelfPermission(
            Manifest.permission.POST_NOTIFICATIONS
        ) != PackageManager.PERMISSION_GRANTED
    }

    /** The app-global notification switch. `areNotificationsEnabled`
     * starts at 24; below that the same reflective int-op check the
     * support library uses applies, with no new dependency: the op id
     * resolves by name at runtime because the string op constant is
     * not in this compile SDK. */
    fun appNotificationsEnabled(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 24) {
            val manager = context.getSystemService(
                Context.NOTIFICATION_SERVICE
            ) as NotificationManager
            return manager.areNotificationsEnabled()
        }
        return try {
            val ops = context.getSystemService(
                Context.APP_OPS_SERVICE
            ) as android.app.AppOpsManager
            val opsClass = Class.forName(ops.javaClass.name)
            val checkOp = opsClass.getMethod("checkOpNoThrow",
                Integer.TYPE, Integer.TYPE, String::class.java)
            val opField =
                opsClass.getDeclaredField("OP_POST_NOTIFICATION")
            val op = opField.getInt(null)
            val mode = checkOp.invoke(ops, op,
                android.os.Process.myUid(),
                context.packageName) as Int
            mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (error: Exception) {
            // An exotic ROM that cannot answer must not newly deny.
            true
        }
    }

    fun channelOpen(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 26) return true
        val manager = context.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager
        val channel = manager.getNotificationChannel(CHANNEL_ID)
            ?: return true
        return channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.moonlit_reminder_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT
        )
        channel.description = context.getString(
            R.string.moonlit_reminder_channel_desc
        )
        manager.createNotificationChannel(channel)
    }

    /** Next trigger on the anchor's twelve-hour grid at or after now:
     * a future anchor fires at itself, an overdue one at its next
     * future slot. A past trigger would fire its backlog immediately,
     * so callers never pass a raw overdue anchor to the alarm. */
    fun firstFutureTrigger(anchorMillis: Long, nowMillis: Long): Long {
        if (nowMillis <= anchorMillis) return anchorMillis
        val elapsed = nowMillis - anchorMillis
        val steps = (elapsed + REPEAT_MILLIS - 1) / REPEAT_MILLIS
        return anchorMillis + steps * REPEAT_MILLIS
    }

    fun schedule(context: Context, eligibleMillis: Long) {
        val alarms = context.getSystemService(
            Context.ALARM_SERVICE
        ) as AlarmManager
        alarms.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            firstFutureTrigger(
                eligibleMillis, System.currentTimeMillis()
            ),
            REPEAT_MILLIS,
            alarmIntent(context)
        )
    }

    fun scheduleDebug(context: Context, fireMillis: Long,
        title: String, body: String
    ) {
        val alarms = context.getSystemService(
            Context.ALARM_SERVICE
        ) as AlarmManager
        alarms.set(
            AlarmManager.RTC_WAKEUP,
            fireMillis,
            debugIntent(context, title, body)
        )
    }

    fun cancel(context: Context) {
        val alarms = context.getSystemService(
            Context.ALARM_SERVICE
        ) as AlarmManager
        cancelToken(alarms, context, ACTION_ALARM, REQUEST_ALARM)
        cancelToken(alarms, context, ACTION_DEBUG, REQUEST_DEBUG)
        val manager = context.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
    }

    /** Retire one delivery token without creating it: look it up with
     * NO_CREATE (extras never distinguish tokens) and, only when one
     * exists, drop its alarms and cancel the token itself so later
     * probes stop seeing it. */
    private fun cancelToken(alarms: AlarmManager, context: Context,
        action: String, requestCode: Int
    ) {
        val probe = Intent(
            context, MoonlitReminderReceiver::class.java
        ).setAction(action)
        val existing = PendingIntent.getBroadcast(
            context,
            requestCode,
            probe,
            PendingIntent.FLAG_NO_CREATE or
                PendingIntent.FLAG_IMMUTABLE
        ) ?: return
        alarms.cancel(existing)
        existing.cancel()
    }

    /** What this install asked the OS to hold, from the persisted
     * mirror. Intent, not an AlarmManager query: no public API
     * reports a held alarm. */
    fun scheduleIntentPersisted(context: Context): Boolean {
        val store = MoonlitReminderStore.prefs(context)
        return store.getBoolean(
            MoonlitReminderStore.KEY_ENABLED, false
        ) && store.getLong(
            MoonlitReminderStore.KEY_ELIGIBLE_MILLIS, 0L
        ) > 0L
    }

    /** Whether a matching alarm token exists right now. Token
     * existence only: scheduling, firing, and retiring all shape
     * the token table, so this never claims the OS holds an alarm. */
    fun alarmTokenPresent(context: Context): Boolean {
        val intent = Intent(context,
            MoonlitReminderReceiver::class.java).setAction(ACTION_ALARM)
        val existing = PendingIntent.getBroadcast(
            context,
            REQUEST_ALARM,
            intent,
            PendingIntent.FLAG_NO_CREATE or
                PendingIntent.FLAG_IMMUTABLE
        )
        return existing != null
    }

    fun deliver(context: Context, title: String, body: String) {
        ensureChannel(context)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_moonlit_beacon)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            launch.putExtra(EXTRA_LAUNCHED, true)
            launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            builder.setContentIntent(
                PendingIntent.getActivity(
                    context,
                    REQUEST_LAUNCH,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )
            )
        }
        val manager = context.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    /**
     * True when the game is genuinely foregrounded right now: either the
     * OS still ranks this process foreground, or the plugin recorded a
     * fresh resume. A stale resume record (crash without pause) never
     * suppresses on its own.
     */
    fun appForegrounded(context: Context): Boolean {
        val store = MoonlitReminderStore.prefs(context)
        if (store.getBoolean(MoonlitReminderStore.KEY_RESUMED, false)) {
            val at = store.getLong(
                MoonlitReminderStore.KEY_RESUMED_AT_MILLIS, 0L
            )
            if (System.currentTimeMillis() - at
                < RESUMED_FRESH_MILLIS
            ) {
                return true
            }
        }
        val manager = context.getSystemService(
            Context.ACTIVITY_SERVICE
        ) as ActivityManager
        val processes = manager.runningAppProcesses ?: return false
        val pid = android.os.Process.myPid()
        for (info in processes) {
            if (info.pid == pid) {
                return info.importance == ActivityManager
                    .RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            }
        }
        return false
    }

    private fun alarmIntent(context: Context): PendingIntent {
        val intent = Intent(
            context, MoonlitReminderReceiver::class.java
        ).setAction(ACTION_ALARM)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_ALARM,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun debugIntent(context: Context, title: String,
        body: String
    ): PendingIntent {
        val intent = Intent(
            context, MoonlitReminderReceiver::class.java
        ).setAction(ACTION_DEBUG)
        intent.putExtra(EXTRA_TITLE, title)
        intent.putExtra(EXTRA_BODY, body)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_DEBUG,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
        )
    }
}

/**
 * Alarm, debug, and boot receiver for attendance reminders. Every
 * delivery path re-checks the persisted opt-out, the OS permission, the
 * channel state, and the foreground state before posting.
 */
class MoonlitReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> onBoot(context)
            MoonlitReminderAlarm.ACTION_DEBUG -> onDebug(context, intent)
            else -> onAlarm(context)
        }
    }

    private fun onBoot(context: Context) {
        val store = MoonlitReminderStore.prefs(context)
        if (!store.getBoolean(MoonlitReminderStore.KEY_ENABLED, false)) {
            return
        }
        val eligible = store.getLong(
            MoonlitReminderStore.KEY_ELIGIBLE_MILLIS, 0L
        )
        if (eligible <= 0L) return
        // Raw anchor in: schedule() moves an overdue trigger onto the
        // anchor grid's next future slot instead of firing now.
        MoonlitReminderAlarm.schedule(context, eligible)
    }

    private fun onAlarm(context: Context) {
        val store = MoonlitReminderStore.prefs(context)
        if (!store.getBoolean(MoonlitReminderStore.KEY_ENABLED, false)) {
            return
        }
        if (!MoonlitReminderAlarm.notificationsAllowed(context)) return
        if (!MoonlitReminderAlarm.channelOpen(context)) return
        if (MoonlitReminderAlarm.appForegrounded(context)) return
        MoonlitReminderAlarm.deliver(
            context,
            store.getString(MoonlitReminderStore.KEY_TITLE, "")
                .orEmpty(),
            store.getString(MoonlitReminderStore.KEY_BODY, "")
                .orEmpty()
        )
    }

    private fun onDebug(context: Context, intent: Intent) {
        // QA path: same OS and foreground guards as production, but no
        // Settings intent or twelve-hour deadline is required.
        if (!MoonlitReminderAlarm.notificationsAllowed(context)) return
        if (!MoonlitReminderAlarm.channelOpen(context)) return
        if (MoonlitReminderAlarm.appForegrounded(context)) return
        MoonlitReminderAlarm.deliver(
            context,
            intent.getStringExtra(MoonlitReminderAlarm.EXTRA_TITLE)
                .orEmpty(),
            intent.getStringExtra(MoonlitReminderAlarm.EXTRA_BODY)
                .orEmpty()
        )
    }
}
