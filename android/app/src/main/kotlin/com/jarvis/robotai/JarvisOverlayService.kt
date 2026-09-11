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
import android.bluetooth.BluetoothAdapter
import android.content.ContentValues
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.AlarmClock
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
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
    private var dotView: View? = null
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
        // NOT_STICKY: kalau user mematikan popup, sistem tidak boleh
        // menghidupkannya lagi sendiri.
        rebuildOverlay()
        val wantAuto = prefs().getBoolean("popup_autolisten", false) ||
            prefs().getBoolean("flutter.popup_autolisten", false)
        if (wantAuto) startAutoListen() else stopAutoListen()
        return START_NOT_STICKY
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
        val title = pref("popup_title", "jarvis")
        val iconKey = pref("popup_icon", "robot")
        val imgPath = pref("popup_image", "")
        val d = dp(1f)

        // MINIMALIS: tanpa background box, hanya ikon + nama + titik status.
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(8 * d, 8 * d, 8 * d, 8 * d)
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
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            setShadowLayer(6f, 0f, 0f, Color.BLACK)
        }
        box.addView(tv)
        // Titik status kecil: cyan = standby, hijau = dengar, oranye = proses.
        val dot = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(a)
            }
        }
        val dotP = LinearLayout.LayoutParams(10 * d, 10 * d).apply {
            topMargin = 4 * d
            gravity = Gravity.CENTER_HORIZONTAL
        }
        box.addView(dot, dotP)
        dotView = dot

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

    /** Status popup = warna titik (nama + ikon tidak diubah). */
    private fun setDot(c: Int) {
        try {
            val v = dotView ?: return
            v.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(c)
            }
        } catch (_: Exception) {}
    }

    private fun setSubtitle(s: String) {
        // Teks status tidak ditampilkan (popup minimalis: ikon + nama saja).
        // Dipetakan ke warna titik agar user tetap tahu kondisi.
        val lower = s.lowercase()
        when {
            lower.contains("dengar") || lower.contains("“") -> setDot(0xFF00FF9D.toInt())
            lower.contains("tanya") || lower.contains("proses") -> setDot(0xFFFFB300.toInt())
            lower.contains("mic diblokir") || lower.contains("gagal") -> setDot(0xFFFF4D6D.toInt())
            else -> setDot(accent())
        }
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
                        // DUCKING: suara Jarvis hanya mengecilkan video/musik,
                        // bukan me-pause (USAGE_ASSISTANT, API 21+).
                        if (Build.VERSION.SDK_INT >= 21) {
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
        "yutub" to "com.google.android.youtube",
        "instagram" to "com.instagram.android", "ig" to "com.instagram.android",
        "tiktok" to "com.zhiliaoapp.musically",
        "telegram" to "org.telegram.messenger", "tele" to "org.telegram.messenger",
        "spotify" to "com.spotify.music",
        "chrome" to "com.android.chrome", "krom" to "com.android.chrome",
        "kamera" to "com.android.camera", "camera" to "com.android.camera",
        "maps" to "com.google.android.apps.maps", "gmaps" to "com.google.android.apps.maps",
        "gmail" to "com.google.android.gm",
        "telepon" to "com.android.dialer",
        "pesan" to "com.google.android.apps.messaging",
        "sms" to "com.google.android.apps.messaging",
        "kalkulator" to "com.google.android.calculator",
        "jam" to "com.google.android.deskclock",
        "alarm" to "com.google.android.deskclock",
        "pengaturan" to "com.android.settings",
        "setelan" to "com.android.settings",
        "shopee" to "com.shopee.id", "sopi" to "com.shopee.id", "shopi" to "com.shopee.id",
        "tokopedia" to "com.tokopedia.tkpd", "toped" to "com.tokopedia.tkpd"
    )

    private fun handleVoiceCommand(raw: String) {
        val t = raw.lowercase().trim()
        var s = t.replaceFirst(Regex("^(halo |hai |hey |hei )?jarvis[ ,]*"), "").trim()
        s = s.replaceFirst(
            Regex("^(tolong|tolongin|coba|eh+|woi|woy|bang|min)\\s+"), ""
        ).trim()
        // Versi tanpa spasi: tangkap salah-dengar STT ("nya lain" -> "nyalain").
        val c = s.replace(Regex("\\s+"), "")
        fun has(keys: List<String>): Boolean {
            for (k in keys) {
                if (s.contains(k)) return true
                val kc = k.replace(" ", "")
                if (kc.isNotEmpty() && c.contains(kc)) return true
            }
            return false
        }
        try {
            // BUKA APLIKASI (layar/hp/hape/alarm = perintah daya/jam, BUKAN app)
            if (has(listOf("buka", "open", "jalankan", "nyalain", "idupin", "hidupin")) &&
                !has(listOf("layar", "hp", "hape", "handphone", "alarm", "senter", "lampu"))
            ) {
                var target = s.replace(
                    Regex("(tolong|dong|coba|buka|bukain|bukakan|open|jalankan|nyalain|idupin|hidupin)"),
                    " "
                ).replace("wasap", "whatsapp")
                    .replace(Regex("\\s+"), " ").trim()
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
                if (pkg == null) {
                    // Fallback cerdas: cari app terdekat di HP.
                    val best = AppFinder.findBest(packageManager, target)
                    if (best != null) {
                        pkg = best.second
                        target = best.first
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
            // NYALAKAN LAYAR (layar-mati, bukan mati total).
            // WakeLock + Activity transparan + coba swipe kunci geser.
            if (has(
                    listOf(
                        "nyalakan layar", "nyalakan hp", "nyalakan hape",
                        "nyalain layar", "nyalain hp", "nyalain hape",
                        "idupin layar", "idupin hp",
                        "hidupkan layar", "hidupkan hp",
                        "bangun", "wake up"
                    )
                )
            ) {
                wakeScreen()
                speak("Layar dinyalakan, Sir.")
                return
            }
            // KUNCI LAYAR
            val mauKunci = (has(listOf("kunci", "matiin", "matikan")) &&
                has(listOf("layar", "hp", "hape"))) || has(listOf("lock"))
            if (mauKunci && !has(listOf("senter", "lampu"))) {
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
            // ALARM: "pasang alarm jam 7 pagi" (buka jam sistem terisi)
            if (s.contains("alarm")) {
                val num = Regex("(\\d{1,2})(?:[:.](\\d{2}))?").find(s)
                if (num != null) {
                    var h = num.groupValues[1].toInt()
                    val m = if (num.groupValues[2].isNotEmpty()) {
                        num.groupValues[2].toInt()
                    } else {
                        0
                    }
                    if ((s.contains("siang") || s.contains("sore") ||
                                s.contains("malam")) && h < 12
                    ) {
                        h += 12
                    }
                    if (h in 0..23 && m in 0..59) {
                        try {
                            val i = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                                putExtra(AlarmClock.EXTRA_HOUR, h)
                                putExtra(AlarmClock.EXTRA_MINUTES, m)
                                putExtra(AlarmClock.EXTRA_MESSAGE, "Jarvis")
                                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(i)
                            speak("Membuka jam untuk alarm, Sir.")
                            return
                        } catch (_: Exception) {}
                    }
                }
                speak("Jam berapa alarmnya Sir? Contoh: pasang alarm jam 6 pagi.")
                return
            }
            // TANGKAP LAYAR ke galeri ("screenshot", "ss").
            if (has(listOf("tangkap layar", "screenshot", "ambil screenshot")) ||
                s == "ss" || s.startsWith("ss ")
            ) {
                speak("Menangkap layar, Sir.")
                saveShotToGallery()
                return
            }
            // REKAM LAYAR butuh Activity: arahkan buka app.
            if (s.contains("rekam layar") || s.contains("mulai rekam") ||
                s.contains("stop rekam") || s.contains("berhenti rekam")
            ) {
                speak("Buka app Jarvis untuk rekam layar ya Sir. Di sana ucapkan rekam layar.")
                openAppAutoListen()
                return
            }
            // WIFI
            if (s.contains("wifi") || s.contains("wi-fi")) {
                val on = !(s.contains("mati") || s.contains("matikan") ||
                    s.contains("matiin") || s.contains("off"))
                try {
                    if (Build.VERSION.SDK_INT >= 29) {
                        val i = Intent(Settings.Panel.ACTION_WIFI)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        speak("Panel WiFi dibuka, Sir.")
                    } else {
                        @Suppress("DEPRECATION")
                        val wm = applicationContext
                            .getSystemService(Context.WIFI_SERVICE) as WifiManager
                        @Suppress("DEPRECATION")
                        wm.isWifiEnabled = on
                        speak(if (on) "WiFi nyala." else "WiFi mati.")
                    }
                } catch (_: Exception) {
                    speak("WiFi gagal, Sir.")
                }
                return
            }
            // BLUETOOTH
            if (s.contains("bluetooth") || s.contains("blutut")) {
                if (s.contains("pengaturan") || s.contains("setting")) {
                    try {
                        val i = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                    } catch (_: Exception) {}
                    return
                }
                val on = !(s.contains("mati") || s.contains("matikan") ||
                    s.contains("matiin") || s.contains("off"))
                try {
                    @Suppress("DEPRECATION")
                    val ba = BluetoothAdapter.getDefaultAdapter()
                    if (ba == null) {
                        speak("HP ini tidak punya Bluetooth.")
                    } else {
                        @Suppress("DEPRECATION")
                        if (on) ba.enable() else ba.disable()
                        speak(if (on) "Bluetooth nyala." else "Bluetooth mati.")
                    }
                } catch (_: Exception) {
                    speak("Bluetooth butuh izin Nearby devices. Buka app Jarvis sekali ya Sir.")
                }
                return
            }
            // FOTO (buka kamera; jepret manual)
            if (s == "foto" || s.startsWith("foto ") || s.contains("ambil foto") ||
                s.contains("selfie")
            ) {
                try {
                    val i = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(i)
                    speak("Kamera dibuka, Sir.")
                } catch (_: Exception) {
                    speak("Kamera gagal dibuka.")
                }
                return
            }
            // BRIEFING (offline)
            if (s.contains("briefing") || s.contains("laporan pagi")) {
                try {
                    val now = java.util.Date()
                    val day = java.text.SimpleDateFormat("EEEE", Locale("id", "ID")).format(now)
                    val date = java.text.SimpleDateFormat("d MMMM yyyy", Locale("id", "ID")).format(now)
                    val hm = java.text.SimpleDateFormat("HH:mm", Locale("id", "ID")).format(now)
                    val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    speak("Selamat pagi Sir. Hari $day, $date, jam $hm, baterai $pct persen.")
                } catch (_: Exception) {
                    speak("Briefing gagal Sir.")
                }
                return
            }
            // LAWAKAN receh (offline)
            if (s.contains("lawak") || s.contains("lucu") || s.contains("humor") ||
                s.contains("guyon")
            ) {
                val jokes = listOf(
                    "Kenapa programmer benci alam? Karena terlalu banyak bug, Sir.",
                    "Kenapa HP tidak pernah bohong? Karena selalu ada sinyal kebenaran, Sir.",
                    "Saya mau cuti Sir... tapi saya tinggal di HP ini."
                )
                speak(jokes[(System.currentTimeMillis() % jokes.size).toInt()])
                return
            }
            // LIHAT LAYAR: screenshot + AI vision menjelaskan.
            if (has(
                    listOf(
                        "lihat layar", "baca layar", "tangkap layar",
                        "screenshot", "apa yang tampil", "apa di layar"
                    )
                )
            ) {
                screenshotAndAsk()
                return
            }
            // MODE DERING HP
            if (s.contains("mode getar") || s == "getar") {
                setRinger(AudioManager.RINGER_MODE_VIBRATE, "HP mode getar, Sir.")
                return
            }
            if (s.contains("mode hening") || s == "hening") {
                setRinger(AudioManager.RINGER_MODE_SILENT, "HP mode hening, Sir.")
                return
            }
            if (s.contains("mode normal") || s.contains("mode dering")) {
                setRinger(AudioManager.RINGER_MODE_NORMAL, "HP mode normal, Sir.")
                return
            }
            // MUSIK
            if (s.contains("musik jeda") || s.contains("musik pause") || s.contains("jeda musik")) {
                mediaPress(KeyEvent.KEYCODE_MEDIA_PAUSE)
                speak("Musik dijeda, Sir.")
                return
            }
            if (s.contains("musik main") || s.contains("lanjut musik") || s.contains("putar musik")) {
                mediaPress(KeyEvent.KEYCODE_MEDIA_PLAY)
                speak("Musik main, Sir.")
                return
            }
            if (s.contains("lagu berikut") || s.contains("lagu selanjut") || s.contains("ganti lagu")) {
                mediaPress(KeyEvent.KEYCODE_MEDIA_NEXT)
                speak("Lagu berikutnya, Sir.")
                return
            }
            if (s.contains("lagu sebelum") || s.contains("kembali lagu")) {
                mediaPress(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
                speak("Lagu sebelumnya, Sir.")
                return
            }
            // RUTIN
            if (s.contains("mode tidur") || s.contains("selamat tidur")) {
                setRinger(AudioManager.RINGER_MODE_SILENT, null)
                lockNow()
                speak("Mode tidur, Sir. Hening dan terkunci.")
                return
            }
            if (s.contains("mode kerja")) {
                setRinger(AudioManager.RINGER_MODE_NORMAL, null)
                launchPkg("com.google.android.gm")
                speak("Mode kerja, Sir.")
                return
            }
            if (s.contains("mode nonton") || s.contains("mode film")) {
                setRinger(AudioManager.RINGER_MODE_VIBRATE, null)
                launchPkg("com.google.android.youtube")
                speak("Mode nonton, Sir.")
                return
            }
            // KALKULATOR (offline)
            if ((s.startsWith("berapa") || s.startsWith("hitung")) && s.any { it.isDigit() }) {
                val h = calcId(s)
                if (h != null) {
                    speak("Hasilnya $h, Sir.")
                    return
                }
            }
            // Selain itu -> Groq AI
            groqAsk(raw)
        } catch (_: Exception) {
            speak("Maaf Sir, ada gangguan.")
        }
    }

    /** Nyalakan layar dari service: WakeLock + Activity transparan + swipe. */
    private fun wakeScreen() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            @Suppress("DEPRECATION")
            val wl = pm.newWakeLock(
                android.os.PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    android.os.PowerManager.ON_AFTER_RELEASE,
                "jarvis:wakeupSvc"
            )
            wl.acquire(5000)
        } catch (_: Exception) {}
        try {
            val i = Intent(this, WakeActivity::class.java)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
        } catch (_: Exception) {}
        // Coba buka kunci geser sesaat setelah layar nyala.
        handler.postDelayed({
            try {
                JarvisAccessibilityService.swipeUp()
            } catch (_: Exception) {}
        }, 1200)
    }

    /** Tangkap layar lalu simpan ke galeri (Pictures/Jarvis). */
    private fun saveShotToGallery() {
        JarvisAccessibilityService.screenshot { r ->
            handler.post {
                if (r.startsWith("ERR:")) {
                    speak(r.removePrefix("ERR:"))
                    return@post
                }
                try {
                    val src = File(r)
                    val name = "jarvis_${System.currentTimeMillis()}.jpg"
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, name)
                        put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                        if (Build.VERSION.SDK_INT >= 29) {
                            put(
                                MediaStore.Images.Media.RELATIVE_PATH,
                                "Pictures/Jarvis"
                            )
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                    }
                    val uri = contentResolver.insert(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values
                    )
                    if (uri == null) {
                        speak("Galeri menolak, Sir.")
                        return@post
                    }
                    contentResolver.openOutputStream(uri)?.use { o ->
                        java.io.FileInputStream(src).use { it.copyTo(o) }
                    }
                    if (Build.VERSION.SDK_INT >= 29) {
                        values.clear()
                        values.put(MediaStore.Images.Media.IS_PENDING, 0)
                        contentResolver.update(uri, values, null, null)
                    }
                    speak("$name tersimpan di galeri, Sir.")
                } catch (_: Exception) {
                    speak("Gagal simpan screenshot.")
                }
            }
        }
    }

    private fun camIdList(): Array<String> {
        return try {
            (getSystemService(Context.CAMERA_SERVICE) as CameraManager).cameraIdList
        } catch (_: Exception) {
            emptyArray()
        }
    }

    private fun setRinger(mode: Int, say: String?) {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.ringerMode = mode
            if (say != null) speak(say)
        } catch (_: Exception) {
            speak("Mode suara dikunci DND, Sir.")
        }
    }

    private fun mediaPress(code: Int) {
        try {
            val down = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                putExtra(
                    Intent.EXTRA_KEY_EVENT,
                    KeyEvent(KeyEvent.ACTION_DOWN, code)
                )
            }
            val up = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                putExtra(
                    Intent.EXTRA_KEY_EVENT,
                    KeyEvent(KeyEvent.ACTION_UP, code)
                )
            }
            sendOrderedBroadcast(down, null)
            sendOrderedBroadcast(up, null)
        } catch (_: Exception) {}
    }

    private fun lockNow() {
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE)
                as DevicePolicyManager
            val admin = ComponentName(this, AdminReceiver::class.java)
            if (dpm.isAdminActive(admin)) dpm.lockNow()
        } catch (_: Exception) {}
    }

    private fun launchPkg(pkg: String) {
        try {
            packageManager.getLaunchIntentForPackage(pkg)?.let {
                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(it)
            }
        } catch (_: Exception) {}
    }

    /** Kalkulator mini Indonesia (dua-stack, tanpa rekursi).
     * Return hasil format koma / null bila gagal. */
    private fun calcId(s: String): String? {
        return try {
            var e = s.replaceFirst(Regex("^(berapa|hitung)\\s+"), "")
                .replace("tambah", "+").replace("plus", "+")
                .replace("kurang", "-").replace("minus", "-")
                .replace("kali", "*").replace("bagi", "/")
                .replace("dibagi", "/").replace("persen", "/100")
                .replace("%", "/100").replace("koma", ".")
                .replace("x", "*")
            e = e.filter {
                it.isDigit() || it == '+' || it == '-' || it == '*' ||
                    it == '/' || it == '.' || it == '(' || it == ')' ||
                    it == ' '
            }.trim()
            if (!e.any { it.isDigit() }) return null
            val toks = Regex("\\d+\\.?\\d*|[+\\-*/()]")
                .findAll(e.replace(" ", "")).map { it.value }.toList()
            // Tangani minus unary: "-5" -> "0-5", "(-3" -> "(0-3".
            val fixed = ArrayList<String>()
            for (i in toks.indices) {
                val tk = toks[i]
                if (tk == "-" && (i == 0 || toks[i - 1] in listOf("+", "-", "*", "/", "("))) {
                    fixed.add("0")
                }
                fixed.add(tk)
            }
            val prec = mapOf("+" to 1, "-" to 1, "*" to 2, "/" to 2)
            val vals = ArrayDeque<Double>()
            val ops = ArrayDeque<String>()
            fun apply() {
                val op = ops.removeLast()
                val r = vals.removeLast()
                val l = vals.removeLast()
                vals.addLast(
                    when (op) {
                        "+" -> l + r
                        "-" -> l - r
                        "*" -> l * r
                        else -> l / r
                    }
                )
            }
            for (tk in fixed) {
                when {
                    tk.toDoubleOrNull() != null -> vals.addLast(tk.toDouble())
                    tk == "(" -> ops.addLast(tk)
                    tk == ")" -> {
                        while (ops.isNotEmpty() && ops.last() != "(") apply()
                        if (ops.isEmpty()) return null
                        ops.removeLast()
                    }
                    tk in prec -> {
                        while (ops.isNotEmpty() && ops.last() != "(" &&
                            prec[ops.last()]!! >= prec[tk]!!
                        ) apply()
                        ops.addLast(tk)
                    }
                    else -> return null
                }
            }
            while (ops.isNotEmpty()) {
                if (ops.last() == "(") return null
                apply()
            }
            if (vals.size != 1) return null
            val v = vals.last()
            if (v.isInfinite() || v.isNaN()) return null
            if (v == kotlin.math.floor(v)) v.toLong().toString()
            else "%.2f".format(v).replace(".", ",")
        } catch (_: Exception) {
            null
        }
    }

    private fun screenshotAndAsk() {
        setSubtitle("Lihat layar...")
        JarvisAccessibilityService.screenshot { r ->
            handler.post {
                if (r.startsWith("ERR:")) {
                    speak(r.removePrefix("ERR:"))
                    return@post
                }
                groqAskVision(r)
            }
        }
    }

    /** Tanya AI vision dengan gambar screenshot (model multimodal + cadangan). */
    private fun groqAskVision(path: String) {
        val key = pref("groq_key", "")
        if (key.isEmpty() || key.contains("GANTI")) {
            speak("Isi API key Groq di app Jarvis dulu ya Sir.")
            return
        }
        setSubtitle("Analisa layar...")
        Thread {
            val models = listOf(
                "meta-llama/llama-4-maverick-17b-128e-instruct",
                "meta-llama/llama-4-scout-17b-16e-instruct"
            )
            var done = false
            var lastCode = -1
            var b64 = ""
            try {
                val bytes = File(path).readBytes()
                if (bytes.size > 4 * 1024 * 1024) {
                    handler.post { speak("Gambar layar terlalu besar Sir.") }
                    return@Thread
                }
                b64 = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
            } catch (_: Exception) {
                handler.post { speak("Gagal baca gambar layar Sir.") }
                return@Thread
            }
            val q = "Lihat gambar screenshot layar HP ini. Jelaskan singkat " +
                "dalam Bahasa Indonesia apa yang tampil dan info pentingnya, " +
                "maksimal 3 kalimat. Panggil user Sir."
            for (model in models) {
                if (done) break
                try {
                    val url =
                        java.net.URL("https://api.groq.com/openai/v1/chat/completions")
                    val c = url.openConnection() as javax.net.ssl.HttpsURLConnection
                    c.requestMethod = "POST"
                    c.connectTimeout = 20000
                    c.readTimeout = 30000
                    c.doOutput = true
                    c.setRequestProperty("Content-Type", "application/json")
                    c.setRequestProperty("Authorization", "Bearer $key")
                    val body = JSONObject()
                        .put("model", model)
                        .put("temperature", 0.5)
                        .put("max_tokens", 300)
                        .put(
                            "messages", org.json.JSONArray().put(
                                JSONObject()
                                    .put("role", "user")
                                    .put(
                                        "content", org.json.JSONArray()
                                            .put(
                                                JSONObject()
                                                    .put("type", "text")
                                                    .put("content", q)
                                            )
                                            .put(
                                                JSONObject()
                                                    .put("type", "image_url")
                                                    .put(
                                                        "image_url", JSONObject().put(
                                                            "url",
                                                            "data:image/jpeg;base64,$b64"
                                                        )
                                                    )
                                            )
                                    )
                            )
                        ).toString()
                    c.outputStream.use { it.write(body.toByteArray()) }
                    val code = c.responseCode
                    lastCode = code
                    val stream = if (code == 200) c.inputStream else c.errorStream
                    val txt = stream.bufferedReader().use { it.readText() }
                    if (code == 200) {
                        val reply = JSONObject(txt)
                            .getJSONArray("choices").getJSONObject(0)
                            .getJSONObject("message").getString("content").trim()
                        done = true
                        handler.post { speak(reply) }
                    } else if (code == 401) {
                        done = true
                        handler.post { speak("API key salah Sir.") }
                    }
                } catch (_: Exception) {
                    lastCode = -2
                }
            }
            if (!done) {
                handler.post { speak("Vision gagal ($lastCode). Coba lagi ya Sir.") }
            }
        }.start()
    }

    private fun groqAsk(userText: String) {
        val key = pref("groq_key", "")
        if (key.isEmpty() || key.contains("GANTI")) {
            speak("Isi API key Groq di app Jarvis dulu ya Sir.")
            return
        }
        setSubtitle("Tanya AI...")
        Thread {
            // Model + cadangan. Urutan cepat dulu agar sat-set.
            val models = listOf(
                "openai/gpt-oss-20b",
                "openai/gpt-oss-120b",
                "qwen/qwen3.6-27b"
            )
            var done = false
            var lastCode = -1
            for (model in models) {
                if (done) break
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
                        "WAJIB SELALU jawab Bahasa Indonesia (campur Inggris santai). " +
                        "JANGAN PERNAH jawab full Inggris. Singkat maks 2 kalimat, panggil user Sir."
                    val body = JSONObject()
                        .put("model", model)
                        .put("temperature", 0.7)
                        .put("max_tokens", 250)
                        .put(
                            "messages", org.json.JSONArray()
                                .put(JSONObject().put("role", "system").put("content", sys))
                                .put(JSONObject().put("role", "user").put("content", userText))
                        ).toString()
                    c.outputStream.use { it.write(body.toByteArray()) }
                    val code = c.responseCode
                    lastCode = code
                    val stream = if (code == 200) c.inputStream else c.errorStream
                    val txt = stream.bufferedReader().use { it.readText() }
                    if (code == 200) {
                        val reply = JSONObject(txt)
                            .getJSONArray("choices").getJSONObject(0)
                            .getJSONObject("message").getString("content").trim()
                        done = true
                        handler.post { speak(reply) }
                    } else if (code == 401) {
                        done = true
                        handler.post { speak("API key salah Sir. Buat baru ya Sir.") }
                    }
                    // 404/429/5xx -> coba model cadangan (kuota per model).
                    // else if dihapus: semua non-401 lanjut ke model berikut.
                } catch (e: Exception) {
                    lastCode = -2
                }
            }
            if (!done) {
                handler.post { speak("Semua model gagal ($lastCode). Cek internet ya Sir.") }
            }
        }.start()
    }
}
