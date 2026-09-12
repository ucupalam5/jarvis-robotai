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
        // 1) Cepat: lokasi terakhir yang masih segar (<30 menit).
        lastKnown(ctx)?.let { return formatLoc(it, false) }
        // 2) Minta fix baru sekali, tunggu maksimal 20 detik agar FIND
        //    jarak jauh "langsung" dapat titik, bukan pesan basi.
        val fresh = freshFix(ctx, 20000)
        if (fresh != null) return formatLoc(fresh, true)
        return "Jarvis: lokasi belum ada. Nyalakan GPS + buka Maps sekali ya Sir."
    }

    private data class Fix(val loc: android.location.Location, val fresh: Boolean)

    private fun lastKnown(ctx: Context): Fix? {
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
                    return null
                } catch (_: Exception) {}
            }
            val b = best ?: return null
            val ageMin = ((System.currentTimeMillis() - b.time) / 60000).toInt()
            if (ageMin > 30) null else Fix(b, false)
        } catch (_: Exception) {
            null
        }
    }

    private fun freshFix(ctx: Context, timeoutMs: Long): Fix? {
        return try {
            val lm = ctx.getSystemService(Context.LOCATION_SERVICE)
                as LocationManager
            val providers = ArrayList<String>()
            try {
                if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    providers.add(LocationManager.GPS_PROVIDER)
                }
            } catch (_: Exception) {}
            try {
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    providers.add(LocationManager.NETWORK_PROVIDER)
                }
            } catch (_: Exception) {}
            if (providers.isEmpty()) return null
            val latch = java.util.concurrent.CountDownLatch(1)
            var got: android.location.Location? = null
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                val cs = android.os.CancellationSignal()
                for (p in providers) {
                    try {
                        lm.getCurrentLocation(
                            p, cs,
                            ctx.mainExecutor,
                            java.util.function.Consumer { l ->
                                if (l != null && got == null) {
                                    got = l
                                    latch.countDown()
                                }
                            }
                        )
                    } catch (_: Exception) {}
                }
                latch.await(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
                try {
                    cs.cancel()
                } catch (_: Exception) {}
            } else {
                val listener = object : android.location.LocationListener {
                    override fun onLocationChanged(l: android.location.Location) {
                        got = l
                        latch.countDown()
                    }
                    override fun onStatusChanged(p: String?, s: Int, e: android.os.Bundle?) {}
                    override fun onProviderEnabled(p: String) {}
                    override fun onProviderDisabled(p: String) {}
                }
                for (p in providers) {
                    try {
                        @Suppress("DEPRECATION")
                        lm.requestSingleUpdate(p, listener, ctx.mainLooper)
                    } catch (_: Exception) {}
                }
                latch.await(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
                try {
                    lm.removeUpdates(listener)
                } catch (_: Exception) {}
            }
            val g = got ?: return null
            Fix(g, true)
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun formatLoc(f: Fix, fresh: Boolean): String {
        val b = f.loc
        val ageMin = ((System.currentTimeMillis() - b.time) / 60000).toInt()
        val age = if (fresh || ageMin < 1) "baru saja" else "$ageMin mnt lalu"
        return "Jarvis di sini Sir: https://maps.google.com/?q=${b.latitude},${b.longitude} (GPS, $age)"
    }
}
