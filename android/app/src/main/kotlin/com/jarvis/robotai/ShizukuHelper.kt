package com.jarvis.robotai

import android.content.pm.PackageManager
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Helper Shizuku: jalankan shell level-ADB tanpa root.
 * Contoh: input tap/swipe/text/keyevent, am start, cmd statusbar.
 * Syarat: install app Shizuku, Start via pairing WiFi (tanpa PC bisa,
 * Android 11+), lalu izinkan com.jarvis.robotai di Authorized apps.
 */
object ShizukuHelper {

    fun isBinderAlive(): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (_: Exception) {
            false
        }
    }

    fun isGranted(): Boolean {
        return try {
            if (!isBinderAlive()) return false
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }

    fun requestPermission(code: Int) {
        try {
            if (isBinderAlive() && !isGranted()) {
                Shizuku.requestPermission(code)
            }
        } catch (_: Exception) {}
    }

    /** Jalankan 1 perintah shell via Shizuku. Timeout ~10 detik. */
    fun exec(cmd: String): String {
        if (!isBinderAlive()) return "Shizuku belum aktif. Buka app Shizuku > Start."
        if (!isGranted()) return "Izin Shizuku belum diberikan. Buka Shizuku > Authorized apps > izinkan Jarvis."
        return try {
            val process = Shizuku.newProcess(arrayOf("sh", "-c", cmd), null, null)
            val out = StringBuilder()
            BufferedReader(InputStreamReader(process.inputStream)).use { r ->
                var line = r.readLine()
                var count = 0
                while (line != null && count < 50) {
                    out.appendLine(line)
                    line = r.readLine()
                    count++
                }
            }
            try {
                val finished = process.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)
                if (!finished) return "OK"
            } catch (_: Exception) {}
            process.destroy()
            "OK"
        } catch (e: SecurityException) {
            "Izin Shizuku ditolak: ${e.message}"
        } catch (e: Exception) {
            "Gagal Shizuku exec: ${e.message}"
        }
    }

    /** Nyalakan layar + swipe + coba ketik PIN (best-effort per merk HP). */
    fun wakeAndUnlock(pin: String): String {
        var r = exec("input keyevent KEYCODE_WAKEUP")
        if (r.startsWith("Shizuku") || r.startsWith("Izin")) return r
        Thread.sleep(700)
        exec("input swipe 500 1500 500 500 300")
        val safePin = pin.filter { it.isDigit() }
        if (safePin.isNotEmpty()) {
            Thread.sleep(700)
            exec("input text $safePin")
            Thread.sleep(400)
            exec("input keyevent KEYCODE_ENTER")
            return "OK: layar dinyalakan + PIN dicoba. Kalau tidak kebuka, tempel fingerprint ya Sir (blokir keamanan Android)."
        }
        return "OK"
    }

    fun tap(x: Int, y: Int): String = exec("input tap $x $y")

    fun typeText(text: String): String {
        val safe = text.replace("'", "").replace("\"", "").replace("\n", " ").take(200)
        if (safe.isBlank()) return "Teks kosong, Sir."
        return exec("input text '${safe.replace(" ", "%s")}'")
    }
}
