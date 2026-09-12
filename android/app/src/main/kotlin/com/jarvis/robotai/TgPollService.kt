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
        return prefs().getString("tg_token", "")
            ?: prefs().getString("flutter.tg_token", "") ?: ""
    }

    private fun tgChat(): String {
        return prefs().getString("tg_chat", "")
            ?: prefs().getString("flutter.tg_chat", "") ?: ""
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
            .setContentText("Perintah Telegram: FIND / RING / LOCK.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
        if (pi != null) builder.setContentIntent(pi)
        val notif = builder.build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            )
        } else {
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

    private fun tgSend(token: String, chat: String, text: String) {
        try {
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
                "Jarvis online, Sir. Perintah: FIND / RING / LOCK / BATERAI / JAM."
            )
            else -> tgSend(
                token, chat,
                "Perintah tidak dikenal, Sir. Coba: FIND / RING / LOCK / BATERAI / JAM."
            )
        }
    }
}
