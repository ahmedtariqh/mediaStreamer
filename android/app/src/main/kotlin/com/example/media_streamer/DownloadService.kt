package com.example.media_streamer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.yausername.youtubedl_android.YoutubeDL
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Downloads survive activity/Flutter engine destruction. One worker bounds
 * CPU, network and FFmpeg memory use; subsequent downloads remain queued. */
class DownloadService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    private val scheduled = ConcurrentHashMap.newKeySet<String>()
    private val threads = ConcurrentHashMap<String, Thread>()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var shuttingDown = false
    private var wakeLock: PowerManager.WakeLock? = null
    private val wakeLockMonitor = Any()

    override fun onCreate() {
        super.onCreate()
        instance = this
        DownloadStore.initialize(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Required before any extraction, disk work or plugin initialization.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification("Preparing download"), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification("Preparing download"))
        }
        val id = intent?.getStringExtra("id")
        if (id == null) stopSelf(startId) else schedule(id)
        return START_NOT_STICKY
    }

    private fun schedule(id: String) {
        if (shuttingDown || !scheduled.add(id)) return
        worker.execute {
            threads[id] = Thread.currentThread()
            try {
                if (DownloadStore.get(id)?.status != "queued") return@execute
                runDownload(id)
            } catch (error: Exception) {
                DownloadStore.update(id) { task ->
                    if (task.status in listOf("downloading", "queued")) {
                        task.status = "failed"
                        task.error = friendlyError(error)
                    }
                }
                val task = DownloadStore.get(id)
                if (task?.status == "failed") showResult(task, "Download failed: ${task.error}")
            } finally {
                // Cancellation can interrupt a worker before a process is registered.
                // execute() also destroys its process when its thread is interrupted.
                synchronized(threads) {
                    threads.remove(id)
                    Thread.interrupted()
                }
                scheduled.remove(id)
                val task = DownloadStore.get(id)
                if (task?.status == "cancelled") DownloadPublisher.staging(this, id).deleteRecursively()
                if (!shuttingDown && task?.status == "queued") schedule(id)
                main.post {
                    if (scheduled.isEmpty() && !DownloadStore.hasRunning()) {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopSelf()
                    }
                }
            }
        }
    }

    private fun runDownload(id: String) {
        MediaExtractor.initialize(this)
        val task = DownloadStore.get(id) ?: return
        if (!DownloadStore.tryStart(id)) return
        val directory = DownloadPublisher.staging(this, id)
        check(directory.isDirectory || directory.mkdirs()) { "Could not create download directory." }
        val request = MediaExtractor.request(task.url).apply {
            MediaExtractor.configureFormat(this, task.format)
            addOption("--continue")
            addOption("--newline")
            addOption("--no-simulate")
            addOption("--concurrent-fragments", 2)
            addOption("--output", "${directory.absolutePath}/media.%(ext)s")
            addOption("--print", "after_move:filepath")
            addOption("--progress")
            addOption("--progress-template", "download:MS_PROGRESS:%(progress.downloaded_bytes)s:%(progress.total_bytes,progress.total_bytes_estimate)s:%(progress.speed)s")
        }
        synchronized(wakeLockMonitor) {
            wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MediaStreamer:download").apply {
                    acquire(6 * 60 * 60 * 1000L)
                }
        }
        try {
            var lastUpdate = 0L
            val response = YoutubeDL.getInstance().execute(request, id) { _, _, line ->
                val now = System.currentTimeMillis()
                if (now - lastUpdate >= 500 && line.startsWith("MS_PROGRESS:")) {
                    lastUpdate = now
                    val parts = line.split(':')
                    DownloadStore.update(id, save = false) {
                        it.downloadedBytes = parts.getOrNull(1)?.toDoubleOrNull()?.toLong() ?: 0
                        it.totalBytes = parts.getOrNull(2)?.toDoubleOrNull()?.toLong() ?: 0
                        it.speed = parts.getOrNull(3)?.toDoubleOrNull()?.takeIf { speed -> speed.isFinite() } ?: 0.0
                        it.progress = if (it.totalBytes > 0) (it.downloadedBytes.toDouble() / it.totalBytes).coerceIn(0.0, 0.99) else 0.0
                    }
                    updateNotification(task)
                }
            }
            // Only accept a completed file reported by yt-dlp inside this task's
            // private staging directory; never publish .part or fragment files.
            val source = response.out.lineSequence().map { File(it.trim()) }.lastOrNull {
                it.isFile && it.canonicalFile.parentFile == directory.canonicalFile &&
                    it.extension !in listOf("part", "ytdl", "temp")
            } ?: error("The extractor did not produce a complete media file.")
            if (DownloadStore.get(id)?.status != "downloading") return
            // Publishing can copy a large file. Never hold the store monitor
            // during IO: pause/cancel and Android's timeout callback must remain responsive.
            val (path, uri) = DownloadPublisher.publish(this, task, source)
            var accepted = false
            DownloadStore.update(id) {
                if (it.status != "downloading") return@update
                accepted = true
                it.filePath = path
                it.contentUri = uri
                it.status = "completed"
                it.completedAt = System.currentTimeMillis()
                it.progress = 1.0
                it.downloadedBytes = source.length()
                it.totalBytes = source.length()
                it.speed = 0.0
            }
            if (!accepted) {
                DownloadPublisher.delete(this, task.copy(filePath = path, contentUri = uri))
                return
            }
            if (task.status == "completed") {
                directory.deleteRecursively()
                showResult(task, "Saved to Downloads/MediaStreamer")
            }
        } finally {
            releaseWakeLock()
        }
    }

    private fun notification(text: String, task: NativeTask? = null): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(task?.title ?: "MediaStreamer")
            .setContentText(text).setContentIntent(open).setOnlyAlertOnce(true)
            .setOngoing(true).setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (task != null) {
            builder.setProgress(100, (task.progress * 100).toInt(), task.totalBytes <= 0)
            for ((action, label) in listOf("pause" to "Pause", "cancel" to "Cancel")) {
                val intent = Intent(this, DownloadActionReceiver::class.java).putExtra("id", task.id).putExtra("command", action)
                val pending = PendingIntent.getBroadcast(this, (task.id + action).hashCode(), intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                builder.addAction(0, label, pending)
            }
        }
        return builder.build()
    }

    private fun updateNotification(task: NativeTask) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID,
            notification("${(task.progress * 100).toInt()}% · ${(task.speed / 1024).toInt()} KB/s", task))
    }

    private fun showResult(task: NativeTask, message: String) {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        getSystemService(NotificationManager::class.java).notify(task.id.hashCode(),
            NotificationCompat.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(task.title).setContentText(message).setContentIntent(open).setAutoCancel(true).build())
    }

    private fun interrupt(id: String) {
        synchronized(threads) { threads[id]?.interrupt() }
        // The wrapper destroys its process when execute's waiting thread is
        // interrupted. Do not schedule a later kill under this reusable ID:
        // it could otherwise kill a newly resumed download.
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopWorkers("Android stopped this long-running download. Tap resume to continue.")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopWorkers(message: String) {
        shuttingDown = true
        for (id in scheduled) {
            DownloadStore.update(id) { if (it.status in listOf("queued", "downloading")) { it.status = "paused"; it.error = message } }
            interrupt(id)
        }
        worker.shutdownNow()
    }

    private fun releaseWakeLock() = synchronized(wakeLockMonitor) {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    override fun onDestroy() {
        stopWorkers("Download interrupted. Tap resume to continue.")
        releaseWakeLock()
        if (instance === this) instance = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL = "native_downloads"
        private const val NOTIFICATION_ID = 8100
        @Volatile private var instance: DownloadService? = null

        internal fun enqueue(context: Context, args: Map<String, Any?>) {
            DownloadStore.initialize(context)
            val url = MediaExtractor.requireUrl(args["url"] as? String ?: "")
            val task = DownloadStore.add(url, args["format"] as? String ?: "best", args["title"] as? String ?: "Video",
                args["videoId"] as? String ?: "", args["thumbnailUrl"] as? String ?: "")
            start(context, task.id)
        }

        private fun start(context: Context, id: String) {
            try {
                ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java).putExtra("id", id))
            } catch (error: Exception) {
                DownloadStore.update(id) { it.status = "failed"; it.error = "Could not start background download: ${error.message}" }
                throw error
            }
        }

        internal fun command(context: Context, command: String, id: String) {
            DownloadStore.initialize(context)
            val task = DownloadStore.get(id) ?: return
            when (command) {
                "pause", "cancel" -> {
                    DownloadStore.update(id) {
                        if (it.status in listOf("queued", "downloading", "paused", "failed")) {
                            it.status = if (command == "pause") "paused" else "cancelled"
                            it.speed = 0.0
                        }
                    }
                    instance?.interrupt(id)
                    if (command == "cancel" && instance?.scheduled?.contains(id) != true) DownloadPublisher.staging(context, id).deleteRecursively()
                }
                "resume" -> {
                    if (task.status !in listOf("paused", "failed")) return
                    DownloadStore.update(id) { it.status = "queued"; it.error = null }
                    start(context, id)
                }
                "removeHistory" -> DownloadStore.remove(id)
                "deleteFile" -> {
                    require(task.status == "completed") { "Download has not completed." }
                    DownloadPublisher.delete(context, task)
                }
                else -> throw IllegalArgumentException("Unknown download command.")
            }
        }

        private fun friendlyError(error: Exception): String {
            val message = error.message.orEmpty()
            return when {
                message.contains("private", true) || message.contains("login", true) || message.contains("sign in", true) ->
                    "This video requires login or is private. Try a publicly accessible video."
                message.contains("Unsupported URL", true) -> "This link is not supported or contains no downloadable video."
                message.contains("No space", true) -> "Your device has insufficient free space."
                else -> message.takeLast(600).ifBlank { "Download interrupted. Check your connection and retry." }
            }
        }
    }
}
