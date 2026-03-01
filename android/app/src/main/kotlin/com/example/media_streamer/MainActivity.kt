package com.example.media_streamer

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.mediastreamer/view_intent"
    private var initialFilePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Capture intent before super.onCreate so it's available when Flutter asks
        handleViewIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        result.success(initialFilePath)
                        // Clear after reading so it's not re-delivered
                        initialFilePath = null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleViewIntent(intent)

        // Notify Flutter about the new file
        val path = initialFilePath ?: return
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod("openFile", path)
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
     * Resolve a content:// or file:// URI to an absolute file path.
     */
    private fun resolveUri(uri: Uri): String? {
        // file:// scheme — path is directly available
        if (uri.scheme == "file") {
            return uri.path
        }

        // content:// scheme — query the content resolver
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

            // Fallback: try to get the path from the URI directly
            return uri.path
        }

        return uri.path
    }
}
