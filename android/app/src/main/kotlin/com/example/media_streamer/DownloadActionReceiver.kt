package com.example.media_streamer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DownloadActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val command = intent.getStringExtra("command") ?: return
        if (command !in listOf("pause", "cancel")) return
        val pending = goAsync()
        MediaExtractor.controlExecutor.execute {
            try {
                DownloadService.command(context, command, id)
            } catch (error: Exception) {
                android.util.Log.w("MediaStreamer", "Notification action failed", error)
            } finally { pending.finish() }
        }
    }
}
