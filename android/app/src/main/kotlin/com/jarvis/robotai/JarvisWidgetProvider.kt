package com.jarvis.robotai

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Widget home screen Jarvis: tap ikon = buka app + langsung dengar.
 * Cara pasang: tahan home screen > Widget > Jarvis.
 */
class JarvisWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray
    ) {
        for (id in ids) {
            try {
                val open = context.packageManager
                    .getLaunchIntentForPackage(context.packageName)?.apply {
                        putExtra("jarvis_autolisten", true)
                    } ?: Intent(context, MainActivity::class.java).apply {
                    putExtra("jarvis_autolisten", true)
                }
                val pi = PendingIntent.getActivity(
                    context, 0, open,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )
                val views = RemoteViews(context.packageName, R.layout.widget_jarvis)
                views.setOnClickPendingIntent(R.id.widget_root, pi)
                manager.updateAppWidget(id, views)
            } catch (_: Exception) {}
        }
    }
}
