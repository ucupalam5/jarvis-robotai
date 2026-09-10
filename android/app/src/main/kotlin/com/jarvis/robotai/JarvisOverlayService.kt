package com.jarvis.robotai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
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
import java.io.File

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
    private var lastX = 0
    private var lastY = 120

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        startFg()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        rebuildOverlay()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
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
                        // Tap popup = buka app + LANGSUNG dengar (tanpa tap orb).
                        try {
                            packageManager.getLaunchIntentForPackage(packageName)?.let {
                                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                it.putExtra("jarvis_autolisten", true)
                                startActivity(it)
                            }
                        } catch (_: Exception) {}
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
}
