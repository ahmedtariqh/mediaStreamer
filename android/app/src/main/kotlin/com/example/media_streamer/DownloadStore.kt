package com.example.media_streamer

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

internal data class NativeTask(
    val id: String = UUID.randomUUID().toString(),
    val url: String,
    val format: String,
    var title: String,
    val videoId: String = "",
    val thumbnailUrl: String = "",
    @Volatile var status: String = "queued",
    var filePath: String = "",
    var contentUri: String = "",
    var progress: Double = 0.0,
    var downloadedBytes: Long = 0,
    var totalBytes: Long = 0,
    var speed: Double = 0.0,
    var error: String? = null,
    var completedAt: Long = 0,
) {
    fun map(): Map<String, Any?> = mapOf("id" to id, "url" to url, "format" to format,
        "title" to title, "videoId" to videoId, "thumbnailUrl" to thumbnailUrl,
        "status" to status, "filePath" to filePath, "contentUri" to contentUri,
        "progress" to progress, "downloadedBytes" to downloadedBytes,
        "totalBytes" to totalBytes, "speed" to speed, "error" to error, "completedAt" to completedAt)
}

/** The service and both activities use this one process-wide durable store. */
internal object DownloadStore {
    private val tasks = linkedMapOf<String, NativeTask>()
    private var context: Context? = null

    @Synchronized
    fun initialize(appContext: Context) {
        if (context != null) return
        context = appContext.applicationContext
        try {
            val data = JSONArray(context!!.getSharedPreferences("native_downloads", 0).getString("tasks", "[]"))
            for (i in 0 until data.length()) {
                try {
                    val obj = data.getJSONObject(i)
                    val interrupted = obj.optString("status") in listOf("queued", "downloading")
                    val task = NativeTask(id = obj.getString("id"), url = obj.getString("url"),
                        format = obj.getString("format"), title = obj.optString("title", "Video"),
                        videoId = obj.optString("videoId"), thumbnailUrl = obj.optString("thumbnailUrl"),
                        status = if (interrupted) "paused" else obj.optString("status", "failed"),
                        filePath = obj.optString("filePath"), contentUri = obj.optString("contentUri"),
                        completedAt = obj.optLong("completedAt"),
                        error = if (interrupted) "Download interrupted. Tap resume to continue." else obj.optString("error").takeIf { it.isNotEmpty() && it != "null" })
                    tasks[task.id] = task
                } catch (_: Exception) { /* Keep valid entries if one is damaged. */ }
            }
        } catch (_: Exception) { /* A damaged store must not prevent app startup. */ }
    }

    @Synchronized
    fun add(url: String, format: String, title: String, videoId: String, thumbnail: String): NativeTask {
        require(MediaExtractor.validFormat(format)) { "Unsupported download format." }
        val key = MediaExtractor.identity(url)
        val duplicate = tasks.values.any { MediaExtractor.identity(it.url) == key && it.format == format &&
            (it.status in listOf("queued", "downloading", "paused") || it.status == "completed" && File(it.filePath).exists()) }
        require(!duplicate) { "This format is already downloading or saved. Choose another format or remove the saved file first." }
        val task = NativeTask(url = url, format = format, title = title.ifBlank { "Video" }, videoId = videoId, thumbnailUrl = thumbnail)
        tasks[task.id] = task
        persist()
        return task
    }

    @Synchronized
    fun get(id: String): NativeTask? = tasks[id]

    @Synchronized
    fun update(id: String, save: Boolean = true, update: (NativeTask) -> Unit) {
        tasks[id]?.let(update)
        if (save) persist()
    }

    @Synchronized
    fun tryStart(id: String): Boolean {
        val task = tasks[id] ?: return false
        if (task.status != "queued") return false
        task.status = "downloading"
        task.error = null
        persist()
        return true
    }

    @Synchronized
    fun snapshot(): List<Map<String, Any?>> = tasks.values.filter { it.status != "cancelled" }.map { task ->
        task.map() + ("fileExists" to (task.status == "completed" && File(task.filePath).exists()))
    }

    @Synchronized
    fun hasRunning() = tasks.values.any { it.status in listOf("queued", "downloading") }

    @Synchronized
    fun remove(id: String) {
        val task = tasks[id] ?: return
        require(task.status !in listOf("queued", "downloading", "paused")) { "Cancel the download first." }
        tasks.remove(id)
        persist()
    }

    @Synchronized
    private fun persist() {
        val values = tasks.values.toList()
        context!!.getSharedPreferences("native_downloads", 0).edit()
            .putString("tasks", JSONArray(values.map { JSONObject(it.map()) }).toString()).apply()
    }
}
