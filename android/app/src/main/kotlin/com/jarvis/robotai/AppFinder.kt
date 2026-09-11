package com.jarvis.robotai

import android.content.pm.PackageManager

/**
 * Pencari aplikasi cerdas dipakai MainActivity + popup service.
 * Urutan: package persis -> mengandung keyword -> label terdekat (Levenshtein).
 */
object AppFinder {

    fun levenshtein(a: String, b: String): Int {
        if (a == b) return 0
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var prev = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            val cur = IntArray(b.length + 1)
            cur[0] = i
            for (j in 1..b.length) {
                cur[j] = minOf(
                    prev[j] + 1,
                    cur[j - 1] + 1,
                    prev[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1
                )
            }
            prev = cur
        }
        return prev[b.length]
    }

    /** Return Pair(label, package) atau null bila tak ketemu. */
    fun findBest(pm: PackageManager, keyword: String): Pair<String, String>? {
        val kw = keyword.trim()
        if (kw.isEmpty()) return null
        // 1) package persis
        try {
            val info = pm.getApplicationInfo(kw, 0)
            val label = pm.getApplicationLabel(info)?.toString() ?: kw
            if (pm.getLaunchIntentForPackage(kw) != null) return Pair(label, kw)
        } catch (_: Exception) {}
        val apps = try {
            pm.getInstalledApplications(0)
        } catch (_: Exception) {
            return null
        }
        // 2) mengandung keyword (abaikan spasi)
        val flat = kw.replace(" ", "").lowercase()
        for (app in apps) {
            val label = try {
                pm.getApplicationLabel(app)?.toString() ?: continue
            } catch (_: Exception) {
                continue
            }
            if (app.packageName.contains(kw, ignoreCase = true) ||
                label.contains(kw, ignoreCase = true) ||
                (flat.isNotEmpty() &&
                    (app.packageName.replace(" ", "")
                        .contains(flat, ignoreCase = true) ||
                        label.replace(" ", "")
                            .contains(flat, ignoreCase = true)))
            ) {
                if (pm.getLaunchIntentForPackage(app.packageName) != null) {
                    return Pair(label, app.packageName)
                }
            }
        }
        // 3) label terdekat (toleransi salah-dengar STT)
        var bestLabel: String? = null
        var bestPkg: String? = null
        var bestScore = 999
        val keys = kw.lowercase().split(Regex("\\s+")).filter { it.length > 2 }
        if (keys.isEmpty()) return null
        for (app in apps) {
            val label = try {
                pm.getApplicationLabel(app)?.toString() ?: continue
            } catch (_: Exception) {
                continue
            }
            val pkgFlat = app.packageName.lowercase()
            val labelFlat = label.lowercase().replace(" ", "")
            if (labelFlat.isEmpty()) continue
            for (w in keys) {
                // cocok dengan label ATAU nama package (misal "gopay", "ovo")
                val dLabel = levenshtein(w, labelFlat)
                val pkgTail = pkgFlat.substringAfterLast(".")
                val dPkg = levenshtein(w, pkgTail)
                val d = minOf(dLabel, dPkg)
                val refLen = minOf(labelFlat.length, 8)
                val limit = if (refLen <= 4) 1 else 2
                val starts =
                    labelFlat.startsWith(w) || pkgTail.startsWith(w)
                if ((d <= limit || starts) && d < bestScore) {
                    if (pm.getLaunchIntentForPackage(app.packageName) != null) {
                        bestScore = d
                        bestLabel = label
                        bestPkg = app.packageName
                    }
                }
            }
        }
        return if (bestPkg != null) Pair(bestLabel!!, bestPkg) else null
    }
}
