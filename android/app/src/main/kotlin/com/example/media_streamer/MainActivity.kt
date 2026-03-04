package com.example.media_streamer

import android.content.Intent
import android.database.Cursor
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val VIEW_CHANNEL = "com.mediastreamer/view_intent"
    private val MEDIA_STORE_CHANNEL = "com.mediastreamer/media_store"
    private val MEDIA_QUERY_CHANNEL = "com.mediastreamer/media_query"
    private var initialFilePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        handleViewIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // View intent channel — open files from external apps
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIEW_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        result.success(initialFilePath)
                        initialFilePath = null
                    }
                    else -> result.notImplemented()
                }
            }

        // MediaStore scan channel — notify system about new files
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_STORE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val filePath = call.arguments as? String
                        if (filePath != null) {
                            MediaScannerConnection.scanFile(
                                this, arrayOf(filePath), null
                            ) { _, _ -> }
                            result.success(true)
                        } else {
                            result.error("INVALID_ARG", "File path is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Media query channel — query MediaStore for all media files
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_QUERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "queryMedia" -> {
                        val includeVideo = call.argument<Boolean>("includeVideo") ?: true
                        val includeAudio = call.argument<Boolean>("includeAudio") ?: true
                        try {
                            val mediaFiles = queryAllMedia(includeVideo, includeAudio)
                            result.success(mediaFiles)
                        } catch (e: Exception) {
                            result.error("QUERY_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleViewIntent(intent)

        val path = initialFilePath ?: return
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, VIEW_CHANNEL).invokeMethod("openFile", path)
        }
        initialFilePath = null
    }

    private fun handleViewIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val filePath = resolveUri(uri)
        if (filePath != null) {
            initialFilePath = filePath
        }
    }

    /**
     * Query MediaStore for all video and audio files on the device.
     * Returns a list of maps with path, name, size, modified, isVideo.
     */
    private fun queryAllMedia(includeVideo: Boolean, includeAudio: Boolean): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()

        if (includeVideo) {
            queryMediaStore(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                true
            )?.let { results.addAll(it) }
        }

        if (includeAudio) {
            queryMediaStore(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                false
            )?.let { results.addAll(it) }
        }

        // Sort by date modified descending (newest first)
        results.sortByDescending { (it["modified"] as? Long) ?: 0L }
        return results
    }

    private fun queryMediaStore(uri: Uri, isVideo: Boolean): List<Map<String, Any?>>? {
        val projection = arrayOf(
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )

        val results = mutableListOf<Map<String, Any?>>()
        var cursor: Cursor? = null

        try {
            cursor = contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
            )

            cursor?.use {
                val pathIndex = it.getColumnIndex(MediaStore.MediaColumns.DATA)
                val nameIndex = it.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeIndex = it.getColumnIndex(MediaStore.MediaColumns.SIZE)
                val modifiedIndex = it.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)

                while (it.moveToNext()) {
                    val path = if (pathIndex >= 0) it.getString(pathIndex) else null
                    val name = if (nameIndex >= 0) it.getString(nameIndex) else null
                    val size = if (sizeIndex >= 0) it.getLong(sizeIndex) else 0L
                    val modified = if (modifiedIndex >= 0) it.getLong(modifiedIndex) else 0L

                    if (path != null && name != null) {
                        results.add(mapOf(
                            "path" to path,
                            "name" to name,
                            "size" to size.toInt(),
                            "modified" to modified,
                            "isVideo" to isVideo,
                        ))
                    }
                }
            }
        } catch (e: Exception) {
            // Log but don't crash
        } finally {
            cursor?.close()
        }

        return results
    }

    private fun resolveUri(uri: Uri): String? {
        if (uri.scheme == "file") {
            return uri.path
        }

        if (uri.scheme == "content") {
            try {
                val projection = arrayOf(MediaStore.MediaColumns.DATA)
                contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                        if (idx >= 0) {
                            return cursor.getString(idx)
                        }
                    }
                }
            } catch (_: Exception) {}
            return uri.path
        }

        return uri.path
    }
}
