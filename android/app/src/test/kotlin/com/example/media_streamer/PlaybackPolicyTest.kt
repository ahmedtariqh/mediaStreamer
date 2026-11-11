package com.example.media_streamer

import kotlin.random.Random
import org.junit.Assert.*
import org.junit.Test

class PlaybackPolicyTest {
    @Test
    fun repeatOneAppliesOnlyToAutomaticAdvance() {
        assertEquals(1, PlaybackPolicy.next(3, 1, "one", false, true))
        assertEquals(2, PlaybackPolicy.next(3, 1, "one", false, false))
    }

    @Test
    fun repeatAllWrapsAndOffStops() {
        assertNull(PlaybackPolicy.next(3, 2, "off", false, true))
        assertEquals(0, PlaybackPolicy.next(3, 2, "all", false, true))
        assertNull(PlaybackPolicy.next(0, 0, "all", true, true))
    }

    @Test
    fun shuffleNeverImmediatelyRepeatsWhenAlternativesExist() {
        for (i in 0..99) assertNotEquals(
            2,
            PlaybackPolicy.next(5, 2, "off", true, false, Random(i)),
        )
        assertNull(PlaybackPolicy.next(1, 0, "off", true, true))
    }

    @Test
    fun reorderKeepsThePlayingItemSelected() {
        assertEquals(4, PlaybackPolicy.movedIndex(1, 1, 4))
        assertEquals(2, PlaybackPolicy.movedIndex(3, 1, 4))
        assertEquals(3, PlaybackPolicy.movedIndex(2, 4, 0))
        assertEquals(1, PlaybackPolicy.movedIndex(1, 3, 4))
    }

    @Test
    fun seekAndRateAreBoundedAndNanIsSafe() {
        assertEquals(0L, PlaybackPolicy.seek(-5000, 10000))
        assertEquals(10000L, PlaybackPolicy.seek(90000, 10000))
        assertEquals(5000L, PlaybackPolicy.seek(5000, 0))
        assertEquals(1f, PlaybackPolicy.rate(Float.NaN))
        assertEquals(.25f, PlaybackPolicy.rate(-1f))
        assertEquals(8f, PlaybackPolicy.rate(20f))
    }

    @Test
    fun abLoopNeedsTwoOrderedPointsAndSeeksAtB() {
        assertFalse(PlaybackPolicy.loop(4000, -1, 3000))
        assertFalse(PlaybackPolicy.loop(4000, 3000, 2000))
        assertFalse(PlaybackPolicy.loop(2999, 1000, 3000))
        assertTrue(PlaybackPolicy.loop(3000, 1000, 3000))
    }
}
