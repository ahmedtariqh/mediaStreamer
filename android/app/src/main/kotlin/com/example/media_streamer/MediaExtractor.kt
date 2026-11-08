package com.example.media_streamer

import android.content.Context
import android.net.Uri
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** One local extractor for YouTube, Facebook, Instagram, TikTok, X and Vimeo. */
object MediaExtractor {
    private var initialized = false
    private val timeouts = Executors.newSingleThreadScheduledExecutor()
    val metadataExecutor = Executors.newFixedThreadPool(2)
    val controlExecutor = Executors.newSingleThreadExecutor()

    @Synchronized
    fun initialize(context: Context) {
        if (initialized) return
        YoutubeDL.getInstance().init(context.applicationContext)
        FFmpeg.getInstance().init(context.applicationContext)
        ExtractorUpdater.check(context.applicationContext)
        initialized = true
    }

    fun request(url: String): YoutubeDLRequest = YoutubeDLRequest(requireUrl(url)).apply {
        addOption("--no-playlist")
        addOption("--no-warnings")
        addOption("--socket-timeout", 20)
        addOption("--retries", 3)
        addOption("--fragment-retries", 3)
        addOption("--extractor-retries", 2)
    }

    fun extract(context: Context, url: String): Map<String, Any> {
        initialize(context)
        val request = request(url).apply {
            addOption("--dump-single-json")
            addOption("--skip-download")
        }
        val id = "metadata-${UUID.randomUUID()}"
        val timeout = timeouts.schedule({ YoutubeDL.getInstance().destroyProcessById(id) }, 60, TimeUnit.SECONDS)
        val data = try {
            JSONObject(YoutubeDL.getInstance().execute(request, id, null).out)
        } finally {
            timeout.cancel(false)
        }
        return parseInfo(data)
    }

    internal fun parseInfo(data: JSONObject): Map<String, Any> {
        require(!data.optBoolean("is_live")) { "Live streams are not supported. Try again after the broadcast ends." }
        val rawFormats = data.optJSONArray("formats")
        val formats = (0 until (rawFormats?.length() ?: 0)).mapNotNull { rawFormats?.optJSONObject(it) }
            .filter { it.optString("vcodec") != "none" || it.optString("acodec") != "none" }
        val hasVideo = formats.any { it.optString("vcodec", "none") != "none" } || data.optString("vcodec", "none") != "none"
        val hasAudio = formats.any { it.optString("acodec", "none") != "none" } || data.optString("acodec", "none") != "none"
        require(hasVideo || hasAudio) { "This link does not contain downloadable media." }
        val choices = mutableListOf<Map<String, Any>>()
        fun option(id: String, label: String, audioOnly: Boolean = false, container: String = "MP4 / MKV") {
            choices.add(mapOf("id" to id, "label" to label, "audioOnly" to audioOnly,
                "container" to container, "codec" to if (audioOnly) "Extracted audio" else "Video + original audio", "size" to 0))
        }
        if (hasVideo) {
            option("best", "Best quality")
            val maxHeight = formats.maxOfOrNull { it.optInt("height", 0) } ?: 0
            for (height in listOf(1080, 720, 480, 360)) {
                if (height <= maxHeight && formats.any {
                    it.optString("vcodec", "none") != "none" && it.optInt("height", 0) in 1..height
                }) option("video-$height", "Up to ${height}p")
            }
        }
        if (hasAudio) {
            option("audio-m4a", "M4A audio", true, "M4A")
            option("audio-mp3", "MP3 audio", true, "MP3")
        }
        return mapOf("id" to data.optString("id", "video"), "title" to data.optString("title", "Video"),
            "thumbnail" to data.optString("thumbnail", ""), "formats" to choices)
    }

    fun configureFormat(request: YoutubeDLRequest, format: String) {
        require(validFormat(format)) { "Unsupported download format." }
        if (format.startsWith("audio-")) {
            request.addOption("-f", "bestaudio/best")
            request.addOption("--extract-audio")
            request.addOption("--audio-format", format.removePrefix("audio-"))
            request.addOption("--audio-quality", "0")
        } else {
            val height = format.removePrefix("video-").toIntOrNull()
            val limit = if (height != null) "[height<=$height]" else ""
            // Prefer widely playable AVC/AAC. Fall back to the site's available
            // codecs; FFmpeg merges adaptive video and audio into a real container.
            request.addOption("-f", "bestvideo$limit[vcodec^=avc1]+bestaudio[ext=m4a]/best$limit[ext=mp4]/bestvideo$limit+bestaudio/best$limit/bestvideo$limit")
            request.addOption("--merge-output-format", "mp4/mkv")
        }
    }

    fun validFormat(format: String) = format in setOf("best", "video-1080", "video-720", "video-480", "video-360", "audio-m4a", "audio-mp3")

    fun requireUrl(text: String): String {
        val value = Regex("https?://[^\\s<>\"\\p{Cntrl}]+", RegexOption.IGNORE_CASE).find(text)?.value
            ?.trimEnd('.', ',', ';', '!', ')', ']', '}') ?: throw IllegalArgumentException("Share a valid video URL.")
        val uri = Uri.parse(value)
        require(!uri.host.isNullOrBlank() && uri.userInfo == null) { "Invalid video URL." }
        return uri.buildUpon().fragment(null).build().toString()
    }

    fun identity(url: String): String {
        val uri = Uri.parse(url)
        val host = uri.host.orEmpty().lowercase().removePrefix("www.").removePrefix("m.")
        val videoId = when {
            host == "youtu.be" -> uri.pathSegments.firstOrNull()
            host == "youtube.com" -> uri.getQueryParameter("v") ?: uri.pathSegments.let {
                if (it.firstOrNull() in listOf("shorts", "live", "embed")) it.getOrNull(1) else null
            }
            else -> null
        }
        return if (videoId != null) "youtube:$videoId" else uri.buildUpon().fragment(null).build().toString()
    }
}
