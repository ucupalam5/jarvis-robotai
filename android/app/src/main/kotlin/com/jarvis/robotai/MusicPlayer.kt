package com.jarvis.robotai

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.ContextCompat

/**
 * Pemutar MP3 lokal HP (MediaStore -> MediaPlayer).
 * Dipakai MainActivity (app) + popup service. Tanpa internet.
 * Syarat: READ_MEDIA_AUDIO (33+) / READ_EXTERNAL_STORAGE (<33).
 */
object MusicPlayer {

    @Volatile private var player: MediaPlayer? = null

    fun hasPermission(ctx: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.checkSelfPermission(
                ctx, Manifest.permission.READ_MEDIA_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                ctx, Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    /** Putar lagu yang judulnya paling cocok. Return "OK:Judul" / pesan gagal. */
    @Synchronized
    fun play(ctx: Context, title: String): String {
        if (!hasPermission(ctx)) {
            return "NEED_AUDIO:Butuh izin file audio. Buka app Jarvis > Pusat Kekuasaan ya Sir."
        }
        stop()
        val words = title.lowercase().split(Regex("\\s+")).filter { it.length > 2 }
        if (words.isEmpty()) return "Judul lagunya apa, Sir?"
        return try {
            val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val proj = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE
            )
            var bestUri: Uri? = null
            var bestTitle = ""
            var bestScore = 999
            ctx.contentResolver.query(uri, proj, null, null, null)?.use { cur ->
                val iId = cur.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val iT = cur.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                var count = 0
                while (cur.moveToNext() && count < 3000) {
                    count++
                    val t = (cur.getString(iT) ?: "").lowercase()
                    if (t.isEmpty()) continue
                    var score = 999
                    for (w in words) {
                        if (t.contains(w)) {
                            score = minOf(score, t.length - w.length)
                        }
                    }
                    if (score < bestScore) {
                        bestScore = score
                        bestTitle = cur.getString(iT) ?: title
                        bestUri = ContentUris.withAppendedId(uri, cur.getLong(iId))
                    }
                }
            }
            if (bestUri == null) {
                return "Lagu $title tidak ketemu di HP, Sir. Coba: youtube $title."
            }
            val mp = MediaPlayer()
            mp.setDataSource(ctx, bestUri!!)
            mp.setOnCompletionListener {
                try {
                    it.release()
                } catch (_: Exception) {}
                if (player === it) player = null
            }
            mp.prepare()
            mp.start()
            player = mp
            "OK:$bestTitle"
        } catch (e: SecurityException) {
            "NEED_AUDIO:Butuh izin file audio. Buka app Jarvis > Pusat Kekuasaan ya Sir."
        } catch (e: Exception) {
            "Gagal putar musik: ${e.message}"
        }
    }

    @Synchronized
    fun stop() {
        try {
            player?.stop()
        } catch (_: Exception) {}
        try {
            player?.release()
        } catch (_: Exception) {}
        player = null
    }

    fun isPlaying(): Boolean {
        return try {
            player?.isPlaying == true
        } catch (_: Exception) {
            false
        }
    }
}
