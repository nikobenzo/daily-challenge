package app.dailychallenge.android

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.dailychallenge.android.widget.ChallengeWidgets
import app.dailychallenge.core.ChallengeTime
import app.dailychallenge.core.KeyValueStore
import app.dailychallenge.core.NotificationPermission
import app.dailychallenge.core.ReminderScheduler
import app.dailychallenge.core.SessionStore
import app.dailychallenge.core.WaterReminderController
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.security.KeyStore
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device-local preferences (appearance, reminder settings). Never synced, never backed up. */
class SharedPrefsStore(context: Context, name: String = "device") : KeyValueStore {
    private val prefs = context.getSharedPreferences(name, Context.MODE_PRIVATE)
    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun putString(key: String, value: String?) { prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply() }
}

/**
 * The auth session, encrypted with an AES-GCM key that lives in the Android Keystore and
 * never leaves it. Only tokens are stored, never a password; nothing is logged. A file that
 * cannot be decrypted (a restored device, a removed key) is treated as signed out.
 */
class KeystoreSessionStore(context: Context, name: String) : SessionStore {
    private val file = File(context.noBackupFilesDir, "$name.session")
    private val alias = "daily-challenge-session"

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build())
        return generator.generateKey()
    }

    override fun load(): String? {
        if (!file.exists()) return null
        return try {
            val bytes = file.readBytes()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 1, bytes[0].toInt()))
            String(cipher.doFinal(bytes, 1 + bytes[0], bytes.size - 1 - bytes[0]), Charsets.UTF_8)
        } catch (_: Exception) {
            file.delete()
            null
        }
    }

    override fun save(value: String?) {
        if (value == null) {
            file.delete()
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = cipher.iv
        val sealed = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeBytes(byteArrayOf(iv.size.toByte()) + iv + sealed)
        if (!temporary.renameTo(file)) {
            temporary.delete()
            throw java.io.IOException("Could not save the session")
        }
    }
}

/**
 * Water reminders as inexact alarms that may run while idle, one per queued slot (at most
 * [WaterReminderController.QUEUED_LIMIT]); each posts a notification. No exact-alarm
 * permission is needed: a reminder can arrive a few minutes late, never early.
 */
class AlarmReminderScheduler(private val context: Context, private val prefs: KeyValueStore) : ReminderScheduler {
    private val alarms = context.getSystemService(AlarmManager::class.java)

    override fun permission(): NotificationPermission {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            return if (Build.VERSION.SDK_INT >= 33 && prefs.getString(ASKED_KEY) == null) NotificationPermission.NOT_DETERMINED
            else NotificationPermission.DENIED
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return if (prefs.getString(ASKED_KEY) == null) NotificationPermission.NOT_DETERMINED else NotificationPermission.DENIED
        return NotificationPermission.ALLOWED
    }

    override fun replace(dates: List<Double>, zone: ZoneId) {
        cancel()
        dates.take(WaterReminderController.QUEUED_LIMIT).forEachIndexed { index, date ->
            val millis = (ChallengeTime.toUnix(date) * 1000).toLong()
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pending(index, PendingIntent.FLAG_UPDATE_CURRENT)!!)
        }
    }

    override fun cancel() {
        for (index in 0 until WaterReminderController.QUEUED_LIMIT) {
            pending(index, PendingIntent.FLAG_NO_CREATE)?.let { alarms.cancel(it); it.cancel() }
        }
    }

    private fun pending(index: Int, flags: Int): PendingIntent? = PendingIntent.getBroadcast(
        context, index, Intent(context, ReminderReceiver::class.java).setAction(ACTION),
        flags or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        const val ACTION = "app.dailychallenge.android.WATER_REMINDER"
        const val CHANNEL = "water-reminders"
        /** Set once the person has been asked for notification permission (Android 13+). */
        const val ASKED_KEY = "notifications-asked"

        fun createChannel(context: Context) {
            val channel = NotificationChannel(CHANNEL, context.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_DEFAULT)
            channel.description = context.getString(R.string.reminder_channel_description)
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}

/** Posts one water check-in. The words are the Apple apps' own. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmReminderScheduler.ACTION) return
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        AlarmReminderScheduler.createChannel(context)
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, AlarmReminderScheduler.CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Water check-in")
            // No number: check-ins are queued ahead, and the day's goal may change before one arrives.
            .setContentText("Time for some water. Drink only what you still need toward today's goal.")
            .setStyle(NotificationCompat.BigTextStyle().bigText("Time for some water. Drink only what you still need toward today's goal."))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Permission was withdrawn after the alarm was set.
        }
    }

    companion object {
        const val NOTIFICATION_ID = 4_000
    }
}

/** Alarms do not survive a restart or an update; plan the remaining reminders again. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Only the system's broadcasts re-plan reminders; anything else is ignored.
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIMEZONE_CHANGED)) return
        val graph = (context.applicationContext as DailyChallengeApp).graph
        graph.tracker.reload()
        graph.tracker.refreshReminders()
        ChallengeWidgets.requestRefresh(context)
    }
}

/**
 * Background sync while the app is closed, at times Android chooses (at most every 30
 * minutes, with a network): other devices' entries arrive and reminders are re-planned,
 * as the iPhone's background refresh does.
 */
class SyncWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val graph = (applicationContext as DailyChallengeApp).graph
        withContext(Dispatchers.Main) { graph.backgroundRefresh() }
        return Result.success()
    }

    companion object {
        private const val NAME = "challenge-sync"

        fun schedule(context: Context, signedIn: Boolean) {
            val work = WorkManager.getInstance(context)
            if (!signedIn) {
                work.cancelUniqueWork(NAME)
                return
            }
            val request = PeriodicWorkRequestBuilder<SyncWorker>(30, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            work.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        /**
         * After a widget tap: one run of this same app sync once there is a network, a few
         * seconds later so quick taps share it. The widget itself never networks.
         */
        fun requestSoon(context: Context) {
            val request = OneTimeWorkRequestBuilder<SyncWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setInitialDelay(5, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(SOON, ExistingWorkPolicy.REPLACE, request)
        }

        private const val SOON = "challenge-sync-soon"
    }
}
