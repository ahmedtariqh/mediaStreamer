package com.example.media_streamer

import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

internal class DownloadChannel(private val activity: Activity, engine: FlutterEngine) {
    private val main = Handler(Looper.getMainLooper())
    private var pending: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null

    init {
        DownloadStore.initialize(activity)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.mediastreamer/downloads").setMethodCallHandler { call, result ->
            val args = (call.arguments as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value } ?: emptyMap()
            val work = {
                val executor = if (call.method == "extract") MediaExtractor.metadataExecutor else MediaExtractor.controlExecutor
                executor.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "extract" -> MediaExtractor.extract(activity.applicationContext, args["url"] as? String ?: "")
                            "snapshot" -> DownloadStore.snapshot()
                            "enqueue" -> { DownloadService.enqueue(activity.applicationContext, args); null }
                            "pause", "resume", "cancel", "removeHistory", "deleteFile" -> {
                                DownloadService.command(activity.applicationContext, call.method, args["id"] as? String ?: ""); null
                            }
                            else -> throw IllegalArgumentException("Unknown download method.")
                        }
                        main.post { result.success(value) }
                    } catch (error: Exception) {
                        main.post { result.error("DOWNLOAD_ERROR", error.message ?: "Download operation failed.", null) }
                    }
                }
                Unit
            }
            if (call.method == "enqueue" && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                if (pending != null) {
                    result.error("PERMISSION_PENDING", "Finish the storage permission request first.", null)
                } else {
                    pending = work
                    pendingResult = result
                    ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 8101)
                }
            } else {
                if (call.method == "enqueue" && Build.VERSION.SDK_INT >= 33 &&
                    ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8102)
                }
                work()
            }
        }
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != 8101) return
        val work = pending
        val result = pendingResult
        pending = null
        pendingResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) work?.invoke()
        else result?.error("STORAGE_PERMISSION", "Storage permission is required to save downloads on this Android version.", null)
    }
}
