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
