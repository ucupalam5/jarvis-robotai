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
 * Butuh izin: RECEIVE_SMS + SEND_SMS (+ LOCATION untuk FIND).
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Telephony.SmsIntents.SMS_RECEIVED_ACTION) return
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
            val cmd = text.substring(code.length).trim().uppercase()
                .split(Regex("\\s+")).firstOrNull() ?: ""
            when (cmd) {
                "RING" -> {
                    ringLoud(ctx)
                    replySms(ctx, from, "Jarvis: HP berbunyi sekarang, Sir.")
                }
                "LOCK" -> {
                    lockNow(ctx)
                    replySms(ctx, from, "Jarvis: HP dikunci.")
                }
                else -> replySms(ctx, from, findText(ctx))
            }
        } catch (_: Exception) {}
    }

    private fun replySms(ctx: Context, to: String, msg: String) {
        try {
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

    private fun ringLoud(ctx: Context) {
        try {
            val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.ringerMode = AudioManager.RINGER_MODE_NORMAL
            am.setStreamVolume(
                AudioManager.STREAM_ALARM,
                am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0
            )
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: return
            val ring = RingtoneManager.getRingtone(ctx, uri) ?: return
            ring.streamType = AudioManager.STREAM_ALARM
            ring.play()
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    ring.stop()
                } catch (_: Exception) {}
            }, 30000)
        } catch (_: Exception) {}
    }

    private fun lockNow(ctx: Context) {
        try {
            val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE)
                as DevicePolicyManager
            val admin = ComponentName(ctx, AdminReceiver::class.java)
            if (dpm.isAdminActive(admin)) dpm.lockNow()
        } catch (_: Exception) {}
    }

    private fun findText(ctx: Context): String {
        try {
            val lm = ctx.getSystemService(Context.LOCATION_SERVICE)
                as LocationManager
            var best: android.location.Location? = null
            for (p in listOf(
                LocationManager.GPS_PROVIDER,
                LocationManager.NETWORK_PROVIDER
            )) {
                try {
                    val l = lm.getLastKnownLocation(p) ?: continue
                    if (best == null || (l.time > best.time)) best = l
                } catch (_: SecurityException) {
                    return "Jarvis: butuh izin lokasi. Aktifkan: Settings HP > Apps > JARVIS > Permissions > Location."
                } catch (_: Exception) {}
            }
            val b = best ?: return "Jarvis: lokasi belum ada. Nyalakan GPS + buka Maps sekali ya Sir."
            val ageMin = ((System.currentTimeMillis() - b.time) / 60000).toInt()
            val age = if (ageMin < 1) "baru saja" else "$ageMin mnt lalu"
            return "Jarvis di sini Sir: https://maps.google.com/?q=${b.latitude},${b.longitude} (GPS, $age)"
        } catch (_: Exception) {
            return "Jarvis: gagal baca lokasi."
        }
    }
}
