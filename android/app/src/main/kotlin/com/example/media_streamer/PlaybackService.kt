package com.example.media_streamer

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.*
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import org.json.JSONArray
import org.json.JSONObject
import org.videolan.libvlc.*
import org.videolan.libvlc.util.VLCVideoLayout

/** The service owns the only decoder. Flutter routes only attach/detach a surface. */
class PlaybackService : Service() {
    companion object {
        var instance: PlaybackService? = null
            private set

        var inPip = false
        const val CHANNEL = "media_playback"
        const val NOTIFICATION = 7901

        fun send(context: Context, method: String, args: Map<*, *> = emptyMap<Any, Any>()) {
            instance
                ?.takeUnless { it.stopping }
                ?.let {
                    it.command(method, JSONObject(args))
                    return
                }
            val intent =
                Intent(context, PlaybackService::class.java)
                    .putExtra("method", method)
                    .putExtra("args", JSONObject(args).toString())
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun configure(context: Context, args: JSONObject) {

            val edit = context.getSharedPreferences("vlc_playback", MODE_PRIVATE).edit()
            if (args.has("resume")) edit.putBoolean("resume", args.getBoolean("resume"))
            if (args.has("autoPip")) edit.putBoolean("autoPip", args.getBoolean("autoPip"))
            if (args.has("networkCaching"))
                edit.putInt("networkCaching", args.getInt("networkCaching").coerceIn(300, 10000))
            if (args.has("hardware"))
                edit.putString(
                    "hardware",
                    args.getString("hardware").takeIf {
                        it in setOf("auto", "hardware", "software")
                    } ?: "auto",
                )
            edit.apply()
        }

        fun saved(context: Context): Map<String, Any?> {
            val prefs = context.getSharedPreferences("vlc_playback", MODE_PRIVATE)
            val items =
                try {
                    JSONArray(prefs.getString("queue", "[]"))
                } catch (_: Exception) {
                    JSONArray()
                }
            return mapOf(
                "queue" to (0 until items.length()).map { jsonMap(items.getJSONObject(it)) },
                "index" to prefs.getInt("index", 0),
                "position" to prefs.getLong("position", 0),
                "duration" to 0L,
                "playing" to false,
                "visible" to prefs.getBoolean("visible", false),
                "rate" to
                    (if (prefs.getBoolean("globalRate", true)) prefs.getFloat("rate", 1f)
                        else
                            prefs.getFloat(
                                "rate:${items.optJSONObject(prefs.getInt("index", 0))?.optString("uri")}",
                                1f,
                            ))
                        .toDouble(),
                "globalRate" to prefs.getBoolean("globalRate", true),
                "repeat" to prefs.getString("repeat", "off"),
                "shuffle" to prefs.getBoolean("shuffle", false),
            )
        }

        fun jsonMap(json: JSONObject): Map<String, Any?> =
            json.keys().asSequence().associateWith { key ->
                when (val value = json.opt(key)) {
                    JSONObject.NULL -> null
                    is JSONObject -> jsonMap(value)
                    is JSONArray -> (0 until value.length()).map { value.opt(it) }
                    else -> value
                }
            }
    }

    private val main = Handler(Looper.getMainLooper())
    private val prefs by lazy { getSharedPreferences("vlc_playback", MODE_PRIVATE) }
    private var vlc: LibVLC? = null
    private var player: MediaPlayer? = null
    private var descriptor: ParcelFileDescriptor? = null
    private var session: MediaSessionCompat? = null
    private val queue = mutableListOf<JSONObject>()
    private val history = mutableListOf<Int>()
    private var index = 0
    private var stopping = false
    private var destroyed = false
    private var generation = 0
    private var finishedUri: String? = null
    private var mediaDetails: List<Map<String, Any?>> = emptyList()
    private var currentUri: String? = null
    private var error: String? = null
    private var buffering = false
    private var repeat = "off"
    private var shuffle = false
    private var audioOnly = false
    private var visible = false
    private var a = -1L
    private var b = -1L
    private var sleepUntil = 0L
    private var sleepAtEnd = false
    private var resumeAt = 0L
    private var saveTicks = 0
    private var wasInterrupted = false
    private lateinit var audio: AudioManager
    private var focus: AudioFocusRequest? = null
    private var wake: PowerManager.WakeLock? = null
    private var equalizer: MediaPlayer.Equalizer? = null
    private var eqEnabled = false
    private var eqBands = FloatArray(10)
    private var eqPreamp = 0f
    private var surface: VLCVideoLayout? = null
    private var discoverers = mutableListOf<RendererDiscoverer>()
    private val renderers = linkedMapOf<String, RendererItem>()
    private var castName: String? = null
    private var multicast: android.net.wifi.WifiManager.MulticastLock? = null
    private val noisy =
        object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) {
                pause()
            }
        }
    private val focusListener =
        AudioManager.OnAudioFocusChangeListener { change ->
            main.post {
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS -> {
                        wasInterrupted = false
                        pause()
                    }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                        wasInterrupted = player?.isPlaying == true
                        pause(false)
                    }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> player?.setVolume(30)
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        player?.setVolume(prefs.getInt("volume", 100))
                        if (wasInterrupted) {
                            wasInterrupted = false
                            play()
                        }
                    }
                }
            }
        }
    private val ticker =
        object : Runnable {
            override fun run() {
                val p = player
                if (p != null) {
                    if (p.isPlaying && PlaybackPolicy.loop(p.time, a, b)) p.setTime(a)
                    if (sleepUntil > 0 && System.currentTimeMillis() >= sleepUntil) {
                        sleepUntil = 0
                        if (!sleepAtEnd) pause()
                    }
                    if (++saveTicks % 20 == 0) {
                        save()
                        updateNotification()
                    }
                }
                main.postDelayed(this, if (p?.isPlaying == true) 250 else 1000)
            }
        }

    override fun onCreate() {
        super.onCreate()
        instance = this
        audio = getSystemService(AUDIO_SERVICE) as AudioManager
        val items =
            try {
                JSONArray(prefs.getString("queue", "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
        for (i in 0 until items.length()) queue.add(items.getJSONObject(i))
        index = prefs.getInt("index", 0).coerceIn(0, (queue.size - 1).coerceAtLeast(0))
        repeat = prefs.getString("repeat", "off") ?: "off"
        shuffle = prefs.getBoolean("shuffle", false)
        visible = prefs.getBoolean("visible", false)
        session =
            MediaSessionCompat(this, "MediaStreamer").apply {
                setCallback(
                    object : MediaSessionCompat.Callback() {
                        override fun onPlay() = play()

                        override fun onPause() = pause()

                        override fun onStop() = stopPlayback()

                        override fun onSkipToNext() = next(false)

                        override fun onSkipToPrevious() = previous()

                        override fun onSeekTo(pos: Long) {
                            player?.setTime(PlaybackPolicy.seek(pos, player?.length ?: 0))
                        }

                        override fun onFastForward() {
                            player?.let {
                                it.setTime(PlaybackPolicy.seek(it.time + 10000, it.length))
                            }
                        }

                        override fun onRewind() {
                            player?.let {
                                it.setTime(PlaybackPolicy.seek(it.time - 10000, it.length))
                            }
                        }
                    }
                )
                isActive = true
            }
        if (Build.VERSION.SDK_INT >= 26)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(
                    NotificationChannel(
                        CHANNEL,
                        "Media playback",
                        NotificationManager.IMPORTANCE_LOW,
                    )
                )
        ServiceCompat.startForeground(
            this,
            NOTIFICATION,
            notification(),
            if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            else 0,
        )
        if (Build.VERSION.SDK_INT >= 33)
            registerReceiver(
                noisy,
                IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
                RECEIVER_NOT_EXPORTED,
            )
        else
            @Suppress("DEPRECATION")
            registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        main.post(ticker)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopping = false
        instance = this
        ServiceCompat.startForeground(
            this,
            NOTIFICATION,
            notification(),
            if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            else 0,
        )
        try {
            command(
                intent?.getStringExtra("method") ?: "pause",
                JSONObject(intent?.getStringExtra("args") ?: "{}"),
            )
        } catch (e: Throwable) {
            error = e.message ?: "Playback failed"
            pause()
            updateNotification()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?) = null

    private fun ensureEngine(): MediaPlayer {
        player?.let {
            return it
        }
        val engine =
            LibVLC(
                this,
                arrayListOf(
                    "--audio-time-stretch",
                    "--no-video-title-show",
                    "--network-caching=${prefs.getInt("networkCaching", 1500)}",
                ),
            )
        vlc = engine
        val p = MediaPlayer(engine)
        player = p
        installListener(p)
        p.setVolume(prefs.getInt("volume", 100))
        eqEnabled = prefs.getBoolean("eqEnabled", false)
        try {
            val saved = JSONArray(prefs.getString("eqBands", "[]"))
            for (i in 0 until minOf(saved.length(), 10)) eqBands[i] = saved.getDouble(i).toFloat()
        } catch (_: Exception) {}
        eqPreamp = prefs.getFloat("eqPreamp", 0f)
        applyEqualizer()
        (surface ?: VideoSurface.layout)?.let { bind(it) }
        return p
    }

    private fun readMediaDetails(p: MediaPlayer) {
        val media = p.media ?: return
        try {
            mediaDetails =
                (0 until media.trackCount).map { i ->
                    val track = media.getTrack(i)
                    val info =
                        mutableMapOf<String, Any?>(
                            "type" to track.type,
                            "codec" to track.codec,
                            "language" to track.language,
                            "bitrate" to track.bitrate,
                        )
                    if (track is org.videolan.libvlc.interfaces.IMedia.VideoTrack)
                        info.putAll(
                            mapOf(
                                "width" to track.width,
                                "height" to track.height,
                                "fps" to
                                    if (track.frameRateDen > 0)
                                        track.frameRateNum.toDouble() / track.frameRateDen
                                    else 0.0,
                            )
                        )
                    if (track is org.videolan.libvlc.interfaces.IMedia.AudioTrack)
                        info.putAll(mapOf("channels" to track.channels, "sampleRate" to track.rate))
                    info
                }
        } finally {
            media.release()
        }
    }

    private fun installListener(p: MediaPlayer) {
        val epoch = generation
        p.setEventListener { event ->
            if (player !== p || epoch != generation) return@setEventListener
            when (event.type) {
                MediaPlayer.Event.Playing -> {
                    buffering = false
                    error = null
                    if (p.videoTracksCount == 0 && p.audioTracksCount > 0) audioOnly = true
                    if (resumeAt > 0) {
                        p.setTime(resumeAt)
                        resumeAt = 0
                    }
                    readMediaDetails(p)
                    applyRate()
                    updateNotification()
                }
                MediaPlayer.Event.Buffering -> buffering = event.buffering < 100
                MediaPlayer.Event.Paused -> updateNotification()
                MediaPlayer.Event.EndReached -> {
                    finishedUri = currentUri
                    currentUri?.let {
                        prefs
                            .edit()
                            .putLong("position:$it", 0)
                            .putString("completedUri", it)
                            .apply()
                    }
                    if (sleepAtEnd && sleepUntil == 0L) {
                        sleepAtEnd = false
                        pause()
                    } else next(true)
                }
                MediaPlayer.Event.EncounteredError -> {
                    buffering = false
                    error =
                        "Unable to play this media. Check the file, network or decoding settings."
                    pause()
                    updateNotification()
                }
            }
        }
    }

    fun bind(layout: VLCVideoLayout?) {
        player?.let { if (it.vlcVout.areViewsAttached()) it.detachViews() }
        surface = layout
        if (layout == null) player?.setVideoTrackEnabled(!audioOnly && castName != null)
        if (layout != null)
            player?.let {
                it.attachViews(layout, null, true, false)
                it.setVideoTrackEnabled(!audioOnly)
            }
    }

    private fun open(newIndex: Int, legacyPosition: Long = 0) {
        if (queue.isEmpty()) return
        save()
        index = newIndex.coerceIn(0, queue.lastIndex)
        val item = queue[index]
        val uri = item.getString("uri")
        val p = ensureEngine()
        generation++
        p.setEventListener(null)
        p.stop()
        descriptor?.close()
        descriptor = null
        finishedUri = null
        mediaDetails = emptyList()
        currentUri = uri
        error = null
        a = -1
        b = -1
        audioOnly = item.optBoolean("audio", false)
        val parsed = if (uri.startsWith("/")) Uri.fromFile(java.io.File(uri)) else Uri.parse(uri)
        val media =
            if (parsed.scheme == "content") {
                val fd =
                    contentResolver.openFileDescriptor(parsed, "r")
                        ?: kotlin.error("The document is unavailable")
                descriptor = fd
                Media(vlc!!, fd.fileDescriptor)
            } else Media(vlc!!, parsed)
        try {
            val hardware = prefs.getString("hardware", "auto") ?: "auto"
            media.setHWDecoderEnabled(hardware != "software", hardware == "hardware")
            media.addOption(":network-caching=${prefs.getInt("networkCaching", 1500)}")
            p.media = media
        } finally {
            media.release()
        }
        resumeAt =
            if (prefs.getBoolean("resume", true)) prefs.getLong("position:$uri", legacyPosition)
            else 0
        p.setVideoTrackEnabled(!audioOnly && surface != null)
        installListener(p)
        visible = true
        play()
        save()
    }

    private fun requestFocus(): Boolean {
        val result =
            if (Build.VERSION.SDK_INT >= 26) {
                if (focus == null)
                    focus =
                        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                            .setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                                    .build()
                            )
                            .setOnAudioFocusChangeListener(focusListener)
                            .build()
                audio.requestAudioFocus(focus!!)
            } else
                @Suppress("DEPRECATION")
                audio.requestAudioFocus(
                    focusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN,
                )
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun play() {
        if (currentUri == null) {
            if (queue.isNotEmpty()) open(index)
            return
        }
        if (!requestFocus()) {
            error = "Audio focus unavailable. Try again after the call."
            return
        }
        visible = true
        ensureEngine().play()
        if (wake == null)
            wake =
                (getSystemService(POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MediaStreamer:playback")
                    .apply { setReferenceCounted(false) }
        if (wake?.isHeld != true) wake?.acquire(6 * 60 * 60 * 1000L)
        updateNotification()
    }

    private fun pause(abandon: Boolean = true) {
        player?.pause()
        if (wake?.isHeld == true) wake?.release()
        if (abandon) {
            if (Build.VERSION.SDK_INT >= 26) focus?.let { audio.abandonAudioFocusRequest(it) }
            else @Suppress("DEPRECATION") audio.abandonAudioFocus(focusListener)
        }
        save()
        updateNotification()
    }

    private fun next(automatic: Boolean) {
        val target = PlaybackPolicy.next(queue.size, index, repeat, shuffle, automatic)
        if (target != null) {
            history.add(index)
            open(target)
        } else {
            pause()
            player?.setTime(0)
            save()
        }
    }

    private fun previous() {
        if ((player?.time ?: 0) > 3000) {
            player?.setTime(0)
            return
        }
        val target =
            if (history.isNotEmpty()) history.removeAt(history.lastIndex)
            else if (index > 0) index - 1 else if (repeat == "all") queue.lastIndex else 0
        open(target)
    }

    private fun applyRate() {
        val uri = currentUri ?: return
        player?.rate =
            PlaybackPolicy.rate(
                if (prefs.getBoolean("globalRate", true)) prefs.getFloat("rate", 1f)
                else prefs.getFloat("rate:$uri", 1f)
            )
    }

    private fun applyEqualizer() {
        equalizer =
            MediaPlayer.Equalizer.create().apply {
                setPreAmp(eqPreamp)
                for (i in eqBands.indices) setAmp(i, eqBands[i])
            }
        player?.setEqualizer(if (eqEnabled) equalizer else null)
    }

    fun command(method: String, args: JSONObject) {
        when (method) {
            "open" -> {
                save()
                prefs.edit().remove("completedUri").apply()
                queue.clear()
                val list = args.getJSONArray("items")
                for (i in 0 until list.length()) queue.add(list.getJSONObject(i))
                history.clear()
                currentUri = null
                open(args.optInt("index", 0), args.optLong("legacyPosition", 0))
            }
            "play" -> play()
            "toggle" -> if (player?.isPlaying == true) pause() else play()
            "pause" -> pause()
            "stop" -> stopPlayback()
            "next" -> next(false)
            "previous" -> previous()
            "seek" ->
                player?.let { it.setTime(PlaybackPolicy.seek(args.getLong("position"), it.length)) }
            "rate" -> {
                val r = PlaybackPolicy.rate(args.getDouble("rate").toFloat())
                val global = args.optBoolean("global", true)
                prefs
                    .edit()
                    .putBoolean("globalRate", global)
                    .putFloat(
                        if (global) "rate"
                        else "rate:${currentUri ?: queue.getOrNull(index)?.optString("uri")}",
                        r,
                    )
                    .apply()
                player?.rate = r
            }
            "temporaryRate" -> player?.rate = PlaybackPolicy.rate(args.getDouble("rate").toFloat())
            "volume" -> {
                val value = args.getInt("value").coerceIn(0, 200)
                player?.setVolume(value)
                prefs.edit().putInt("volume", value).apply()
            }
            "repeat" -> {
                repeat =
                    args.getString("value").takeIf { it in setOf("off", "one", "all") } ?: "off"
                save()
            }
            "shuffle" -> {
                shuffle = args.getBoolean("value")
                save()
            }
            "audioOnly" -> {
                audioOnly = args.getBoolean("value")
                player?.setVideoTrackEnabled(!audioOnly && surface != null)
            }
            "aspect" ->
                player?.let {
                    val value = args.optString("value")
                    it.setVideoScale(
                        when (value) {
                            "fill" -> MediaPlayer.ScaleType.SURFACE_FILL
                            "crop" -> MediaPlayer.ScaleType.SURFACE_FIT_SCREEN
                            "16:9" -> MediaPlayer.ScaleType.SURFACE_16_9
                            "4:3" -> MediaPlayer.ScaleType.SURFACE_4_3
                            "2.35:1" -> MediaPlayer.ScaleType.SURFACE_235_1
                            "original" -> MediaPlayer.ScaleType.SURFACE_ORIGINAL
                            else -> MediaPlayer.ScaleType.SURFACE_BEST_FIT
                        }
                    )
                }
            "track" ->
                when (args.getString("type")) {
                    "audio" -> player?.setAudioTrack(args.getInt("id"))
                    "subtitle" -> player?.setSpuTrack(args.getInt("id"))
                    "video" -> player?.setVideoTrack(args.getInt("id"))
                }
            "subtitle" ->
                player?.addSlave(
                    org.videolan.libvlc.interfaces.IMedia.Slave.Type.Subtitle,
                    Uri.parse(args.getString("uri")),
                    true,
                )
            "delay" ->
                if (args.getString("type") == "audio")
                    player?.setAudioDelay(args.getLong("ms") * 1000)
                else player?.setSpuDelay(args.getLong("ms") * 1000)
            "chapter" -> player?.chapter = args.getInt("index")
            "sleep" -> {
                val minutes = args.optLong("minutes", 0).coerceIn(0, 1440)
                sleepUntil = if (minutes > 0) System.currentTimeMillis() + minutes * 60000 else 0
                sleepAtEnd = minutes > 0 && args.optBoolean("finishTrack", false)
            }
            "ab" -> {
                a = args.optLong("a", -1)
                b = args.optLong("b", -1)
            }
            "enqueue",
            "playNext" -> {
                val list = args.getJSONArray("items")
                val at =
                    if (method == "playNext") (index + 1).coerceAtMost(queue.size) else queue.size
                for (i in 0 until list.length()) queue.add(at + i, list.getJSONObject(i))
                save()
            }
            "select" -> open(args.getInt("index"))
            "move" -> {
                val from = args.getInt("from")
                val to = args.getInt("to")
                require(from in queue.indices && to in queue.indices)
                val item = queue.removeAt(from)
                queue.add(to, item)
                index = PlaybackPolicy.movedIndex(index, from, to)
                history.clear()
                save()
            }
            "remove" -> {
                val at = args.getInt("index")
                require(at in queue.indices)
                save()
                queue.removeAt(at)
                history.clear()
                if (at == index) {
                    currentUri = null
                    player?.stop()
                    if (queue.isEmpty()) stopPlayback()
                    else open(index.coerceAtMost(queue.lastIndex))
                } else {
                    if (at < index) index--
                    save()
                }
            }
            "equalizer" -> {
                ensureEngine()
                eqEnabled = args.optBoolean("enabled", true)
                if (args.has("preset")) {
                    val preset = MediaPlayer.Equalizer.createFromPreset(args.getInt("preset"))
                    eqPreamp = preset.preAmp
                    for (i in eqBands.indices) eqBands[i] = preset.getAmp(i)
                }
                if (args.has("bands")) {
                    val values = args.getJSONArray("bands")
                    for (i in eqBands.indices) eqBands[i] =
                        values.optDouble(i, 0.0).toFloat().coerceIn(-20f, 20f)
                }
                eqPreamp =
                    args.optDouble("preamp", eqPreamp.toDouble()).toFloat().coerceIn(-20f, 20f)
                prefs
                    .edit()
                    .putBoolean("eqEnabled", eqEnabled)
                    .putString("eqBands", JSONArray(eqBands.toList()).toString())
                    .putFloat("eqPreamp", eqPreamp)
                    .apply()
                applyEqualizer()
            }
            "relocate" -> {
                val old = args.getString("old")
                val new = args.getString("new")
                queue.filter { it.optString("uri") == old }.forEach { it.put("uri", new) }
                if (currentUri == old) currentUri = new
                if (finishedUri == old) finishedUri = new
                save()
            }
            "settings" -> configure(this, args)
            "discover" -> discover()
            "cast" -> {
                val id = args.optString("id")
                player?.setRenderer(renderers[id])
                castName = renderers[id]?.displayName
                player?.setVideoTrackEnabled(!audioOnly && (surface != null || castName != null))
            }
        }
    }

    private fun discover() {
        if (discoverers.isNotEmpty()) return
        val engine =
            vlc
                ?: run {
                    ensureEngine()
                    vlc!!
                }
        multicast =
            (applicationContext.getSystemService(WIFI_SERVICE) as android.net.wifi.WifiManager)
                .createMulticastLock("MediaStreamer renderers")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        RendererDiscoverer.list(engine)?.forEach { desc ->
            val d = RendererDiscoverer(engine, desc.name)
            d.setEventListener { event ->
                val item = event.item
                item.retain()
                main.post {
                    if (destroyed) {
                        item.release()
                        return@post
                    }
                    val id = item.name
                    if (event.type == RendererDiscoverer.Event.ItemAdded) {
                        renderers.remove(id)?.release()
                        renderers[id] = item
                    } else {
                        renderers.remove(id)?.release()
                        item.release()
                    }
                }
            }
            discoverers.add(d)
            d.start()
        }
        main.postDelayed({ stopDiscovery() }, 120000)
    }

    private fun stopDiscovery() {
        discoverers.forEach {
            it.stop()
            it.release()
        }
        discoverers.clear()
        if (multicast?.isHeld == true) multicast?.release()
        multicast = null
    }

    fun snapshot(): Map<String, Any?> {
        val p = player ?: return saved(this) + mapOf("error" to error)
        fun tracks(items: Array<MediaPlayer.TrackDescription>?): List<Map<String, Any>> =
            items?.map { mapOf("id" to it.id, "name" to it.name) } ?: emptyList()
        val chapters = p?.let { it.getChapters(it.title) }
        return mapOf(
            "queue" to queue.map { jsonMap(it) },
            "index" to index,
            "position" to (p?.time?.coerceAtLeast(0) ?: prefs.getLong("position", 0)),
            "duration" to (p?.length?.coerceAtLeast(0) ?: 0),
            "playing" to (p?.isPlaying ?: false),
            "visible" to visible,
            "buffering" to buffering,
            "error" to error,
            "rate" to (p?.rate ?: prefs.getFloat("rate", 1f)).toDouble(),
            "globalRate" to prefs.getBoolean("globalRate", true),
            "repeat" to repeat,
            "shuffle" to shuffle,
            "volume" to (p?.volume ?: 100),
            "audioOnly" to audioOnly,
            "a" to a,
            "b" to b,
            "sleepUntil" to sleepUntil,
            "sleepAtEnd" to sleepAtEnd,
            "audioTracks" to tracks(p?.audioTracks),
            "subtitleTracks" to tracks(p?.spuTracks),
            "videoTracks" to tracks(p?.videoTracks),
            "audioTrack" to p?.audioTrack,
            "subtitleTrack" to p?.spuTrack,
            "videoTrack" to p?.videoTrack,
            "audioDelay" to ((p?.audioDelay ?: 0) / 1000),
            "subtitleDelay" to ((p?.spuDelay ?: 0) / 1000),
            "chapters" to
                (chapters?.mapIndexed { i, c ->
                    mapOf("index" to i, "name" to c.name, "time" to c.timeOffset)
                } ?: emptyList()),
            "eqEnabled" to eqEnabled,
            "eqBands" to eqBands.map { it.toDouble() },
            "eqPreamp" to eqPreamp.toDouble(),
            "eqPresets" to
                (0 until MediaPlayer.Equalizer.getPresetCount()).map {
                    MediaPlayer.Equalizer.getPresetName(it)
                },
            "eqFrequencies" to
                (0 until MediaPlayer.Equalizer.getBandCount()).map {
                    MediaPlayer.Equalizer.getBandFrequency(it).toDouble()
                },
            "renderers" to renderers.map { mapOf("id" to it.key, "name" to it.value.displayName) },
            "castName" to castName,
            "completedUri" to prefs.getString("completedUri", null),
            "mediaDetails" to mediaDetails,
        )
    }

    private fun save() {
        val edit =
            prefs
                .edit()
                .putString("queue", JSONArray(queue).toString())
                .putInt("index", index)
                .putString("repeat", repeat)
                .putBoolean("shuffle", shuffle)
                .putBoolean("visible", visible)
        val position =
            if (currentUri != null && currentUri == finishedUri) 0L
            else player?.time?.coerceAtLeast(0) ?: prefs.getLong("position", 0)
        edit.putLong("position", position)
        currentUri?.let { edit.putLong("position:$it", position) }
        edit.apply()
    }

    private fun pending(method: String): PendingIntent =
        PendingIntent.getBroadcast(
            this,
            method.hashCode(),
            Intent(this, PlaybackActionReceiver::class.java).putExtra("method", method),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun notification(): Notification {
        val launch =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(queue.getOrNull(index)?.optString("title") ?: "MediaStreamer")
            .setContentText(error ?: if (player?.isPlaying == true) "Playing" else "Paused")
            .setContentIntent(launch)
            .setOnlyAlertOnce(true)
            .setOngoing(player?.isPlaying == true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_media_previous, "Previous", pending("previous"))
            .addAction(
                if (player?.isPlaying == true) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play,
                "Play / Pause",
                pending("toggle"),
            )
            .addAction(android.R.drawable.ic_media_next, "Next", pending("next"))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", pending("stop"))
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(session!!.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    private fun updateNotification() {
        session?.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(
                    MediaMetadataCompat.METADATA_KEY_TITLE,
                    queue.getOrNull(index)?.optString("title"),
                )
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, player?.length ?: 0)
                .build()
        )
        val actions =
            PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_STOP or
                PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
        session?.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (player?.isPlaying == true) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    player?.time ?: 0,
                    player?.rate ?: 1f,
                )
                .build()
        )
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(
            NOTIFICATION,
            notification(),
        )
    }

    private fun stopPlayback() {
        stopping = true
        pause()
        visible = false
        save()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (player?.isPlaying != true) stopPlayback()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        destroyed = true
        save()
        main.removeCallbacksAndMessages(null)
        stopDiscovery()
        renderers.values.forEach { it.release() }
        renderers.clear()
        unregisterReceiver(noisy)
        session?.release()
        if (wake?.isHeld == true) wake?.release()
        if (Build.VERSION.SDK_INT >= 26) focus?.let { audio.abandonAudioFocusRequest(it) }
        else @Suppress("DEPRECATION") audio.abandonAudioFocus(focusListener)
        val p = player
        player = null
        p?.setEventListener(null)
        p?.let { if (it.vlcVout.areViewsAttached()) it.detachViews() }
        val engine = vlc
        val fd = descriptor
        descriptor = null
        vlc = null
        if (instance === this) instance = null
        java.util.concurrent.Executors.newSingleThreadExecutor().apply {
            execute {
                p?.stop()
                fd?.close()
                p?.release()
                engine?.release()
            }
            shutdown()
        }
        super.onDestroy()
    }
}

class PlaybackActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PlaybackService.send(context, intent.getStringExtra("method") ?: return)
    }
}
