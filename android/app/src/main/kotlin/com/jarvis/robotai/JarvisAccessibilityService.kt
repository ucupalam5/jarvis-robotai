package com.jarvis.robotai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.File
import java.io.FileOutputStream

/**
 * Otomatisasi Jarvis TANPA root / TANPA aplikasi tambahan.
 * Syarat sekali saja: Settings HP > Accessibility > Jarvis > ON.
 * Bisa: tap koordinat, swipe, isi teks, klik tombol berdasar label
 * (misal tombol "Kirim" WA), tombol back/home.
 */
class JarvisAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile private var instance: JarvisAccessibilityService? = null
        @Volatile private var shotCb: ((String) -> Unit)? = null

        fun isEnabled(): Boolean = instance != null

        fun globalBackAndHome() {
            try {
                instance?.performGlobalAction(GLOBAL_ACTION_BACK)
                Thread.sleep(300)
                instance?.performGlobalAction(GLOBAL_ACTION_HOME)
            } catch (_: Exception) {}
        }

        /** Tap koordinat relatif 0..1000 (aman beda ukuran layar). */
        fun tapAt(x1000: Int, y1000: Int): String {
            val s = instance
                ?: return "Aksesibilitas belum aktif. Aktifkan: Settings HP > Accessibility > Jarvis > ON."
            return try {
                val dm = s.resources.displayMetrics
                val x = (x1000 / 1000f * dm.widthPixels)
                    .coerceIn(0f, dm.widthPixels.toFloat())
                val y = (y1000 / 1000f * dm.heightPixels)
                    .coerceIn(0f, dm.heightPixels.toFloat())
                val path = Path().apply { moveTo(x, y) }
                val g = GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, 80))
                    .build()
                if (s.dispatchGesture(g, null, null)) "OK"
                else "Gesture ditolak sistem."
            } catch (e: Exception) {
                "Gagal tap: ${e.message}"
            }
        }

        /** Swipe atas (reels berikutnya / buka kunci geser / scroll). */
        fun swipeUp(): String {
            val s = instance
                ?: return "Aksesibilitas belum aktif. Aktifkan: Settings HP > Accessibility > Jarvis > ON."
            return try {
                val dm = s.resources.displayMetrics
                val path = Path().apply {
                    moveTo(dm.widthPixels / 2f, dm.heightPixels * 0.8f)
                    lineTo(dm.widthPixels / 2f, dm.heightPixels * 0.3f)
                }
                val g = GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, 300))
                    .build()
                if (s.dispatchGesture(g, null, null)) "OK"
                else "Gesture ditolak sistem."
            } catch (e: Exception) {
                "Gagal swipe: ${e.message}"
            }
        }

        /** Swipe bawah (reels sebelumnya / scroll atas). */
        fun swipeDown(): String {
            val s = instance
                ?: return "Aksesibilitas belum aktif. Aktifkan: Settings HP > Accessibility > Jarvis > ON."
            return try {
                val dm = s.resources.displayMetrics
                val path = Path().apply {
                    moveTo(dm.widthPixels / 2f, dm.heightPixels * 0.3f)
                    lineTo(dm.widthPixels / 2f, dm.heightPixels * 0.8f)
                }
                val g = GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, 300))
                    .build()
                if (s.dispatchGesture(g, null, null)) "OK"
                else "Gesture ditolak sistem."
            } catch (e: Exception) {
                "Gagal swipe: ${e.message}"
            }
        }

        /** Isi teks ke kolom yang sedang fokus (fallback: kolom edit pertama). */
        fun typeText(text: String): String {
            val s = instance
                ?: return "Aksesibilitas belum aktif. Aktifkan: Settings HP > Accessibility > Jarvis > ON."
            if (text.isBlank()) return "Teks kosong, Sir."
            return try {
                val root = s.rootInActiveWindow ?: return "Tidak ada jendela aktif."
                val target = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                    ?: findEditable(root)
                    ?: return "Tidak ada kolom teks. Tap kolom chat dulu ya Sir."
                val args = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        text
                    )
                }
                if (target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) "OK"
                else "Gagal mengisi teks."
            } catch (e: Exception) {
                "Gagal mengetik: ${e.message}"
            }
        }

        /** Klik tombol "Kirim"/"Send" (untuk kirim WA otomatis). */
        fun clickSend(): String {
            val s = instance
                ?: return "Aksesibilitas belum aktif. Aktifkan: Settings HP > Accessibility > Jarvis > ON."
            return try {
                val root = s.rootInActiveWindow ?: return "Tidak ada jendela aktif."
                for (label in listOf("Kirim", "Send")) {
                    val nodes = root.findAccessibilityNodeInfosByText(label)
                    for (n in nodes) {
                        var cur: AccessibilityNodeInfo? = n
                        var depth = 0
                        while (cur != null && depth < 4) {
                            if (cur.isClickable) {
                                if (cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return "OK"
                                break
                            }
                            cur = cur.parent
                            depth++
                        }
                    }
                }
                "Tombol Kirim tidak ketemu. Pastikan chat WA terbuka ya Sir."
            } catch (e: Exception) {
                "Gagal klik kirim: ${e.message}"
            }
        }

        private fun findEditable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (node.isEditable) return node
            for (i in 0 until node.childCount) {
                val c = node.getChild(i) ?: continue
                val r = findEditable(c)
                if (r != null) return r
            }
            return null
        }

        /**
         * Screenshot layar TANPA dialog (khusus AccessibilityService, Android 11+).
         * Callback: path file JPG, atau "ERR:pesan".
         */
        fun screenshot(cb: (String) -> Unit) {
            val s = instance
            if (s == null) {
                cb("ERR:Aksesibilitas belum aktif. Aktifkan: Settings HP > Accessibility > Jarvis > ON.")
                return
            }
            if (Build.VERSION.SDK_INT < 30) {
                cb("ERR:Lihat layar butuh Android 11+ ya Sir.")
                return
            }
            if (shotCb != null) {
                cb("ERR:Sibuk, coba lagi sebentar ya Sir.")
                return
            }
            shotCb = cb
            try {
                s.takeScreenshot(
                    Display.DEFAULT_DISPLAY,
                    s.mainExecutor,
                    object : TakeScreenshotCallback {
                        override fun onSuccess(result: ScreenshotResult) {
                            shotCb = null
                            try {
                                val bmp = Bitmap.wrapHardwareBuffer(
                                    result.hardwareBuffer, result.colorSpace
                                )
                                try {
                                    if (bmp == null) {
                                        cb("ERR:Gagal baca gambar layar.")
                                        return
                                    }
                                    val out = File(s.cacheDir, "jarvis_shot.jpg")
                                    FileOutputStream(out).use {
                                        bmp.compress(
                                            Bitmap.CompressFormat.JPEG, 70, it
                                        )
                                    }
                                    cb(out.absolutePath)
                                } finally {
                                    try {
                                        result.hardwareBuffer.close()
                                    } catch (_: Exception) {}
                                }
                            } catch (e: Exception) {
                                cb("ERR:Gagal simpan screenshot: ${e.message}")
                            }
                        }

                        override fun onFailure(code: Int) {
                            shotCb = null
                            cb("ERR:Screenshot ditolak sistem ($code).")
                        }
                    }
                )
            } catch (e: Exception) {
                shotCb = null
                cb("ERR:Screenshot gagal: ${e.message}")
            }
        }
    }

    override fun onServiceConnected() { instance = this }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}
    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }
}
