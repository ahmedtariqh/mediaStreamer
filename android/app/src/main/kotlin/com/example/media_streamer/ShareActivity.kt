package com.example.media_streamer

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/** A small native dialog over the sending app. No second Flutter/audio engine,
 * overlay permission, or hidden activity is needed to keep downloading. */
class ShareActivity : Activity() {
    private var dialog: AlertDialog? = null
    private var generation = 0
    private var pendingDownload: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShare(intent)
    }

    private fun handleShare(intent: Intent) {
        val token = ++generation
        dialog?.dismiss()
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString().orEmpty()
        val url = try { MediaExtractor.requireUrl(text) } catch (error: Exception) {
            showError(error.message ?: "Share a video link."); return
        }
        dialog = AlertDialog.Builder(this).setTitle("MediaStreamer")
            .setMessage("Finding video and audio formats…")
            .setNegativeButton("Cancel") { _, _ -> finish() }
            .setOnCancelListener { finish() }.show()
        MediaExtractor.metadataExecutor.execute {
            try {
                val info = MediaExtractor.extract(applicationContext, url)
                @Suppress("UNCHECKED_CAST")
                val formats = info["formats"] as List<Map<String, Any>>
                runOnUiThread {
                    if (isFinishing || isDestroyed || token != generation) return@runOnUiThread
                    dialog?.dismiss()
                    dialog = AlertDialog.Builder(this).setTitle(info["title"] as String)
                        .setItems(formats.map { it["label"] as String }.toTypedArray()) { _, index ->
                            pendingDownload = mapOf("url" to url, "format" to formats[index]["id"],
                                "title" to info["title"], "videoId" to info["id"], "thumbnailUrl" to info["thumbnail"])
                            requestDownloadPermissions()
                        }.setNegativeButton("Cancel") { _, _ -> finish() }
                        .setOnCancelListener { finish() }.show()
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (!isFinishing && !isDestroyed && token == generation) showError(error.message ?: "Could not load this video.")
                }
            }
        }
    }

    private fun requestDownloadPermissions() {
        val permission = when {
            Build.VERSION.SDK_INT < 29 -> Manifest.permission.WRITE_EXTERNAL_STORAGE
            Build.VERSION.SDK_INT >= 33 -> Manifest.permission.POST_NOTIFICATIONS
            else -> null
        }
        if (permission != null && ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(permission), 8101)
        } else startDownload()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 8101) return
        if (Build.VERSION.SDK_INT < 29 && grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) {
            showError("Storage permission is required to save to Downloads.")
        } else startDownload() // Notification denial must not prevent a download.
    }

    private fun startDownload() {
        val args = pendingDownload ?: return
        pendingDownload = null
        try {
            DownloadService.enqueue(this, args)
            Toast.makeText(this, "Download queued · You can keep watching", Toast.LENGTH_SHORT).show()
            finish() // Reveals YouTube immediately; the foreground service owns the work.
        } catch (error: Exception) {
            showError(error.message ?: "Could not start download.")
        }
    }

    private fun showError(message: String) {
        dialog?.dismiss()
        dialog = AlertDialog.Builder(this).setTitle("Unable to download")
            .setMessage(message.takeLast(700))
            .setPositiveButton("Close") { _, _ -> finish() }.setOnCancelListener { finish() }.show()
    }

    override fun onDestroy() {
        generation++
        dialog?.dismiss()
        super.onDestroy()
    }
}
