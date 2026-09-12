package com.jarvis.robotai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Sehabis HP reboot, nyalakan lagi remote Telegram bila dikonfigurasi.
 * (Service tidak hidup sendiri setelah reboot tanpa ini.)
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        try {
            val sp = ctx.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val token = sp.getString("tg_token", "")
                ?: sp.getString("flutter.tg_token", "") ?: ""
            val chat = sp.getString("tg_chat", "")
                ?: sp.getString("flutter.tg_chat", "") ?: ""
            if (token.isBlank() || chat.isBlank()) return
            ContextCompat.startForegroundService(
                ctx, Intent(ctx, TgPollService::class.java)
            )
        } catch (_: Exception) {}
    }
}
