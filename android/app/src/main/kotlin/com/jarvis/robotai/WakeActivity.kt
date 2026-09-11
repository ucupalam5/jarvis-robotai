package com.jarvis.robotai

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.WindowManager

/**
 * Activity transparan yang hanya bertugas MENYALAKAN layar +
 * membuka kunci geser, lalu tutup sendiri ~1 detik.
 * Dipanggil oleh wakeUp() (aplikasi) dan popup auto-dengar (service).
 * Catatan: PIN/pola/fingerprint tetap harus manual (aturan Android).
 */
class WakeActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            if (Build.VERSION.SDK_INT >= 27) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }
            try {
                val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                if (Build.VERSION.SDK_INT >= 26) {
                    km.requestDismissKeyguard(this, null)
                }
            } catch (_: Exception) {}
        } catch (_: Exception) {}
        try {
            window.decorView.postDelayed({
                try {
                    finish()
                } catch (_: Exception) {}
            }, 1200)
        } catch (_: Exception) {
            try {
                finish()
            } catch (_: Exception) {}
        }
    }
}
