package com.jarvis.robotai

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.util.Locale
import org.json.JSONObject

/**
 * Popup robot Jarvis MELAYANG di atas aplikasi lain (native, tanpa plugin).
 * Ikon/warna/teks/gambar dibaca dari SharedPreferences Flutter
 * (file "FlutterSharedPreferences") setiap service di-start ulang,
 * jadi ganti setting = restart service = tampilan baru.
 */
class JarvisOverlayService : Service() {

    companion object {
        @Volatile var running = false
            private set
        private const val NOTIF_ID = 1001
        private const val CHANNEL_ID = "jarvis_overlay"
    }

    private var wm: WindowManager? = null
    private var root: View? = null
    private var subtitleView: TextView? = null
    private var lastX = 0
    private var lastY = 120

    // --- Auto-dengar: recognizer + TTS hidup di service, tanpa tap ---
    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var autoListen = false
    private var sessionActive = false
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        startFg()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        rebuildOverlay()
        val wantAuto = prefs().getBoolean("popup_autolisten", false) ||
            prefs().getBoolean("flutter.popup_autolisten", false)
        if (wantAuto) startAutoListen() else stopAutoListen()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        stopAutoListen()
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        removeOverlay()
        super.onDestroy()
    }

    private fun prefs() =
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /** Baca key dengan fallback prefix "flutter." (jaga-jaga beda versi plugin). */
    private fun pref(key: String, def: String): String {
        val p = prefs()
        p.getString(key, null)?.let { return it }
        p.getString("flutter.$key", null)?.let { return it }
        return def
    }

    private fun dp(v: Float): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics
        ).toInt()

    private fun accent(): Int {
        return try {
            Color.parseColor("#" + pref("popup_color", "00D4FF"))
        } catch (_: Exception) {
            Color.parseColor("#00D4FF")
        }
    }

    private fun startFg() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "JARVIS popup", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("JARVIS standby")
            .setContentText("Popup robot aktif. Tap untuk buka Jarvis.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
        try {
            packageManager.getLaunchIntentForPackage(packageName)?.let {
                builder.setContentIntent(
                    PendingIntent.getActivity(
                        this, 0, it,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }
        } catch (_: Exception) {}
        val notif = builder.build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun removeOverlay() {
        try {
            root?.let { wm?.removeView(it) }
        } catch (_: Exception) {}
        root = null
        subtitleView = null
    }

    private fun iconRes(key: String): Int = when (key) {
        "bolt" -> R.drawable.ic_ov_bolt
        "eye" -> R.drawable.ic_ov_eye
        "chip" -> R.drawable.ic_ov_chip
        else -> R.drawable.ic_ov_robot
    }

    private fun galleryBitmap(path: String): android.graphics.Bitmap? {
        if (path.isEmpty()) return null
        return try {
            val f = File(path)
            if (!f.exists()) return null
            val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, b)
            var s = 1
            while (b.outWidth / s > 256 || b.outHeight / s > 256) s *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = s })
        } catch (_: Exception) {
            null
        }
    }

    private fun rebuildOverlay() {
        removeOverlay()
        if (Build.VERSION.SDK_INT >= 23 &&
            !android.provider.Settings.canDrawOverlays(this)
        ) return
        val w = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm = w
        val a = accent()
        val title = pref("popup_title", "JARVIS standby...")
        val iconKey = pref("popup_icon", "robot")
        val imgPath = pref("popup_image", "")
        val d = dp(1f)

        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(12 * d, 12 * d, 12 * d, 12 * d)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 20f * d
                setColor(0xCC0A1628.toInt())
                setStroke(2 * d, a)
            }
        }

        val iv = ImageView(this)
        val bmp = galleryBitmap(imgPath)
        if (bmp != null) {
            iv.setImageBitmap(bmp)
        } else {
            iv.setImageResource(iconRes(iconKey))
            iv.setColorFilter(a)
        }
        iv.clipToOutline = true
        iv.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(v: View, o: Outline) {
                o.setRoundRect(0, 0, v.width, v.height, 18f * d)
            }
        }
        box.addView(iv, 70 * d, 70 * d)

        val tv = TextView(this).apply {
            text = title
            setTextColor(a)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
        }
        box.addView(tv)
        val sub = TextView(this).apply {
            text = "Tap untuk bicara"
            setTextColor(Color.parseColor("#B3FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            gravity = Gravity.CENTER
        }
        box.addView(sub)
        subtitleView = sub

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = lastX
            y = lastY
        }

        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var downT = 0L
        box.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    startX = params.x
                    startY = params.y
                    downT = System.currentTimeMillis()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (e.rawX - downX).toInt()
                    params.y = startY + (e.rawY - downY).toInt()
                    try {
                        w.updateViewLayout(box, params)
                    } catch (_: Exception) {}
                    lastX = params.x
                    lastY = params.y
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (dx * dx + dy * dy < 100 &&
                        System.currentTimeMillis() - downT < 350
                    ) {
                        // Tap popup: kalau auto-dengar ON, paksa 1 sesi dengar.
                        // Kalau OFF, buka app + auto-dengar sekali (tanpa tap orb).
                        if (autoListen) {
                            beginSession()
                        } else {
                            openAppAutoListen()
                        }
                    }
                    true
                }
                else -> false
            }
        }

        try {
            w.addView(box, params)
            root = box
        } catch (_: Exception) {
            root = null
        }
    }

    // ================= AUTO-DENGAR (tanpa tap) =================

    private fun setSubtitle(s: String) {
        try {
            subtitleView?.text = s
        } catch (_: Exception) {}
    }

    private fun openAppAutoListen() {
        try {
            packageManager.getLaunchIntentForPackage(packageName)?.let {
                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                it.putExtra("jarvis_autolisten", true)
                startActivity(it)
            }
        } catch (_: Exception) {}
    }

    private fun startAutoListen() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            setSubtitle("STT tak tersedia di HP ini")
            return
        }
        if (ContextCompat.checkSelfPermission(
                this, Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            setSubtitle("Butuh izin mic: buka app Jarvis sekali")
            return
        }
        autoListen = true
        ensureTts()
        beginSession()
    }

    private fun stopAutoListen() {
        autoListen = false
        sessionActive = false
        try {
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: Exception) {}
        recognizer = null
    }

    private fun retrySoon(ms: Long = 1200) {
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ beginSession() }, ms)
    }

    private fun beginSession() {
        if (!autoListen || !running) return
        if (sessionActive) return
        try {
            if (recognizer == null) {
                recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                recognizer?.setRecognitionListener(recListener)
            }
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "id-ID")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            }
            sessionActive = true
            setSubtitle("🎤 dengar...")
            recognizer?.startListening(i)
        } catch (_: Exception) {
            sessionActive = false
            retrySoon()
        }
    }

    private val recListener = object : RecognitionListener {
        override fun onReadyForSpeech(p: Bundle?) {
            setSubtitle("🎤 dengar...")
        }
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(v: Float) {}
        override fun onBufferReceived(b: ByteArray?) {}
        override fun onEndOfSpeech() {
            setSubtitle("Proses...")
        }
        override fun onPartialResults(r: Bundle?) {
            val t = r?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull() ?: return
            if (t.isNotBlank()) setSubtitle("“$t”")
        }
        override fun onResults(r: Bundle?) {
            sessionActive = false
            val t = r?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()?.trim() ?: ""
            if (t.isEmpty()) {
                retrySoon(700)
                return
            }
            handleVoiceCommand(t)
            handler.postDelayed({ beginSession() }, 900)
        }
        override fun onError(code: Int) {
            sessionActive = false
            if (!autoListen || !running) return
            when (code) {
                SpeechRecognizer.ERROR_CLIENT,
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                    setSubtitle("Mic diblokir. Buka app Jarvis sekali.")
                    autoListen = false
                }
                else -> retrySoon()
            }
        }
        override fun onEvent(type: Int, p: Bundle?) {}
    }

    private fun ensureTts() {
        if (tts != null) return
        try {
            tts = TextToSpeech(this) { st ->
                if (st == TextToSpeech.SUCCESS) {
                    try {
                        val id = Locale("id", "ID")
                        tts?.language =
                            if (tts?.isLanguageAvailable(id) ?: 0 >= 0) id
                            else Locale.getDefault()
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
    }

    private fun speak(text: String) {
        setSubtitle(if (text.length > 60) text.take(60) + "…" else text)
        try {
            ensureTts()
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "jarvis")
        } catch (_: Exception) {}
    }

    // ---- Perintah lokal (native, tanpa buka app) ----

    private val appMap = mapOf(
        "whatsapp" to "com.whatsapp", "wa" to "com.whatsapp",
        "youtube" to "com.google.android.youtube", "yt" to "com.google.android.youtube",
        "instagram" to "com.instagram.android", "ig" to "com.instagram.android",
        "tiktok" to "com.zhiliaoapp.musically",
        "telegram" to "org.telegram.messenger",
        "spotify" to "com.spotify.music",
        "chrome" to "com.android.chrome",
        "kamera" to "com.android.camera", "camera" to "com.android.camera",
        "maps" to "com.google.android.apps.maps",
        "gmail" to "com.google.android.gm",
        "telepon" to "com.android.dialer",
        "pesan" to "com.google.android.apps.messaging",
        "sms" to "com.google.android.apps.messaging",
        "kalkulator" to "com.google.android.calculator",
        "jam" to "com.google.android.deskclock",
        "alarm" to "com.google.android.deskclock",
        "pengaturan" to "com.android.settings",
        "setelan" to "com.android.settings"
    )

    private fun handleVoiceCommand(raw: String) {
        val t = raw.lowercase().trim()
        val s = t.replaceFirst(Regex("^(halo |hai |hey |hei )?jarvis[ ,]*"), "").trim()
        try {
            // BUKA APLIKASI
            val open = Regex("(buka|bukain|bukakan|open|jalankan)\\s+(.+)").find(s)
            if (open != null) {
                var target = open.groupValues[2].replace("wasap", "whatsapp").trim()
                var pkg: String? = appMap[target]
                if (pkg == null) {
                    for ((k, v) in appMap) {
                        if (target == k || target.contains(k)) {
                            pkg = v
                            target = k
                            break
                        }
                    }
                }
                if (pkg != null) {
                    val i = packageManager.getLaunchIntentForPackage(pkg)
                    if (i != null) {
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        speak("Membuka $target, Sir.")
                        return
                    }
                }
                speak("Aplikasi $target tidak ketemu, Sir.")
                return
            }
            // TUTUP / HOME
            if (s.contains("tutup") || s.contains("close")) {
                val i = Intent(Intent.ACTION_MAIN)
                i.addCategory(Intent.CATEGORY_HOME)
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                speak("Ditutup, Sir.")
                return
            }
            // KUNCI LAYAR
            if ((s.contains("kunci") && s.contains("layar")) ||
                s.contains("matikan layar") || s.contains("kunci hp")
            ) {
                try {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE)
                        as android.app.admin.DevicePolicyManager
                    val admin = ComponentName(this, AdminReceiver::class.java)
                    if (dpm.isAdminActive(admin)) {
                        dpm.lockNow()
                        return
                    }
                } catch (_: Exception) {}
                speak("Aktifkan Device Admin dulu di app Jarvis ya Sir.")
                return
            }
            // SENTER
            if (s.contains("senter") || s.contains("flashlight")) {
                try {
                    val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cam = camIdList().firstOrNull()
                    if (cam != null) {
                        cm.setTorchMode(cam, !s.contains("mati"))
                        speak(if (s.contains("mati")) "Senter mati." else "Senter nyala.")
                        return
                    }
                } catch (_: Exception) {}
                speak("Senter gagal, Sir.")
                return
            }
            // VOLUME
            if (s.contains("volume") || s.contains("suara")) {
                try {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val up = s.contains("naik") || s.contains("besar") || s.contains("keras")
                    am.adjustStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                        0
                    )
                    speak(if (up) "Volume naik." else "Volume turun.")
                    return
                } catch (_: Exception) {}
            }
            // JAM
            if (s.contains("jam berapa") || s == "jam") {
                val f = java.text.SimpleDateFormat("HH:mm", Locale("id", "ID"))
                speak("Jam ${f.format(java.util.Date())}, Sir.")
                return
            }
            // BATERAI
            if (s.contains("baterai") || s.contains("batre")) {
                try {
                    val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    speak("Baterai $pct persen, Sir.")
                    return
                } catch (_: Exception) {}
            }
            // Selain itu -> Groq AI
            groqAsk(raw)
        } catch (_: Exception) {
            speak("Maaf Sir, ada gangguan.")
        }
    }

    private fun camIdList(): Array<String> {
        return try {
            (getSystemService(Context.CAMERA_SERVICE) as CameraManager).cameraIdList
        } catch (_: Exception) {
            emptyArray()
        }
    }

    private fun groqAsk(userText: String) {
        val key = pref("groq_key", "")
        if (key.isEmpty() || key.contains("GANTI")) {
            speak("Isi API key Groq di app Jarvis dulu ya Sir.")
            return
        }
        setSubtitle("Tanya AI...")
        Thread {
            try {
                val url =
                    java.net.URL("https://api.groq.com/openai/v1/chat/completions")
                val c = url.openConnection() as javax.net.ssl.HttpsURLConnection
                c.requestMethod = "POST"
                c.connectTimeout = 20000
                c.readTimeout = 20000
                c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json")
                c.setRequestProperty("Authorization", "Bearer $key")
                val sys = "Kamu JARVIS, asisten RobotAI ala Iron Man. " +
                    "Bahasa Indonesia campur Inggris, singkat maks 2 kalimat, panggil user Sir."
                val body = JSONObject()
                    .put("model", "llama-3.3-70b-versatile")
                    .put("temperature", 0.7)
                    .put("max_tokens", 300)
                    .put(
                        "messages", org.json.JSONArray()
                            .put(JSONObject().put("role", "system").put("content", sys))
                            .put(JSONObject().put("role", "user").put("content", userText))
                    ).toString()
                c.outputStream.use { it.write(body.toByteArray()) }
                val code = c.responseCode
                val stream = if (code == 200) c.inputStream else c.errorStream
                val txt = stream.bufferedReader().use { it.readText() }
                if (code == 200) {
                    val reply = JSONObject(txt)
                        .getJSONArray("choices").getJSONObject(0)
                        .getJSONObject("message").getString("content").trim()
                    handler.post { speak(reply) }
                } else {
                    handler.post { speak("Groq gagal $code. Cek key atau kuota ya Sir.") }
                }
            } catch (e: Exception) {
                handler.post { speak("Offline Sir. Cek internet.") }
            }
        }.start()
    }
}
