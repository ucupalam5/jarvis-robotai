package com.jarvis.robotai

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.AlarmClock
import android.provider.Settings
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "jarvis/control"
    private val MIC_REQ = 2001
    private val PICK_REQ = 2002
    private var micResult: MethodChannel.Result? = null
    private var pickResult: MethodChannel.Result? = null
    private var notifResult: MethodChannel.Result? = null
    private var camResult: MethodChannel.Result? = null
    private val NOTIF_REQ = 2004
    private val CAM_REQ = 2005
    private var hfWl: PowerManager.WakeLock? = null
    @Volatile private var pendingAutolisten = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra("jarvis_autolisten", false) == true) {
            pendingAutolisten = true
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("jarvis_autolisten", false)) {
            pendingAutolisten = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openApp" -> {
                        val keyword = call.argument<String>("keyword") ?: ""
                        result.success(openApp(keyword))
                    }
                    "closeApp" -> result.success(closeApp())
                    "goHome" -> result.success(goHome())
                    "lockScreen" -> result.success(lockScreen())
                    "flashlight" -> {
                        val on = call.argument<Boolean>("on") ?: true
                        result.success(toggleFlashlight(on))
                    }
                    "volumeUp" -> result.success(volume(1))
                    "volumeDown" -> result.success(volume(-1))
                    "wakeUp" -> result.success(wakeUp())
                    "getBattery" -> result.success(getBattery())
                    "setAlarm" -> {
                        val h = call.argument<Int>("hour") ?: -1
                        val m = call.argument<Int>("minute") ?: 0
                        val label = call.argument<String>("label") ?: "Jarvis"
                        result.success(setAlarm(h, m, label))
                    }
                    "dial" -> {
                        val n = call.argument<String>("number") ?: ""
                        result.success(dial(n))
                    }
                    "sms" -> {
                        val n = call.argument<String>("number") ?: ""
                        val b = call.argument<String>("body") ?: ""
                        result.success(sms(n, b))
                    }
                    "webSearch" -> {
                        val q = call.argument<String>("query") ?: ""
                        result.success(webSearch(q))
                    }
                    "openSettingsPage" -> {
                        val p = call.argument<String>("page") ?: ""
                        result.success(openSettingsPage(p))
                    }
                    "requestMic" -> requestMic(result)
                    "pickImage" -> pickImage(result)
                    // --- Popup robot native ---
                    "overlayShow" -> result.success(overlayShow())
                    "overlayHide" -> {
                        try {
                            stopService(Intent(this, JarvisOverlayService::class.java))
                        } catch (_: Exception) {}
                        result.success("OK")
                    }
                    "overlayActive" -> result.success(
                        if (JarvisOverlayService.running) "YA" else "TIDAK"
                    )
                    "overlayPerm" -> result.success(
                        if (Build.VERSION.SDK_INT < 23 ||
                            Settings.canDrawOverlays(this)
                        ) "YA" else "TIDAK"
                    )
                    // --- Handsfree: tahan CPU redup agar mic tetap dengar ---
                    "handsfreeWake" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        result.success(handsfreeWake(on))
                    }
                    // --- Popup tap -> auto dengar (dikonsumsi sekali) ---
                    "consumeAutolisten" -> {
                        val v = pendingAutolisten
                        pendingAutolisten = false
                        result.success(if (v) "YA" else "TIDAK")
                    }
                    // --- Izin notifikasi (untuk notif popup di Android 13+) ---
                    "requestNotif" -> requestNotif(result)
                    // --- Izin kamera (untuk senter) ---
                    "requestCamera" -> requestCamera(result)
                    // --- Daftar semua aplikasi (bantu cari app) ---
                    "listApps" -> result.success(listApps())
                    // --- Mode dering HP: normal / getar / hening ---
                    "ringerMode" -> {
                        val m = call.argument<String>("mode") ?: "normal"
                        result.success(ringerMode(m))
                    }
                    // --- Tombol media: musik pause/main/lagu ---
                    "mediaKey" -> {
                        val code = call.argument<Int>("code") ?: 85
                        result.success(mediaKey(code))
                    }
                    // --- Otomatisasi via Accessibility (tanpa root/aplikasi tambahan) ---
                    "accCheck" -> result.success(accStatus())
                    "accOpenSettings" -> {
                        try {
                            val i = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success("OK")
                        } catch (e: Exception) {
                            result.success("Gagal buka pengaturan: ${e.message}")
                        }
                    }
                    "accTap" -> {
                        val x = call.argument<Int>("x") ?: 935
                        val y = call.argument<Int>("y") ?: 950
                        result.success(JarvisAccessibilityService.tapAt(x, y))
                    }
                    "accSwipeUp" -> result.success(JarvisAccessibilityService.swipeUp())
                    "accType" -> {
                        val text = call.argument<String>("text") ?: ""
                        result.success(JarvisAccessibilityService.typeText(text))
                    }
                    "accClickSend" ->
                        result.success(JarvisAccessibilityService.clickSend())
                    else -> result.notImplemented()
                }
            }
    }

    private fun openApp(keyword: String): String {
        return try {
            val pm = packageManager
            // 1) langsung sebagai package name
            var intent = pm.getLaunchIntentForPackage(keyword)
            // 2) cari aplikasi yang mengandung keyword (longgar: abaikan spasi).
            if (intent == null) {
                val flat = keyword.replace(" ", "").lowercase()
                val apps = pm.getInstalledApplications(0)
                val found = apps.firstOrNull {
                    val pkg = it.packageName
                    val label = pm.getApplicationLabel(it)?.toString() ?: ""
                    pkg.contains(keyword, ignoreCase = true) ||
                    label.contains(keyword, ignoreCase = true) ||
                    (flat.isNotEmpty() &&
                        (pkg.replace(" ", "").contains(flat, ignoreCase = true) ||
                            label.replace(" ", "").contains(flat, ignoreCase = true)))
                }
                if (found != null) intent = pm.getLaunchIntentForPackage(found.packageName)
            }
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                "OK"
            } else {
                "Aplikasi '$keyword' tidak ditemukan, Sir."
            }
        } catch (e: Exception) {
            "Gagal membuka: ${e.message}"
        }
    }

    private fun closeApp(): String {
        return try {
            // Cara sopan tanpa root: tekan BACK lalu HOME via Accessibility.
            // + kill background process milik task teratas (best-effort).
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val tasks = am.appTasks
            if (tasks.isNotEmpty()) {
                try { tasks[0].finishAndRemoveTask() } catch (_: Exception) {}
            }
            goHome()
            JarvisAccessibilityService.globalBackAndHome()
            "OK"
        } catch (e: Exception) {
            "Gagal menutup: ${e.message}"
        }
    }

    private fun goHome(): String {
        return try {
            val i = Intent(Intent.ACTION_MAIN)
            i.addCategory(Intent.CATEGORY_HOME)
            i.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(i)
            "OK"
        } catch (e: Exception) {
            "Gagal: ${e.message}"
        }
    }

    private fun lockScreen(): String {
        return try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val admin = ComponentName(this, AdminReceiver::class.java)
            if (dpm.isAdminActive(admin)) {
                dpm.lockNow()
                "OK"
            } else {
                // Minta aktifkan Device Admin sekali saja
                val i = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                i.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                i.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Aktifkan agar Jarvis bisa mengunci / mematikan layar via suara, Sir.")
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                "Aktifkan Device Admin dulu ya Sir, lalu ulangi perintahnya."
            }
        } catch (e: Exception) {
            "Gagal mengunci: ${e.message}"
        }
    }

    private fun toggleFlashlight(on: Boolean): String {
        return try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val camId = cm.cameraIdList.firstOrNull() ?: return "HP ini tidak punya flash, Sir."
            cm.setTorchMode(camId, on)
            "OK"
        } catch (e: Exception) {
            "Gagal senter: ${e.message}"
        }
    }

    private fun volume(dir: Int): String {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                if (dir > 0) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                AudioManager.FLAG_SHOW_UI
            )
            "OK"
        } catch (e: Exception) {
            "Gagal volume: ${e.message}"
        }
    }

    private fun wakeUp(): String {
        return try {
            // Nyalakan layar via WakeLock (tanpa root/Shizuku).
            // Catatan: hanya menyalakan layar. PIN/fingerprint tetap manual.
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "jarvis:wakeup"
            )
            wl.acquire(3000)
            wl.release()
            "OK"
        } catch (e: Exception) {
            "Gagal menyalakan layar: ${e.message}"
        }
    }

    private fun getBattery(): String {
        return try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
            "BATERAI:$pct:${if (charging) 1 else 0}"
        } catch (e: Exception) {
            "Gagal baca baterai: ${e.message}"
        }
    }

    private fun setAlarm(hour: Int, minute: Int, label: String): String {
        if (hour !in 0..23 || minute !in 0..59) return "Jam tidak valid, Sir."
        return try {
            val i = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_MESSAGE, label)
                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(i)
            "OK"
        } catch (e: Exception) {
            "Gagal pasang alarm: ${e.message}"
        }
    }

    private fun dial(number: String): String {
        val digits = number.filter { it.isDigit() || it == '+' }
        return try {
            val i = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$digits"))
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
            "OK"
        } catch (e: Exception) {
            "Gagal membuka dialer: ${e.message}"
        }
    }

    private fun sms(number: String, body: String): String {
        val digits = number.filter { it.isDigit() || it == '+' }
        if (digits.length < 6) return "Nomor tidak valid, Sir."
        return try {
            val i = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$digits")).apply {
                putExtra("sms_body", body)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(i)
            "OK"
        } catch (e: Exception) {
            "Gagal membuka SMS: ${e.message}"
        }
    }

    private fun webSearch(query: String): String {
        if (query.isBlank()) return "Mau cari apa, Sir?"
        return try {
            val url = "https://www.google.com/search?q=" + Uri.encode(query)
            val i = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
            "OK"
        } catch (e: Exception) {
            "Gagal membuka browser: ${e.message}"
        }
    }

    private fun openSettingsPage(page: String): String {
        return try {
            val action = when (page) {
                "wifi" -> Settings.ACTION_WIFI_SETTINGS
                "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                "display" -> Settings.ACTION_DISPLAY_SETTINGS
                "sound" -> Settings.ACTION_SOUND_SETTINGS
                "battery" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
                "apps" -> Settings.ACTION_APPLICATION_SETTINGS
                else -> Settings.ACTION_SETTINGS
            }
            val i = Intent(action)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
            "OK"
        } catch (e: Exception) {
            "Gagal membuka pengaturan: ${e.message}"
        }
    }

    private fun accStatus(): String {
        return if (JarvisAccessibilityService.isEnabled()) "OK"
        else "BELUM: aktifkan di Settings HP > Accessibility > Jarvis > ON."
    }

    private fun overlayShow(): String {
        if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(this)) {
            return "NO_PERM:Buka Settings HP > Apps > JARVIS > Display over other apps > Allow ya Sir."
        }
        return try {
            ContextCompat.startForegroundService(
                this, Intent(this, JarvisOverlayService::class.java)
            )
            "OK"
        } catch (e: Exception) {
            "Gagal tampilkan popup: ${e.message}"
        }
    }

    private fun handsfreeWake(on: Boolean): String {        return try {
            if (on) {
                if (hfWl == null) {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    @Suppress("DEPRECATION")
                    hfWl = pm.newWakeLock(
                        PowerManager.SCREEN_DIM_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE,
                        "jarvis:handsfree"
                    ).apply { setReferenceCounted(false) }
                }
                if (hfWl?.isHeld != true) hfWl?.acquire()
            } else {
                try {
                    if (hfWl?.isHeld == true) hfWl?.release()
                } catch (_: Exception) {}
            }
            "OK"
        } catch (e: Exception) {
            "Gagal wake lock: ${e.message}"
        }
    }

    /** Minta izin microphone saat user tap orb (tanpa plugin tambahan). */
    private fun requestMic(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this, Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success("OK")
            return
        }
        micResult = result
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQ
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MIC_REQ) {
            val r = micResult
            micResult = null
            if (r == null) return
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            ) {
                r.success("OK")
            } else {
                r.success("DENIED:Buka Settings HP > Apps > JARVIS > Permissions > Microphone > Allow ya Sir.")
            }
        } else if (requestCode == NOTIF_REQ) {
            val r = notifResult
            notifResult = null
            if (r == null) return
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            ) {
                r.success("OK")
            } else {
                r.success("DENIED:Notifikasi ditolak. Popup tetap jalan, tapi tanpa notif status ya Sir.")
            }
        } else if (requestCode == CAM_REQ) {
            val r = camResult
            camResult = null
            if (r == null) return
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            ) {
                r.success("OK")
            } else {
                r.success("DENIED:Senter butuh izin kamera. Buka Settings HP > Apps > JARVIS > Permissions > Camera > Allow ya Sir.")
            }
        }
    }

    /** Izin kamera Android (untuk senter). */
    private fun requestCamera(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this, Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success("OK")
            return
        }
        camResult = result
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.CAMERA), CAM_REQ
        )
    }

    /** Daftar app ber-launcher "label|package" per baris, urut A-Z. */
    private fun listApps(): String {
        return try {
            val pm = packageManager
            val main = Intent(Intent.ACTION_MAIN, null)
            main.addCategory(Intent.CATEGORY_LAUNCHER)
            pm.queryIntentActivities(main, 0)
                .mapNotNull {
                    val label = it.loadLabel(pm)?.toString()?.trim()
                    val pkg = it.activityInfo.packageName
                    if (label.isNullOrEmpty()) null else "$label|$pkg"
                }
                .distinctBy { it.substringAfter("|") }
                .sortedBy { it.substringBefore("|").lowercase() }
                .joinToString("\n")
        } catch (e: Exception) {
            "ERR:${e.message}"
        }
    }

    /** Mode dering: normal / getar / hening (tanpa izin tambahan). */
    private fun ringerMode(mode: String): String {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.ringerMode = when (mode) {
                "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
                "silent" -> AudioManager.RINGER_MODE_SILENT
                else -> AudioManager.RINGER_MODE_NORMAL
            }
            "OK"
        } catch (e: SecurityException) {
            "Matikan DND manual dulu ya Sir (mode Jangan Ganggu mengunci mode suara)."
        } catch (e: Exception) {
            "Gagal mode suara HP: ${e.message}"
        }
    }

    /** Tombol media untuk musik (85 toggle, 126 main, 127 jeda, 87 next, 88 prev). */
    private fun mediaKey(code: Int): String {
        return try {
            val down = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, code))
            }
            val up = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, code))
            }
            sendOrderedBroadcast(down, null)
            sendOrderedBroadcast(up, null)
            "OK"
        } catch (e: Exception) {
            "Gagal kontrol musik: ${e.message}"
        }
    }
    private fun requestNotif(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) {
            result.success("OK")
            return
        }
        if (ContextCompat.checkSelfPermission(
                this, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success("OK")
            return
        }
        notifResult = result
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIF_REQ
        )
    }

    /** Pilih gambar galeri untuk ikon popup. Disalin ke file privat app. */
    private fun pickImage(result: MethodChannel.Result) {
        pickResult = result
        try {
            val i = Intent(Intent.ACTION_PICK)
            i.type = "image/*"
            @Suppress("DEPRECATION")
            startActivityForResult(i, PICK_REQ)
        } catch (e: Exception) {
            pickResult = null
            result.success("Galeri tidak tersedia: ${e.message}")
        }
    }

    @Deprecated("dipakai untuk galeri picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_REQ) {
            val r = pickResult
            pickResult = null
            if (r == null) return
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    val out = File(filesDir, "popup_icon.png")
                    contentResolver.openInputStream(data.data!!)?.use { inp ->
                        out.outputStream().use { o -> inp.copyTo(o) }
                    }
                    r.success(out.absolutePath)
                } catch (e: Exception) {
                    r.success("Gagal salin gambar: ${e.message}")
                }
            } else {
                r.success("BATAL")
            }
        }
    }
}
