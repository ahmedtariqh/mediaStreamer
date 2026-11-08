package com.example.media_streamer

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** Refresh site extractors at most daily, before the first process is started.
 * A failed update leaves the bundled/previous engine usable. Network timeouts,
 * download size and the release's SHA-256 digest are all checked. */
internal object ExtractorUpdater {
    fun check(context: Context) {
        val prefs = context.getSharedPreferences("extractor_updates", 0)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("checkedAt", 0) < 24 * 60 * 60 * 1000L) return
        prefs.edit().putLong("checkedAt", now).apply()
        var temp: File? = null
        try {
            val metadata = connect("https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")
            val release = try { metadata.inputStream.bufferedReader().use { JSONObject(it.readText()) } }
                finally { metadata.disconnect() }
            val tag = release.getString("tag_name")
            if (tag == prefs.getString("version", "")) return
            val assets = release.getJSONArray("assets")
            val asset = (0 until assets.length()).map { assets.getJSONObject(it) }.first { it.getString("name") == "yt-dlp" }
            val url = asset.getString("browser_download_url")
            require(url.startsWith("https://github.com/yt-dlp/yt-dlp/releases/download/"))
            val expected = asset.optString("digest").removePrefix("sha256:")
            require(expected.matches(Regex("[a-fA-F0-9]{64}"))) { "Release digest unavailable; retaining installed extractor." }
            val target = File(context.noBackupFilesDir, "youtubedl-android/yt-dlp/yt-dlp")
            require(target.parentFile!!.isDirectory) { "Extractor directory is missing." }
            val updateFile = File(target.parentFile, "yt-dlp.update")
            temp = updateFile
            val binary = connect(url)
            val digest = MessageDigest.getInstance("SHA-256")
            try {
                binary.inputStream.use { input -> updateFile.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= 25 * 1024 * 1024) { "Extractor update is too large." }
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                    }
                } }
            } finally { binary.disconnect() }
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            require(actual.equals(expected, ignoreCase = true)) { "Extractor update checksum mismatch." }
            kotlin.check(updateFile.renameTo(target)) { "Could not install extractor update." }
            prefs.edit().putString("version", tag).apply()
        } catch (error: Exception) {
            Log.w("MediaStreamer", "Keeping the installed extractor: ${error.message}")
        } finally { temp?.delete() }
    }

    private fun connect(url: String): HttpURLConnection = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 5000
        readTimeout = 10000
        setRequestProperty("User-Agent", "MediaStreamer/0.2")
    }
}
