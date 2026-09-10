package com.jarvis.robotai

import android.content.pm.PackageManager
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Helper Shizuku: jalankan shell ADB tanpa root.
 * Contoh: input tap, input text, input keyevent, am start, cmd statusbar.
 * Harus: install app Shizuku, pairing via WiFi (tanpa PC bisa di Android 11+),
 * lalu grant izin untuk com.jarvis.robotai di app Shizuku.
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

    /** Jalankan 1 perintah shell via Shizuku, kembalikan output. Timeout ~10 detik. */
    fun exec(cmd: String): String {
        if (!isBinderAlive()) return "Shizuku belum aktif. Buka app Shizuku > Start."
        if (!isGranted()) return "Izin Shizuku belum diberikan. Buka Shizuku > Authorized apps > izinkan Jarvis."
        return try {
            // newProcess butuh permission Shizuku, jalan di thread caller.
            // MainActivity memanggil ini dari background thread agar tidak ANR.
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
            val exit = try {
                // tunggu maksimal 10 detik
                val finished = process.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)
                if (finished) process.exitValue() else -1
            } catch (_: Exception) { 0 }
            process.destroy()
            if (exit == 0) "OK" else if (out.isEmpty()) "OK" else "OK: $out"
        } catch (e: SecurityException) {
            "Izin Shizuku ditolak: ${e.message}"
        } catch (e: Exception) {
            "Gagal Shizuku exec: ${e.message}"
        }
    }

    /** Nyalakan layar + swipe + ketik PIN (best-effort, tergantung merk HP). */
    fun wakeAndUnlock(pin: String): String {
        var r = exec("input keyevent KEYCODE_WAKEUP")
        if (r.startsWith("Shizuku") || r.startsWith("Izin")) return r
        Thread.sleep(700)
        exec("input swipe 500 1500 500 500 300")
        if (pin.isNotEmpty()) {
            Thread.sleep(700)
            // PIN hanya angka yang aman untuk input text
            val safePin = pin.filter { it.isDigit() }
            if (safePin.isNotEmpty()) {
                exec("input text $safePin")
                Thread.sleep(400)
                exec("input keyevent KEYCODE_ENTER")
                return "OK: layar dinyalakan + PIN dicoba. Kalau tidak kebuka, tempel fingerprint ya Sir (blokir keamanan Android)."
            }
        }
        return "OK"
    }

    /** Tap koordinat (untuk tombol Kirim WA otomatis, dsb). x y 0-1000. */
    fun tap(x: Int, y: Int): String = exec("input tap $x $y")

    /** Ketik teks via ADB (untuk auto-isi chat bila diizinkan sistem). */
    fun typeText(text: String): String {
        // escape sederhana agar aman di shell
        val safe = text.replace("'", "").replace("\"", "").replace("\n", " ").take(200)
        return exec("input text '${safe.replace(" ", "%s")}'")
    }
}
