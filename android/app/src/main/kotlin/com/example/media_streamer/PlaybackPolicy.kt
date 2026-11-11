package com.example.media_streamer

import kotlin.random.Random

/** Queue decisions independent of Android/JNI, shared by end-of-track and controls. */
object PlaybackPolicy {
    fun next(
        size: Int,
        index: Int,
        repeat: String,
        shuffle: Boolean,
        automatic: Boolean,
        random: Random = Random.Default,
    ): Int? {
        if (size <= 0) return null
        if (automatic && repeat == "one") return index.coerceIn(0, size - 1)
        if (shuffle && size > 1) {
            val value = random.nextInt(size - 1)
            return if (value >= index) value + 1 else value
        }
        return if (index + 1 < size) index + 1 else if (repeat == "all") 0 else null
    }

    fun movedIndex(current: Int, from: Int, to: Int): Int =
        when {
            current == from -> to
            from < current && to >= current -> current - 1
            from > current && to <= current -> current + 1
            else -> current
        }

    fun rate(value: Float): Float = if (value.isFinite()) value.coerceIn(.25f, 8f) else 1f

    fun seek(value: Long, length: Long): Long =
        value.coerceIn(0, if (length > 0) length else Long.MAX_VALUE)

    fun loop(position: Long, a: Long, b: Long): Boolean = a >= 0 && b > a && position >= b
}
