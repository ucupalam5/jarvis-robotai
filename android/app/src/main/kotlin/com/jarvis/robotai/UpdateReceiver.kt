package com.jarvis.robotai

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

/**
 * Menunggu unduhan APK update selesai lalu membuka installer sistem.
 * Didaftarkan di Manifest untuk action DOWNLOAD_COMPLETE.
 */
class UpdateReceiver : BroadcastReceiver() {

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        try {
            val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
            val sp = ctx.getSharedPreferences("jarvis_upd", Context.MODE_PRIVATE)
            if (id == -1L || id != sp.getLong("last_download", -2)) return
            val dm = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.query(DownloadManager.Query().setFilterById(id))?.use { cur ->
                if (!cur.moveToFirst()) return
                val status = cur.getInt(
                    cur.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                )
                if (status != DownloadManager.STATUS_SUCCESSFUL) return
            }
            val apk = File(
                ctx.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS),
                "jarvis-update.apk"
            )
            if (!apk.exists()) return
            val uri: Uri = FileProvider.getUriForFile(
                ctx, ctx.packageName + ".fileprovider", apk
            )
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            ctx.startActivity(view)
        } catch (_: Exception) {}
    }
}
