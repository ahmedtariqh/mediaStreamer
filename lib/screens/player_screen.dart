import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/video_note.dart';
import '../services/database_service.dart';
import '../services/youtube_service.dart';
import '../widgets/post_watch_dialog.dart';

class PlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final String youtubeUrl;

  const PlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    required this.youtubeUrl,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _hasShownDialog = false;
  double _playbackSpeed = 1.0;

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    // Open the local file
    _player.open(Media(widget.filePath));

    // Listen for video completion
    _player.stream.completed.listen((completed) {
      if (completed && !_hasShownDialog) {
        _hasShownDialog = true;
        _showPostWatchDialog();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Playback Speed', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._speeds.map((speed) {
                final isSelected = speed == _playbackSpeed;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : Colors.white24,
                    size: 22,
                  ),
                  title: Text(
                    '${speed}x',
                    style: TextStyle(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: speed == 1.0
                      ? Text(
                          'Normal',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white38,
                          ),
                        )
                      : null,
                  onTap: () {
                    _setSpeed(speed);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _player.setRate(speed);
  }

  Future<void> _showPostWatchDialog() async {
    if (!mounted) return;

    final result = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PostWatchDialog(
        videoTitle: widget.title,
        youtubeUrl: widget.youtubeUrl,
      ),
    );

    if (result == null) {
      // User chose to keep the video
      return;
    }

    if (result['action'] == 'save') {
      // Save notes and delete video
      final note = VideoNote(
        youtubeUrl: widget.youtubeUrl,
        title: widget.title,
        notes: result['notes'] ?? '',
        dateWatched: DateTime.now(),
      );
      await DatabaseService.saveNote(note);
      await YoutubeService.deleteVideo(widget.filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes saved, video deleted')),
        );
        Navigator.pop(context);
      }
    } else if (result['action'] == 'delete') {
      // Just delete
      await YoutubeService.deleteVideo(widget.filePath);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video deleted')));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Playback speed button
          TextButton.icon(
            onPressed: _showSpeedPicker,
            icon: Icon(
              Icons.speed,
              size: 20,
              color: _playbackSpeed != 1.0
                  ? theme.colorScheme.secondary
                  : Colors.white70,
            ),
            label: Text(
              '${_playbackSpeed}x',
              style: TextStyle(
                color: _playbackSpeed != 1.0
                    ? theme.colorScheme.secondary
                    : Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.note_add),
            onPressed: () {
              _player.pause();
              _showPostWatchDialog();
            },
            tooltip: 'Add notes',
          ),
        ],
      ),
      body: Center(
        child: Video(controller: _controller, controls: MaterialVideoControls),
      ),
    );
  }
}
