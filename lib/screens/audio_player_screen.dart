import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../services/database_service.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const AudioPlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late AudioPlayer _player;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.file(widget.filePath),
          tag: MediaItem(
            id: widget.filePath,
            album: "MediaStreamer",
            title: widget.title,
          ),
        ),
      );

      final posMap = await DatabaseService.getPlaybackPosition(widget.filePath);
      if (posMap != null && posMap['positionMs'] != null && (posMap['positionMs'] as int) > 0) {
        await _player.seek(Duration(milliseconds: posMap['positionMs'] as int));
      }

      await _player.play();
      if (mounted) setState(() => _isInit = true);
    } catch (e) {
      debugPrint("Error loading audio: $e");
    }
  }

  @override
  void dispose() {
    final pos = _player.position;
    final dur = _player.duration;
    if (dur != null && dur.inMilliseconds > 0) {
      DatabaseService.savePlaybackPosition(
        filePath: widget.filePath,
        positionMs: pos.inMilliseconds,
        durationMs: dur.inMilliseconds,
        title: widget.title,
      );
    }
    _player.dispose();
    super.dispose();
  }

  String _format(Duration? d) {
    if (d == null) return "0:00";
    final min = d.inMinutes;
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$min:$sec";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Artwork placeholder
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.music_note,
                size: 100,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 48),
            // Title
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),
            // Progress Bar
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final pos = snapshot.data ?? Duration.zero;
                final dur = _player.duration ?? Duration.zero;
                final posVal = pos.inMilliseconds.toDouble();
                final durVal = dur.inMilliseconds.toDouble();
                final val = (posVal > durVal || durVal == 0) ? 0.0 : posVal;

                return Column(
                  children: [
                    Slider(
                      value: val,
                      max: durVal > 0 ? durVal : 1.0,
                      onChanged: (v) {
                        _player.seek(Duration(milliseconds: v.toInt()));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_format(pos), style: const TextStyle(color: Colors.white54)),
                          Text(_format(dur), style: const TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 48,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () {
                    final newPos = _player.position - const Duration(seconds: 10);
                    _player.seek(newPos.isNegative ? Duration.zero : newPos);
                  },
                ),
                const SizedBox(width: 24),
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snapshot) {
                    final playerState = snapshot.data;
                    final playing = playerState?.playing ?? false;
                    return Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        iconSize: 64,
                        color: Colors.white,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () {
                          if (playing) {
                            _player.pause();
                          } else {
                            _player.play();
                          }
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 48,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () {
                    final newPos = _player.position + const Duration(seconds: 10);
                    final dur = _player.duration ?? Duration.zero;
                    _player.seek(newPos > dur ? dur : newPos);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
