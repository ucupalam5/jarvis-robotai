package com.jarvis.robotai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.util.Locale
import org.json.JSONObject

/**
 * Remote Telegram GRATIS (tanpa pulsa, modal internet).
 * Service mandiri: tetap jalan walau popup dimatikan.
 * Perintah (hanya dari chat id terdaftar): FIND / RING / LOCK / BATERAI / JAM.
 * Config di Settings Jarvis: token bot + Hubungkan.
 * Status terakhir ditulis ke prefs "tg_last_ok" (dibaca Settings).
 */
class TgPollService : Service() {

    companion object {
        @Volatile var running = false
            private set
        private const val NOTIF_ID = 1002
        private const val CHANNEL_ID = "jarvis_remote"
    }

    @Volatile private var polling = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        startFg()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (tgToken().isBlank() || tgChat().isBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }
        startPoll()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        polling = false
        super.onDestroy()
    }

    private fun prefs() =
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun tgToken(): String {
        val v1 = prefs().getString("tg_token", "")
        if (!v1.isNullOrBlank()) return v1
        return prefs().getString("flutter.tg_token", "") ?: ""
    }

    private fun tgChat(): String {
        val v1 = prefs().getString("tg_chat", "")
        if (!v1.isNullOrBlank()) return v1
        return prefs().getString("flutter.tg_chat", "") ?: ""
    }

    private fun markOk() {
        try {
            prefs().edit()
                .putLong("tg_last_ok", System.currentTimeMillis())
                .remove("tg_last_err").apply()
        } catch (_: Exception) {}
    }

    private fun markErr(e: String) {
        try {
            prefs().edit().putString("tg_last_err", e.take(90)).apply()
        } catch (_: Exception) {}
    }

    private fun startFg() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Jarvis remote", NotificationManager.IMPORTANCE_LOW)
            )
        }
        var pi: PendingIntent? = null
        try {
            packageManager.getLaunchIntentForPackage(packageName)?.let {
                pi = PendingIntent.getActivity(
                    this, 0, it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }
        } catch (_: Exception) {}
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Jarvis remote standby")
            .setContentText("Perintah Telegram: FIND / RING / LOCK / FLASH / CALL.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
        if (pi != null) builder.setContentIntent(pi)
        val notif = builder.build()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(
                    NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
                )
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIF_ID, notif)
            }
        } catch (_: Exception) {
            // Fallback: tanpa tipe khusus bila permission bermasalah.
            @Suppress("DEPRECATION")
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun startPoll() {
        if (polling) return
        polling = true
        Thread {
            var offset = tgSkipBacklog()
            while (polling && running) {
                try {
                    val token = tgToken()
                    val chat = tgChat()
                    if (token.isBlank() || chat.isBlank()) break
                    val updates = tgGetUpdates(token, offset)
                    markOk()
                    for ((id, fromChat, text) in updates) {
                        offset = maxOf(offset, id + 1)
                        if (fromChat == chat && text.isNotBlank()) {
                            tgHandle(token, chat, text.trim())
                        }
                    }
                } catch (e: Exception) {
                    markErr(e.message ?: "jaringan?")
                    try {
                        Thread.sleep(15000)
                    } catch (_: Exception) {}
                }
            }
            polling = false
        }.start()
    }

    /** Lewati pesan lama agar perintah basi tidak dijalankan. */
    private fun tgSkipBacklog(): Long {
        return try {
            val token = tgToken()
            if (token.isBlank()) return 0L
            val url = java.net.URL(
                "https://api.telegram.org/bot$token/getUpdates?timeout=0&limit=20"
            )
            val c = url.openConnection() as javax.net.ssl.HttpsURLConnection
            c.connectTimeout = 15000
            c.readTimeout = 15000
            val txt = c.inputStream.bufferedReader().use { it.readText() }
            val arr = JSONObject(txt).optJSONArray("result") ?: return 0L
            var maxId = 0L
            for (i in 0 until arr.length()) {
                val id = arr.getJSONObject(i).optLong("update_id", 0L)
                if (id > maxId) maxId = id
            }
            if (maxId > 0) maxId + 1 else 0L
        } catch (_: Exception) {
            0L
        }
    }

    private data class TgUpdate(val id: Long, val chat: String, val text: String)

    private fun tgGetUpdates(token: String, offset: Long): List<TgUpdate> {
        val out = ArrayList<TgUpdate>()
        val url = java.net.URL(
            "https://api.telegram.org/bot$token/getUpdates" +
                "?offset=$offset&timeout=25&allowed_updates=" +
                java.net.URLEncoder.encode("[\"message\"]", "UTF-8")
        )
        val c = url.openConnection() as javax.net.ssl.HttpsURLConnection
        c.connectTimeout = 15000
        c.readTimeout = 40000
        val txt = c.inputStream.bufferedReader().use { it.readText() }
        val arr = JSONObject(txt).optJSONArray("result") ?: return out
        for (i in 0 until arr.length()) {
            val u = arr.getJSONObject(i)
            val msg = u.optJSONObject("message") ?: continue
            val chat = msg.optJSONObject("chat")?.optLong("id")?.toString()
                ?: continue
            val text = msg.optString("text", "")
            out.add(TgUpdate(u.optLong("update_id", 0L), chat, text))
        }
        return out
    }

    /** Screenshot layar lalu kirim sebagai foto Telegram. */
    private fun tgShot(token: String, chat: String) {
        tgSend(token, chat, "Siap Sir, menangkap layar...")
        JarvisAccessibilityService.screenshot { r ->
            if (r.startsWith("ERR:")) {
                tgSend(token, chat, "Jarvis: ${r.removePrefix("ERR:")}")
                return@screenshot
            }
            Thread {
                try {
                    val bytes = java.io.File(r).readBytes()
                    if (bytes.size > 8 * 1024 * 1024) {
                        tgSend(token, chat, "Jarvis: gambar terlalu besar.")
                        return@Thread
                    }
                    val boundary = "Jarvis${System.currentTimeMillis()}"
                    val url = java.net.URL(
                        "https://api.telegram.org/bot$token/sendPhoto"
                    )
                    val c = url.openConnection()
                        as javax.net.ssl.HttpsURLConnection
                    c.requestMethod = "POST"
                    c.connectTimeout = 20000
                    c.readTimeout = 60000
                    c.doOutput = true
                    c.setRequestProperty(
                        "Content-Type", "multipart/form-data; boundary=$boundary"
                    )
                    c.outputStream.use { o ->
                        val w = o.bufferedWriter(Charsets.UTF_8)
                        w.write("--$boundary\r\n")
                        w.write(
                            "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n"
                        )
                        w.write("$chat\r\n")
                        w.write("--$boundary\r\n")
                        w.write(
                            "Content-Disposition: form-data; name=\"photo\"; " +
                                "filename=\"layar.jpg\"\r\n"
                        )
                        w.write("Content-Type: image/jpeg\r\n\r\n")
                        w.flush()
                        o.write(bytes)
                        o.flush()
                        w.write("\r\n--$boundary--\r\n")
                        w.flush()
                    }
                    val code = c.responseCode
                    c.inputStream.use { it.readBytes() }
                    if (code != 200) {
                        tgSend(token, chat, "Jarvis: kirim foto gagal ($code).")
                    }
                } catch (_: Exception) {
                    tgSend(token, chat, "Jarvis: kirim foto gagal.")
                }
            }.start()
        }
    }

    /** Foto via kamera (depan/belakang) lalu kirim ke Telegram. */
    private fun tgCamera(token: String, chat: String, front: Boolean) {
        tgSend(token, chat, "Siap Sir, memotret...")
        Thread {
            try {
                val cm = getSystemService(Context.CAMERA_SERVICE)
                    as android.hardware.camera2.CameraManager
                var camId: String? = null
                for (id in cm.cameraIdList) {
                    val c = cm.getCameraCharacteristics(id)
                    val lens = c.get(android.hardware.camera2.CameraCharacteristics.LENS_FACING)
                    if (front && lens == android.hardware.camera2.CameraCharacteristics.LENS_FACING_FRONT) { camId = id; break }
                    if (!front && lens == android.hardware.camera2.CameraCharacteristics.LENS_FACING_BACK) { camId = id; break }
                }
                if (camId == null) {
                    tgSend(token, chat, "Jarvis: kamera tidak ketemu.")
                    return@Thread
                }
                val reader = android.media.ImageReader.newInstance(1280, 720,
                    android.graphics.ImageFormat.JPEG, 1)
                val latch = java.util.concurrent.CountDownLatch(1)
                var jpg: ByteArray? = null
                reader.setOnImageAvailableListener({ r ->
                    try {
                        val img = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                        val buf = img.planes[0].buffer
                        val b = ByteArray(buf.remaining())
                        buf.get(b)
                        img.close()
                        jpg = b
                    } catch (_: Exception) {}
                    latch.countDown()
                }, android.os.Handler(android.os.Looper.getMainLooper()))
                val hthread = android.os.HandlerThread("tgcam")
                hthread.start()
                val hhandler = android.os.Handler(hthread.looper)
                var session: android.hardware.camera2.CameraCaptureSession? = null
                try {
                    if (checkSelfPermission(android.Manifest.permission.CAMERA)
                        != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        tgSend(token, chat, "Jarvis: izin kamera belum diberikan.")
                        return@Thread
                    }
                    val clatch = java.util.concurrent.CountDownLatch(1)
                    var device: android.hardware.camera2.CameraDevice? = null
                    @Suppress("MissingPermission")
                    cm.openCamera(camId, object : android.hardware.camera2.CameraDevice.StateCallback() {
                        override fun onOpened(d: android.hardware.camera2.CameraDevice) { device = d; clatch.countDown() }
                        override fun onDisconnected(d: android.hardware.camera2.CameraDevice) { clatch.countDown() }
                        override fun onError(d: android.hardware.camera2.CameraDevice, e: Int) { clatch.countDown() }
                    }, hhandler)
                    clatch.await(10, java.util.concurrent.TimeUnit.SECONDS)
                    val dev = device
                    if (dev == null) {
                        tgSend(token, chat, "Jarvis: gagal buka kamera.")
                        return@Thread
                    }
                    val slatch = java.util.concurrent.CountDownLatch(1)
                    dev.createCaptureSession(listOf(reader.surface),
                        object : android.hardware.camera2.CameraCaptureSession.StateCallback() {
                            override fun onConfigured(s: android.hardware.camera2.CameraCaptureSession) { session = s; slatch.countDown() }
                            override fun onConfigureFailed(s: android.hardware.camera2.CameraCaptureSession) { slatch.countDown() }
                        }, hhandler)
                    slatch.await(10, java.util.concurrent.TimeUnit.SECONDS)
                    val sess = session
                    if (sess == null) {
                        tgSend(token, chat, "Jarvis: gagal siapkan kamera.")
                        try { dev.close() } catch (_: Exception) {}
                        return@Thread
                    }
                    val req = dev.createCaptureRequest(
                        android.hardware.camera2.CameraDevice.TEMPLATE_STILL_CAPTURE)
                    req.addTarget(reader.surface)
                    sess.capture(req.build(), null, hhandler)
                    latch.await(15, java.util.concurrent.TimeUnit.SECONDS)
                    try { sess.close() } catch (_: Exception) {}
                    try { dev.close() } catch (_: Exception) {}
                } catch (e: Exception) {
                    tgSend(token, chat, "Jarvis: kamera error.")
                }
                try { hthread.quitSafely() } catch (_: Exception) {}
                try { reader.close() } catch (_: Exception) {}
                val bytes = jpg
                if (bytes == null) {
                    tgSend(token, chat, "Jarvis: gagal ambil foto.")
                    return@Thread
                }
                // Kirim sebagai foto Telegram (pakai jalur yang sama dgn tgShot).
                val boundary = "Jarvis${System.currentTimeMillis()}"
                val url = java.net.URL("https://api.telegram.org/bot$token/sendPhoto")
                val c = url.openConnection() as javax.net.ssl.HttpsURLConnection
                c.requestMethod = "POST"
                c.connectTimeout = 20000
                c.readTimeout = 60000
                c.doOutput = true
                c.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                c.outputStream.use { o ->
                    val w = o.bufferedWriter(Charsets.UTF_8)
                    w.write("--$boundary\r\n")
                    w.write("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n")
                    w.write("$chat\r\n")
                    w.write("--$boundary\r\n")
                    w.write("Content-Disposition: form-data; name=\"photo\"; filename=\"kamera.jpg\"\r\n")
                    w.write("Content-Type: image/jpeg\r\n\r\n")
                    w.flush()
                    o.write(bytes)
                    o.flush()
                    w.write("\r\n--$boundary--\r\n")
                    w.flush()
                }
                val code = c.responseCode
                c.inputStream.use { it.readBytes() }
                if (code != 200) tgSend(token, chat, "Jarvis: kirim foto gagal ($code).")
            } catch (e: Exception) {
                tgSend(token, chat, "Jarvis: kamera gagal.")
            }
        }.start()
    }

    private fun tgSend(token: String, chat: String, text: String) {        try {
            val url = java.net.URL(
                "https://api.telegram.org/bot$token/sendMessage"
            )
            val c = url.openConnection() as javax.net.ssl.HttpsURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 15000
            c.readTimeout = 15000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json")
            val body = JSONObject()
                .put("chat_id", chat)
                .put("text", text.take(3500)).toString()
            c.outputStream.use { it.write(body.toByteArray()) }
            c.inputStream.use { it.readBytes() }
        } catch (_: Exception) {}
    }

    private fun tgHandle(token: String, chat: String, raw: String) {
        val cmd = raw.trim().uppercase().split(Regex("\\s+")).firstOrNull() ?: ""
        when (cmd.trimStart('/')) {
            "FIND", "LOKASI", "DIMANA" -> tgSend(token, chat, SosActions.locateText(this))
            "RING", "BUNYI" -> {
                SosActions.ringLoud(this)
                tgSend(token, chat, "Jarvis: HP berbunyi sekarang, Sir.")
            }
            "LOCK", "KUNCI" -> {
                if (SosActions.lockNow(this)) {
                    tgSend(token, chat, "Jarvis: HP dikunci.")
                } else {
                    tgSend(token, chat, "Jarvis: gagal kunci (Device Admin belum aktif).")
                }
            }
            "BATERAI", "BATTERY" -> {
                try {
                    val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    tgSend(token, chat, "Jarvis: baterai $pct persen, Sir.")
                } catch (_: Exception) {}
            }
            "JAM", "TIME" -> {
                val f = java.text.SimpleDateFormat("EEEE, d MMMM yyyy HH:mm", Locale("id", "ID"))
                tgSend(token, chat, "Jarvis: ${f.format(java.util.Date())}")
            }
            "STATUS", "START", "HALO", "HAI", "PING" -> tgSend(
                token, chat,
                "Jarvis online, Sir. Perintah: FIND / RING / LOCK / SHOT / KAMERA / FLASH / CALL / VOLUME / ALARM / BATERAI / JAM."
            )
            "SHOT", "FOTO", "SCREENSHOT", "SS" -> tgShot(token, chat)
            "KAMERA", "CAMERA", "CAM" -> {
                val arg = raw.trim().split(Regex("\\s+")).drop(1).firstOrNull()?.uppercase() ?: ""
                tgCamera(token, chat, arg == "DEPAN" || arg == "FRONT")
            }
            "VOLUME", "VOL" -> {
                val arg = raw.trim().split(Regex("\\s+")).drop(1).firstOrNull() ?: "80"
                val pct = arg.toIntOrNull() ?: 80
                tgSend(token, chat, SosActions.setVolume(this, pct))
            }
            "FLASH", "SENTER", "TORCH" -> {
                val arg = raw.trim().split(Regex("\\s+")).drop(1).firstOrNull()?.uppercase() ?: "ON"
                tgSend(token, chat, SosActions.setFlash(this, arg != "OFF" && arg != "MATI"))
            }
            "CALL", "TELPON", "TELEPON", "NELPON" -> {
                val arg = raw.trim().split(Regex("\\s+")).drop(1).joinToString(" ")
                if (arg.isBlank()) {
                    tgSend(token, chat, "Format: CALL <nama kontak / nomor>. Contoh: CALL mama")
                } else {
                    tgSend(token, chat, SosActions.callContact(this, arg))
                }
            }
            "ALARM" -> {
                val arg = raw.trim().split(Regex("\\s+")).drop(1).firstOrNull() ?: ""
                if (arg.isBlank()) {
                    tgSend(token, chat, "Format: ALARM 07:30 atau ALARM 45 (menit dari sekarang).")
                } else {
                    tgSend(token, chat, SosActions.setAlarm(this, arg))
                }
            }
            else -> tgSend(
                token, chat,
                "Perintah tidak dikenal, Sir. Coba: FIND / RING / LOCK / SHOT / KAMERA / FLASH / CALL / VOLUME / ALARM / BATERAI / JAM."
            )
        }
    }
}
