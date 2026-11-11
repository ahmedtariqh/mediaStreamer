package com.example.media_streamer

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import java.io.File

internal object DownloadPublisher {
    fun staging(context: Context, id: String) = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), id)

    fun publish(context: Context, task: NativeTask, source: File): Pair<String, String> {
        require(source.isFile && source.length() > 0) { "The download returned an empty file." }
        val safeTitle = task.title.replace(Regex("[\\p{Cntrl}<>:\"/\\\\|?*]"), "_").take(80).trim().ifBlank { "Video" }
        val name = "${safeTitle}_${task.id.take(8)}.${source.extension}"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, MimeTypeMap.getSingleton().getMimeTypeFromExtension(source.extension) ?: "application/octet-stream")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/MediaStreamer")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: error("Could not create a file in Downloads.")
            try {
                resolver.openOutputStream(uri, "w")!!.use { output -> source.inputStream().use { it.copyTo(output) } }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                var path = "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)}/MediaStreamer/$name"
                resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use {
                    if (it.moveToFirst()) path = it.getString(0) ?: path
                }
                return path to uri.toString()
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }
        }
        val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "MediaStreamer")
        check(directory.isDirectory || directory.mkdirs()) { "Storage permission is required to save downloads." }
        val target = File(directory, name)
        val partial = File(directory, "$name.partial")
        try {
            source.copyTo(partial, overwrite = false)
            check(partial.renameTo(target)) { "Could not finish saving the download." }
        } catch (error: Exception) {
            partial.delete()
            throw error
        }
        MediaScannerConnection.scanFile(context, arrayOf(target.path), null, null)
        return target.path to ""
    }

    fun delete(context: Context, task: NativeTask) {
        if (task.contentUri.isNotEmpty()) {
            context.contentResolver.delete(Uri.parse(task.contentUri), null, null)
        } else {
            val file = File(task.filePath)
            check(!file.exists() || file.delete()) { "Could not delete the downloaded file." }
        }
    }
}
