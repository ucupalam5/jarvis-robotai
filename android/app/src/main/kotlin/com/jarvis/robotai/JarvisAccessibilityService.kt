package com.jarvis.robotai

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

class JarvisAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile private var instance: JarvisAccessibilityService? = null
        fun globalBackAndHome() {
            try {
                instance?.performGlobalAction(GLOBAL_ACTION_BACK)
                Thread.sleep(300)
                instance?.performGlobalAction(GLOBAL_ACTION_HOME)
            } catch (_: Exception) {}
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
