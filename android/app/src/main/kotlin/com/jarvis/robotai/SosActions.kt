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

    /** Set volume media 0-100 persen. */
    fun setVolume(ctx: Context, pct: Int): String {
        return try {
            val am = ctx.getSystemService(Context.AUDIO_SERVICE)
                as android.media.AudioManager
            val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
            val v = ((pct.coerceIn(0, 100) * max) / 100).coerceIn(0, max)
            am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, v, 0)
            "Jarvis: volume diset $pct persen, Sir."
        } catch (e: Exception) {
            "Jarvis: gagal atur volume."
        }
    }

    /** Pasang alarm via intent jam sistem. Format: "07:30" atau menit-dari-sekarang "45". */
    fun setAlarm(ctx: Context, arg: String): String {
        return try {
            val cal = java.util.Calendar.getInstance()
            val a = arg.trim()
            if (a.contains(":")) {
                val p = a.split(":")
                if (p.size < 2) return "Jarvis: format salah. Contoh: ALARM 07:30"
                cal.set(java.util.Calendar.HOUR_OF_DAY, p[0].trim().toInt())
                cal.set(java.util.Calendar.MINUTE, p[1].trim().toInt())
                cal.set(java.util.Calendar.SECOND, 0)
                if (cal.timeInMillis <= System.currentTimeMillis()) {
                    cal.add(java.util.Calendar.DAY_OF_YEAR, 1)
                }
            } else {
                val mins = a.toIntOrNull() ?: return "Jarvis: format salah. Contoh: ALARM 45"
                cal.add(java.util.Calendar.MINUTE, mins)
            }
            val hh = cal.get(java.util.Calendar.HOUR_OF_DAY)
            val mm = cal.get(java.util.Calendar.MINUTE)
            // Coba 1: intent alarm standar (tanpa skip UI biar kompatibel).
            val i = android.content.Intent(android.provider.AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(android.provider.AlarmClock.EXTRA_HOUR, hh)
                putExtra(android.provider.AlarmClock.EXTRA_MINUTES, mm)
                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, "Alarm Jarvis")
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val pm = ctx.packageManager
            val canHandle = try {
                i.resolveActivity(pm) != null
            } catch (_: Exception) { false }
            if (!canHandle) {
                // Coba 2: buka aplikasi jam biasa.
                try {
                    val i2 = android.content.Intent(android.provider.AlarmClock.ACTION_SHOW_ALARMS).apply {
                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (i2.resolveActivity(pm) != null) {
                        ctx.startActivity(i2)
                        return "Jarvis: aplikasi jam dibuka, pasang manual jam %02d:%02d ya Sir.".format(hh, mm)
                    }
                } catch (_: Exception) {}
                return "Jarvis: HP ini tidak punya aplikasi alarm yang bisa dipasang otomatis."
            }
            ctx.startActivity(i)
            "Jarvis: alarm dipasang jam %02d:%02d, Sir.".format(hh, mm)
        } catch (e: Exception) {
            "Jarvis: gagal pasang alarm (${e.message})."
        }
    }

    /** Nyalakan/matikan senter. */
    fun setFlash(ctx: Context, on: Boolean): String {
        return try {
            val cm = ctx.getSystemService(Context.CAMERA_SERVICE)
                as android.hardware.camera2.CameraManager
            for (id in cm.cameraIdList) {
                val c = cm.getCameraCharacteristics(id)
                val hasFlash = c.get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
                if (hasFlash) {
                    cm.setTorchMode(id, on)
                    return if (on) "Jarvis: senter NYALA, Sir. 🔦"
                    else "Jarvis: senter mati, Sir."
                }
            }
            "Jarvis: HP ini tidak punya flash."
        } catch (e: Exception) {
            "Jarvis: gagal atur senter."
        }
    }

    /** Cari kontak lalu telpon. Return pesan status. */
    fun callContact(ctx: Context, name: String): String {
        return try {
            if (androidx.core.content.ContextCompat.checkSelfPermission(
                    ctx, android.Manifest.permission.READ_CONTACTS
                ) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                return "Jarvis: butuh izin kontak dulu, Sir."
            }
            if (androidx.core.content.ContextCompat.checkSelfPermission(
                    ctx, android.Manifest.permission.CALL_PHONE
                ) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                return "Jarvis: butuh izin telepon dulu, Sir."
            }
            val q = name.trim()
            if (q.length < 2) return "Jarvis: nama kontak terlalu pendek."
            // Nomor langsung?
            val digits = q.filter { it.isDigit() || it == '+' }
            var num: String? = null
            var label: String? = null
            if (digits.length >= 6 && digits.length >= q.length - 2) {
                num = digits; label = digits
            } else {
                val uri = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
                val proj = arrayOf(
                    android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                val col = android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " LIKE ?"
                ctx.contentResolver.query(uri, proj, col, arrayOf("%$q%"), null)?.use {
                    if (it.moveToFirst()) {
                        label = it.getString(0) ?: q
                        num = (it.getString(1) ?: "").filter { ch -> ch.isDigit() || ch == '+' }
                    }
                }
            }
            if (num.isNullOrBlank() || num!!.length < 6) {
                return "Jarvis: kontak \"$q\" tidak ketemu."
            }
            val i = android.content.Intent(android.content.Intent.ACTION_CALL).apply {
                data = android.net.Uri.parse("tel:$num")
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(i)
            "Jarvis: menelpon $label, Sir. 📞"
        } catch (e: Exception) {
            "Jarvis: gagal menelpon."
        }
    }
}
