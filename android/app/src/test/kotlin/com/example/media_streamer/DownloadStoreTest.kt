package com.example.media_streamer

import android.content.Context
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class DownloadStoreTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private fun resetProcess() {
        DownloadStore::class.java.getDeclaredField("context").apply { isAccessible = true }.set(null, null)
        val tasks = DownloadStore::class.java.getDeclaredField("tasks").apply { isAccessible = true }.get(null) as MutableMap<*, *>
        tasks.clear()
    }
    @Before fun reset() {
        resetProcess()
        context.getSharedPreferences("native_downloads", 0).edit().clear().commit()
        DownloadStore.initialize(context)
    }
    @Test fun duplicateDetectionIgnoresYouTubeTrackingButAllowsAudioAndVideo() {
        DownloadStore.add("https://youtu.be/abc?si=one", "best", "Video", "abc", "")
        assertThrows(IllegalArgumentException::class.java) {
            DownloadStore.add("https://www.youtube.com/watch?v=abc&si=two", "best", "Video", "abc", "")
        }
        DownloadStore.add("https://m.youtube.com/shorts/abc", "audio-mp3", "Video", "abc", "")
        assertEquals(2, DownloadStore.snapshot().size)
    }
    @Test fun interruptedDownloadsCanBeResumedAfterProcessRestart() {
        val task = DownloadStore.add("https://fb.watch/example/", "best", "Video", "123", "")
        DownloadStore.update(task.id) { it.status = "downloading" }
        resetProcess()
        DownloadStore.initialize(context)
        assertEquals("paused", DownloadStore.get(task.id)!!.status)
        assertTrue(DownloadStore.get(task.id)!!.error!!.contains("interrupted"))
    }
    @Test fun savedFilesBlockDuplicatesButDeletedFilesAllowRedownload() {
        val task = DownloadStore.add("https://vimeo.com/123", "best", "Clip", "123", "")
        val file = File(context.cacheDir, "saved.mp4").apply { writeText("test media") }
        DownloadStore.update(task.id) { it.status = "completed"; it.filePath = file.path }
        assertThrows(IllegalArgumentException::class.java) {
            DownloadStore.add(task.url, "best", "Clip", "123", "")
        }
        file.delete()
        DownloadStore.add(task.url, "best", "Clip", "123", "")
        assertEquals(2, DownloadStore.snapshot().size)
    }
    @Test fun malformedHistoryDoesNotCrashStartup() {
        resetProcess()
        context.getSharedPreferences("native_downloads", 0).edit().putString("tasks", "not json").commit()
        DownloadStore.initialize(context)
        assertTrue(DownloadStore.snapshot().isEmpty())
    }
    @Test fun pausingQueuedWorkPreventsALateWorkerFromStartingIt() {
        val task = DownloadStore.add("https://vimeo.com/123", "best", "Clip", "123", "")
        DownloadStore.update(task.id) { it.status = "paused" }
        assertFalse(DownloadStore.tryStart(task.id))
        assertEquals("paused", DownloadStore.get(task.id)!!.status)
        DownloadStore.update(task.id) { it.status = "queued" }
        assertTrue(DownloadStore.tryStart(task.id))
        assertFalse(DownloadStore.tryStart(task.id))
    }
    @Test fun activeTasksCannotBeRemovedFromHistory() {
        val task = DownloadStore.add("https://vimeo.com/123", "best", "Clip", "123", "")
        assertThrows(IllegalArgumentException::class.java) { DownloadStore.remove(task.id) }
        assertEquals("queued", DownloadStore.get(task.id)!!.status)
    }
}
