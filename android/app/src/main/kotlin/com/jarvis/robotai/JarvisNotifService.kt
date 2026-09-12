package com.jarvis.robotai

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.app.RemoteInput

/**
 * Telinga Jarvis: dengar notifikasi WA/Telegram/SMS/Email masuk.
 * - "ada pesan apa" -> baca terakhir (via NotifStore).
 * - "balas ..." -> balas via aksi Reply bawaan notif (tanpa buka app).
 * - Auto-bacakan (pref notif_read_auto) -> diucapkan langsung.
 * Syarat sekali: Settings > Notifications > Notification access > Jarvis ON.
 * Semua data hanya di HP (in-memory), tidak dikirim ke mana pun.
 */
object NotifStore {
    data class Msg(
        val key: String,
        val pkg: String,
        val sender: String,
        val text: String,
        val time: Long,
        val action: Notification.Action?,
        val remoteInput: RemoteInput?
    )

    @Volatile var latest: Msg? = null
        private set
    private val recent = ArrayDeque<Msg>()

    // Anti-berisik: satu notif yang sama hanya dibacakan 1x per 10 menit.
    @Volatile private var lastSpokenKey = ""
    @Volatile private var lastSpokenAt = 0L

    @Synchronized
    fun push(m: Msg) {
        latest = m
        recent.removeAll { it.key == m.key }
        recent.addFirst(m)
        while (recent.size > 10) recent.removeLast()
    }

    /** Hapus dari ingatan saat notif digeser/hilang (stop baca yang basi). */
    @Synchronized
    fun removeByKey(key: String) {
        recent.removeAll { it.key == key }
        if (latest?.key == key) latest = recent.firstOrNull()
    }

    /** true bila boleh dibacakan sekarang (bukan update berulang). */
    @Synchronized
    fun shouldSpeak(pkg: String, sender: String, text: String): Boolean {
        val key = "$pkg|$sender|$text"
        val now = System.currentTimeMillis()
        if (key == lastSpokenKey && now - lastSpokenAt < 10 * 60 * 1000) {
            return false
        }
        lastSpokenKey = key
        lastSpokenAt = now
        return true
    }

    @Synchronized
    fun findBySender(name: String): Msg? {
        val q = name.lowercase().trim()
        if (q.length < 2) return null
        val all = ArrayList<Msg>()
        latest?.let { all.add(it) }
        all.addAll(recent)
        return all.firstOrNull {
            it.sender.lowercase().contains(q) || q.contains(it.sender.lowercase())
        }
    }

    /** Balas via RemoteInput notif. target null = pesan terakhir. */
    fun replyTo(target: Msg?, text: String): String {
        val t = target ?: latest ?: return "Belum ada pesan masuk, Sir."
        val a = t.action ?: return "Pesan dari ${t.sender} tidak bisa dibalas otomatis."
        val ri = t.remoteInput ?: return "Tidak ada kolom balasnya, Sir."
        if (text.isBlank()) return "Mau balas apa, Sir?"
        return try {
            val intent = Intent()
            val bundle = Bundle()
            bundle.putCharSequence(ri.resultKey, text)
            RemoteInput.addResultsToIntent(arrayOf(ri), intent, bundle)
            a.actionIntent.send()
            "OK:${t.sender}"
        } catch (e: Exception) {
            "Gagal balas: ${e.message}"
        }
    }

    fun appName(pkg: String): String = when {
        pkg.contains("whatsapp") -> "WhatsApp"
        pkg.contains("telegram") -> "Telegram"
        pkg.contains("messaging") || pkg.contains("sms") -> "SMS"
        pkg.contains("gmail") -> "Gmail"
        pkg.contains("instagram") -> "Instagram"
        pkg.contains("facebook.orca") || pkg.contains("messenger") -> "Messenger"
        else -> "notifikasi"
    }
}

class JarvisNotifService : NotificationListenerService() {

    private var tts: android.speech.tts.TextToSpeech? = null

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            if (sbn.packageName == packageName) return
            if (sbn.isOngoing) return
            val n = sbn.notification ?: return
            if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
            val ex = n.extras ?: return
            val title = ex.getCharSequence(Notification.EXTRA_TITLE)
                ?.toString()?.trim() ?: ""
            val text = (ex.getCharSequence(Notification.EXTRA_TEXT)
                ?: ex.getCharSequence(Notification.EXTRA_BIG_TEXT))
                ?.toString()?.trim() ?: ""
            if (title.isEmpty() || text.isEmpty()) return
            var replyAction: Notification.Action? = null
            var ri: RemoteInput? = null
            for (a in n.actions ?: emptyArray()) {
                val ris = a.remoteInputs
                if (!ris.isNullOrEmpty()) {
                    replyAction = a
                    ri = ris[0]
                    break
                }
            }
            NotifStore.push(
                NotifStore.Msg(
                    sbn.key, sbn.packageName, title, text,
                    System.currentTimeMillis(), replyAction, ri
                )
            )
            val sp = getSharedPreferences(
                "FlutterSharedPreferences", MODE_PRIVATE
            )
            val auto = sp.getBoolean("notif_read_auto", false) ||
                sp.getBoolean("flutter.notif_read_auto", false)
            // Update kecil (progress dsb, ONLY_ALERT_ONCE) tidak dibacakan ulang.
            val quiet = n.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0
            if (auto && !quiet &&
                NotifStore.shouldSpeak(sbn.packageName, title, text)
            ) {
                val app = NotifStore.appName(sbn.packageName)
                val short = if (text.length > 200) text.take(200) + "…" else text
                speakNotif("Pesan $app dari $title: $short")
            }
        } catch (_: Exception) {}
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        try {
            // Notif digeser pengguna = anggap basi, jangan dibaca/dibalas lagi.
            NotifStore.removeByKey(sbn.key)
        } catch (_: Exception) {}
    }

    private fun ensureTts() {
        if (tts != null) return
        try {
            tts = android.speech.tts.TextToSpeech(this) { st ->
                if (st == android.speech.tts.TextToSpeech.SUCCESS) {
                    try {
                        val id = java.util.Locale("id", "ID")
                        tts?.language =
                            if (tts?.isLanguageAvailable(id) ?: 0 >= 0) id
                            else java.util.Locale.getDefault()
                        if (android.os.Build.VERSION.SDK_INT >= 21) {
                            tts?.setAudioAttributes(
                                android.media.AudioAttributes.Builder()
                                    .setUsage(android.media.AudioAttributes.USAGE_ASSISTANT)
                                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                                    .build()
                            )
                        }
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
    }

    private fun speakNotif(text: String) {
        try {
            ensureTts()
            tts?.speak(
                text, android.speech.tts.TextToSpeech.QUEUE_ADD, Bundle(), "notif"
            )
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        super.onDestroy()
    }
}
