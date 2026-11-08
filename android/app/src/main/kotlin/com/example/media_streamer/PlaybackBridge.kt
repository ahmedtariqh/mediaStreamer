package com.example.media_streamer

import android.app.Activity
import android.app.PictureInPictureParams
import android.app.RecoverableSecurityException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Rational
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.videolan.libvlc.util.VLCVideoLayout

class PlaybackBridge(private val activity: MainActivity, engine: FlutterEngine) {
    private val channel =
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.mediastreamer/player")
    private var pending: MethodChannel.Result? = null
    private var kind = ""
    private var mutation: Pair<String, Map<*, *>>? = null
    private var mutationResult: MethodChannel.Result? = null
    private val io = java.util.concurrent.Executors.newSingleThreadExecutor()

    init {
        engine.platformViewsController.registry.registerViewFactory(
            "mediastreamer/vlc",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(
                    context: android.content.Context,
                    viewId: Int,
                    args: Any?,
                ): PlatformView =
                    object : PlatformView {
                        private val layout =
                            VLCVideoLayout(context).also {
                                VideoSurface.layout = it
                                PlaybackService.instance?.bind(it)
                            }

                        override fun getView(): View = layout

                        override fun dispose() {
                            if (VideoSurface.layout === layout) {
                                VideoSurface.layout = null
                                PlaybackService.instance?.bind(null)
                            }
                        }
                    }
            },
        )
        channel.setMethodCallHandler { call, result ->
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                when (call.method) {
                    "deleteMedia",
                    "renameMedia" -> {
                        check(mutationResult == null) { "A media operation is already pending" }
                        mutation = call.method to args
                        mutationResult = result
                        mutate(false)
                    }
                    "settings" -> {
                        PlaybackService.configure(activity, org.json.JSONObject(args))
                        result.success(null)
                    }
                    "clearResume",
                    "forgetResume" -> {
                        val prefs =
                            activity.getSharedPreferences("vlc_playback", Activity.MODE_PRIVATE)
                        val edit = prefs.edit()
                        if (call.method == "clearResume")
                            prefs.all.keys
                                .filter {
                                    it.startsWith("position:") ||
                                        it == "position" ||
                                        it == "completedUri"
                                }
                                .forEach { edit.remove(it) }
                        else edit.remove("position:${args["uri"]}")
                        edit.apply()
                        result.success(null)
                    }
                    "relocate" -> {
                        val old = args["old"] as String
                        val new = args["new"] as String
                        val prefs =
                            activity.getSharedPreferences("vlc_playback", Activity.MODE_PRIVATE)
                        val saved = org.json.JSONArray(prefs.getString("queue", "[]"))
                        for (i in 0 until saved.length()) {
                            val item = saved.getJSONObject(i)
                            if (item.optString("uri") == old) item.put("uri", new)
                        }
                        prefs
                            .edit()
                            .putString("queue", saved.toString())
                            .putLong("position:$new", prefs.getLong("position:$old", 0))
                            .remove("position:$old")
                            .apply()
                        DownloadStore.initialize(activity)
                        DownloadStore.relocate(old, new)
                        PlaybackService.instance?.command("relocate", org.json.JSONObject(args))
                        result.success(null)
                    }
                    "snapshot" ->
                        result.success(
                            PlaybackService.instance?.snapshot() ?: PlaybackService.saved(activity)
                        )
                    "pip" -> {
                        enterPip()
                        result.success(null)
                    }
                    "screenOn" -> {
                        if (args["value"] == true)
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else
                            activity.window.clearFlags(
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                            )
                        result.success(null)
                    }
                    "brightness" -> {
                        activity.window.attributes =
                            activity.window.attributes.apply {
                                screenBrightness =
                                    (args["value"] as Number).toFloat().let {
                                        if (it < 0) -1f else it.coerceIn(.01f, 1f)
                                    }
                            }
                        result.success(null)
                    }
                    "pickMedia",
                    "pickSubtitle",
                    "pickPlaylist" -> {
                        check(pending == null) { "A file picker is already open" }
                        pending = result
                        kind = call.method
                        val intent =
                            Intent(Intent.ACTION_OPEN_DOCUMENT)
                                .addCategory(Intent.CATEGORY_OPENABLE)
                                .setType(if (kind == "pickMedia") "*/*" else "*/*")
                                .addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                                )
                        if (kind == "pickMedia") {
                            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            intent.putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("video/*", "audio/*"))
                        }
                        activity.startActivityForResult(intent, 8301)
                    }
                    "readText" -> {
                        val uri = Uri.parse(args["uri"] as String)
                        io.execute {
                            try {
                                val bytes =
                                    activity.contentResolver.openInputStream(uri)?.use { input ->
                                        val out = java.io.ByteArrayOutputStream()
                                        val buffer = ByteArray(8192)
                                        while (out.size() <= 2 * 1024 * 1024) {
                                            val count = input.read(buffer)
                                            if (count < 0) break
                                            out.write(buffer, 0, count)
                                        }
                                        out.toByteArray()
                                    } ?: kotlin.error("Document unavailable")
                                require(bytes.size <= 2 * 1024 * 1024) { "Playlist is too large" }
                                activity.runOnUiThread {
                                    result.success(bytes.toString(Charsets.UTF_8))
                                }
                            } catch (e: Exception) {
                                activity.runOnUiThread {
                                    result.error("READ_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    else -> {
                        PlaybackService.send(activity, call.method, args)
                        result.success(null)
                    }
                }
            } catch (e: Throwable) {
                result.error("PLAYER_ERROR", e.message, null)
            }
        }
    }

    fun enterPip() {
        if (Build.VERSION.SDK_INT < 26) return
        activity.enterPictureInPictureMode(
            PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
        )
    }

    fun autoPip() {
        if (
            activity
                .getSharedPreferences("vlc_playback", Activity.MODE_PRIVATE)
                .getBoolean("autoPip", false) &&
                PlaybackService.instance?.snapshot()?.get("playing") == true &&
                VideoSurface.layout != null
        )
            enterPip()
    }

    fun pipChanged(value: Boolean) {
        PlaybackService.inPip = value
        channel.invokeMethod("pipChanged", value)
    }

    fun onActivityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (request == 8302) {
            if (result != Activity.RESULT_OK) {
                mutationResult?.error("CANCELLED", "Media operation cancelled", null)
                mutationResult = null
                mutation = null
            } else if (mutation?.first == "deleteMedia" && Build.VERSION.SDK_INT >= 30) {
                mutationResult?.success(true)
                mutationResult = null
                mutation = null
            } else mutate(true)
            return true
        }
        if (request != 8301) return false
        val callback = pending ?: return true
        pending = null
        if (result != Activity.RESULT_OK || data == null) {
            callback.success(emptyList<Any>())
            return true
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { for (i in 0 until it.itemCount) uris.add(it.getItemAt(i).uri) }
            ?: data.data?.let { uris.add(it) }
        val requestKind = kind
        io.execute {
            try {
                val items =
                    uris.map { uri ->
                        try {
                            activity.contentResolver.takePersistableUriPermission(
                                uri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION,
                            )
                        } catch (_: Exception) {}
                        var title = uri.lastPathSegment ?: "Media"
                        activity.contentResolver
                            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                            ?.use { if (it.moveToFirst()) title = it.getString(0) }
                        val playbackUri =
                            if (requestKind == "pickSubtitle") {
                                val file =
                                    java.io.File(
                                        activity.cacheDir,
                                        "subtitle-${System.currentTimeMillis()}-${title.replace(Regex("[^\\p{L}\\p{N}._-]"), "_")}",
                                    )
                                activity.contentResolver.openInputStream(uri)?.use { input ->
                                    file.outputStream().use { output ->
                                        val buffer = ByteArray(8192)
                                        var total = 0
                                        while (true) {
                                            val count = input.read(buffer)
                                            if (count < 0) break
                                            total += count
                                            require(total <= 20 * 1024 * 1024) {
                                                "Subtitle is too large"
                                            }
                                            output.write(buffer, 0, count)
                                        }
                                    }
                                } ?: kotlin.error("Subtitle unavailable")
                                Uri.fromFile(file).toString()
                            } else uri.toString()
                        mapOf(
                            "uri" to playbackUri,
                            "title" to title,
                            "audio" to
                                (activity.contentResolver.getType(uri)?.startsWith("audio/") ==
                                    true),
                        )
                    }
                activity.runOnUiThread { callback.success(items) }
            } catch (e: Exception) {
                activity.runOnUiThread { callback.error("PICK_FAILED", e.message, null) }
            }
        }
        return true
    }

    private fun mutate(approved: Boolean) {
        val op = mutation ?: return
        val callback = mutationResult ?: return
        val uriText =
            op.second["contentUri"]?.toString().orEmpty().ifEmpty {
                op.second["uri"]
                    ?.toString()
                    .orEmpty()
                    .takeIf { it.startsWith("content://") }
                    .orEmpty()
            }
        val uri = uriText.takeIf { it.isNotEmpty() }?.let { Uri.parse(it) }
        io.execute {
            try {
                var renamedPath: String? = null
                if (uri != null) {
                    val count =
                        if (op.first == "deleteMedia")
                            activity.contentResolver.delete(uri, null, null)
                        else {
                            val name = op.second["name"]?.toString().orEmpty()
                            require(
                                name.isNotBlank() && !name.contains('/') && !name.contains('\\')
                            ) {
                                "Invalid file name"
                            }
                            activity.contentResolver.update(
                                uri,
                                ContentValues().apply {
                                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                                },
                                null,
                                null,
                            )
                        }
                    require(count > 0) { "The media could not be changed" }
                    if (op.first == "renameMedia") {
                        if (op.second["uri"]?.toString()?.startsWith("content://") == true)
                            renamedPath = op.second["uri"].toString()
                        else
                            activity.contentResolver
                                .query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
                                ?.use { if (it.moveToFirst()) renamedPath = it.getString(0) }
                        if (renamedPath.isNullOrBlank())
                            renamedPath =
                                java.io
                                    .File(
                                        java.io.File(op.second["uri"].toString()).parentFile,
                                        op.second["name"].toString(),
                                    )
                                    .path
                    }
                } else {
                    val path = op.second["uri"]?.toString() ?: kotlin.error("Missing file")
                    require(path.startsWith("/")) { "Only local media can be changed" }
                    val file = java.io.File(path)
                    if (op.first == "deleteMedia")
                        require(file.delete()) { "Unable to delete file" }
                    else {
                        val name = op.second["name"]?.toString().orEmpty()
                        require(
                            name.isNotBlank() &&
                                name != "." &&
                                name != ".." &&
                                !name.contains('/') &&
                                !name.contains('\\')
                        ) {
                            "Invalid file name"
                        }
                        val target = java.io.File(file.parentFile, name)
                        require(!target.exists() && file.renameTo(target)) {
                            "Unable to rename file"
                        }
                        renamedPath = target.path
                        android.media.MediaScannerConnection.scanFile(
                            activity,
                            arrayOf(target.path),
                            null,
                            null,
                        )
                    }
                    android.media.MediaScannerConnection.scanFile(
                        activity,
                        arrayOf(path),
                        null,
                        null,
                    )
                }
                activity.runOnUiThread {
                    mutation = null
                    mutationResult = null
                    callback.success(renamedPath ?: true)
                }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    try {
                        if (!approved && uri != null && (e is SecurityException)) {
                            val sender =
                                if (Build.VERSION.SDK_INT >= 30) {
                                    if (op.first == "deleteMedia")
                                        MediaStore.createDeleteRequest(
                                                activity.contentResolver,
                                                listOf(uri),
                                            )
                                            .intentSender
                                    else
                                        MediaStore.createWriteRequest(
                                                activity.contentResolver,
                                                listOf(uri),
                                            )
                                            .intentSender
                                } else if (
                                    Build.VERSION.SDK_INT >= 29 && e is RecoverableSecurityException
                                )
                                    e.userAction.actionIntent.intentSender
                                else throw e
                            activity.startIntentSenderForResult(sender, 8302, null, 0, 0, 0)
                        } else throw e
                    } catch (failure: Exception) {
                        mutation = null
                        mutationResult = null
                        callback.error("MEDIA_OPERATION", failure.message, null)
                    }
                }
            }
        }
    }

    fun dispose() {
        PlaybackService.instance?.bind(null)
        VideoSurface.layout = null
        mutationResult?.error("CANCELLED", "Activity closed", null)
        mutationResult = null
        mutation = null
        channel.setMethodCallHandler(null)
        pending?.success(emptyList<Any>())
        pending = null
        io.shutdown()
    }
}

object VideoSurface {
    var layout: VLCVideoLayout? = null
}
