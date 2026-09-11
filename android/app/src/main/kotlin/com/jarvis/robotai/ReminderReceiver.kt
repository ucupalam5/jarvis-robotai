package com.jarvis.robotai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import java.util.Locale

/**
 * Bunyi saat pengingat Jarvis jatuh tempo: notifikasi + suara.
 * Dijadwalkan via AlarmManager (setReminder di MainActivity).
 */
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(ctx: Context, intent: Intent) {
        val text = intent.getStringExtra("text") ?: "Waktunya, Sir."
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        "jarvis_reminder",
                        "Pengingat Jarvis",
                        NotificationManager.IMPORTANCE_HIGH
                    )
                )
            }
            val open = ctx.packageManager
                .getLaunchIntentForPackage(ctx.packageName)?.let {
                    android.app.PendingIntent.getActivity(
                        ctx, 0, it,
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                            android.app.PendingIntent.FLAG_IMMUTABLE
                    )
                }
            val notif = NotificationCompat.Builder(ctx, "jarvis_reminder")
                .setContentTitle("⏰ Pengingat Jarvis")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentIntent(open)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            nm.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notif)
        } catch (_: Exception) {}
        // Ucapkan juga (best-effort, butuh data suara offline bila offline).
        try {
            var tts: TextToSpeech? = null
            tts = TextToSpeech(ctx) { st ->
                try {
                    if (st == TextToSpeech.SUCCESS) {
                        val id = Locale("id", "ID")
                        tts?.language =
                            if ((tts?.isLanguageAvailable(id) ?: 0) >= 0) id
                            else Locale.getDefault()
                        tts?.speak("Pengingat Sir. $text", TextToSpeech.QUEUE_FLUSH, null, "rem")
                    }
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }
}
