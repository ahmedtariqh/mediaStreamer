package com.example.media_streamer

import com.yausername.youtubedl_android.YoutubeDLRequest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MediaExtractorTest {
    @Test fun shareTextAndYouTubeIdentity() {
        assertEquals("https://youtu.be/abc?t=20", MediaExtractor.requireUrl("Watch this\nhttps://youtu.be/abc?t=20"))
        assertEquals("youtube:abc", MediaExtractor.identity("https://m.youtube.com/shorts/abc?feature=share"))
        assertEquals("youtube:abc", MediaExtractor.identity("https://www.youtube.com/watch?v=abc&si=tracking"))
        assertNotEquals("youtube:abc", MediaExtractor.identity("https://youtube.com.evil.example/watch?v=abc"))
    }
    @Test fun audioFormatsUseActualExtractionAndConversion() {
        for (format in listOf("audio-mp3", "audio-m4a")) {
            val request = YoutubeDLRequest("https://example.com/video")
            MediaExtractor.configureFormat(request, format)
            assertEquals("bestaudio/best", request.getOption("-f"))
            assertTrue(request.hasOption("--extract-audio"))
            assertEquals(format.removePrefix("audio-"), request.getOption("--audio-format"))
        }
    }
    @Test fun videoSelectionMergesAudioAndCapsEveryVideoFallback() {
        val request = YoutubeDLRequest("https://example.com/video")
        MediaExtractor.configureFormat(request, "video-720")
        val selector = request.getOption("-f")!!
        assertTrue(selector.contains("+bestaudio"))
        assertTrue(selector.split('/').all { it.contains("[height<=720]") })
        assertEquals("mp4/mkv", request.getOption("--merge-output-format"))
    }
    @Test fun silentVideoHasNoUnusableAudioOptions() {
        val info = MediaExtractor.parseInfo(JSONObject("""{"id":"123","title":"Silent clip","formats":[{"vcodec":"h264","acodec":"none","height":720}]}"""))
        @Suppress("UNCHECKED_CAST")
        val choices = info["formats"] as List<Map<String, Any>>
        assertTrue(choices.any { it["id"] == "best" })
        assertFalse(choices.any { it["audioOnly"] == true })
    }
    @Test fun fixedResolutionSourcesDoNotOfferUnavailableLowerQualities() {
        val info = MediaExtractor.parseInfo(JSONObject("""{"formats":[{"vcodec":"h264","acodec":"aac","height":1080}]}"""))
        @Suppress("UNCHECKED_CAST")
        val choices = info["formats"] as List<Map<String, Any>>
        assertTrue(choices.any { it["id"] == "video-1080" })
        assertFalse(choices.any { it["id"] == "video-720" })
    }
    @Test fun audioOnlySourcesHaveNoUnusableVideoOptions() {
        val info = MediaExtractor.parseInfo(JSONObject("""{"formats":[{"vcodec":"none","acodec":"aac"}]}"""))
        @Suppress("UNCHECKED_CAST")
        val choices = info["formats"] as List<Map<String, Any>>
        assertEquals(2, choices.size)
        assertTrue(choices.all { it["audioOnly"] == true })
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsArbitraryFormatArguments() {
        MediaExtractor.configureFormat(YoutubeDLRequest("https://example.com/video"), "--exec=bad")
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsNonWebShares() { MediaExtractor.requireUrl("file:///private/file") }
}
