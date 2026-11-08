package com.example.media_streamer

import android.content.Context
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class PlaybackServiceStateTest {
    private lateinit var context: Context

    @Before
    fun reset() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("vlc_playback", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test
    fun browsingAndRestoringAQueueDoesNotInitializeADecoderOrAutoplay() {
        context
            .getSharedPreferences("vlc_playback", Context.MODE_PRIVATE)
            .edit()
            .putString("queue", """[{"uri":"/music/a.m4a","title":"Audio","audio":true}]""")
            .putBoolean("visible", true)
            .putLong("position", 42000)
            .commit()
        val controller = Robolectric.buildService(PlaybackService::class.java).create()
        val service = controller.get()
        assertEquals(false, service.snapshot()["playing"])
        assertEquals(42000L, service.snapshot()["position"])
        assertEquals(1, (service.snapshot()["queue"] as List<*>).size)
        controller.destroy()
        assertNull(PlaybackService.instance)
    }

    @Test
    fun queueEditsPersistWithoutDroppingOtherItems() {
        val controller = Robolectric.buildService(PlaybackService::class.java).create()
        val service = controller.get()
        service.command(
            "enqueue",
            JSONObject("""{"items":[{"uri":"/a.mp4","title":"A"},{"uri":"/b.mp4","title":"B"}]}"""),
        )
        service.command("move", JSONObject("""{"from":0,"to":1}"""))
        val saved = PlaybackService.saved(context)
        assertEquals(1, saved["index"])
        assertEquals("B", ((saved["queue"] as List<*>)[0] as Map<*, *>)["title"])
        service.command("remove", JSONObject("""{"index":0}"""))
        assertEquals(1, (PlaybackService.saved(context)["queue"] as List<*>).size)
        assertEquals(0, PlaybackService.saved(context)["index"])
        controller.destroy()
    }

    @Test
    fun settingsDoNotStartPlaybackAndClampInvalidBufferSizes() {
        PlaybackService.configure(
            context,
            JSONObject(
                """{"resume":false,"autoPip":true,"networkCaching":-50,"hardware":"unknown"}"""
            ),
        )
        val prefs = context.getSharedPreferences("vlc_playback", Context.MODE_PRIVATE)
        assertFalse(prefs.getBoolean("resume", true))
        assertTrue(prefs.getBoolean("autoPip", false))
        assertEquals(300, prefs.getInt("networkCaching", 0))
        assertEquals("auto", prefs.getString("hardware", ""))
        assertNull(PlaybackService.instance)
    }

    @Test
    fun perTrackSpeedIsRestoredBeforeTheDecoderStarts() {
        context
            .getSharedPreferences("vlc_playback", Context.MODE_PRIVATE)
            .edit()
            .putString("queue", """[{"uri":"/a.mp3","title":"A"}]""")
            .putBoolean("globalRate", false)
            .putFloat("rate:/a.mp3", 1.5f)
            .commit()
        assertEquals(1.5, PlaybackService.saved(context)["rate"])
        val controller = Robolectric.buildService(PlaybackService::class.java).create()
        controller.get().command("rate", JSONObject("""{"rate":2,"global":false}"""))
        assertEquals(
            2f,
            context
                .getSharedPreferences("vlc_playback", Context.MODE_PRIVATE)
                .getFloat("rate:/a.mp3", 0f),
            0f,
        )
        controller.destroy()
    }
}
