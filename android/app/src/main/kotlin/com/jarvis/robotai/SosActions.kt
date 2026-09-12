package com.jarvis.robotai

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.location.LocationManager
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper

/**
 * Aksi darurat dipakai SMS find-my-phone DAN remote Telegram.
 * - RING: bunyi keras 30 detik walau silent.
 * - LOCK: kunci HP (butuh Device Admin).
 * - FIND: teks link lokasi GPS terakhir.
 */
object SosActions {

    fun ringLoud(ctx: Context) {
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
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    ring.stop()
                } catch (_: Exception) {}
            }, 30000)
        } catch (_: Exception) {}
    }

    fun lockNow(ctx: Context): Boolean {
        return try {
            val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE)
                as DevicePolicyManager
            val admin = ComponentName(ctx, AdminReceiver::class.java)
            if (dpm.isAdminActive(admin)) {
                dpm.lockNow()
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    fun locateText(ctx: Context): String {
        return try {
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
            val b = best
                ?: return "Jarvis: lokasi belum ada. Nyalakan GPS + buka Maps sekali ya Sir."
            val ageMin = ((System.currentTimeMillis() - b.time) / 60000).toInt()
            val age = if (ageMin < 1) "baru saja" else "$ageMin mnt lalu"
            "Jarvis di sini Sir: https://maps.google.com/?q=${b.latitude},${b.longitude} (GPS, $age)"
        } catch (_: Exception) {
            "Jarvis: gagal baca lokasi."
        }
    }
}
