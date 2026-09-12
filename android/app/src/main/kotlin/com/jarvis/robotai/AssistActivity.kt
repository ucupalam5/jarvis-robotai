package com.jarvis.robotai

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Pintu asisten default: bila Jarvis dipilih sebagai Digital assistant
 * (tombol power / usap home), langsung buka + dengar. Tanpa root, gratis.
 */
class AssistActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val open = packageManager
                .getLaunchIntentForPackage(packageName)?.apply {
                    putExtra("jarvis_autolisten", true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                } ?: Intent(this, MainActivity::class.java).apply {
                putExtra("jarvis_autolisten", true)
            }
            startActivity(open)
        } catch (_: Exception) {}
        try {
            finish()
        } catch (_: Exception) {}
    }
}
