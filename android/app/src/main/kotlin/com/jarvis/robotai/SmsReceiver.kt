package com.jarvis.robotai

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SmsMessage

/**
 * Find-my-phone via SMS dari HP lain. Format:
 *   <KODE> RING  -> HP bunyi keras 30 detik (walau silent)
 *   <KODE> LOCK  -> kunci HP (butuh Device Admin)
 *   <KODE>       -> balas SMS berisi link lokasi GPS
 * Kode diatur di Settings Jarvis (default JARVIS123). JAGA RAHASIA.
 * Opsional: batasi pengirim lewat allowlist "Nomor tepercaya SOS" di
 * Settings (dipisah koma). Kalau diisi, SMS dari nomor lain diabaikan.
 * Butuh izin: RECEIVE_SMS + SEND_SMS (+ LOCATION untuk FIND).
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        try {
            val sp = ctx.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val code = ((sp.getString("sos_code", "JARVIS123")
                ?: sp.getString("flutter.sos_code", "JARVIS123")
                ?: "JARVIS123").trim().uppercase())
            if (code.length < 4) return
            @Suppress("DEPRECATION")
            val pdus = intent.extras?.get("pdus") as? Array<*> ?: return
            val format = intent.extras?.getString("format")
            var from = ""
            val body = StringBuilder()
            for (p in pdus) {
                @Suppress("DEPRECATION")
                val m = if (format != null) {
                    SmsMessage.createFromPdu(p as ByteArray, format)
                } else {
                    SmsMessage.createFromPdu(p as ByteArray)
                }
                if (from.isEmpty()) from = m.originatingAddress ?: ""
                body.append(m.messageBody)
            }
            if (from.isEmpty()) return
            val text = body.toString().trim()
            if (!text.uppercase().startsWith(code)) return
            // Allowlist nomor tepercaya (diset di Settings Jarvis, dipisah koma).
            // Kalau diisi, SMS dari nomor di luar daftar DIABAIKAN walau
            // kodenya benar. Kalau kosong, perilaku lama (siapa pun berkode).
            val trustedRaw = (sp.getString("sos_trusted", "")
                ?: sp.getString("flutter.sos_trusted", "") ?: "")
            val trusted = trustedRaw.split(",")
                .map { normPhone(it) }
                .filter { it.length >= 9 }
                .toSet()
            if (trusted.isNotEmpty() && normPhone(from) !in trusted) return
            val cmd = text.substring(code.length).trim().uppercase()
                .split(Regex("\\s+")).firstOrNull() ?: ""
            when (cmd) {
                "RING" -> {
                    SosActions.ringLoud(ctx)
                    replySms(ctx, from, "Jarvis: HP berbunyi sekarang, Sir.")
                }
                "LOCK" -> {
                    if (SosActions.lockNow(ctx)) {
                        replySms(ctx, from, "Jarvis: HP dikunci.")
                    } else {
                        replySms(ctx, from, "Jarvis: gagal kunci (Device Admin belum aktif).")
                    }
                }
                else -> replySms(ctx, from, SosActions.locateText(ctx))
            }
        } catch (_: Exception) {}
    }

    /**
     * Normalisasi nomor HP agar bisa dibandingkan:
     * buang non-digit, samakan format Indonesia 62xxxxxxxxxx -> 0xxxxxxxxxx.
     */
    private fun normPhone(p: String): String {
        var d = p.filter { it.isDigit() }
        if (d.startsWith("62")) d = "0" + d.substring(2)
        return d
    }

    private fun replySms(ctx: Context, to: String, msg: String) {        try {
            val sm = if (Build.VERSION.SDK_INT >= 31) {
                ctx.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = sm.divideMessage(msg)
            if (parts.size <= 1) {
                sm.sendTextMessage(to, null, msg, null, null)
            } else {
                sm.sendMultipartTextMessage(to, null, parts, null, null)
            }
        } catch (_: Exception) {}
    }

}
