package com.jarvis.robotai

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku

class MainActivity : FlutterActivity() {
    private val CHANNEL = "jarvis/control"
    private val SHIZUKU_REQ = 1001

    private val shizukuListener = Shizuku.OnRequestPermissionResultListener { _, grantResult ->
        // hasil izin Shizuku, tidak perlu aksi khusus, Flutter bisa cek ulang via shizukuCheck
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        try { Shizuku.addRequestPermissionResultListener(shizukuListener) } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try { Shizuku.removeRequestPermissionResultListener(shizukuListener) } catch (_: Exception) {}
        super.onDestroy()
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
                    // --- Shizuku (ADB tanpa root) ---
                    "shizukuCheck" -> result.success(shizukuStatus())
                    "shizukuRequest" -> {
                        ShizukuHelper.requestPermission(SHIZUKU_REQ)
                        result.success("Permintaan izin Shizuku dikirim. Cek app Shizuku ya Sir.")
                    }
                    "shizukuExec" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        // jalan di background biar tidak ANR
                        Thread {
                            val r = ShizukuHelper.exec(cmd)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }
                    "shizukuWakeUnlock" -> {
                        val pin = call.argument<String>("pin") ?: ""
                        Thread {
                            val r = ShizukuHelper.wakeAndUnlock(pin)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }
                    "shizukuTap" -> {
                        val x = call.argument<Int>("x") ?: 935
                        val y = call.argument<Int>("y") ?: 950
                        Thread {
                            val r = ShizukuHelper.tap(x, y)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }
                    "shizukuType" -> {
                        val text = call.argument<String>("text") ?: ""
                        Thread {
                            val r = ShizukuHelper.typeText(text)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openApp(keyword: String): String {
        return try {
            val pm = packageManager
            // 1) langsung sebagai package name
            var intent = pm.getLaunchIntentForPackage(keyword)
            // 2) cari aplikasi yang mengandung keyword
            if (intent == null) {
                val apps = pm.getInstalledApplications(0)
                val found = apps.firstOrNull {
                    it.packageName.contains(keyword, ignoreCase = true) ||
                    (pm.getApplicationLabel(it)?.toString()
                        ?.contains(keyword, ignoreCase = true) == true)
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

    private fun shizukuStatus(): String {
        return try {
            val alive = ShizukuHelper.isBinderAlive()
            val granted = ShizukuHelper.isGranted()
            when {
                !alive -> "NONAKTIF: Buka app Shizuku > Start (pairing WiFi, tanpa PC bisa)."
                !granted -> "BELUM_IZIN: Buka Shizuku > Authorized apps > izinkan com.jarvis.robotai."
                else -> "OK"
            }
        } catch (e: Exception) {
            "Gagal cek Shizuku: ${e.message}"
        }
    }
}
